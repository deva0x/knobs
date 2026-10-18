import Foundation
import KnobsCore
import Testing

private func fixture(_ name: String) throws -> String {
    let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/help/\(name).txt")
    return try String(contentsOf: url, encoding: .utf8)
}

private func option(_ flag: String, in options: [HelpOption]) -> HelpOption? {
    options.first { $0.flags.contains(flag) }
}

@Suite struct HelpParserTests {
    @Test func shortAndLongSpellingsWithASeparateValue() {
        let options = HelpParser.options(in: "  -o, --output TEMPLATE   Output filename template\n")
        #expect(
            options == [
                HelpOption(
                    flags: ["-o", "--output"], valueName: "TEMPLATE", valueStyle: .separate,
                    summary: "Output filename template")
            ])
        #expect(options.first?.preferredFlag == "--output")
    }

    @Test func wrappedDescriptionsThatStartWithAFlagStayDescriptions() {
        let options = HelpParser.options(
            in: """
                  --skip-text          Skip OCR on any pages that already contain text, unlike
                                       --force-ocr).
                  --force-ocr          Rasterize any text or vector objects on each page
                """)
        #expect(options.map(\.flags) == [["--skip-text"], ["--force-ocr"]])
        #expect(option("--skip-text", in: options)?.summary.hasSuffix("--force-ocr).") == true)
    }

    /// Golden counts for the real help fixtures: a parser change that swallows or invents options shows up here,
    /// not only in the one flag per tool checked below. Update a count only after reading the new parse.
    @Test(arguments: [
        ("7zz", 46), ("curl", 250), ("ffmpeg", 42), ("gs", 7), ("jq", 29), ("magick", 261), ("ocrmypdf", 59),
        ("pandoc", 109), ("rsync", 151), ("whisper-cli", 66), ("yt-dlp", 246),
    ])
    func realHelpTextYieldsTheKnownNumberOfOptions(tool: String, count: Int) throws {
        #expect(HelpParser.options(in: try fixture(tool)).count == count)
    }

    @Test func longOnlyOptionsOnTheirOwnIndentedLineStayOptions() throws {
        let options = HelpParser.options(in: try fixture("pandoc"))
        #expect(option("--data-dir", in: options) != nil)
        #expect(option("--template", in: options) != nil)
        #expect(options.count > 100)
    }

    @Test func optionalBracketsBeforeAValueStillTakeTheValue() {
        let options = HelpParser.options(in: "  -i[r[-|0]]{@listfile|!wildcard} : Include filenames\n")
        #expect(option("-i", in: options)?.valueStyle == .attached)
        #expect(option("-i", in: options)?.valueName != nil)
    }

    @Test func optionsTakingSeveralValuesAreMarked() {
        let options = HelpParser.options(in: "  --arg name value          set $name to value;\n")
        #expect(option("--arg", in: options)?.takesSeveralValues == true)
    }

    @Test func onOffOptionHasNoValue() {
        let option = HelpParser.options(in: "  -y                  overwrite output files").first
        #expect(option?.valueName == nil)
        #expect(option?.summary == "overwrite output files")
    }

    @Test func equalsAndAttachedValuesKeepTheirStyle() {
        let options = HelpParser.options(
            in: """
                --info=FLAGS             fine-grained informational verbosity
                  -o{Directory} : set Output directory
                 -sOutputFile=<file> select output file
                """)
        #expect(option("--info", in: options)?.valueStyle == .equals)
        #expect(option("-o", in: options)?.valueStyle == .attached)
        #expect(option("-o", in: options)?.valueName == "Directory")
        #expect(option("-sOutputFile", in: options)?.valueName == "file")
    }

    @Test func indentedLinesContinueTheDescription() {
        let options = HelpParser.options(
            in: """
                    --use-extractors NAMES          Extractor names to use separated by commas.
                                                    You can also use regexes
                    --list-extractors               List all supported extractors
                """)
        #expect(options.count == 2)
        #expect(options[0].summary == "Extractor names to use separated by commas. You can also use regexes")
    }

    @Test func twoColumnLinesGiveTwoOptions() {
        let options = HelpParser.options(
            in: " -dNOPAUSE           no pause after page   | -q       `quiet', fewer messages")
        #expect(options.map(\.preferredFlag) == ["-dNOPAUSE", "-q"])
    }

    @Test func proseAndDividersAreNotOptions() {
        let options = HelpParser.options(
            in: """
                Usage: tool [OPTIONS] FILE
                ---
                - a bullet point
                -5 is a negative number
                """)
        #expect(options.isEmpty)
    }

    @Test func whisperWidelySpacedSpecsAndBracketedDefaults() throws {
        let options = HelpParser.options(in: try fixture("whisper-cli"))
        let threads = try #require(option("--threads", in: options))
        #expect(threads.flags == ["-t", "--threads"])
        #expect(threads.valueName == "N")
        #expect(threads.summary == "number of threads to use during computation")
    }

    @Test(arguments: [
        ("jq", "--null-input"), ("curl", "--append"), ("yt-dlp", "--output"), ("rsync", "--verbose"),
        ("ffmpeg", "-y"), ("7zz", "-bt"), ("magick", "-adjoin"), ("gs", "-dBATCH"), ("ocrmypdf", "--deskew"),
        ("pandoc", "--standalone"), ("whisper-cli", "--output-file"),
    ])
    func realHelpTextYieldsTheExpectedOption(tool: String, flag: String) throws {
        let options = HelpParser.options(in: try fixture(tool))
        #expect(option(flag, in: options) != nil, "\(tool): \(options.prefix(5).map(\.flags))")
        #expect(options.count >= 5)
        #expect(Set(options.map(\.preferredFlag)).count == options.count)
    }

    @Test func tablesThatRepeatKnownFlagsAreSkipped() {
        let options = HelpParser.options(
            in: """
                    -t, --preset-alias PRESET       Apply a preset
                Preset Aliases:
                    -t mp3                          -f 'ba[acodec^=mp3]/ba/b' -x --audio-format mp3
                """)
        #expect(options.map(\.preferredFlag) == ["--preset-alias"])
    }

    @Test func punctuationIsNotAValueName() {
        let options = HelpParser.options(in: "--help, -h               show this help (* -h is help only on its own)")
        #expect(options.first?.valueName == nil)
    }

    @Test func repeatedValueAndDefaultAreStrippedFromTheSummary() {
        let options = HelpParser.options(
            in: "  -vp N,     --vad-speech-pad-ms N  N [30     ] VAD speech padding (extend segments)")
        #expect(options.first?.summary == "VAD speech padding (extend segments)")
    }

    @Test func optionCountIsCapped() {
        let text = (1...(HelpParser.maximumOptions + 50)).map { "  --option\($0)   does \($0)" }.joined(separator: "\n")
        #expect(HelpParser.options(in: text).count == HelpParser.maximumOptions)
    }
}

@Suite struct HelpTaskBuilderTests {
    private let options = [
        HelpOption(flags: ["-y"], valueName: nil, valueStyle: .separate, summary: "overwrite"),
        HelpOption(flags: ["-o", "--output"], valueName: "FILE", valueStyle: .separate, summary: "output"),
        HelpOption(flags: ["--info"], valueName: "FLAGS", valueStyle: .equals, summary: ""),
        HelpOption(flags: ["-o"], valueName: "Directory", valueStyle: .attached, summary: ""),
    ]

    @Test func passwordsBecomeSecretFields() {
        let generated = HelpTaskBuilder.task(
            from: [HelpOption(flags: ["--video-password"], valueName: "PASSWORD", valueStyle: .separate, summary: "")],
            toolName: "tool")
        #expect(generated.task.fields.first?.kind == .secret)
    }

    @Test func secretValuesAreFoundByTheirValueNameToo() {
        let generated = HelpTaskBuilder.task(
            from: [
                HelpOption(flags: ["-p"], valueName: "Password", valueStyle: .attached, summary: ""),
                HelpOption(flags: ["-u", "--user"], valueName: "user:password", valueStyle: .separate, summary: ""),
                HelpOption(flags: ["--password-file"], valueName: "FILE", valueStyle: .equals, summary: ""),
            ], toolName: "tool")
        #expect(generated.task.fields.map(\.kind).prefix(3) == [.secret, .secret, .text(placeholder: "FILE")])
    }

    @Test func optionsTakingSeveralValuesAreLeftToExtraArguments() {
        let generated = HelpTaskBuilder.task(
            from: [
                HelpOption(
                    flags: ["--arg"], valueName: "name value", valueStyle: .separate, summary: "",
                    takesSeveralValues: true)
            ], toolName: "jq")
        #expect(generated.options.isEmpty)
    }

    @Test func onlySwitchedOnOptionsAppearInTheCommand() throws {
        let generated = HelpTaskBuilder.task(from: options, toolName: "tool")
        let manifest = ToolManifest(
            id: "tool", name: "tool", summary: "", executable: "tool", brewFormula: "tool", homepage: nil,
            symbol: "terminal", tint: .gray, tasks: [generated.task])

        let argv = builder().build(
            generated.task, of: manifest,
            values: [
                "option1": .toggle(true), "option2": .text("out file.txt"), "option3": .text("progress2"),
                "option4": .text("/tmp/x"), "files": .paths(["/a/b.json"]),
            ],
            extraArguments: "-v"
        ).command.argv

        #expect(argv == ["-y", "--output", "out file.txt", "--info=progress2", "-o/tmp/x", "-v", "/a/b.json"])
        #expect(
            builder().build(generated.task, of: manifest, values: [:], extraArguments: "").command.argv.isEmpty)
    }

    @Test func generatedTaskFromRealHelpIsAValidManifest() throws {
        let generated = HelpTaskBuilder.task(from: HelpParser.options(in: try fixture("curl")), toolName: "curl")
        let manifest = ToolManifest(
            id: "curl", name: "curl", summary: "s", executable: "curl", brewFormula: "curl", homepage: nil,
            symbol: "terminal", tint: .gray, tasks: [generated.task])
        #expect(throws: Never.self) { try ManifestLoader.validate(manifest, source: "curl --help") }
        #expect(generated.options.count == generated.task.fields.count - 1)
    }
}
