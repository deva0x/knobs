import Foundation
import KnobsCore

/// The repository's `Manifests/` folder, found relative to this file so tests run from any directory.
let manifestsDirectory = URL(filePath: #filePath)
    .deletingLastPathComponent()  // Support
    .deletingLastPathComponent()  // KnobsCoreTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // repository root
    .appending(path: "Manifests")

func loadRepositoryManifest(_ id: String) throws -> ToolManifest {
    let file = manifestsDirectory.appending(path: "\(id).json")
    return try ManifestLoader.load(try Data(contentsOf: file), source: file.lastPathComponent)
}

/// A small valid manifest as a JSON object, for tests to tweak one key at a time.
func minimalManifest(task: [String: Any] = minimalTask()) -> [String: Any] {
    [
        "schemaVersion": 1,
        "id": "sample",
        "name": "Sample",
        "summary": "A sample tool.",
        "executable": "sample",
        "install": ["brew": "sample"],
        "symbol": "star",
        "tint": "purple",
        "tasks": [task],
    ]
}

func minimalTask(
    fields: [[String: Any]] = [["id": "input", "label": "File", "kind": "inputFile"]],
    arguments: [Any] = ["{input}", "{extra}", "{output}"],
    output: [String: Any]? = ["template": "{input.stem} out.txt", "nextTo": "input"]
) -> [String: Any] {
    var task: [String: Any] = [
        "id": "do-it",
        "title": "Do it",
        "summary": "Does it.",
        "symbol": "star",
        "fields": fields,
        "arguments": arguments,
    ]
    task["output"] = output
    return task
}

func load(_ object: [String: Any]) throws(ManifestError) -> ToolManifest {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return try ManifestLoader.load(data, source: "sample.json")
}

/// Expects loading to fail and returns the error, so a test can check its path and wording.
func loadingError(_ object: [String: Any]) -> ManifestError? {
    do {
        _ = try load(object)
        return nil
    } catch {
        return error
    }
}

/// A builder whose disk holds exactly `existingFiles`.
func builder(existingFiles: Set<String> = []) -> CommandBuilder {
    CommandBuilder(outputNamer: OutputNamer(fileExists: { existingFiles.contains($0) }), homeDirectory: "/Users/me")
}
