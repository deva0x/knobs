import Foundation
import KnobsCore
import Observation

/// The app's state: the tools, where they are installed, what is selected, and one session per task.
@MainActor
@Observable
final class AppModel {
    let manifests: [ToolManifest]
    let manifestFailures: [ManifestError]
    private(set) var executables: [String: URL] = [:]

    var selectedToolID: String? {
        didSet {
            if oldValue != selectedToolID { taskPath = [] }
        }
    }
    /// The navigation stack inside the selected tool: empty shows the task gallery, one entry shows a task.
    var taskPath: [String] = []
    var isPaletteVisible = false

    private(set) var library: KnobsLibrary
    /// Shown once in the window when the saved settings couldn't be read or written.
    var libraryProblem: String?

    private var sessions: [String: TaskSession] = [:]
    private let locator: ToolLocator
    private let runner: ToolRunner
    private let libraryFile: LibraryFile

    init(manifestsDirectory: URL, dataDirectory: URL, environment: [String: String]) {
        libraryFile = LibraryFile(url: dataDirectory.appending(path: "library.json"))
        do {
            library = try libraryFile.load()
        } catch {
            library = KnobsLibrary()
            libraryProblem = "Your saved settings couldn't be read, so Knobs started fresh. (\(error))"
        }
        let catalog = ManifestLoader.loadCatalog(in: manifestsDirectory)
        manifests = catalog.manifests
        manifestFailures = catalog.failures
        locator = ToolLocator(environmentPath: environment["PATH"])
        runner = ToolRunner(environment: ToolRunner.environment(base: environment, locator: locator))
        selectedToolID = catalog.manifests.first?.id
        refreshAvailability()
    }

    var selectedTool: ToolManifest? {
        manifests.first { $0.id == selectedToolID }
    }

    var selectedTask: ManifestTask? {
        guard let taskID = taskPath.last else { return nil }
        return selectedTool?.task(withID: taskID)
    }

    /// Looks every tool up again, for "Check again" after the user installs one.
    func refreshAvailability() {
        var found: [String: URL] = [:]
        for manifest in manifests {
            found[manifest.id] = locator.locate(manifest.executable)
        }
        executables = found
    }

    func isInstalled(_ manifest: ToolManifest) -> Bool {
        executables[manifest.id] != nil
    }

    func session(for task: ManifestTask, of manifest: ToolManifest) -> TaskSession {
        let key = KnobsLibrary.key(toolID: manifest.id, taskID: task.id)
        if let session = sessions[key] { return session }
        let session = TaskSession(
            manifest: manifest, task: task, initialValues: library.lastValues(forTask: key))
        session.onFinish = { [weak self] outcome, outputURL in
            self?.recordRun(of: manifest, task, outcome: outcome, outputURL: outputURL)
        }
        sessions[key] = session
        return session
    }

    /// True while any task of this tool is running, for the sidebar's activity dot.
    func isRunningAnything(of manifest: ToolManifest) -> Bool {
        sessions.values.contains { $0.manifest.id == manifest.id && $0.isRunning }
    }

    func open(toolID: String, taskID: String?) {
        selectedToolID = toolID
        taskPath = taskID.map { [$0] } ?? []
    }

    func run(_ session: TaskSession) {
        guard let executable = executables[session.manifest.id], session.draft.isRunnable else { return }
        library.rememberValues(session.rememberableValues, forTask: session.id)
        saveLibrary()
        session.start(executable: executable, runner: runner)
    }

    // MARK: Presets and recent runs

    func presets(for session: TaskSession) -> [Preset] {
        library.presets(forTask: session.id)
    }

    func savePreset(named name: String, from session: TaskSession) {
        library.savePreset(named: name, values: session.rememberableValues, forTask: session.id, id: UUID())
        saveLibrary()
    }

    func deletePreset(_ preset: Preset, of session: TaskSession) {
        library.deletePreset(preset.id, forTask: session.id)
        saveLibrary()
    }

    func clearRecentRuns() {
        library.clearRecentRuns()
        saveLibrary()
    }

    /// The tool and task behind a recent run, when both still exist.
    func resolve(_ run: RecentRun) -> (ToolManifest, ManifestTask)? {
        guard let manifest = manifests.first(where: { $0.id == run.toolID }),
            let task = manifest.task(withID: run.taskID)
        else { return nil }
        return (manifest, task)
    }

    private func recordRun(of manifest: ToolManifest, _ task: ManifestTask, outcome: RunOutcome, outputURL: URL?) {
        guard outcome != .cancelled else { return }
        library.recordRun(
            RecentRun(
                id: UUID(), toolID: manifest.id, taskID: task.id, finishedAt: Date(),
                succeeded: outcome == .succeeded, outputPath: outputURL?.path))
        saveLibrary()
    }

    private func saveLibrary() {
        do {
            try libraryFile.save(library)
        } catch {
            libraryProblem = "Knobs couldn't save your settings. (\(error))"
        }
    }

    /// Files opened with Knobs (dropped on the Dock icon, or `open -a Knobs`): they fill the visible task when
    /// it accepts them, otherwise the first task that does, preferring the selected tool.
    func openFiles(_ urls: [URL]) {
        guard let first = urls.first else { return }
        if let session = visibleSession, !session.isRunning, let field = session.primaryInputField,
            FileTypeCheck.accepts(first, for: field.kind)
        {
            session.setValue(.paths(Self.paths(urls, for: field)), for: field)
            return
        }
        let toolsInOrder = manifests.filter { $0.id == selectedToolID } + manifests.filter { $0.id != selectedToolID }
        for manifest in toolsInOrder {
            for task in manifest.tasks {
                let session = session(for: task, of: manifest)
                guard !session.isRunning, let field = session.primaryInputField,
                    FileTypeCheck.accepts(first, for: field.kind)
                else { continue }
                open(toolID: manifest.id, taskID: task.id)
                session.setValue(.paths(Self.paths(urls, for: field)), for: field)
                return
            }
        }
    }

    private static func paths(_ urls: [URL], for field: Field) -> [String] {
        if case .inputFile(_, true) = field.kind { return urls.map(\.path) }
        return [urls[0].path]
    }

    /// The session behind the visible task, for menu commands such as Run and Cancel.
    var visibleSession: TaskSession? {
        guard let tool = selectedTool, let task = selectedTask else { return nil }
        return session(for: task, of: tool)
    }
}
