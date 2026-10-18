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
    /// False when an unreadable library couldn't be moved aside, so saving would destroy it.
    private var isSavingLibraryAllowed = true
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
        } catch let readError {
            // Start fresh, but never by overwriting the old file: keep it beside the new one, or don't save at all.
            library = KnobsLibrary()
            do {
                let kept = try libraryFile.setAside(at: Date())
                libraryProblem =
                    "Your saved settings couldn't be read (\(readError)), so Knobs started fresh. The old file was kept as \(kept.lastPathComponent)."
            } catch let moveError {
                isSavingLibraryAllowed = false
                libraryProblem =
                    "Your saved settings couldn't be read (\(readError)), and couldn't be moved aside (\(moveError)), so Knobs started fresh and won't save over them this session."
            }
        }
        let catalog = ManifestLoader.loadCatalog(in: manifestsDirectory)
        bundledManifests = catalog.manifests
        manifestFailures = catalog.failures
        locator = ToolLocator(environmentPath: environment["PATH"])
        runner = ToolRunner(environment: ToolRunner.environment(base: environment, locator: locator))
        helpReader = HelpReader(runner: runner)
        // Reopen the tool used most recently, so the app picks up where it left off.
        let recentToolID = library.recentRuns.first?.toolID
        selectedToolID =
            catalog.manifests.first { $0.id == recentToolID }?.id ?? catalog.manifests.first?.id
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
        locator.locate(executable.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func addTool(named executable: String) {
        let name = executable.trimmingCharacters(in: .whitespacesAndNewlines)
        guard library.addTool(named: name) else { return }
        saveLibrary()
        refreshAvailability()
        open(toolID: Self.addedToolIDPrefix + name, taskID: HelpTaskBuilder.taskID)
    }

    /// Removing a tool while it runs would leave a run nothing can reach or cancel, so it waits until it stops.
    func canRemoveTool(_ manifest: ToolManifest) -> Bool {
        isAdded(manifest) && !isRunningAnything(of: manifest)
    }

    func removeTool(_ manifest: ToolManifest) {
        guard canRemoveTool(manifest) else { return }
        sessions = sessions.filter { $0.value.manifest.id != manifest.id }
        allOptions[manifest.id] = nil
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

    /// Where the copy of the tool that Knobs runs lives, or nil when it isn't installed.
    func location(of manifest: ToolManifest) -> URL? {
        executables[manifest.id]
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

    var hasRunningTasks: Bool {
        sessions.values.contains(where: \.isRunning)
    }

    /// Cancels every run and waits for them to stop, up to the runner's own SIGKILL grace period plus a margin,
    /// so quitting never leaves a tool running on its own.
    func stopAllRuns() async {
        let running = sessions.values.filter(\.isRunning)
        for session in running { session.cancel() }
        for _ in 0..<Self.stopPollLimit where running.contains(where: \.isRunning) {
            try? await Task.sleep(for: Self.stopPollInterval)
        }
    }

    private static let stopPollInterval = Duration.milliseconds(100)
    /// 6 seconds: SIGTERM, 3 seconds' grace, SIGKILL, then up to 2 seconds to drain output.
    private static let stopPollLimit = 60

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

    /// Whether Run is available: the tool is installed, the command is complete, and the task isn't running.
    func canRun(_ session: TaskSession) -> Bool {
        isInstalled(session.manifest) && session.draft.isRunnable && !session.isRunning
    }

    func run(_ session: TaskSession) {
        guard canRun(session), let executable = executables[session.manifest.id] else { return }
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

    func renamePreset(_ preset: Preset, to name: String, of session: TaskSession) {
        guard library.renamePreset(preset.id, to: name, forTask: session.id) else { return }
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
        guard isSavingLibraryAllowed else { return }
        do {
            try libraryFile.save(library)
        } catch {
            libraryProblem = "Knobs couldn't save your settings. (\(error))"
        }
    }

    /// Files opened with Knobs, waiting for the user to pick which task gets them.
    struct PendingFiles: Identifiable {
        struct Choice: Identifiable {
            let manifest: ToolManifest
            let task: ManifestTask
            /// The task takes one file, but several were opened.
            let usesOnlyFirstFile: Bool
            /// Task ids repeat across tools, so the tool is part of the id.
            var id: String { KnobsLibrary.key(toolID: manifest.id, taskID: task.id) }
        }

        let id = UUID()
        let urls: [URL]
        let choices: [Choice]
    }

    var pendingFiles: PendingFiles?

    /// Files opened with Knobs (dropped on the Dock icon, or `open -a Knobs`). They fill the visible task when it
    /// takes them all. Otherwise, one fitting task opens directly, and several are offered as a choice. Installed
    /// tools come first, and tasks that name the files' type are preferred over tasks that take anything (such as
    /// making an archive).
    /// `tool` limits the choice to one tool's tasks, for files dropped on that tool's home.
    func openFiles(_ urls: [URL], in tool: ToolManifest? = nil) {
        guard !urls.isEmpty else { return }
        func fits(_ field: Field?) -> Bool {
            guard let field else { return false }
            return urls.allSatisfy { FileTypeCheck.accepts($0, for: field.kind) }
        }
        if let session = visibleSession, !session.isRunning, fits(Self.openableField(of: session.task)) {
            use(urls, in: session)
            return
        }
        let fitting = (tool.map { [$0] } ?? manifests)
            .flatMap { manifest in manifest.tasks.map { (manifest: manifest, task: $0) } }
            .filter { fits(Self.openableField(of: $0.task)) }
        let installed = fitting.filter { isInstalled($0.manifest) }
        let pool = installed.isEmpty ? fitting : installed
        let specific = pool.filter { candidate in
            Self.openableField(of: candidate.task).map { FileTypeCheck.namesSpecificTypes($0.kind) } ?? false
        }
        // With several files, tasks that take several (Merge PDFs) come first. Single-file tasks stay on offer,
        // marked as using only the first file, rather than being hidden or quietly dropping files.
        let choices = (specific.isEmpty ? pool : specific).map { candidate in
            PendingFiles.Choice(
                manifest: candidate.manifest, task: candidate.task,
                usesOnlyFirstFile: urls.count > 1
                    && !(Self.openableField(of: candidate.task).map(Self.takesSeveralFiles) ?? false))
        }
        .enumerated()
        .sorted { lhs, rhs in
            // Closest fit first: tasks for several files when several were opened, then tasks that accept fewer
            // types (a video-only task before one for any image, video or PDF), then manifest order.
            let left = (lhs.element.usesOnlyFirstFile, Self.acceptedTypeCount(of: lhs.element.task), lhs.offset)
            let right = (rhs.element.usesOnlyFirstFile, Self.acceptedTypeCount(of: rhs.element.task), rhs.offset)
            return (left.0 ? 1 : 0, left.1, left.2) < (right.0 ? 1 : 0, right.1, right.2)
        }
        .map(\.element)
        if choices.count == 1, let only = choices.first, !only.usesOnlyFirstFile {
            use(urls, for: only.task, of: only.manifest)
        } else if !choices.isEmpty {
            pendingFiles = PendingFiles(urls: urls, choices: choices)
        }
    }

    /// Whether any of the tool's tasks takes all of these files, so a drop can say no before anything happens.
    func canOpen(_ urls: [URL], in tool: ToolManifest) -> Bool {
        tool.tasks.contains { task in
            guard let field = Self.openableField(of: task) else { return false }
            return urls.allSatisfy { FileTypeCheck.accepts($0, for: field.kind) }
        }
    }

    /// Opens a task with the given files in its main input.
    func use(_ urls: [URL], for task: ManifestTask, of manifest: ToolManifest) {
        pendingFiles = nil
        open(toolID: manifest.id, taskID: task.id)
        use(urls, in: session(for: task, of: manifest))
    }

    private func use(_ urls: [URL], in session: TaskSession) {
        guard !session.isRunning, let field = Self.openableField(of: session.task) else { return }
        session.setValue(.paths(Self.paths(urls, for: field)), for: field)
    }

    /// The field that opened files go into: the first file or folder input.
    private static func openableField(of task: ManifestTask) -> Field? {
        task.fields.first { field in
            switch field.kind {
            case .inputFile, .inputFolder: true
            default: false
            }
        }
    }

    /// How many types the task's input accepts; a task that takes anything counts as accepting the most.
    private static func acceptedTypeCount(of task: ManifestTask) -> Int {
        guard case .inputFile(let types, _)? = openableField(of: task)?.kind, !types.isEmpty else { return .max }
        return types.count
    }

    private static func takesSeveralFiles(_ field: Field) -> Bool {
        if case .inputFile(_, true) = field.kind { return true }
        return false
    }

    private static func paths(_ urls: [URL], for field: Field) -> [String] {
        if case .inputFile(_, true) = field.kind { return urls.map(\.path) }
        return [urls[0].path]
    }

    /// The session behind the visible task, for menu commands such as Run and Cancel. It only looks sessions up:
    /// menus read this while SwiftUI is drawing, when creating state isn't allowed. The task's view has already
    /// created its session.
    var visibleSession: TaskSession? {
        guard let tool = selectedTool, let task = selectedTask else { return nil }
        return sessions[KnobsLibrary.key(toolID: tool.id, taskID: task.id)]
    }
}
