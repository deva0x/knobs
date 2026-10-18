import Foundation
import KnobsCore
import Testing

@Suite struct KnobsLibraryTests {
    private let key = KnobsLibrary.key(toolID: "ffmpeg", taskID: "shrink-video")
    private let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    @Test func rememberedValuesComeBackForTheSameTaskOnly() {
        var library = KnobsLibrary()
        library.rememberValues(["quality": .integer(20)], forTask: key)
        #expect(library.lastValues(forTask: key) == ["quality": .integer(20)])
        #expect(library.lastValues(forTask: "ffmpeg/trim").isEmpty)
    }

    @Test func presetsAreSortedByName() {
        var library = KnobsLibrary()
        library.savePreset(named: "WhatsApp", values: [:], forTask: key, id: firstID)
        library.savePreset(named: "email", values: [:], forTask: key, id: secondID)
        #expect(library.presets(forTask: key).map(\.name) == ["email", "WhatsApp"])
    }

    @Test func savingWithAnExistingNameUpdatesThatPreset() {
        var library = KnobsLibrary()
        library.savePreset(named: "Small", values: ["quality": .integer(30)], forTask: key, id: firstID)
        library.savePreset(named: "  small ", values: ["quality": .integer(32)], forTask: key, id: secondID)
        #expect(library.presets(forTask: key).count == 1)
        #expect(library.presets(forTask: key)[0].id == firstID)
        #expect(library.presets(forTask: key)[0].values == ["quality": .integer(32)])
    }

    @Test func blankPresetNamesAreRefused() {
        var library = KnobsLibrary()
        #expect(library.savePreset(named: "   ", values: [:], forTask: key, id: firstID) == nil)
        #expect(library.presets(forTask: key).isEmpty)
    }

    @Test func deletingAPresetRemovesOnlyThatOne() {
        var library = KnobsLibrary()
        library.savePreset(named: "A", values: [:], forTask: key, id: firstID)
        library.savePreset(named: "B", values: [:], forTask: key, id: secondID)
        library.deletePreset(firstID, forTask: key)
        #expect(library.presets(forTask: key).map(\.name) == ["B"])
    }

    @Test func recentRunsKeepTheNewestFirstAndAreCapped() {
        var library = KnobsLibrary()
        for index in 0..<(KnobsLibrary.maximumRecentRuns + 5) {
            library.recordRun(
                RecentRun(
                    id: UUID(), toolID: "ffmpeg", taskID: "trim",
                    finishedAt: Date(timeIntervalSince1970: Double(index)),
                    succeeded: true, outputPath: nil))
        }
        #expect(library.recentRuns.count == KnobsLibrary.maximumRecentRuns)
        #expect(library.recentRuns.first?.finishedAt == Date(timeIntervalSince1970: 34))
    }
}

@Suite struct LibraryFileTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "knobs-library-\(UUID().uuidString)/library.json")
    }

    @Test func missingFileLoadsAnEmptyLibrary() throws {
        #expect(try LibraryFile(url: temporaryFile()).load() == KnobsLibrary())
    }

    @Test func savedLibraryLoadsBackUnchanged() throws {
        let file = LibraryFile(url: temporaryFile())
        defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
        var library = KnobsLibrary()
        library.rememberValues(
            ["quality": .integer(20), "size": .text("1280"), "folder": .paths(["/tmp"]), "mute": .toggle(true)],
            forTask: "ffmpeg/shrink-video")
        library.savePreset(named: "Tiny", values: ["quality": .integer(34)], forTask: "ffmpeg/shrink-video", id: UUID())
        library.recordRun(
            RecentRun(
                id: UUID(), toolID: "ffmpeg", taskID: "shrink-video", finishedAt: Date(timeIntervalSince1970: 1_000),
                succeeded: true, outputPath: "/tmp/a.mp4"))

        try file.save(library)

        let loaded = try file.load()
        #expect(loaded.lastValues(forTask: "ffmpeg/shrink-video") == library.lastValues(forTask: "ffmpeg/shrink-video"))
        #expect(loaded.presets(forTask: "ffmpeg/shrink-video") == library.presets(forTask: "ffmpeg/shrink-video"))
        #expect(loaded.recentRuns == library.recentRuns)
    }

    @Test func aDamagedFileCanBeSetAsideInsteadOfOverwritten() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ broken".utf8).write(to: url)

        let kept = try LibraryFile(url: url).setAside(at: Date(timeIntervalSince1970: 0))

        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try Data(contentsOf: kept) == Data("{ broken".utf8))
        #expect(kept.deletingLastPathComponent() == url.deletingLastPathComponent())
    }

    @Test func damagedFileIsReportedNotIgnored() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ broken".utf8).write(to: url)
        #expect(throws: LibraryFile.LibraryFileError.self) { try LibraryFile(url: url).load() }
    }
}

@Suite struct AddedToolsTests {
    @Test func toolsAreAddedOnceByBareName() {
        var library = KnobsLibrary()
        let first = library.addTool(named: " jq ")
        let again = library.addTool(named: "jq")
        let path = library.addTool(named: "/usr/bin/curl")
        #expect(first && !again && !path)
        #expect(library.addedTools == ["jq"])
        library.removeTool(named: "jq")
        #expect(library.addedTools.isEmpty)
    }

    @Test func aLibraryWithoutNewerKeysStillLoads() throws {
        let library = try JSONDecoder().decode(KnobsLibrary.self, from: Data(#"{"version": 1}"#.utf8))
        #expect(library.addedTools.isEmpty)
        #expect(library.recentRuns.isEmpty)
    }
}

@Suite struct HelpReaderTests {
    @Test func collectsWhatTheToolPrints() async {
        let reader = HelpReader(runner: ToolRunner(environment: ProcessInfo.processInfo.environment))
        let text = await reader.helpText(executable: URL(filePath: "/bin/echo"), arguments: ["  -x   do x"])
        #expect(HelpParser.options(in: text).map(\.preferredFlag) == ["-x"])
    }
}
