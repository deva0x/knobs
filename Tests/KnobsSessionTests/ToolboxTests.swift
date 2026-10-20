import Foundation
import KnobsCore
import KnobsSession
import Synchronization
import Testing

/// A pretend disk where tests decide which programs are installed, and can install one later.
private final class InstalledPrograms: Sendable {
    private let paths: Mutex<Set<String>>

    init(_ paths: Set<String> = []) {
        self.paths = Mutex(paths)
    }

    func install(_ path: String) {
        paths.withLock { _ = $0.insert(path) }
    }

    func contains(_ path: String) -> Bool {
        paths.withLock { $0.contains(path) }
    }
}

@MainActor
@Suite struct ToolboxTests {
    /// A tool that prefers `7zz` but is also installed as `7z` on some systems, like the real 7-Zip manifest.
    private static let sevenZipManifest = """
        {
          "schemaVersion": 1, "id": "7zip", "name": "7-Zip", "summary": "Archives.",
          "executable": "7zz", "alternativeExecutables": ["7z"], "install": { "brew": "sevenzip" },
          "symbol": "archivebox", "tint": "brown",
          "tasks": [{
            "id": "extract", "title": "Extract", "summary": "Extracts.", "symbol": "archivebox",
            "fields": [{ "id": "input", "label": "Archive", "kind": "inputFile" }],
            "arguments": ["x", "{input}", "{extra}"]
          }]
        }
        """

    private func makeToolbox(installed: InstalledPrograms) throws -> (Toolbox, URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "knobs-toolbox-\(UUID().uuidString)")
        let manifests = folder.appending(path: "Manifests")
        try FileManager.default.createDirectory(at: manifests, withIntermediateDirectories: true)
        try Data(Self.sevenZipManifest.utf8).write(to: manifests.appending(path: "7zip.json"))
        let toolbox = Toolbox(
            manifestsDirectory: manifests, dataDirectory: folder.appending(path: "Data"), environment: [:],
            isExecutableFile: installed.contains)
        return (toolbox, folder)
    }

    /// A one-task manifest for a tool installed by `formula`, as pdftoppm and pdftotext are both by poppler.
    private static func manifest(id: String, executable: String, formula: String) -> String {
        """
        {
          "schemaVersion": 1, "id": "\(id)", "name": "\(id)", "summary": "A tool.",
          "executable": "\(executable)", "install": { "brew": "\(formula)" }, "symbol": "doc", "tint": "yellow",
          "tasks": [{
            "id": "run", "title": "Run", "summary": "Runs.", "symbol": "doc",
            "fields": [{ "id": "input", "label": "File", "kind": "inputFile" }],
            "arguments": ["{input}", "{extra}"]
          }]
        }
        """
    }

    private func makeToolboxWithPoppler(installed: InstalledPrograms) throws -> (Toolbox, URL) {
        let (_, folder) = try makeToolbox(installed: installed)
        let manifests = folder.appending(path: "Manifests")
        try Data(Self.manifest(id: "pdftoppm", executable: "pdftoppm", formula: "poppler").utf8)
            .write(to: manifests.appending(path: "pdftoppm.json"))
        try Data(Self.manifest(id: "pdftotext", executable: "pdftotext", formula: "poppler").utf8)
            .write(to: manifests.appending(path: "pdftotext.json"))
        let toolbox = Toolbox(
            manifestsDirectory: manifests, dataDirectory: folder.appending(path: "Data"), environment: [:],
            isExecutableFile: installed.contains)
        return (toolbox, folder)
    }

    @Test func missingToolsAreListedOncePerHomebrewFormula() throws {
        let (toolbox, folder) = try makeToolboxWithPoppler(installed: InstalledPrograms())
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(toolbox.missingFormulas == ["poppler", "sevenzip"])
    }

    @Test func anInstalledToolLeavesTheMissingList() throws {
        let installed = InstalledPrograms(["/opt/homebrew/bin/7zz"])
        let (toolbox, folder) = try makeToolboxWithPoppler(installed: installed)
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(toolbox.missingFormulas == ["poppler"])
    }

    @Test func homebrewIsFoundWhereItInstallsItself() throws {
        let installed = InstalledPrograms()
        let (toolbox, folder) = try makeToolbox(installed: installed)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(!toolbox.isHomebrewInstalled)

        installed.install("/opt/homebrew/bin/brew")
        toolbox.refreshAvailability()

        #expect(toolbox.isHomebrewInstalled)
    }

    @Test func aFinishedRunIsReportedWithItsSessionAndOutcome() async throws {
        let installed = InstalledPrograms(["/usr/bin/true"])
        let (_, folder) = try makeToolbox(installed: installed)
        defer { try? FileManager.default.removeItem(at: folder) }
        let manifests = folder.appending(path: "Manifests")
        try Data(Self.manifest(id: "yes", executable: "true", formula: "coreutils").utf8)
            .write(to: manifests.appending(path: "yes.json"))
        let toolbox = Toolbox(
            manifestsDirectory: manifests, dataDirectory: folder.appending(path: "Data"), environment: [:],
            isExecutableFile: installed.contains)
        let manifest = try #require(toolbox.manifest(withID: "yes"))
        let session = toolbox.session(for: try #require(manifest.tasks.first), of: manifest)
        session.values["input"] = .paths([folder.appending(path: "file.txt").path])

        let (finished, outcome) = await withCheckedContinuation { continuation in
            toolbox.onRunFinished = { session, outcome in continuation.resume(returning: (session, outcome)) }
            toolbox.run(session)
        }

        #expect(finished === session)
        #expect(outcome == .succeeded)
        #expect(toolbox.runningSessions.isEmpty)
    }

    @Test func checkAgainFindsAToolInstalledUnderAnotherNameAfterLaunch() throws {
        let installed = InstalledPrograms()
        let (toolbox, folder) = try makeToolbox(installed: installed)
        defer { try? FileManager.default.removeItem(at: folder) }
        let before = try #require(toolbox.manifest(withID: "7zip"))
        #expect(!toolbox.isInstalled(before))

        installed.install("/usr/bin/7z")
        toolbox.refreshAvailability()

        let after = try #require(toolbox.manifest(withID: "7zip"))
        #expect(after.executable == "7z")
        #expect(toolbox.location(of: after)?.path == "/usr/bin/7z")
    }

    @Test func aTaskOpenedBeforeCheckAgainRunsTheToolUnderItsNewName() throws {
        let installed = InstalledPrograms()
        let (toolbox, folder) = try makeToolbox(installed: installed)
        defer { try? FileManager.default.removeItem(at: folder) }
        let before = try #require(toolbox.manifest(withID: "7zip"))
        let task = try #require(before.tasks.first)
        _ = toolbox.session(for: task, of: before)

        installed.install("/usr/bin/7z")
        toolbox.refreshAvailability()

        let after = try #require(toolbox.manifest(withID: "7zip"))
        #expect(toolbox.session(for: task, of: after).manifest.executable == "7z")
    }
}
