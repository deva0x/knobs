import Foundation
import KnobsCore
import Testing

@Suite struct ToolLocatorTests {
    @Test func homebrewIsSearchedBeforeTheSystemFolders() {
        let installed: Set = ["/opt/homebrew/bin/tool", "/usr/bin/tool"]
        let locator = ToolLocator(environmentPath: nil, isExecutableFile: { installed.contains($0) })
        #expect(locator.locate("tool")?.path == "/opt/homebrew/bin/tool")
    }

    @Test func relativeLaunchPathFoldersAreIgnored() {
        let locator = ToolLocator(environmentPath: ".:bin:/custom/bin", isExecutableFile: { _ in false })
        #expect(locator.searchPaths.allSatisfy { $0.hasPrefix("/") })
        #expect(locator.searchPaths.contains("/custom/bin"))
    }

    @Test func foldersAreNeverTools() {
        #expect(ToolLocator(environmentPath: nil).locate(".") == nil)
        #expect(ToolLocator(environmentPath: nil).locate("..") == nil)
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

    @Test func aToolInstalledOnlyUnderAnotherNameRunsUnderThatName() {
        let locator = ToolLocator(environmentPath: nil, isExecutableFile: { $0 == "/usr/bin/7z" })
        #expect(locator.resolve(sevenZip()).executable == "7z")
    }

    @Test func thePreferredNameWinsWhenBothAreInstalled() {
        let installed: Set = ["/usr/bin/7z", "/usr/bin/7zz"]
        let locator = ToolLocator(environmentPath: nil, isExecutableFile: { installed.contains($0) })
        #expect(locator.resolve(sevenZip()).executable == "7zz")
    }

    @Test func aToolThatIsNotInstalledKeepsItsPreferredName() {
        let locator = ToolLocator(environmentPath: nil, isExecutableFile: { _ in false })
        #expect(locator.resolve(sevenZip()).executable == "7zz")
    }

    private func sevenZip() -> ToolManifest {
        ToolManifest(
            id: "7zip", name: "7-Zip", summary: "", executable: "7zz", alternativeExecutables: ["7z"],
            brewFormula: "sevenzip", homepage: nil, symbol: "archivebox", tint: .brown, tasks: [])
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

    @Test func numbersThatArentFiniteAreIgnored() throws {
        var parser = try #require(ProgressParser(.percent(pattern: #"(\w+)%"#)))
        #expect(parser.progress(after: "nan%") == nil)
        #expect(parser.progress(after: "inf%") == nil)
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
    #if os(Linux)
        private static let runsOnLinux = true
    #else
        private static let runsOnLinux = false
    #endif

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

    @Test func aBurstOfManyLinesArrivesWholeAndInOrder() async {
        let count = 5_000
        let run = runner.start(
            executable: URL(filePath: "/usr/bin/seq"), arguments: ["1", String(count)], workingDirectory: nil,
            progress: nil)
        let lines = await events(of: run).compactMap { event -> String? in
            if case .line(let text, _) = event { return text }
            return nil
        }
        #expect(lines == (1...count).map(String.init))
    }

    @Test func aHelperThatKeepsTheOutputOpenDoesNotHoldUpTheEnd() async {
        let helperLifetime = Duration.seconds(5)
        let run = runner.start(
            executable: URL(filePath: "/bin/sh"), arguments: ["-c", "/bin/sleep 5 & echo done"],
            workingDirectory: nil, progress: nil)
        let started = ContinuousClock.now
        #expect(await events(of: run) == [.line("done", .standardOutput), .finished(.succeeded)])
        // Ended by the drain timeout after the tool exited, not by the helper closing the pipe. On Linux,
        // Foundation's Process reports the exit only once the helper has exited too (BUG-016).
        let elapsed = ContinuousClock.now - started
        withKnownIssue("BUG-016: on Linux, Process reports the tool's exit only once its helpers exit") {
            #expect(elapsed < helperLifetime)
        } when: {
            Self.runsOnLinux
        }
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
        // Well under the grace period, so SIGTERM stopped it rather than the SIGKILL that follows.
        #expect(ContinuousClock.now - started < ToolRunner.defaultCancelGracePeriod)
    }

    /// The same rule covers Cancel pressed just after a tool exited but before its exit was collected.
    @Test func aToolThatExitsCleanlyAfterCancelHasStillSucceeded() async {
        let run = runner.start(
            executable: URL(filePath: "/bin/sh"),
            arguments: ["-c", "trap 'exit 0' TERM; /bin/sleep 30 >/dev/null 2>&1 & echo ready; wait"],
            workingDirectory: nil, progress: nil)
        var outcome: RunOutcome?
        for await event in run.events {
            switch event {
            case .line("ready", _): run.cancel()
            case .finished(let finished): outcome = finished
            default: break
            }
        }
        #expect(outcome == .succeeded)
    }

    @Test func cancelAlsoStopsChildrenThatIgnoreTheFirstSignal() async throws {
        let quickRunner = ToolRunner(
            environment: ProcessInfo.processInfo.environment, cancelGracePeriod: .milliseconds(200))
        // The child inherits the ignored SIGTERM, so only the group-wide SIGKILL can stop it.
        let run = quickRunner.start(
            executable: URL(filePath: "/bin/sh"), arguments: ["-c", "trap '' TERM; /bin/sleep 30 & echo $!; wait"],
            workingDirectory: nil, progress: nil)
        var childID: pid_t?
        for await event in run.events {
            if case .line(let text, _) = event, childID == nil {
                childID = pid_t(text)
                run.cancel()
            }
        }
        let child = try #require(childID)
        // A killed process lingers as a zombie until launchd collects it, so allow it a moment to disappear.
        var isGone = kill(child, 0) != 0
        for _ in 0..<100 where !isGone {
            try await Task.sleep(for: .milliseconds(20))
            isGone = kill(child, 0) != 0
        }
        #expect(isGone)
    }

    @Test func progressEventsFollowTheLinesThatReportThem() async {
        let run = runner.start(
            executable: URL(filePath: "/bin/echo"), arguments: ["50%"], workingDirectory: nil,
            progress: .percent(pattern: #"(\d+)%"#))
        #expect(await events(of: run) == [.line("50%", .standardOutput), .progress(0.5), .finished(.succeeded)])
    }

    @Test func standardErrorIsCapturedSeparately() async {
        let run = runner.start(
            executable: URL(filePath: "/bin/sh"), arguments: ["-c", "echo oops >&2; exit 1"], workingDirectory: nil,
            progress: nil)
        let events = await events(of: run)
        #expect(events.contains { if case .line(_, .standardError) = $0 { true } else { false } })
        #expect(events.last == .finished(.failed(exitCode: 1)))
    }
}
