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
    public static let cancelGracePeriod: TimeInterval = 3
    /// How long to wait for output to drain after the tool exits, in case a child process holds the pipe open.
    public static let drainTimeout: TimeInterval = 2

    private let environment: [String: String]

    /// `environment` is passed to every tool. Build it with `ToolRunner.environment(base:locator:)`.
    public init(environment: [String: String]) {
        self.environment = environment
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
        let run = ToolRun(progress: progress.flatMap(ProgressParser.init))
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

    /// Partial lines longer than this are emitted anyway, so a tool that never prints a newline can't grow memory.
    private static let maximumPendingBytes = 64 * 1024

    private struct State: ~Copyable {
        var process: Process?
        var isCancelled = false
        var exitStatus: (status: Int32, reason: Process.TerminationReason)?
        var openStreams: Set<OutputLog.Stream> = [.standardOutput, .standardError]
        var pending: [OutputLog.Stream: Data] = [:]
        var progress: ProgressParser?
        var isFinished = false
    }

    fileprivate init(progress: ProgressParser?) {
        (events, continuation) = AsyncStream.makeStream(of: RunEvent.self, bufferingPolicy: .unbounded)
        state = Mutex(State(progress: progress))
    }

    /// Asks the tool to stop: SIGTERM now, SIGKILL after the grace period if it is still running.
    public func cancel() {
        let process = state.withLock { state -> Process? in
            guard !state.isFinished else { return nil }
            state.isCancelled = true
            return state.process
        }
        guard let process, process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + ToolRunner.cancelGracePeriod) {
            if process.isRunning { kill(pid, SIGKILL) }
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
        let events = state.withLock { state -> [RunEvent] in
            var buffer = state.pending[stream, default: Data()]
            buffer.append(data)
            var lines: [String] = []
            // Tools such as ffmpeg redraw their status with carriage returns, so \r ends a line too.
            while let end = buffer.firstIndex(where: { $0 == UInt8(ascii: "\n") || $0 == UInt8(ascii: "\r") }) {
                lines.append(String(decoding: buffer[buffer.startIndex..<end], as: UTF8.self))
                buffer = Data(buffer[buffer.index(after: end)...])
            }
            if buffer.count > Self.maximumPendingBytes {
                lines.append(String(decoding: buffer, as: UTF8.self))
                buffer = Data()
            }
            state.pending[stream] = buffer
            return lines.filter { !$0.isEmpty }.flatMap { line in Self.events(for: line, from: stream, state: &state) }
        }
        for event in events { continuation.yield(event) }
    }

    private static func events(for line: String, from stream: OutputLog.Stream, state: inout State) -> [RunEvent] {
        var events: [RunEvent] = [.line(line, stream)]
        if let fraction = state.progress?.progress(after: line) { events.append(.progress(fraction)) }
        return events
    }

    private func streamClosed(_ stream: OutputLog.Stream) {
        let events = state.withLock { state -> [RunEvent] in
            state.openStreams.remove(stream)
            guard let rest = state.pending.removeValue(forKey: stream), !rest.isEmpty else { return [] }
            return Self.events(for: String(decoding: rest, as: UTF8.self), from: stream, state: &state)
        }
        for event in events { continuation.yield(event) }
        finishIfDone()
    }

    private func processExited(status: Int32, reason: Process.TerminationReason) {
        state.withLock { $0.exitStatus = (status, reason) }
        finishIfDone()
        DispatchQueue.global().asyncAfter(deadline: .now() + ToolRunner.drainTimeout) { [weak self] in
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

    private func finish(with outcome: RunOutcome) {
        let isFirst = state.withLock { state -> Bool in
            guard !state.isFinished else { return false }
            state.isFinished = true
            state.process = nil
            return true
        }
        guard isFirst else { return }
        continuation.yield(.finished(outcome))
        continuation.finish()
    }
}
