import Foundation
import KnobsCore
import KnobsSession
import Observation

/// The Mac app's navigation around the shared `Toolbox`: which tool and task are on screen, the Go to Task palette,
/// and files opened with Knobs waiting for a task.
@MainActor
@Observable
final class AppModel {
    let toolbox: Toolbox

    private(set) var selectedToolID: String?
    /// The navigation stack inside the selected tool: empty shows the task gallery, one entry shows a task.
    var taskPath: [String] = []
    /// A task to open in a tool that is being switched to (see `open(toolID:taskID:)`).
    private var pendingTask: PendingTask?
    var isPaletteVisible = false

    init(manifestsDirectory: URL, dataDirectory: URL, environment: [String: String]) {
        toolbox = Toolbox(
            manifestsDirectory: manifestsDirectory, dataDirectory: dataDirectory, environment: environment)
        // Reopen the tool used most recently, so the app picks up where it left off.
        let recentToolID = toolbox.library.recentRuns.first?.toolID
        selectedToolID =
            toolbox.bundledManifests.first { $0.id == recentToolID }?.id ?? toolbox.bundledManifests.first?.id
    }

    var selectedTool: ToolManifest? {
        selectedToolID.flatMap(toolbox.manifest(withID:))
    }

    var selectedTask: ManifestTask? {
        guard let taskID = taskPath.last, let tool = selectedTool else { return nil }
        return toolbox.task(withID: taskID, in: tool)
    }

    /// Adds a tool by name and opens its "All options".
    func addTool(named executable: String) {
        guard let toolID = toolbox.addTool(named: executable) else { return }
        open(toolID: toolID, taskID: HelpTaskBuilder.taskID)
    }

    /// Removes an added tool, and shows the first tool if it was the one on screen.
    func removeTool(_ manifest: ToolManifest) {
        guard toolbox.canRemoveTool(manifest) else { return }
        toolbox.removeTool(manifest)
        if selectedToolID == manifest.id { selectTool(toolbox.bundledManifests.first?.id) }
    }

    /// Selects a tool from the sidebar, showing its gallery. Selecting the current tool keeps its open task.
    func selectTool(_ toolID: String?) {
        guard toolID != selectedToolID else { return }
        selectedToolID = toolID
        taskPath = []
        pendingTask = nil
    }

    /// Jumps straight to a tool, and to one of its tasks when given.
    func open(toolID: String, taskID: String?) {
        guard toolID != selectedToolID else {
            taskPath = taskID.map { [$0] } ?? []
            return
        }
        // Switching tools rebuilds the detail's navigation stack, which ignores a path set in the same moment
        // (BUG-009). So the task waits here until the new tool's home is on screen and opens it.
        selectedToolID = toolID
        taskPath = []
        pendingTask = taskID.map { PendingTask(toolID: toolID, taskID: $0) }
    }

    /// Opens the task waiting for `toolID`'s home, if there is one; the home calls this once it is on screen.
    func openPendingTask(of toolID: String) {
        guard let pendingTask, pendingTask.toolID == toolID else { return }
        self.pendingTask = nil
        taskPath = [pendingTask.taskID]
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
        let fitting = (tool.map { [$0] } ?? toolbox.manifests)
            .flatMap { manifest in manifest.tasks.map { (manifest: manifest, task: $0) } }
            .filter { fits(Self.openableField(of: $0.task)) }
        let installed = fitting.filter { toolbox.isInstalled($0.manifest) }
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
        use(urls, in: toolbox.session(for: task, of: manifest))
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

    /// The session behind the visible task, for menu commands such as Run and Cancel. The task's view has already
    /// created it.
    var visibleSession: TaskSession? {
        guard let tool = selectedTool, let task = selectedTask else { return nil }
        return toolbox.existingSession(forTask: KnobsLibrary.key(toolID: tool.id, taskID: task.id))
    }
}

/// A task waiting for its tool's home to appear before it opens.
struct PendingTask: Equatable {
    let toolID: String
    let taskID: String
}
