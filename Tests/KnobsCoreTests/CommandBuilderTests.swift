import KnobsCore
import Testing

@Suite struct CommandBuilderTests {
    private let video = "/Users/me/Movies/holiday.mov"

    private func shrinkTask() throws -> (ToolManifest, ManifestTask) {
        let manifest = try loadRepositoryManifest("ffmpeg")
        return (manifest, try #require(manifest.task(withID: "shrink-video")))
    }

    @Test func shrinkVideoWithDefaultsBuildsTheExpectedArgv() throws {
        let (manifest, task) = try shrinkTask()

        let draft = builder().build(task, of: manifest, values: ["input": .paths([video])], extraArguments: "")

        #expect(draft.isRunnable)
        #expect(
            draft.command.argv == [
                "-hide_banner", "-nostdin", "-i", video,
                "-vf", "scale='min(1280,iw)':-2",
                "-c:v", "libx264", "-preset", "medium", "-crf", "26",
                "-c:a", "aac", "-b:a", "128k",
                "-movflags", "+faststart",
                "/Users/me/Movies/holiday small.mp4",
            ])
        #expect(draft.command.outputPath == "/Users/me/Movies/holiday small.mp4")
    }

    @Test func conditionalsFollowTheUsersChoices() throws {
        let (manifest, task) = try shrinkTask()
        let values: [String: FieldValue] = [
            "input": .paths([video]), "size": .text(""), "quality": .integer(20), "mute": .toggle(true),
        ]

        let argv = builder().build(task, of: manifest, values: values, extraArguments: "").command.argv

        #expect(!argv.contains("-vf"))
        #expect(argv.contains("-an"))
        #expect(!argv.contains("aac"))
        #expect(argv[argv.firstIndex(of: "-crf")! + 1] == "20")
    }

    @Test func aHostileFileNameStaysOneArgument() throws {
        let (manifest, task) = try shrinkTask()
        let hostile = "/tmp/my video; rm -rf ~ $(whoami) 'x\".mov"

        let argv = builder().build(task, of: manifest, values: ["input": .paths([hostile])], extraArguments: "")
            .command.argv

        #expect(argv.contains(hostile))
        #expect(argv.filter { $0.contains("rm -rf") }.count == 2)  // the input and the derived output, each whole
    }

    @Test func extraArgumentsAreInsertedWhereTheManifestPutsThem() throws {
        let (manifest, task) = try shrinkTask()

        let argv = builder().build(
            task, of: manifest, values: ["input": .paths([video])], extraArguments: #"-metadata title="Our trip""#
        ).command.argv

        #expect(argv.suffix(3) == ["-metadata", "title=Our trip", "/Users/me/Movies/holiday small.mp4"])
    }

    @Test func unbalancedExtraArgumentsArePreviewedButBlockRunning() throws {
        let (manifest, task) = try shrinkTask()

        let draft = builder().build(task, of: manifest, values: ["input": .paths([video])], extraArguments: "-x \"open")

        #expect(!draft.isRunnable)
        #expect(draft.problems == [.extraArguments(.unclosedQuote("\""))])
        #expect(draft.command.arguments.contains(CommandPart(text: "-x \"open", role: .extra)))
    }

    @Test func missingRequiredFileShowsItsLabelAndBlocksRunning() throws {
        let (manifest, task) = try shrinkTask()

        let draft = builder().build(task, of: manifest, values: [:], extraArguments: "")

        #expect(!draft.isRunnable)
        #expect(draft.problems == [.missingValue(fieldID: "input", label: "Video")])
        #expect(draft.command.arguments.contains(CommandPart(text: "Video", role: .missing)))
        #expect(draft.command.displayString.contains("‹Video›"))
    }

    @Test func existingOutputGetsANumberInsteadOfBeingOverwritten() throws {
        let (manifest, task) = try shrinkTask()
        let taken: Set<String> = ["/Users/me/Movies/holiday small.mp4", "/Users/me/Movies/holiday small 2.mp4"]

        let draft = builder(existingFiles: taken).build(
            task, of: manifest, values: ["input": .paths([video])], extraArguments: "")

        #expect(draft.command.outputPath == "/Users/me/Movies/holiday small 3.mp4")
        #expect(draft.command.argv.last == "/Users/me/Movies/holiday small 3.mp4")
    }

    @Test func extensionPartKeepsTheInputsFormat() throws {
        let manifest = try loadRepositoryManifest("ffmpeg")
        let task = try #require(manifest.task(withID: "trim"))

        let draft = builder().build(
            task, of: manifest, values: ["input": .paths(["/a/clip.mkv"]), "end": .text("10")], extraArguments: "")

        #expect(draft.command.outputPath == "/a/clip trimmed.mkv")
        #expect(draft.command.argv.prefix(6) == ["-hide_banner", "-nostdin", "-ss", "00:00:00", "-to", "10"])
    }

    @Test func emptyOptionalTextLeavesItsConditionalOut() throws {
        let manifest = try loadRepositoryManifest("ffmpeg")
        let task = try #require(manifest.task(withID: "trim"))

        let argv = builder().build(task, of: manifest, values: ["input": .paths(["/a/clip.mkv"])], extraArguments: "")
            .command.argv

        #expect(!argv.contains("-to"))
    }

    @Test func multipleFilesExpandToOneArgumentEach() throws {
        let fields: [[String: Any]] = [
            ["id": "pages", "label": "PDFs", "kind": "inputFile", "multiple": true],
            ["id": "folder", "label": "Save in", "kind": "outputFolder"],
        ]
        let manifest = try load(
            minimalManifest(
                task: minimalTask(
                    fields: fields, arguments: ["-o", "{output}", "{pages}", "{extra}"],
                    output: ["template": "merged.pdf", "folder": "folder"])))

        let argv = builder().build(
            manifest.tasks[0], of: manifest,
            values: ["pages": .paths(["/a/1.pdf", "/a/2 two.pdf"]), "folder": .paths(["/out"])], extraArguments: ""
        ).command.argv

        #expect(argv == ["-o", "/out/merged.pdf", "/a/1.pdf", "/a/2 two.pdf"])
    }

    @Test func equalsConditionsPickTheBranchForTheChosenOption() throws {
        let fields: [[String: Any]] = [
            ["id": "input", "label": "File", "kind": "inputFile"],
            [
                "id": "mode", "label": "Mode", "kind": "choice", "default": "crop",
                "options": [["value": "crop", "label": "Crop"], ["value": "pad", "label": "Pad"]],
            ],
        ]
        let manifest = try load(
            minimalManifest(
                task: minimalTask(
                    fields: fields,
                    arguments: [
                        "{input}", ["if": "mode", "equals": "pad", "then": ["-extent"], "else": ["-crop"]], "{extra}",
                        "{output}",
                    ])))
        let input: [String: FieldValue] = ["input": .paths(["/a/x.png"])]

        let cropped = builder().build(manifest.tasks[0], of: manifest, values: input, extraArguments: "")
        let padded = builder().build(
            manifest.tasks[0], of: manifest, values: input.merging(["mode": .text("pad")]) { $1 }, extraArguments: "")

        #expect(cropped.command.argv.contains("-crop"))
        #expect(padded.command.argv.contains("-extent"))
    }

    @Test func outputPathPartsAndFolderDefaultsWithTilde() throws {
        let fields: [[String: Any]] = [
            ["id": "input", "label": "File", "kind": "inputFile"],
            ["id": "folder", "label": "Save in", "kind": "outputFolder", "default": "~/Downloads"],
        ]
        let manifest = try load(
            minimalManifest(
                task: minimalTask(
                    fields: fields, arguments: ["-of", "{output.base}", "{input}", "{extra}"],
                    output: ["template": "{input.stem} transcript.txt", "folder": "folder"])))

        let draft = builder().build(
            manifest.tasks[0], of: manifest, values: ["input": .paths(["/a/talk.wav"])], extraArguments: "")

        #expect(draft.command.outputPath == "/Users/me/Downloads/talk transcript.txt")
        #expect(draft.command.argv.prefix(2) == ["-of", "/Users/me/Downloads/talk transcript"])
    }

    @Test func outputNextToSeveralFilesGoesNextToTheFirst() throws {
        let fields: [[String: Any]] = [["id": "pages", "label": "PDFs", "kind": "inputFile", "multiple": true]]
        let manifest = try load(
            minimalManifest(
                task: minimalTask(
                    fields: fields, arguments: ["-o", "{output}", "{pages}", "{extra}"],
                    output: ["template": "{pages.stem} merged.pdf", "nextTo": "pages"])))

        let draft = builder().build(
            manifest.tasks[0], of: manifest, values: ["pages": .paths(["/a/one.pdf", "/b/two.pdf"])], extraArguments: ""
        )

        #expect(draft.command.outputPath == "/a/one merged.pdf")
    }

    @Test func secretsRunForRealButAreMaskedInThePreview() throws {
        let fields: [[String: Any]] = [
            ["id": "input", "label": "File", "kind": "inputFile"],
            ["id": "password", "label": "Password", "kind": "secret"],
        ]
        let manifest = try load(
            minimalManifest(
                task: minimalTask(fields: fields, arguments: ["-p{password}", "{input}", "{extra}", "{output}"])))

        let command = builder().build(
            manifest.tasks[0], of: manifest, values: ["input": .paths(["/a/x.txt"]), "password": .text("hunter2")],
            extraArguments: ""
        ).command

        #expect(command.argv.first == "-phunter2")
        #expect(!command.displayString.contains("hunter2"))
        #expect(command.displayString.contains(CommandPart.secretMask))
    }

    @Test func partsAreTaggedForColoring() throws {
        let (manifest, task) = try shrinkTask()

        let parts = builder().build(task, of: manifest, values: ["input": .paths([video])], extraArguments: "-y")
            .command.arguments

        #expect(parts.first == CommandPart(text: "-hide_banner", role: .flag))
        #expect(parts.contains(CommandPart(text: video, role: .path)))
        #expect(parts.contains(CommandPart(text: "26", role: .value)))
        #expect(parts.contains(CommandPart(text: "-y", role: .extra)))
    }

    @Test func displayStringQuotesForTheShell() throws {
        let (manifest, task) = try shrinkTask()

        let display = builder().build(
            task, of: manifest, values: ["input": .paths(["/a/my clip.mov"])], extraArguments: ""
        )
        .command.displayString

        #expect(
            display.hasPrefix("ffmpeg -hide_banner -nostdin -i '/a/my clip.mov' -vf 'scale='\\''min(1280,iw)'\\'':-2'"))
    }
}
