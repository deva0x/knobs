import Foundation
import KnobsCore
import Observation

/// The app's state: the tools, where they are installed, what is selected, and one session per task.
@MainActor
@Observable
final class AppModel {
    /// What "All options" knows about a tool, read from its help text on first visit.
    enum AllOptionsState: Equatable {
        case loading
        case ready(HelpTaskBuilder.GeneratedTask)
        case unavailable
    }

    let bundledManifests: [ToolManifest]
    let manifestFailures: [ManifestError]
    private(set) var allOptions: [String: AllOptionsState] = [:]
    private(set) var executables: [String: URL] = [:]

    private(set) var selectedToolID: String?
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
    private let helpReader: HelpReader

    static let addedToolIDPrefix = "added-"

    /// Every tool in the sidebar: the bundled ones, then the ones the user added.
    var manifests: [ToolManifest] {
        bundledManifests + addedManifests
    }

    /// Tools added by name have no hand-written tasks; everything comes from "All options".
    var addedManifests: [ToolManifest] {
        library.addedTools.map { name in
            ToolManifest(
                id: Self.addedToolIDPrefix + name, name: name,
                summary: "Added by you. Its options come from its own help.",
                executable: name, brewFormula: name, homepage: nil, symbol: "terminal", tint: .gray, tasks: [])
        }
    }

    func isAdded(_ manifest: ToolManifest) -> Bool {
        manifest.id.hasPrefix(Self.addedToolIDPrefix)
    }

    init(manifestsDirectory: URL, dataDirectory: URL, environment: [String: String]) {
        libraryFile = LibraryFile(url: dataDirectory.appending(path: "library.json"))
        do {
            library = try libraryFile.load()
        } catch {
            library = KnobsLibrary()
            libraryProblem = "Your saved settings couldn't be read, so Knobs started fresh. (\(error))"
        }
        let catalog = ManifestLoader.loadCatalog(in: manifestsDirectory)
        bundledManifests = catalog.manifests
        manifestFailures = catalog.failures
        locator = ToolLocator(environmentPath: environment["PATH"])
        runner = ToolRunner(environment: ToolRunner.environment(base: environment, locator: locator))
        helpReader = HelpReader(runner: runner)
        selectedToolID = catalog.manifests.first?.id
        refreshAvailability()
    }

    var selectedTool: ToolManifest? {
        manifests.first { $0.id == selectedToolID }
    }

    var selectedTask: ManifestTask? {
        guard let taskID = taskPath.last, let tool = selectedTool else { return nil }
        return task(withID: taskID, in: tool)
    }

    /// A manifest task, or the generated "All options" task once its help has been read.
    func task(withID taskID: String, in manifest: ToolManifest) -> ManifestTask? {
        if taskID == HelpTaskBuilder.taskID, case .ready(let generated)? = allOptions[manifest.id] {
            return generated.task
        }
        return manifest.task(withID: taskID)
    }

    /// Reads the tool's help once and builds its "All options" task.
    func loadAllOptions(for manifest: ToolManifest) async {
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

    // MARK: Added tools

    func locate(_ executable: String) -> URL? {
        locator.locate(executable.trimmingCharacters(in: .whitespaces))
    }

    func addTool(named executable: String) {
        let name = executable.trimmingCharacters(in: .whitespaces)
        guard library.addTool(named: name) else { return }
        saveLibrary()
        refreshAvailability()
        open(toolID: Self.addedToolIDPrefix + name, taskID: HelpTaskBuilder.taskID)
    }

    func removeTool(_ manifest: ToolManifest) {
        guard isAdded(manifest) else { return }
        library.removeTool(named: manifest.executable)
        saveLibrary()
        if selectedToolID == manifest.id { selectTool(bundledManifests.first?.id) }
    }

    /// Looks every tool up again, for "Check again" after the user installs one.
    func refreshAvailability() {
        var found: [String: URL] = [:]
        allOptions = allOptions.filter { $0.value != .unavailable }
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

    /// Selects a tool from the sidebar, showing its gallery. Selecting the current tool keeps its open task.
    func selectTool(_ toolID: String?) {
        guard toolID != selectedToolID else { return }
        selectedToolID = toolID
        taskPath = []
    }

    /// Jumps straight to a tool, and to one of its tasks when given.
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
            let task = task(withID: run.taskID, in: manifest)
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
