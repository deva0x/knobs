import Foundation
import KnobsCore
import Testing

/// Every rule in "Validation errors" of docs/MANIFEST_FORMAT.md, each failing with a precise path.
@Suite struct ManifestValidationTests {
    @Test func theMinimalFixtureIsValid() throws {
        _ = try load(minimalManifest())
    }

    @Test func invalidJSONNamesTheFile() {
        #expect(throws: ManifestError.self) { try ManifestLoader.load(Data("{".utf8), source: "broken.json") }
    }

    @Test func unknownTopLevelKeyIsRejected() {
        var manifest = minimalManifest()
        manifest["colour"] = "red"
        let error = loadingError(manifest)
        #expect(error?.path == "colour")
        #expect(error?.problem.contains("isn't a known key") == true)
    }

    @Test func unknownKeyForAFieldKindIsRejected() {
        let task = minimalTask(fields: [["id": "input", "label": "File", "kind": "inputFile", "minimum": 1]])
        #expect(loadingError(minimalManifest(task: task))?.path == "tasks[0].fields[0].minimum")
    }

    @Test func wrongTypeNamesWhatWasExpected() {
        var manifest = minimalManifest()
        manifest["name"] = 42
        let error = loadingError(manifest)
        #expect(error?.path == "name")
        #expect(error?.problem == "should be a string, not a whole number")
    }

    @Test func missingRequiredKeyIsReported() {
        var manifest = minimalManifest()
        manifest.removeValue(forKey: "symbol")
        #expect(loadingError(manifest)?.path == "symbol")
    }

    @Test func otherSchemaVersionsAreRejected() {
        var manifest = minimalManifest()
        manifest["schemaVersion"] = 2
        #expect(loadingError(manifest)?.path == "schemaVersion")
    }

    @Test func unknownTintIsRejected() {
        var manifest = minimalManifest()
        manifest["tint"] = "chartreuse"
        #expect(loadingError(manifest)?.path == "tint")
    }

    @Test func executableMustNotBeAPath() {
        var manifest = minimalManifest()
        manifest["executable"] = "/usr/bin/sample"
        #expect(loadingError(manifest)?.path == "executable")
    }

    @Test func toolIDMustBeLowercaseWithDashes() {
        var manifest = minimalManifest()
        manifest["id"] = "Sample Tool"
        #expect(loadingError(manifest)?.path == "id")
    }

    @Test func duplicateTaskIDsAreRejected() {
        var manifest = minimalManifest()
        manifest["tasks"] = [minimalTask(), minimalTask()]
        #expect(loadingError(manifest)?.path == "tasks[1].id")
    }

    @Test func duplicateFieldIDsAreRejected() {
        let field: [String: Any] = ["id": "input", "label": "File", "kind": "inputFile"]
        #expect(
            loadingError(minimalManifest(task: minimalTask(fields: [field, field])))?.path == "tasks[0].fields[1].id")
    }

    @Test(arguments: ["extra", "output"])
    func reservedFieldIDsAreRejected(id: String) {
        let fields: [[String: Any]] = [
            ["id": "input", "label": "File", "kind": "inputFile"], ["id": id, "label": "X", "kind": "text"],
        ]
        #expect(loadingError(minimalManifest(task: minimalTask(fields: fields)))?.path == "tasks[0].fields[1].id")
    }

    @Test func unknownFieldKindIsRejected() {
        let task = minimalTask(fields: [["id": "input", "label": "File", "kind": "slider"]])
        #expect(loadingError(minimalManifest(task: task))?.path == "tasks[0].fields[0].kind")
    }

    @Test func integerDefaultOutsideItsRangeIsRejected() {
        let fields: [[String: Any]] = [
            ["id": "input", "label": "File", "kind": "inputFile"],
            ["id": "level", "label": "Level", "kind": "integer", "minimum": 1, "maximum": 9, "default": 10],
        ]
        #expect(loadingError(minimalManifest(task: minimalTask(fields: fields)))?.path == "tasks[0].fields[1].default")
    }

    @Test func integerRangeMustNotBeBackwards() {
        let fields: [[String: Any]] = [
            ["id": "input", "label": "File", "kind": "inputFile"],
            ["id": "level", "label": "Level", "kind": "integer", "minimum": 9, "maximum": 1],
        ]
        #expect(loadingError(minimalManifest(task: minimalTask(fields: fields)))?.path == "tasks[0].fields[1].maximum")
    }

    @Test func choiceDefaultMustBeOneOfTheOptions() {
        let fields: [[String: Any]] = [
            ["id": "input", "label": "File", "kind": "inputFile"],
            [
                "id": "size", "label": "Size", "kind": "choice", "default": "huge",
                "options": [["value": "s", "label": "Small"]],
            ],
        ]
        #expect(loadingError(minimalManifest(task: minimalTask(fields: fields)))?.path == "tasks[0].fields[1].default")
    }

    @Test func choiceNeedsAtLeastOneOption() {
        let fields: [[String: Any]] = [
            ["id": "input", "label": "File", "kind": "inputFile"],
            ["id": "size", "label": "Size", "kind": "choice", "options": [[String: Any]]()],
        ]
        #expect(loadingError(minimalManifest(task: minimalTask(fields: fields)))?.path == "tasks[0].fields[1].options")
    }

    @Test func placeholderForAnUnknownFieldIsRejected() {
        let task = minimalTask(arguments: ["{input}", "{nope}", "{extra}", "{output}"])
        let error = loadingError(minimalManifest(task: task))
        #expect(error?.path == "tasks[0].arguments[1]")
        #expect(error?.problem.contains("{nope}") == true)
    }

    @Test func conditionalOnAnUnknownFieldIsRejected() {
        let task = minimalTask(arguments: [["if": "nope", "then": ["-x"]], "{input}", "{extra}", "{output}"])
        #expect(loadingError(minimalManifest(task: task))?.path == "tasks[0].arguments[0].if")
    }

    @Test func pathPartsOnlyWorkOnFileFields() {
        let fields: [[String: Any]] = [
            ["id": "input", "label": "File", "kind": "inputFile"], ["id": "name", "label": "Name", "kind": "text"],
        ]
        let task = minimalTask(fields: fields, arguments: ["{input}", "{name.stem}", "{extra}", "{output}"])
        #expect(loadingError(minimalManifest(task: task))?.path == "tasks[0].arguments[1]")
    }

    @Test func unknownPathPartIsRejected() {
        let task = minimalTask(arguments: ["{input.folder}", "{extra}", "{output}"])
        #expect(loadingError(minimalManifest(task: task))?.problem.contains(".folder") == true)
    }

    @Test func unbalancedBracesAreRejected() {
        let task = minimalTask(arguments: ["{input", "{extra}", "{output}"])
        #expect(loadingError(minimalManifest(task: task))?.path == "tasks[0].arguments[0]")
    }

    @Test func extraMustAppearExactlyOnce() {
        let none = minimalTask(arguments: ["{input}", "{output}"])
        let twice = minimalTask(arguments: ["{input}", "{extra}", "{extra}", "{output}"])
        #expect(loadingError(minimalManifest(task: none))?.path == "tasks[0].arguments")
        #expect(loadingError(minimalManifest(task: twice))?.path == "tasks[0].arguments")
    }

    @Test func extraMustBeAListItemOfItsOwn() {
        let task = minimalTask(arguments: ["{input}", "--opts={extra}", "{output}"])
        #expect(loadingError(minimalManifest(task: task))?.path == "tasks[0].arguments[1]")
    }

    @Test func outputPlaceholderNeedsAnOutputRule() {
        let task = minimalTask(arguments: ["{input}", "{extra}", "{output}"], output: nil)
        #expect(loadingError(minimalManifest(task: task))?.problem.contains("no output rule") == true)
    }

    @Test func outputRuleMustBeUsed() {
        let task = minimalTask(arguments: ["{input}", "{extra}"])
        #expect(loadingError(minimalManifest(task: task))?.path == "tasks[0].output")
    }

    @Test func outputNextToMustNameAFileField() {
        let task = minimalTask(output: ["template": "out.txt", "nextTo": "missing"])
        #expect(loadingError(minimalManifest(task: task))?.path == "tasks[0].output.nextTo")
    }

    @Test func outputNeedsExactlyOneLocation() {
        let task = minimalTask(output: ["template": "out.txt"])
        #expect(loadingError(minimalManifest(task: task))?.path == "tasks[0].output")
    }

    @Test func multiFileFieldMustBeAListItemOfItsOwn() {
        let fields: [[String: Any]] = [
            ["id": "input", "label": "File", "kind": "inputFile"],
            ["id": "pages", "label": "Pages", "kind": "inputFile", "multiple": true],
        ]
        let task = minimalTask(fields: fields, arguments: ["{input}", "--add={pages}", "{extra}", "{output}"])
        #expect(loadingError(minimalManifest(task: task))?.path == "tasks[0].arguments[1]")
    }

    @Test func progressPatternMustCompile() {
        var task = minimalTask()
        task["progress"] = ["percent": "(unclosed"]
        #expect(loadingError(minimalManifest(task: task))?.path == "tasks[0].progress.percent")
    }

    @Test func percentPatternNeedsOneCaptureGroup() {
        var task = minimalTask()
        task["progress"] = ["percent": "\\d+%"]
        #expect(loadingError(minimalManifest(task: task))?.path == "tasks[0].progress.percent")
    }

    @Test func errorDescriptionNamesFilePathAndProblem() {
        let error = ManifestError(source: "x.json", path: "tasks[0].id", problem: "is missing")
        #expect(error.localizedDescription == "x.json at tasks[0].id: is missing")
    }
}
