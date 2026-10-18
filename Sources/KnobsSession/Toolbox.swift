import Foundation
import KnobsCore
import Observation

/// The tools Knobs offers and what it remembers about them: the bundled and added tools, where each is installed,
/// one session per task, the saved library, and each tool's "All options" task. The Mac and Linux apps share it
/// and add only their own windows and navigation.
@MainActor
@Observable
public final class Toolbox {
    /// What "All options" knows about a tool, read from its help text on first visit.
    public enum AllOptionsState: Equatable {
        case loading
        case ready(HelpTaskBuilder.GeneratedTask)
        case unavailable
    }

    /// The bundled tools, each under the name it is installed as (7-Zip as `7z` on Ubuntu), found once at launch.
    public let bundledManifests: [ToolManifest]
    public let manifestFailures: [ManifestError]
    public private(set) var allOptions: [String: AllOptionsState] = [:]
    public private(set) var library: KnobsLibrary
    /// A problem reading or writing the saved settings, in plain words, for the app to show.
    public var libraryProblem: String?

    private var executables: [String: URL] = [:]
    private var sessions: [String: TaskSession] = [:]
    /// False when an unreadable library couldn't be moved aside, so saving would destroy it.
    private var isSavingLibraryAllowed = true
    private let locator: ToolLocator
    private let runner: ToolRunner
    private let libraryFile: LibraryFile
    private let helpReader: HelpReader
    private let now: () -> Date

    /// `isExecutableFile` and `now` are injected so tests can decide what is installed and when things happen.
    public init(
        manifestsDirectory: URL,
        dataDirectory: URL,
        environment: [String: String],
        isExecutableFile: @escaping @Sendable (String) -> Bool = ToolLocator.isExecutableRegularFile,
        now: @escaping () -> Date = Date.init
    ) {
        self.now = now
        libraryFile = LibraryFile(url: dataDirectory.appending(path: "library.json"))
        var problem: String?
        do {
            library = try libraryFile.load()
        } catch let readError {
            // Start fresh, but never by overwriting the old file: keep it beside the new one, or don't save at all.
            library = KnobsLibrary()
            do {
                let kept = try libraryFile.setAside(at: now())
                problem =
                    "Your saved settings couldn't be read (\(readError)), so Knobs started fresh. The old file was kept as \(kept.lastPathComponent)."
            } catch let moveError {
                isSavingLibraryAllowed = false
                problem =
                    "Your saved settings couldn't be read (\(readError)), and couldn't be moved aside (\(moveError)), so Knobs started fresh and won't save over them this session."
            }
        }
        let catalog = ManifestLoader.loadCatalog(in: manifestsDirectory)
        let locator = ToolLocator(environmentPath: environment["PATH"], isExecutableFile: isExecutableFile)
        bundledManifests = catalog.manifests.map(locator.resolve)
        manifestFailures = catalog.failures
        self.locator = locator
        runner = ToolRunner(environment: ToolRunner.environment(base: environment, locator: locator))
        helpReader = HelpReader(runner: runner)
        if let problem { report(problem) }
        refreshAvailability()
    }

    // MARK: Tools

    /// Every tool in the sidebar: the bundled ones, then the ones the user added.
    public var manifests: [ToolManifest] {
        bundledManifests + addedManifests
    }

    public var addedManifests: [ToolManifest] {
        library.addedTools.map(ToolManifest.addedTool(named:))
    }

    public func manifest(withID id: String) -> ToolManifest? {
        manifests.first { $0.id == id }
    }

    public func isInstalled(_ manifest: ToolManifest) -> Bool {
        executables[manifest.id] != nil
    }

    /// Where the copy of the tool that Knobs runs lives, or nil when it isn't installed.
    public func location(of manifest: ToolManifest) -> URL? {
        executables[manifest.id]
    }

    /// Where a tool the user is about to add is installed, or nil when no tool has that name.
    public func locate(_ executable: String) -> URL? {
        locator.locate(executable.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Looks every tool up again, for "Check again" after the user installs one.
    public func refreshAvailability() {
        allOptions = allOptions.filter { $0.value != .unavailable }
        var found: [String: URL] = [:]
        for manifest in manifests {
            found[manifest.id] = locator.locate(manifest.executable)
        }
        executables = found
    }

    /// Adds an installed tool by name and returns its id, or nil when the name is taken, isn't installed, or is a
    /// path.
    public func addTool(named executable: String) -> String? {
        let name = executable.trimmingCharacters(in: .whitespacesAndNewlines)
        guard locate(name) != nil, !manifests.contains(where: { $0.executable == name }),
            library.addTool(named: name)
        else { return nil }
        saveLibrary()
        refreshAvailability()
        return ToolManifest.addedTool(named: name).id
    }

    /// Removing a tool while it runs would leave a run nothing can reach or cancel, so it waits until it stops.
    public func canRemoveTool(_ manifest: ToolManifest) -> Bool {
        manifest.isAddedByUser && !isRunningAnything(of: manifest)
    }

    public func removeTool(_ manifest: ToolManifest) {
        guard canRemoveTool(manifest) else { return }
        sessions = sessions.filter { $0.value.manifest.id != manifest.id }
        allOptions[manifest.id] = nil
        library.removeTool(named: manifest.executable)
        saveLibrary()
    }

    // MARK: Tasks and runs

    /// A manifest task, or the generated "All options" task once its help has been read.
    public func task(withID taskID: String, in manifest: ToolManifest) -> ManifestTask? {
        if taskID == HelpTaskBuilder.taskID, case .ready(let generated)? = allOptions[manifest.id] {
            return generated.task
        }
        return manifest.task(withID: taskID)
    }

    /// Reads the tool's help once and builds its "All options" task. A tool whose help gave no options is tried
    /// again after `refreshAvailability()`.
    public func loadAllOptions(for manifest: ToolManifest) async {
        switch allOptions[manifest.id] {
        case .loading?, .ready?: return
        case .unavailable?, nil: break
        }
        guard let executable = executables[manifest.id] else { return }
        allOptions[manifest.id] = .loading
        let text = await helpReader.helpText(executable: executable, arguments: manifest.helpArguments)
        let options = HelpParser.options(in: text)
        allOptions[manifest.id] =
            options.isEmpty ? .unavailable : .ready(HelpTaskBuilder.task(from: options, toolName: manifest.name))
    }

    public func session(for task: ManifestTask, of manifest: ToolManifest) -> TaskSession {
        let key = KnobsLibrary.key(toolID: manifest.id, taskID: task.id)
        if let session = sessions[key] { return session }
        let session = TaskSession(manifest: manifest, task: task, initialValues: library.lastValues(forTask: key))
        session.onFinish = { [weak self] outcome, outputURL in
            self?.recordRun(of: manifest, task, outcome: outcome, outputURL: outputURL)
        }
        sessions[key] = session
        return session
    }

    /// The session of a task that already has one. It only looks: menus read this while SwiftUI is drawing, when
    /// creating state isn't allowed.
    public func existingSession(forTask key: String) -> TaskSession? {
        sessions[key]
    }

    public var hasRunningTasks: Bool {
        sessions.values.contains(where: \.isRunning)
    }

    /// True while any task of this tool is running, for the sidebar's activity dot.
    public func isRunningAnything(of manifest: ToolManifest) -> Bool {
        sessions.values.contains { $0.manifest.id == manifest.id && $0.isRunning }
    }

    /// Whether Run is available: the tool is installed, the command is complete, and the task isn't running.
    public func canRun(_ session: TaskSession) -> Bool {
        isInstalled(session.manifest) && session.draft.isRunnable && !session.isRunning
    }

    public func run(_ session: TaskSession) {
        guard canRun(session), let executable = executables[session.manifest.id] else { return }
        library.rememberValues(session.rememberableValues, forTask: session.id)
        saveLibrary()
        session.start(executable: executable, runner: runner)
    }

    /// Cancels every run and waits for them to stop, up to the runner's own SIGKILL grace period plus a margin,
    /// so quitting never leaves a tool running on its own.
    public func stopAllRuns() async {
        let running = sessions.values.filter(\.isRunning)
        for session in running { session.cancel() }
        for _ in 0..<Self.stopPollLimit where running.contains(where: \.isRunning) {
            try? await Task.sleep(for: Self.stopPollInterval)
        }
    }

    private static let stopPollInterval = Duration.milliseconds(100)
    /// 6 seconds: SIGTERM, 3 seconds' grace, SIGKILL, then up to 2 seconds to drain output.
    private static let stopPollLimit = 60

    // MARK: Presets and recent runs

    public func presets(for session: TaskSession) -> [Preset] {
        library.presets(forTask: session.id)
    }

    public func savePreset(named name: String, from session: TaskSession) {
        library.savePreset(named: name, values: session.rememberableValues, forTask: session.id, id: UUID())
        saveLibrary()
    }

    public func renamePreset(_ preset: Preset, to name: String, of session: TaskSession) {
        guard library.renamePreset(preset.id, to: name, forTask: session.id) else { return }
        saveLibrary()
    }

    public func deletePreset(_ preset: Preset, of session: TaskSession) {
        library.deletePreset(preset.id, forTask: session.id)
        saveLibrary()
    }

    public func clearRecentRuns() {
        library.clearRecentRuns()
        saveLibrary()
    }

    /// The tool and task behind a recent run, when both still exist.
    public func resolve(_ run: RecentRun) -> (ToolManifest, ManifestTask)? {
        guard let manifest = manifest(withID: run.toolID), let task = task(withID: run.taskID, in: manifest)
        else { return nil }
        return (manifest, task)
    }

    private func recordRun(of manifest: ToolManifest, _ task: ManifestTask, outcome: RunOutcome, outputURL: URL?) {
        guard outcome != .cancelled else { return }
        library.recordRun(
            RecentRun(
                id: UUID(), toolID: manifest.id, taskID: task.id, finishedAt: now(),
                succeeded: outcome == .succeeded, outputPath: outputURL?.path))
        saveLibrary()
    }

    private func saveLibrary() {
        guard isSavingLibraryAllowed else { return }
        do {
            try libraryFile.save(library)
        } catch {
            report("Knobs couldn't save your settings. (\(error))")
        }
    }

    /// Shown by the app, and written to standard error, which the system log keeps.
    private func report(_ problem: String) {
        libraryProblem = problem
        FileHandle.standardError.write(Data("knobs: \(problem)\n".utf8))
    }
}
