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
