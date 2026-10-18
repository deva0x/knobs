import Foundation
import KnobsCore
import KnobsSession

/// The Linux app's state: the bundled tools, where each one is installed, one session per task, and the settings
/// remembered between launches. The task sessions are the same `TaskSession` the Mac app uses; only the windows
/// differ.
final class LinuxModel {
    /// Where a tool's "All options" task stands. It is read from the tool's own help the first time it opens.
    enum AllOptionsState {
        case notInstalled
        case notRead
        case reading
        case ready(ManifestTask)
        case unavailable
    }

    let bundledManifests: [ToolManifest]
    let manifestFailures: [ManifestError]
    private(set) var executables: [String: URL] = [:]
    private var sessions: [String: TaskSession] = [:]
    private let locator: ToolLocator
    private let runner: ToolRunner
    private let helpReader: HelpReader
    private var allOptions: [String: AllOptionsState] = [:]
    private var library: KnobsLibrary
    private let libraryFile: LibraryFile
    private var isSavingLibraryAllowed = true

    init(manifestsDirectory: URL, dataDirectory: URL, environment: [String: String]) {
        libraryFile = LibraryFile(url: dataDirectory.appending(path: "library.json"))
        do {
            library = try libraryFile.load()
        } catch let readError {
            // Start fresh, but never by overwriting the old file: keep it beside the new one, or don't save at all.
            library = KnobsLibrary()
            do {
                let kept = try libraryFile.setAside(at: Date())
                Self.report("saved settings couldn't be read (\(readError)); kept them as \(kept.lastPathComponent)")
            } catch let moveError {
                isSavingLibraryAllowed = false
                Self.report(
                    "saved settings couldn't be read (\(readError)) or moved aside (\(moveError)); not saving this time"
                )
            }
        }
        let catalog = ManifestLoader.loadCatalog(in: manifestsDirectory)
        let locator = ToolLocator(environmentPath: environment["PATH"])
        // Each tool under the name it is installed as, such as 7-Zip as `7z` on Ubuntu, once at launch.
        bundledManifests = catalog.manifests.map(locator.resolve)
        manifestFailures = catalog.failures
        self.locator = locator
        runner = ToolRunner(environment: ToolRunner.environment(base: environment, locator: locator))
        helpReader = HelpReader(runner: runner)
        refreshAvailability()
    }

    /// The bundled manifests: `KNOBS_MANIFESTS` when set (development), else `share/knobs/manifests` beside the
    /// installed binary's `bin` folder, as the .deb and .rpm lay it out.
    static func manifestsDirectory(environment: [String: String], executable: URL?) -> URL {
        if let override = environment["KNOBS_MANIFESTS"], !override.isEmpty {
            return URL(filePath: override)
        }
        let prefix = (executable ?? URL(filePath: "/usr/bin/knobs")).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent()
        return prefix.appending(path: "share/knobs/manifests")
    }

    /// Where settings are kept: `$XDG_DATA_HOME/knobs`, or `~/.local/share/knobs` when it isn't set.
    static func dataDirectory(environment: [String: String]) -> URL {
        if let dataHome = environment["XDG_DATA_HOME"], dataHome.hasPrefix("/") {
            return URL(filePath: dataHome).appending(path: "knobs")
        }
        return URL(filePath: NSHomeDirectory()).appending(path: ".local/share/knobs")
    }

    /// Every tool in the sidebar: the bundled ones, then the ones the user added by name.
    var manifests: [ToolManifest] {
        bundledManifests + library.addedTools.map(ToolManifest.addedTool(named:))
    }

    /// Where a tool the user is about to add is installed, or nil when no tool has that name.
    func locate(_ name: String) -> URL? {
        locator.locate(name)
    }

    /// Adds an installed tool by name and returns its id, or nil when the name is taken or not a bare name.
    func addTool(named name: String) -> String? {
        guard !manifests.contains(where: { $0.executable == name }), library.addTool(named: name) else { return nil }
        saveLibrary()
        refreshAvailability()
        return ToolManifest.addedTool(named: name).id
    }

    /// Removing a tool while it runs would leave a run nothing can reach or cancel, so it waits until it stops.
    func canRemoveTool(_ manifest: ToolManifest) -> Bool {
        manifest.isAddedByUser && !sessions.values.contains { $0.manifest.id == manifest.id && $0.isRunning }
    }

    func removeTool(_ manifest: ToolManifest) {
        guard canRemoveTool(manifest) else { return }
        sessions = sessions.filter { $0.value.manifest.id != manifest.id }
        allOptions[manifest.id] = nil
        library.removeTool(named: manifest.executable)
        saveLibrary()
    }

    /// Looks every tool up again, for "Check again" after the user installs one.
    func refreshAvailability() {
        var found: [String: URL] = [:]
        for manifest in manifests {
            found[manifest.id] = locator.locate(manifest.executable)
        }
        executables = found
    }

    func manifest(withID id: String) -> ToolManifest? {
        manifests.first { $0.id == id }
    }

    func location(of manifest: ToolManifest) -> URL? {
        executables[manifest.id]
    }

    func session(for task: ManifestTask, of manifest: ToolManifest) -> TaskSession {
        let key = KnobsLibrary.key(toolID: manifest.id, taskID: task.id)
        if let session = sessions[key] { return session }
        let session = TaskSession(manifest: manifest, task: task, initialValues: library.lastValues(forTask: key))
        sessions[key] = session
        return session
    }

    /// A task by id, including the generated "All options" task once its help has been read.
    func task(withID taskID: String, of manifest: ToolManifest) -> ManifestTask? {
        if taskID == HelpTaskBuilder.taskID, case .ready(let task) = allOptionsState(of: manifest) {
            return task
        }
        return manifest.task(withID: taskID)
    }

    func allOptionsState(of manifest: ToolManifest) -> AllOptionsState {
        guard location(of: manifest) != nil else { return .notInstalled }
        return allOptions[manifest.id] ?? .notRead
    }

    /// Reads the tool's help once, in the background, and builds its "All options" task from it.
    func readAllOptions(of manifest: ToolManifest) {
        guard case .notRead = allOptionsState(of: manifest), let executable = location(of: manifest) else { return }
        allOptions[manifest.id] = .reading
        Task {
            let text = await helpReader.helpText(executable: executable, arguments: manifest.helpArguments)
            let options = HelpParser.options(in: text)
            allOptions[manifest.id] =
                options.isEmpty
                ? .unavailable : .ready(HelpTaskBuilder.task(from: options, toolName: manifest.name).task)
        }
    }

    func canRun(_ session: TaskSession) -> Bool {
        location(of: session.manifest) != nil && session.draft.isRunnable && !session.isRunning
    }

    func run(_ session: TaskSession) {
        guard canRun(session), let executable = location(of: session.manifest) else { return }
        library.rememberValues(session.rememberableValues, forTask: session.id)
        saveLibrary()
        session.start(executable: executable, runner: runner)
    }

    private func saveLibrary() {
        guard isSavingLibraryAllowed else { return }
        do {
            try libraryFile.save(library)
        } catch {
            Self.report("couldn't save settings: \(error)")
        }
    }

    /// Problems with saved settings go to standard error, which the desktop's journal keeps.
    private static func report(_ problem: String) {
        FileHandle.standardError.write(Data("knobs: \(problem)\n".utf8))
    }

    var hasRunningTasks: Bool {
        sessions.values.contains(where: \.isRunning)
    }
}
