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
}
