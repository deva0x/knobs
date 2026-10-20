import Foundation
import KnobsCore
import KnobsSession
import Testing

@MainActor
@Suite struct TaskSessionTests {
    /// A task whose output is a new folder, run by `touch`, which writes into the folder but can't make it, as
    /// pdftoppm does.
    private static let pagesManifest = """
        {
          "schemaVersion": 1, "id": "pages", "name": "Pages", "summary": "Pages.",
          "executable": "touch", "install": { "brew": "coreutils" }, "symbol": "doc", "tint": "yellow",
          "tasks": [{
            "id": "every-page", "title": "Every page", "summary": "Every page.", "symbol": "doc",
            "fields": [{ "id": "input", "label": "PDF", "kind": "inputFile" }],
            "output": { "template": "{input.stem} pages", "nextTo": "input", "newFolder": true },
            "arguments": ["{output}/page-1.png", "{extra}"]
          }]
        }
        """

    private func makeSession(input: URL) throws -> TaskSession {
        let manifest = try ManifestLoader.load(Data(Self.pagesManifest.utf8), source: "pages.json")
        let task = try #require(manifest.tasks.first)
        return TaskSession(manifest: manifest, task: task, initialValues: ["input": .paths([input.path])])
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "knobs-session-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Runs the session's task with `executable` and waits for the outcome it reports when the run ends.
    private func run(_ session: TaskSession, with executable: String) async throws -> RunOutcome {
        // A command that can't run never finishes, so waiting for it would never end.
        try #require(session.draft.isRunnable, "\(session.draft.problems)")
        return await withCheckedContinuation { continuation in
            session.onFinish = { outcome, _ in continuation.resume(returning: outcome) }
            session.start(executable: URL(filePath: executable), runner: ToolRunner(environment: [:]))
        }
    }

    @Test func theNewFolderIsMadeBeforeTheToolRunsAndIsTheResult() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = try makeSession(input: folder.appending(path: "doc.pdf"))
        let pages = folder.appending(path: "doc pages")

        let outcome = try await run(session, with: "/usr/bin/touch")

        #expect(outcome == .succeeded)
        #expect(FileManager.default.fileExists(atPath: pages.appending(path: "page-1.png").path))
        #expect(session.result?.outputURL?.path == pages.path)
        #expect(session.draft.command.outputPath == folder.appending(path: "doc pages 2").path)
    }

    @Test func aFailedRunThatWroteNothingLeavesNoNewFolder() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = try makeSession(input: folder.appending(path: "doc.pdf"))
        let pages = folder.appending(path: "doc pages")

        let outcome = try await run(session, with: "/usr/bin/false")

        #expect(outcome == .failed(exitCode: 1))
        #expect(!FileManager.default.fileExists(atPath: pages.path))
        #expect(session.draft.command.outputPath == pages.path)
    }

    @Test func aFailedRunKeepsWhatTheToolWroteInTheNewFolder() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = try makeSession(input: folder.appending(path: "doc.pdf"))
        // touch writes the page, then fails on a file in a folder that doesn't exist.
        session.extraArguments = folder.appending(path: "missing/file").path

        let outcome = try await run(session, with: "/usr/bin/touch")

        #expect(outcome == .failed(exitCode: 1))
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "doc pages/page-1.png").path))
    }

    @Test func aNewFolderThatCannotBeMadeStopsTheRunBeforeTheToolStarts() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = try makeSession(input: folder.appending(path: "missing/doc.pdf"))

        let outcome = try await run(session, with: "/usr/bin/touch")

        guard case .couldNotStart(let reason) = outcome else {
            Issue.record("expected couldNotStart, got \(outcome)")
            return
        }
        #expect(
            reason.hasPrefix("Knobs couldn't make the folder “doc pages” in \(folder.appending(path: "missing").path)"))
        #expect(session.phase == .finished(outcome))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "missing").path))
    }

    /// A task that copies its input to an output with another extension, as a converting tool would.
    private func makeCopySession(input: URL, outputExtension: String) throws -> TaskSession {
        let json = """
            {
              "schemaVersion": 1, "id": "copy", "name": "Copy", "summary": "Copy.",
              "executable": "cp", "install": { "brew": "coreutils" }, "symbol": "doc", "tint": "gray",
              "tasks": [{
                "id": "copy", "title": "Copy", "summary": "Copy.", "symbol": "doc",
                "fields": [{ "id": "input", "label": "File", "kind": "inputFile" }],
                "output": { "template": "{input.stem} out.\(outputExtension)", "nextTo": "input" },
                "arguments": ["{extra}", "{input}", "{output}"]
              }]
            }
            """
        let manifest = try ManifestLoader.load(Data(json.utf8), source: "copy.json")
        let task = try #require(manifest.tasks.first)
        return TaskSession(manifest: manifest, task: task, initialValues: ["input": .paths([input.path])])
    }

    @Test func aVideoMadeIntoAnotherVideoHasComparableSizes() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clip = folder.appending(path: "clip.mov")
        try Data(count: 1000).write(to: clip)
        let session = try makeCopySession(input: clip, outputExtension: "mp4")

        let outcome = try await run(session, with: "/bin/cp")

        #expect(outcome == .succeeded)
        #expect(session.result?.sizesAreComparable == true)
    }

    @Test func aPDFTurnedIntoTextHasNoSizeChange() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let lease = folder.appending(path: "lease.pdf")
        try Data(count: 1000).write(to: lease)
        let session = try makeCopySession(input: lease, outputExtension: "txt")

        let outcome = try await run(session, with: "/bin/cp")

        #expect(outcome == .succeeded)
        #expect(session.result?.sizesAreComparable == false)
        #expect(session.result?.sizeChange == nil)
    }

    @Test func aNewFolderHasNoSizeChange() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = try makeSession(input: folder.appending(path: "doc.pdf"))

        let outcome = try await run(session, with: "/usr/bin/touch")

        #expect(outcome == .succeeded)
        #expect(session.result?.sizesAreComparable == false)
    }

    // MARK: Several files, one after another

    /// Counts how often a session reports the end of a run, to check that a run over several files reports once.
    private final class FinishCount {
        var count = 0
    }

    /// Starts a run and waits for its one reported end, counting reports so a second one would show.
    private func runCounting(_ session: TaskSession, with executable: String) async throws -> (RunOutcome, FinishCount)
    {
        try #require(session.draft.isRunnable, "\(session.draft.problems)")
        let finishes = FinishCount()
        let outcome = await withCheckedContinuation { continuation in
            session.onFinish = { outcome, _ in
                finishes.count += 1
                if finishes.count == 1 { continuation.resume(returning: outcome) }
            }
            session.start(executable: URL(filePath: executable), runner: ToolRunner(environment: [:]))
        }
        return (outcome, finishes)
    }

    @Test func severalFilesInAOneFileTaskRunOneAfterAnother() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clips = try ["a.mov", "b.mov", "c.mov"].map { name in
            let clip = folder.appending(path: name)
            try Data(count: 100).write(to: clip)
            return clip
        }
        let session = try makeCopySession(input: clips[0], outputExtension: "mp4")
        session.values["input"] = .paths(clips.map(\.path))
        #expect(session.filesRunOneByOne == clips.map(\.path))

        let (outcome, finishes) = try await runCounting(session, with: "/bin/cp")

        #expect(outcome == .succeeded)
        #expect(finishes.count == 1)
        for name in ["a out.mp4", "b out.mp4", "c out.mp4"] {
            #expect(FileManager.default.fileExists(atPath: folder.appending(path: name).path), "\(name)")
        }
        #expect(session.result?.fileCount == 3)
        #expect(session.result?.failedFiles == [])
        #expect(session.result?.folderURL?.path == folder.path)
        #expect(session.result?.outputURL == nil)
    }

    @Test func aFileThatFailsDoesNotStopTheOthers() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appending(path: "a.mov")
        let missing = folder.appending(path: "gone.mov")
        let last = folder.appending(path: "c.mov")
        try Data(count: 100).write(to: first)
        try Data(count: 100).write(to: last)
        let session = try makeCopySession(input: first, outputExtension: "mp4")
        session.values["input"] = .paths([first.path, missing.path, last.path])

        let (outcome, finishes) = try await runCounting(session, with: "/bin/cp")

        #expect(outcome == .succeeded)
        #expect(finishes.count == 1)
        #expect(session.result?.failedFiles == [missing.path])
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "c out.mp4").path))
    }

    @Test func whenEveryFileFailsTheRunFails() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let paths = ["x.mov", "y.mov"].map { folder.appending(path: $0).path }
        let session = try makeCopySession(input: URL(filePath: paths[0]), outputExtension: "mp4")
        session.values["input"] = .paths(paths)

        let (outcome, _) = try await runCounting(session, with: "/bin/cp")

        #expect(outcome == .failed(exitCode: 1))
        #expect(session.result == nil)
    }

    @Test func cancellingStopsTheFilesNotYetStarted() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let paths = try ["a.mov", "b.mov"].map { name in
            let clip = folder.appending(path: name)
            try Data(count: 100).write(to: clip)
            return clip.path
        }
        // A task that waits long enough to be cancelled, whatever file it is given.
        let json = """
            {
              "schemaVersion": 1, "id": "wait", "name": "Wait", "summary": "Waits.",
              "executable": "sleep", "install": { "brew": "coreutils" }, "symbol": "doc", "tint": "gray",
              "tasks": [{
                "id": "wait", "title": "Wait", "summary": "Waits.", "symbol": "doc",
                "fields": [{ "id": "input", "label": "File", "kind": "inputFile" }],
                "arguments": ["30", "{extra}"]
              }]
            }
            """
        let manifest = try ManifestLoader.load(Data(json.utf8), source: "wait.json")
        let session = TaskSession(
            manifest: manifest, task: try #require(manifest.tasks.first), initialValues: ["input": .paths(paths)])

        let outcome = await withCheckedContinuation { continuation in
            session.onFinish = { outcome, _ in continuation.resume(returning: outcome) }
            session.start(executable: URL(filePath: "/bin/sleep"), runner: ToolRunner(environment: [:]))
            session.cancel()
        }

        #expect(outcome == .cancelled)
        #expect(session.phase == .finished(.cancelled))
        #expect(!session.isRunning)
    }
}
