import Foundation
import KnobsCore
import Testing

@Suite struct ManifestLoadingTests {
    @Test func everyManifestInTheRepositoryLoadsWithoutErrors() {
        let catalog = ManifestLoader.loadCatalog(in: manifestsDirectory)
        #expect(catalog.failures.isEmpty, "\(catalog.failures.map(\.localizedDescription))")
        #expect(!catalog.manifests.isEmpty)
    }

    @Test func ffmpegManifestReadsItsToolDetailsAndTasks() throws {
        let manifest = try loadRepositoryManifest("ffmpeg")
        #expect(manifest.executable == "ffmpeg")
        #expect(manifest.brewFormula == "ffmpeg")
        #expect(manifest.tint == .purple)
        #expect(
            manifest.tasks.map(\.id) == [
                "shrink-video", "convert-video", "trim", "extract-audio", "make-gif", "remove-sound",
            ])
    }

    @Test func fieldKindsAndDefaultsAreRead() throws {
        let task = try #require(try loadRepositoryManifest("ffmpeg").task(withID: "shrink-video"))
        #expect(task.field(withID: "input")?.kind == .inputFile(contentTypes: ["public.movie"], allowsMultiple: false))
        #expect(task.field(withID: "input")?.isRequired == true)
        #expect(task.field(withID: "quality")?.kind == .integer(range: 18...34))
        #expect(task.field(withID: "quality")?.defaultValue == .integer(26))
        #expect(task.field(withID: "mute")?.isRequired == false)
        #expect(task.output == OutputRule(template: "{input.stem} small.mp4", location: .nextTo(fieldID: "input")))
    }

    @Test func anOutputIsAFileUnlessItSaysItIsANewFolder() throws {
        let file = try load(minimalManifest())
        let folder = try load(
            minimalManifest(
                task: minimalTask(output: ["template": "{input.stem} pages", "nextTo": "input", "newFolder": true])))
        #expect(file.tasks[0].output?.isNewFolder == false)
        #expect(
            folder.tasks[0].output
                == OutputRule(template: "{input.stem} pages", location: .nextTo(fieldID: "input"), isNewFolder: true))
    }

    @Test func conditionalsWithElseBranchesAreRead() throws {
        let manifest = try load(
            minimalManifest(
                task: minimalTask(
                    fields: [
                        ["id": "input", "label": "File", "kind": "inputFile"],
                        ["id": "loud", "label": "Loud", "kind": "toggle"],
                    ],
                    arguments: [["if": "loud", "then": ["-v"], "else": ["-q"]], "{input}", "{extra}", "{output}"]
                )))
        #expect(
            manifest.tasks[0].arguments[0]
                == .conditional(Condition(fieldID: "loud"), then: [.text("-v")], otherwise: [.text("-q")]))
    }

    @Test func catalogSkipsABadFileButKeepsTheGoodOnes() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "knobs-catalog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONSerialization.data(withJSONObject: minimalManifest()).write(to: folder.appending(path: "good.json"))
        try Data("{ not json".utf8).write(to: folder.appending(path: "bad.json"))

        let catalog = ManifestLoader.loadCatalog(in: folder)

        #expect(catalog.manifests.map(\.id) == ["sample"])
        #expect(catalog.failures.map(\.source) == ["bad.json"])
    }

    @Test func catalogRejectsASecondManifestWithTheSameID() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "knobs-catalog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let data = try JSONSerialization.data(withJSONObject: minimalManifest())
        try data.write(to: folder.appending(path: "a.json"))
        try data.write(to: folder.appending(path: "b.json"))

        let catalog = ManifestLoader.loadCatalog(in: folder)

        #expect(catalog.manifests.count == 1)
        #expect(catalog.failures.first?.source == "b.json")
    }
}
