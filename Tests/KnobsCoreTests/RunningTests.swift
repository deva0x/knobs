import Foundation
import KnobsCore
import Testing

@Suite struct ToolLocatorTests {
    @Test func homebrewIsSearchedBeforeTheSystemFolders() {
        let installed: Set = ["/opt/homebrew/bin/tool", "/usr/bin/tool"]
        let locator = ToolLocator(environmentPath: nil, isExecutableFile: { installed.contains($0) })
        #expect(locator.locate("tool")?.path == "/opt/homebrew/bin/tool")
    }

    @Test func launchPathFoldersAreSearchedLastWithoutDuplicates() {
        let locator = ToolLocator(
            environmentPath: "/custom/bin:/usr/bin:", isExecutableFile: { $0 == "/custom/bin/tool" })
        #expect(locator.locate("tool")?.path == "/custom/bin/tool")
        #expect(locator.searchPaths.last == "/custom/bin")
        #expect(locator.searchPaths.filter { $0 == "/usr/bin" }.count == 1)
    }

    @Test func missingToolIsNil() {
        #expect(ToolLocator(environmentPath: nil, isExecutableFile: { _ in false }).locate("tool") == nil)
    }

    @Test func pathsAreNeverAcceptedAsNames() {
        let locator = ToolLocator(environmentPath: nil, isExecutableFile: { _ in true })
        #expect(locator.locate("../evil") == nil)
        #expect(locator.locate("") == nil)
    }

    @Test func environmentForToolsUsesTheLocatorsPath() {
        let locator = ToolLocator(environmentPath: nil, isExecutableFile: { _ in false })
        let environment = ToolRunner.environment(base: ["PATH": "/usr/bin", "HOME": "/Users/me"], locator: locator)
        #expect(environment["PATH"] == locator.pathEnvironmentValue)
        #expect(environment["HOME"] == "/Users/me")
    }
}

@Suite struct ProgressParserTests {
    @Test func percentIsReadAsAFraction() throws {
        var parser = try #require(ProgressParser(.percent(pattern: #"(\d+(?:\.\d+)?)%"#)))
        #expect(parser.progress(after: "[download]  42.5% of 10MiB") == 0.425)
        #expect(parser.progress(after: "no numbers here") == nil)
    }

    @Test func elapsedTimeIsDividedByTheTotalSeenEarlier() throws {
        let hms = #"(\d+):(\d+):(\d+(?:\.\d+)?)"#
        var parser = try #require(
            ProgressParser(.elapsedOfTotal(currentPattern: "time=" + hms, totalPattern: "Duration: " + hms)))
        #expect(parser.progress(after: "frame=1 time=00:00:01.00") == nil)  // no total yet
        #expect(parser.progress(after: "  Duration: 00:01:40.00, start: 0") == nil)
        #expect(parser.progress(after: "frame=9 time=00:00:25.00 bitrate=1") == 0.25)
    }

    @Test func progressNeverLeavesZeroToOne() throws {
        var parser = try #require(ProgressParser(.percent(pattern: #"(\d+)%"#)))
        #expect(parser.progress(after: "150%") == 1)
    }

    @Test func badPatternGivesNoParser() {
        #expect(ProgressParser(.percent(pattern: "(")) == nil)
    }
}

@Suite struct OutputLogTests {
    @Test func keepsOnlyTheNewestLines() {
        var log = OutputLog(lineLimit: 3)
        for number in 1...5 { log.append("line \(number)", from: .standardOutput) }
        #expect(log.lines.map(\.text) == ["line 3", "line 4", "line 5"])
        #expect(log.droppedLineCount == 2)
        #expect(Set(log.lines.map(\.id)).count == 3)
    }

    @Test func clipsVeryLongLines() {
        var log = OutputLog()
        log.append(String(repeating: "x", count: OutputLog.maximumLineLength + 10), from: .standardError)
        #expect(log.lines[0].text.count == OutputLog.maximumLineLength + 1)
    }

    @Test func picksTheLastErrorLikeLineForTheFailureCard() {
        var log = OutputLog()
        log.append("Input #0, mov", from: .standardError)
        log.append("holiday.mov: No such file or directory", from: .standardError)
        log.append("   ", from: .standardError)
        #expect(log.mostRelevantErrorLine == "holiday.mov: No such file or directory")
    }
}

/// Runs small system programs, so these tests use real processes but no third-party tools.
@Suite struct ToolRunnerTests {
    private let runner = ToolRunner(environment: ProcessInfo.processInfo.environment)

    private func events(of run: ToolRun) async -> [RunEvent] {
        var events: [RunEvent] = []
        for await event in run.events { events.append(event) }
        return events
    }

    @Test func outputLinesArriveInOrderFollowedBySuccess() async {
        let run = runner.start(
            executable: URL(filePath: "/bin/echo"), arguments: ["one two", "three"], workingDirectory: nil,
            progress: nil)
        let events = await events(of: run)
        #expect(events == [.line("one two three", .standardOutput), .finished(.succeeded)])
    }

    @Test func argumentsArePassedVerbatimWithoutAShell() async {
        let run = runner.start(
            executable: URL(filePath: "/bin/echo"), arguments: ["$HOME; echo hacked"], workingDirectory: nil,
            progress: nil)
        let events = await events(of: run)
        #expect(events.first == .line("$HOME; echo hacked", .standardOutput))
    }

    @Test func nonZeroExitIsAFailureWithItsCode() async {
        let run = runner.start(
            executable: URL(filePath: "/usr/bin/false"), arguments: [], workingDirectory: nil, progress: nil)
        #expect(await events(of: run).last == .finished(.failed(exitCode: 1)))
    }

    @Test func missingExecutableCouldNotStart() async {
        let run = runner.start(
            executable: URL(filePath: "/nonexistent/tool"), arguments: [], workingDirectory: nil, progress: nil)
        guard case .finished(.couldNotStart)? = await events(of: run).last else {
            Issue.record("expected couldNotStart")
            return
        }
    }

    @Test func cancelStopsALongRunningTool() async {
        let run = runner.start(
            executable: URL(filePath: "/bin/sleep"), arguments: ["30"], workingDirectory: nil, progress: nil)
        let started = ContinuousClock.now
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            run.cancel()
        }
        #expect(await events(of: run).last == .finished(.cancelled))
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    @Test func progressEventsFollowTheLinesThatReportThem() async {
        let run = runner.start(
            executable: URL(filePath: "/bin/echo"), arguments: ["50%"], workingDirectory: nil,
            progress: .percent(pattern: #"(\d+)%"#))
        #expect(await events(of: run) == [.line("50%", .standardOutput), .progress(0.5), .finished(.succeeded)])
    }

    @Test func standardErrorIsCapturedSeparately() async {
        let run = runner.start(
            executable: URL(filePath: "/bin/ls"), arguments: ["/definitely/not/here"], workingDirectory: nil,
            progress: nil)
        let events = await events(of: run)
        #expect(events.contains { if case .line(_, .standardError) = $0 { true } else { false } })
        #expect(events.last == .finished(.failed(exitCode: 1)))
    }
}
