import Foundation
import KnobsCore
import Testing

/// Helpers for suites named `...IntegrationTests`, which run real third-party tools (see docs/WORKFLOW.md).
enum Integration {
    static let locator = ToolLocator(environmentPath: ProcessInfo.processInfo.environment["PATH"])
    static let runner = ToolRunner(
        environment: ToolRunner.environment(base: ProcessInfo.processInfo.environment, locator: locator))

    /// The tool's path, or nil when it isn't installed. With `KNOBS_REQUIRE_TOOLS=1` a missing tool is a failure
    /// instead of a skip, so release checks can't pass on a Mac without the tools.
    static func tool(_ executable: String, sourceLocation: SourceLocation = #_sourceLocation) -> URL? {
        if let url = locator.locate(executable) { return url }
        if ProcessInfo.processInfo.environment["KNOBS_REQUIRE_TOOLS"] == "1" {
            Issue.record("\(executable) isn't installed, and KNOBS_REQUIRE_TOOLS=1", sourceLocation: sourceLocation)
        } else {
            print("Skipping: \(executable) isn't installed")
        }
        return nil
    }

    /// A fresh folder for one test's files.
    static func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "knobs-integration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Runs a manifest task for real and returns the outcome, the output path and every event.
    static func run(
        _ taskID: String,
        of manifest: ToolManifest,
        executable: URL,
        values: [String: FieldValue],
        extraArguments: String = "",
        in folder: URL
    ) async throws -> (outcome: RunOutcome, outputPath: String?, events: [RunEvent]) {
        let task = try #require(manifest.task(withID: taskID))
        let builder = CommandBuilder(
            outputNamer: OutputNamer(fileExists: { FileManager.default.fileExists(atPath: $0) }),
            homeDirectory: NSHomeDirectory())
        let draft = builder.build(task, of: manifest, values: values, extraArguments: extraArguments)
        #expect(draft.isRunnable, "\(draft.problems)")
        // As the app's TaskSession does: a new-folder output is made, empty, just before the tool starts.
        if task.output?.isNewFolder == true, let newFolder = draft.command.outputPath {
            try FileManager.default.createDirectory(atPath: newFolder, withIntermediateDirectories: false)
        }
        let toolRun = runner.start(
            executable: executable, arguments: draft.command.argv, workingDirectory: folder, progress: task.progress)
        var events: [RunEvent] = []
        for await event in toolRun.events { events.append(event) }
        guard case .finished(let outcome)? = events.last else { throw IntegrationError.noOutcome }
        return (outcome, draft.command.outputPath, events)
    }

    /// Runs a helper command directly, for preparing fixtures or checking a result, and returns what it printed.
    @discardableResult
    static func prepare(_ executable: URL, _ arguments: [String], in folder: URL) async throws -> [String] {
        let run = runner.start(executable: executable, arguments: arguments, workingDirectory: folder, progress: nil)
        var lines: [String] = []
        var outcome: RunOutcome?
        for await event in run.events {
            if case .line(let line, _) = event { lines.append(line) }
            if case .finished(let finished) = event { outcome = finished }
        }
        guard outcome == .succeeded else {
            throw IntegrationError.preparationFailed(lines.suffix(5).joined(separator: "\n"))
        }
        return lines
    }

    enum IntegrationError: Error {
        case noOutcome
        case preparationFailed(String)
    }
}
