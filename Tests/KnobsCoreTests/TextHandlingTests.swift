import KnobsCore
import Testing

@Suite struct ArgumentSplitterTests {
    @Test(arguments: [
        ("", [String]()),
        ("  -y  ", ["-y"]),
        ("-a b   c", ["-a", "b", "c"]),
        (#"title="Our trip""#, ["title=Our trip"]),
        ("'it''s'", ["its"]),
        (#"'a "b" c'"#, [#"a "b" c"#]),
        (#""say \"hi\"""#, [#"say "hi""#]),
        (#""C:\path""#, [#"C:\path"#]),
        (#"one\ word"#, ["one word"]),
        ("''", [""]),
        ("a\tb\nc", ["a", "b", "c"]),
        ("-a \\\n-b", ["-a", "-b"]),
        ("-a \\\r\n-b", ["-a", "-b"]),
        (#""\$HOME \`x\`""#, ["$HOME `x`"]),
        ("my\u{00A0}file", ["my\u{00A0}file"]),
    ])
    func splitsLikeAShellWithoutRunningOne(input: String, expected: [String]) throws {
        #expect(try ArgumentSplitter.split(input) == expected)
    }

    @Test func unclosedSingleQuoteIsAnError() {
        #expect(throws: ArgumentSplitter.SplitError.unclosedQuote("'")) { try ArgumentSplitter.split("'open") }
    }

    @Test func unclosedDoubleQuoteIsAnError() {
        #expect(throws: ArgumentSplitter.SplitError.unclosedQuote("\"")) { try ArgumentSplitter.split("\"open") }
    }

    @Test func trailingBackslashIsAnError() {
        #expect(throws: ArgumentSplitter.SplitError.trailingBackslash) { try ArgumentSplitter.split("end\\") }
    }
}

@Suite struct ShellQuotingTests {
    @Test(arguments: [
        ("-crf", "-crf"),
        ("/Users/me/a.mov", "/Users/me/a.mov"),
        ("", "''"),
        ("my clip.mov", "'my clip.mov'"),
        ("it's", #"'it'\''s'"#),
        ("$(whoami)", "'$(whoami)'"),
        ("=ls", "'=ls'"),
        ("a=b", "a=b"),
    ])
    func quotesOnlyWhatNeedsQuoting(argument: String, expected: String) {
        #expect(ShellQuoting.quote(argument) == expected)
    }

    @Test func quotedTextSplitsBackToTheSameArgument() throws {
        let tricky = ["a b", "it's", "$HOME", #"back\slash"#, "\"q\"", ""]
        let line = tricky.map(ShellQuoting.quote).joined(separator: " ")
        #expect(try ArgumentSplitter.split(line) == tricky)
    }
}

@Suite struct OutputNamerTests {
    @Test func freePathIsUsedAsIs() throws {
        #expect(try OutputNamer(fileExists: { _ in false }).availablePath(for: "/a/out.mp4") == "/a/out.mp4")
    }

    @Test func takenPathGetsTheNextFreeNumber() throws {
        let taken: Set = ["/a/out.mp4", "/a/out 2.mp4"]
        #expect(try OutputNamer(fileExists: { taken.contains($0) }).availablePath(for: "/a/out.mp4") == "/a/out 3.mp4")
    }

    @Test func fileWithoutExtensionGetsANumberToo() throws {
        #expect(try OutputNamer(fileExists: { $0 == "/a/notes" }).availablePath(for: "/a/notes") == "/a/notes 2")
    }

    @Test func givesUpInsteadOfProbingForever() {
        #expect(throws: OutputNamer.NamingError.noFreeName("/a/x.txt")) {
            try OutputNamer(fileExists: { _ in true }).availablePath(for: "/a/x.txt")
        }
    }
}
