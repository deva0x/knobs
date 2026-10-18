import Foundation

/// Runs a tool with its help arguments and collects what it prints, with a time limit, for "All options".
public struct HelpReader: Sendable {
    /// Help should print instantly; a tool still running after this is stopped.
    public static let timeLimit: Duration = .seconds(8)
    /// Help longer than this many lines is cut off.
    public static let maximumLines = 8_000

    private let runner: ToolRunner

    public init(runner: ToolRunner) {
        self.runner = runner
    }

    /// The help text, from standard output and standard error together, in order. Empty when the tool printed
    /// nothing or couldn't start.
    public func helpText(executable: URL, arguments: [String]) async -> String {
        let run = runner.start(executable: executable, arguments: arguments, workingDirectory: nil, progress: nil)
        let watchdog = Task {
            try await Task.sleep(for: Self.timeLimit)
            run.cancel()
        }
        defer { watchdog.cancel() }
        var lines: [String] = []
        for await event in run.events {
            if case .line(let text, _) = event, lines.count < Self.maximumLines { lines.append(text) }
        }
        return lines.joined(separator: "\n")
    }
}
