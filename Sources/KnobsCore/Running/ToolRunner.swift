import Foundation
import Synchronization

/// Something that happened while a tool ran, in order.
public enum RunEvent: Sendable, Hashable {
    case line(String, OutputLog.Stream)
    /// A fraction from 0 to 1, when the task's manifest says how to read progress.
    case progress(Double)
    /// Always the last event.
    case finished(RunOutcome)
}

public enum RunOutcome: Sendable, Hashable {
    case succeeded
    case failed(exitCode: Int32)
    case cancelled
    case couldNotStart(String)
}

/// Launches tools as an argv array with `Process`, never through a shell (DEC-006).
public struct ToolRunner: Sendable {
    /// How long a cancelled tool gets to exit after SIGTERM before it is killed.
    public static let defaultCancelGracePeriod = Duration.seconds(3)
    /// How long to wait for output to drain after the tool exits, in case a child process holds the pipe open.
    public static let drainTimeout = Duration.seconds(2)

    private let environment: [String: String]
    private let cancelGracePeriod: Duration

    /// `environment` is passed to every tool. Build it with `ToolRunner.environment(base:locator:)`.
    public init(environment: [String: String], cancelGracePeriod: Duration = defaultCancelGracePeriod) {
        self.environment = environment
        self.cancelGracePeriod = cancelGracePeriod
    }

    /// The app's environment with `PATH` replaced by the locator's folders, so tools find their helpers.
    public static func environment(base: [String: String], locator: ToolLocator) -> [String: String] {
        var environment = base
        environment["PATH"] = locator.pathEnvironmentValue
        return environment
    }

    /// Starts the tool and returns at once. Read `events` for its output, progress and outcome.
    public func start(
        executable: URL,
        arguments: [String],
        workingDirectory: URL?,
        progress: ProgressRule?
    ) -> ToolRun {
        let run = ToolRun(progress: progress.flatMap(ProgressParser.init), cancelGracePeriod: cancelGracePeriod)
        run.launch(
            executable: executable, arguments: arguments, environment: environment,
            workingDirectory: workingDirectory)
        return run
    }
}

/// One running tool. Cancel it with `cancel()`, or by stopping iteration of `events`.
public final class ToolRun: Sendable {
    public let events: AsyncStream<RunEvent>
    private let continuation: AsyncStream<RunEvent>.Continuation
    private let state: Mutex<State>
    /// Progress has its own lock: a slow pattern must never hold up `cancel()` or the end of the run.
    private let progress: Mutex<ProgressParser?>
    private let cancelGracePeriod: Duration

    /// Partial lines longer than this are emitted anyway, so a tool that never prints a newline can't grow memory.
    private static let maximumPendingBytes = 64 * 1024
    /// Progress is read from the end of a line only; status lines are short, and a pattern's cost grows with input.
    private static let maximumProgressLineLength = 512
    /// Events waiting for a slow reader. Past this, the oldest lines are dropped (the output log keeps only the
    /// newest lines anyway), so a chatty tool can't grow memory without bound. `.finished` is never dropped,
    /// because it is always the newest.
    private static let maximumBufferedEvents = 20_000

    private struct State: ~Copyable {
        var process: Process?
        var isCancelled = false
        var exitStatus: (status: Int32, reason: Process.TerminationReason)?
        var openStreams: Set<OutputLog.Stream> = [.standardOutput, .standardError]
        var pending: [OutputLog.Stream: Data] = [:]
        var isFinished = false
    }

    fileprivate init(progress: ProgressParser?, cancelGracePeriod: Duration) {
        (events, continuation) = AsyncStream.makeStream(
            of: RunEvent.self, bufferingPolicy: .bufferingNewest(Self.maximumBufferedEvents))
        state = Mutex(State())
        self.progress = Mutex(progress)
        self.cancelGracePeriod = cancelGracePeriod
    }

    /// Asks the tool to stop: SIGTERM now, SIGKILL after the grace period. Both go to the tool's whole process
    /// group, so helpers it started (yt-dlp's ffmpeg, ocrmypdf's Ghostscript) stop too. A tool that has already
    /// exited is left alone, so a run that finished just before Cancel still counts as finished.
    public func cancel() {
        let process = state.withLock { state -> Process? in
            guard !state.isFinished, state.exitStatus == nil, let process = state.process else { return nil }
            state.isCancelled = true
            return process
        }
        guard let process, process.isRunning else { return }
        let pid = process.processIdentifier
        // Foundation starts each tool as the leader of its own process group; checked here rather than assumed.
        let leadsGroup = getpgid(pid) == pid
        if leadsGroup { killpg(pid, SIGTERM) } else { kill(pid, SIGTERM) }
        DispatchQueue.global().asyncAfter(deadline: .now() + cancelGracePeriod.timeInterval) {
            if leadsGroup {
                // Sent even if the tool itself has exited, because a helper that ignored SIGTERM may still be
                // running, but only while the group still has members, so a reused id is never signalled.
                if killpg(pid, 0) == 0 { killpg(pid, SIGKILL) }
            } else if process.isRunning {
                kill(pid, SIGKILL)
            }
        }
    }

    fileprivate func launch(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?
    ) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = workingDirectory
        process.standardInput = FileHandle.nullDevice
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        listen(to: standardOutput, as: .standardOutput)
        listen(to: standardError, as: .standardError)
        process.terminationHandler = { [weak self] process in
            self?.processExited(status: process.terminationStatus, reason: process.terminationReason)
        }
        continuation.onTermination = { [weak self] termination in
            if case .cancelled = termination { self?.cancel() }
        }

        state.withLock { $0.process = process }
        do {
            try process.run()
        } catch {
            standardOutput.fileHandleForReading.readabilityHandler = nil
            standardError.fileHandleForReading.readabilityHandler = nil
            finish(with: .couldNotStart(error.localizedDescription))
        }
    }

    private func listen(to pipe: Pipe, as stream: OutputLog.Stream) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                self?.streamClosed(stream)
            } else {
                self?.received(data, from: stream)
            }
        }
    }

    private func received(_ data: Data, from stream: OutputLog.Stream) {
        let lines = state.withLock { state -> [String] in
            guard !state.isFinished else { return [] }
            var buffer = state.pending[stream, default: Data()]
            buffer.append(data)
            var lines: [String] = []
            // Tools redraw their status with carriage returns (ffmpeg) or backspaces (7-Zip), so those end a line too.
            while let end = buffer.firstIndex(where: Self.isLineBreak) {
                lines.append(String(decoding: buffer[buffer.startIndex..<end], as: UTF8.self))
                buffer = Data(buffer[buffer.index(after: end)...])
            }
            if buffer.count > Self.maximumPendingBytes {
                lines.append(String(decoding: buffer, as: UTF8.self))
                buffer = Data()
            }
            state.pending[stream] = buffer
            return lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        emit(lines, from: stream)
    }

    private static func isLineBreak(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r") || byte == 0x08
    }

    /// Reads progress outside the run's lock, then yields under it, so nothing can follow `.finished`.
    private func emit(_ lines: [String], from stream: OutputLog.Stream) {
        guard !lines.isEmpty else { return }
        let events = lines.flatMap { line -> [RunEvent] in
            let tail = String(line.suffix(Self.maximumProgressLineLength))
            guard let fraction = progress.withLock({ $0?.progress(after: tail) }) else { return [.line(line, stream)] }
            return [.line(line, stream), .progress(fraction)]
        }
        state.withLock { state in
            guard !state.isFinished else { return }
            for event in events { continuation.yield(event) }
        }
    }

    private func streamClosed(_ stream: OutputLog.Stream) {
        let rest = state.withLock { state -> String? in
            state.openStreams.remove(stream)
            guard !state.isFinished, let rest = state.pending.removeValue(forKey: stream), !rest.isEmpty else {
                return nil
            }
            return String(decoding: rest, as: UTF8.self)
        }
        if let rest, !rest.trimmingCharacters(in: .whitespaces).isEmpty { emit([rest], from: stream) }
        finishIfDone()
    }

    private func processExited(status: Int32, reason: Process.TerminationReason) {
        state.withLock { $0.exitStatus = (status, reason) }
        finishIfDone()
        DispatchQueue.global().asyncAfter(deadline: .now() + ToolRunner.drainTimeout.timeInterval) { [weak self] in
            self?.finishIfDone(ignoringOpenStreams: true)
        }
    }

    private func finishIfDone(ignoringOpenStreams: Bool = false) {
        let outcome = state.withLock { state -> RunOutcome? in
            guard let exit = state.exitStatus, ignoringOpenStreams || state.openStreams.isEmpty else { return nil }
            if state.isCancelled { return .cancelled }
            return exit.reason == .exit && exit.status == 0 ? .succeeded : .failed(exitCode: exit.status)
        }
        if let outcome { finish(with: outcome) }
    }

    /// Yields `.finished` and ends the stream under the lock, so it is always the last event.
    private func finish(with outcome: RunOutcome) {
        state.withLock { state in
            guard !state.isFinished else { return }
            state.isFinished = true
            state.process = nil
            continuation.yield(.finished(outcome))
            continuation.finish()
        }
    }
}

extension Duration {
    /// Seconds as a `TimeInterval`, for Dispatch deadlines.
    fileprivate var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
