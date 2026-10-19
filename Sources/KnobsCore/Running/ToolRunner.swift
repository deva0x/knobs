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

    /// The most one read of an output pipe takes.
    private static let readBufferBytes = 64 * 1024
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
    /// exited is left alone, and one that exits cleanly anyway still counts as finished (see `outcome(of:)`).
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

        process.terminationHandler = { [weak self] process in
            self?.processExited(status: process.terminationStatus, reason: process.terminationReason)
        }
        continuation.onTermination = { [weak self] termination in
            if case .cancelled = termination { self?.cancel() }
        }

        state.withLock { $0.process = process }
        do {
            try Self.withSignalsUnblocked { try process.run() }
        } catch {
            finish(with: .couldNotStart(error.localizedDescription))
            return
        }
        listen(to: standardOutput, as: .standardOutput)
        listen(to: standardError, as: .standardError)
    }

    /// On Linux, `Process` spawns the tool with the calling thread's signal mask, and Dispatch and Swift
    /// concurrency threads block SIGTERM, so a tool started from one would ignore `cancel()` until SIGKILL.
    /// Spawning with an empty mask gives every tool the default mask it gets on macOS.
    private static func withSignalsUnblocked<T>(_ body: () throws -> T) rethrows -> T {
        #if os(Linux)
            var empty = sigset_t()
            var previous = sigset_t()
            sigemptyset(&empty)
            pthread_sigmask(SIG_SETMASK, &empty, &previous)
            defer { pthread_sigmask(SIG_SETMASK, &previous, nil) }
        #endif
        return try body()
    }

    /// Reads the pipe with blocking reads on a thread of its own until every writer has closed it, then closes the
    /// stream. Not `readabilityHandler`: on Linux it stops being called after the first 8 KB (BUG-014). The thread
    /// reads its own duplicate of the descriptor and closes it itself, so the number can't be reused under it. A
    /// helper that keeps the pipe open after the tool exits keeps the thread waiting until the helper exits (Cancel
    /// stops the whole group); the run itself still finishes through the drain timeout, except where BUG-016 holds
    /// back the exit on Linux. A read error other than an interruption ends the stream like the end of output does,
    /// and so does a failed `dup` (only when the app has run out of descriptors), which loses that stream's output.
    private func listen(to pipe: Pipe, as stream: OutputLog.Stream) {
        let descriptor = dup(pipe.fileHandleForReading.fileDescriptor)
        Thread.detachNewThread { [weak self] in
            defer { close(descriptor) }
            var buffer = [UInt8](repeating: 0, count: Self.readBufferBytes)
            while true {
                let count = read(descriptor, &buffer, buffer.count)
                if count > 0 {
                    self?.received(Data(buffer[..<count]), from: stream)
                } else if count < 0 && errno == EINTR {
                    continue
                } else {
                    break
                }
            }
            self?.streamClosed(stream)
        }
    }

    private func received(_ data: Data, from stream: OutputLog.Stream) {
        let lines = state.withLock { state -> [String] in
            guard !state.isFinished else { return [] }
            var buffer = state.pending[stream, default: Data()]
            buffer.append(data)
            var lines: [String] = []
            // Tools redraw their status with carriage returns (ffmpeg) or backspaces (7-Zip), so those end a line too.
            // The scan moves along the buffer and keeps the unfinished rest once, so a chunk of many short lines
            // costs one pass rather than a copy of the remainder per line.
            var lineStart = buffer.startIndex
            while let end = buffer[lineStart...].firstIndex(where: Self.isLineBreak) {
                lines.append(String(decoding: buffer[lineStart..<end], as: UTF8.self))
                lineStart = buffer.index(after: end)
            }
            buffer = Data(buffer[lineStart...])
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
            self?.finishAfterDrainTimeout()
        }
    }

    /// Finishes once the tool has exited and both of its output streams have closed.
    private func finishIfDone() {
        let outcome = state.withLock { state -> RunOutcome? in
            guard state.openStreams.isEmpty else { return nil }
            return Self.outcome(of: state)
        }
        if let outcome { finish(with: outcome) }
    }

    /// Finishes once the tool has exited, even if a helper it started still holds an output stream open.
    private func finishAfterDrainTimeout() {
        if let outcome = state.withLock({ Self.outcome(of: $0) }) { finish(with: outcome) }
    }

    /// How the run ended, or nil while the tool is still running. A clean exit counts as success even after
    /// Cancel: the tool says it finished its work, and Cancel may have come in the moment between the tool's exit
    /// and Knobs collecting it. A tool that Cancel did stop exits by the signal or with a failure code.
    private static func outcome(of state: borrowing State) -> RunOutcome? {
        guard let exit = state.exitStatus else { return nil }
        if exit.reason == .exit && exit.status == 0 { return .succeeded }
        return state.isCancelled ? .cancelled : .failed(exitCode: exit.status)
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
