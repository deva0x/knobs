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
                "-c:v", "h264", "-preset", "medium", "-crf", "26",
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

    @Test func ghostscriptGetsPercentSignsDoubledInItsOutputPath() throws {
        let manifest = try loadRepositoryManifest("ghostscript")
        for task in manifest.tasks {
            let fileField = try #require(task.fields.first { if case .inputFile = $0.kind { true } else { false } })
            let draft = builder().build(
                task, of: manifest, values: [fileField.id: .paths(["/a/50%d off.pdf"])], extraArguments: "")
            let outputPath = try #require(draft.command.outputPath)
            #expect(outputPath.contains("50%d off"))
            #expect(draft.command.argv.contains("-sOutputFile=" + outputPath.replacing("%", with: "%%")))
        }
    }

    @Test func qpdfRotatesEveryPageUnlessPagesAreListed() throws {
        let manifest = try loadRepositoryManifest("qpdf")
        let task = try #require(manifest.task(withID: "rotate-pages"))

        let everyPage = builder().build(
            task, of: manifest, values: ["input": .paths(["/a/scan.pdf"])], extraArguments: "")
        let somePages = builder().build(
            task, of: manifest, values: ["input": .paths(["/a/scan.pdf"]), "pages": .text("1-2")], extraArguments: "")

        #expect(everyPage.command.argv == ["--warning-exit-0", "--rotate=+90", "/a/scan.pdf", "/a/scan rotated.pdf"])
        #expect(somePages.command.argv[1] == "--rotate=+90:1-2")
    }

    @Test func qpdfPicksPagesFromTheInputInTheGivenOrder() throws {
        let manifest = try loadRepositoryManifest("qpdf")
        let task = try #require(manifest.task(withID: "pick-pages"))

        let draft = builder().build(
            task, of: manifest, values: ["input": .paths(["/a/scan.pdf"]), "pages": .text("3,1-2")], extraArguments: "")

        #expect(
            draft.command.argv == [
                "--warning-exit-0", "/a/scan.pdf", "--pages", ".", "3,1-2", "--", "/a/scan pages.pdf",
            ])
    }

    @Test func qpdfSplitsIntoANewFolderNamedAfterThePDF() throws {
        let manifest = try loadRepositoryManifest("qpdf")
        let task = try #require(manifest.task(withID: "split"))
        let input: [String: FieldValue] = ["input": .paths(["/a/report.pdf"])]

        let onePerPage = builder().build(task, of: manifest, values: input, extraArguments: "").command
        let twoPerFile = builder(existingFiles: ["/a/report split"]).build(
            task, of: manifest, values: input.merging(["pagesPerFile": .integer(2)]) { $1 }, extraArguments: ""
        ).command

        #expect(task.output?.isNewFolder == true)
        #expect(
            onePerPage.argv == ["--warning-exit-0", "--split-pages=1", "/a/report.pdf", "/a/report split/report.pdf"])
        #expect(onePerPage.outputPath == "/a/report split")
        #expect(twoPerFile.argv[1] == "--split-pages=2")
        #expect(twoPerFile.outputPath == "/a/report split 2")
    }

    @Test func qpdfProtectsWithTheSamePasswordForOpeningAndChanging() throws {
        let manifest = try loadRepositoryManifest("qpdf")
        let task = try #require(manifest.task(withID: "protect"))

        let command = builder().build(
            task, of: manifest, values: ["input": .paths(["/a/deed.pdf"]), "password": .text("hunter2")],
            extraArguments: ""
        ).command

        #expect(
            command.argv == [
                "--warning-exit-0", "--encrypt", "--user-password=hunter2", "--owner-password=hunter2", "--bits=256",
                "--", "/a/deed.pdf", "/a/deed locked.pdf",
            ])
        #expect(!command.displayString.contains("hunter2"))
    }

    @Test func img2pdfKeepsTheImagesInTheOrderTheyWereAdded() throws {
        let manifest = try loadRepositoryManifest("img2pdf")
        let task = try #require(manifest.task(withID: "images-to-pdf"))
        let images: [String: FieldValue] = ["images": .paths(["/a/receipt 2.jpg", "/a/receipt 1.png"])]

        let sameSize = builder().build(task, of: manifest, values: images, extraArguments: "").command
        let onA4 = builder().build(
            task, of: manifest, values: images.merging(["pageSize": .text("A4")]) { $1 }, extraArguments: ""
        ).command

        #expect(
            sameSize.argv == [
                "--rotation=ifvalid", "-o", "/a/receipt 2.pdf", "/a/receipt 2.jpg", "/a/receipt 1.png",
            ])
        #expect(onA4.argv.prefix(3) == ["--pagesize", "A4", "--rotation=ifvalid"])
    }

    /// pdftoppm adds the extension itself, so it gets the output path without one.
    @Test func pdftoppmGetsTheOutputNameWithoutItsExtension() throws {
        let manifest = try loadRepositoryManifest("pdftoppm")
        let task = try #require(manifest.task(withID: "page-to-image"))
        let page: [String: FieldValue] = ["input": .paths(["/a/slides.pdf"]), "page": .integer(3)]

        let png = builder().build(task, of: manifest, values: page, extraArguments: "").command
        let jpeg = builder().build(
            task, of: manifest, values: page.merging(["format": .text("jpg")]) { $1 }, extraArguments: ""
        ).command

        #expect(
            png.argv == [
                "-png", "-r", "150", "-f", "3", "-l", "3", "-singlefile", "/a/slides.pdf", "/a/slides page 3",
            ])
        #expect(png.outputPath == "/a/slides page 3.png")
        #expect(jpeg.argv.first == "-jpeg")
        #expect(jpeg.argv.last == "/a/slides page 3")
        #expect(jpeg.outputPath == "/a/slides page 3.jpg")
    }

    /// pdftoppm names every page itself, `page-1.png` and on, inside the new folder that Knobs makes.
    @Test func pdftoppmWritesEveryPageIntoANewFolder() throws {
        let manifest = try loadRepositoryManifest("pdftoppm")
        let task = try #require(manifest.task(withID: "every-page-to-images"))
        let input: [String: FieldValue] = ["input": .paths(["/a/slides.pdf"])]

        let png = builder().build(task, of: manifest, values: input, extraArguments: "").command
        let jpeg = builder(existingFiles: ["/a/slides pages"]).build(
            task, of: manifest, values: input.merging(["format": .text("jpg"), "resolution": .text("300")]) { $1 },
            extraArguments: ""
        ).command

        #expect(task.output?.isNewFolder == true)
        #expect(png.argv == ["-png", "-r", "150", "/a/slides.pdf", "/a/slides pages/page"])
        #expect(png.outputPath == "/a/slides pages")
        #expect(jpeg.argv == ["-jpeg", "-r", "300", "/a/slides.pdf", "/a/slides pages 2/page"])
        #expect(jpeg.outputPath == "/a/slides pages 2")
    }

    @Test func pdftotextKeepsTheLayoutUnlessTurnedOff() throws {
        let manifest = try loadRepositoryManifest("pdftotext")
        let task = try #require(manifest.task(withID: "pdf-to-text"))
        let input: [String: FieldValue] = ["input": .paths(["/a/lease.pdf"])]

        let laidOut = builder().build(task, of: manifest, values: input, extraArguments: "").command
        let flowing = builder().build(
            task, of: manifest, values: input.merging(["layout": .toggle(false)]) { $1 }, extraArguments: ""
        ).command

        #expect(laidOut.argv == ["-layout", "-enc", "UTF-8", "/a/lease.pdf", "/a/lease.txt"])
        #expect(flowing.argv == ["-enc", "UTF-8", "/a/lease.pdf", "/a/lease.txt"])
    }

    @Test func outputNameNeverEndsOrStartsWithADot() throws {
        let manifest = try load(
            minimalManifest(
                task: minimalTask(output: ["template": "{input.stem} clean.{input.ext}", "nextTo": "input"]))
        )

        let draft = builder().build(
            manifest.tasks[0], of: manifest, values: ["input": .paths(["/a/.profile"])], extraArguments: "")

        #expect(draft.command.outputPath == "/a/profile clean")
    }

    @Test func emptyOutputNameBlocksRunning() throws {
        let fields: [[String: Any]] = [
            ["id": "input", "label": "File", "kind": "inputFile"],
            ["id": "name", "label": "Name", "kind": "text", "required": false],
        ]
        let manifest = try load(
            minimalManifest(
                task: minimalTask(fields: fields, output: ["template": "{name}", "nextTo": "input"])))

        let draft = builder(existingFiles: ["/a"]).build(
            manifest.tasks[0], of: manifest, values: ["input": .paths(["/a/x.txt"])], extraArguments: "")

        #expect(draft.problems.contains(.outputUnavailable("/a")))
        #expect(!draft.isRunnable)
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
            // Required, as in 7-Zip's "Create a password-protected archive", which is what makes "-p{password}" valid.
            ["id": "password", "label": "Password", "kind": "secret", "required": true],
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
