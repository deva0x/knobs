import Foundation
import KnobsCore
import Observation

/// Everything about one task of one tool: the user's values, the live command, and the current or last run.
/// Each (tool, task) pair has its own session, so a run keeps going while the user looks at other tasks.
@MainActor
@Observable
final class TaskSession: Identifiable {
    enum Phase: Equatable {
        case idle
        case running(startedAt: Date)
        case finished(RunOutcome)
    }

    /// What a successful run produced, for the result card.
    struct RunResult: Equatable {
        let outputURL: URL?
        /// Where results went when the task has no single output file, such as yt-dlp's download folder.
        let folderURL: URL?
        let inputBytes: Int64?
        let outputBytes: Int64?
        let duration: TimeInterval
    }

    let manifest: ToolManifest
    let task: ManifestTask
    nonisolated var id: String { KnobsLibrary.key(toolID: manifest.id, taskID: task.id) }

    var values: [String: FieldValue] {
        didSet { rebuildDraft() }
    }
    var extraArguments = "" {
        didSet { rebuildDraft() }
    }

    private(set) var draft: CommandDraft
    private(set) var phase: Phase = .idle
    /// From 0 to 1 when the tool reports progress, otherwise nil.
    private(set) var progress: Double?
    private(set) var log = OutputLog()
    private(set) var result: RunResult?

    private let builder: CommandBuilder
    private var toolRun: ToolRun?
    private var inputBytesAtStart: Int64?
    private var reportedOutputPath: String?
    private let outputPathExpression: NSRegularExpression?
    private let clock: () -> Date
    /// Called once per run when it ends, with the outcome and the file it produced.
    var onFinish: ((RunOutcome, URL?) -> Void)?

    init(
        manifest: ToolManifest, task: ManifestTask, initialValues: [String: FieldValue],
        clock: @escaping () -> Date = Date.init
    ) {
        self.manifest = manifest
        self.task = task
        self.values = initialValues
        self.clock = clock
        let builder = CommandBuilder(
            outputNamer: OutputNamer(fileExists: { FileManager.default.fileExists(atPath: $0) }),
            homeDirectory: NSHomeDirectory())
        self.builder = builder
        self.draft = builder.build(task, of: manifest, values: initialValues, extraArguments: "")
        self.outputPathExpression = task.outputPathPattern.flatMap { try? NSRegularExpression(pattern: $0) }
    }

    /// Whether a run leaves a file or folder to show. Tasks that only report (such as showing metadata) don't,
    /// so their output is shown instead.
    var producesResult: Bool {
        task.output != nil || task.outputPathPattern != nil || outputFolderField != nil
    }

    private var outputFolderField: Field? {
        task.fields.first { $0.kind == .outputFolder }
    }

    /// The task's main input: the first single- or multi-file field, shown as the big drop zone.
    var primaryInputField: Field? {
        task.fields.first { if case .inputFile = $0.kind { true } else { false } }
    }

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    /// The value a field shows: what the user set, else the manifest default.
    func value(of field: Field) -> FieldValue? {
        values[field.id] ?? field.defaultValue
    }

    func setValue(_ value: FieldValue?, for field: Field) {
        values[field.id] = value
    }

    /// Values worth remembering between launches and in presets: everything except the main input file, which
    /// changes every time, and secrets, which are never stored.
    var rememberableValues: [String: FieldValue] {
        values.filter { id, _ in
            guard let field = task.field(withID: id) else { return false }
            return field.kind != .secret && field.id != primaryInputField?.id
        }
    }

    /// Applies a preset's settings, keeping the main input file the user already chose.
    func applyPreset(_ presetValues: [String: FieldValue]) {
        var merged = values.filter { id, _ in id == primaryInputField?.id }
        for (id, value) in presetValues where task.field(withID: id) != nil {
            merged[id] = value
        }
        values = merged
    }

    func resetToDefaults() {
        values = values.filter { id, _ in id == primaryInputField?.id }
        extraArguments = ""
    }

    func start(executable: URL, runner: ToolRunner) {
        guard !isRunning else { return }
        rebuildDraft()
        guard draft.isRunnable else { return }
        let command = draft.command
        log = OutputLog()
        progress = nil
        result = nil
        reportedOutputPath = nil
        let startedAt = clock()
        phase = .running(startedAt: startedAt)
        let inputPaths = primaryInputField.flatMap { value(of: $0)?.pathList } ?? []
        inputBytesAtStart = inputPaths.count == 1 ? Self.fileSize(atPath: inputPaths[0]) : nil

        let workingDirectory = command.outputPath.map { URL(filePath: $0).deletingLastPathComponent() }
        let run = runner.start(
            executable: executable, arguments: command.argv, workingDirectory: workingDirectory, progress: task.progress
        )
        toolRun = run
        Task { [weak self] in
            for await event in run.events {
                self?.handle(event, command: command, startedAt: startedAt)
            }
        }
    }

    func cancel() {
        toolRun?.cancel()
    }

    func dismissResult() {
        guard !isRunning else { return }
        phase = .idle
        result = nil
    }

    private func handle(_ event: RunEvent, command: Command, startedAt: Date) {
        switch event {
        case .line(let text, let stream):
            log.append(text, from: stream)
            if let path = Self.firstCapture(of: outputPathExpression, in: text) { reportedOutputPath = path }
        case .progress(let fraction):
            progress = fraction
        case .finished(let outcome):
            toolRun = nil
            if outcome == .succeeded {
                let outputPath = [reportedOutputPath, command.outputPath].compactMap { $0 }
                    .first { FileManager.default.fileExists(atPath: $0) }
                let folderPath = outputFolderField.flatMap { value(of: $0)?.firstPath }
                    .map { ($0 as NSString).expandingTildeInPath }
                result = RunResult(
                    outputURL: outputPath.map { URL(filePath: $0) },
                    folderURL: folderPath.map { URL(filePath: $0) },
                    inputBytes: inputBytesAtStart,
                    outputBytes: outputPath.flatMap(Self.fileSize(atPath:)),
                    duration: clock().timeIntervalSince(startedAt)
                )
                progress = 1
            }
            phase = .finished(outcome)
            onFinish?(outcome, result?.outputURL)
            // The output now exists, so the next run must pick a fresh name.
            rebuildDraft()
        }
    }

    private func rebuildDraft() {
        draft = builder.build(task, of: manifest, values: values, extraArguments: extraArguments)
    }

    private static let maximumItemsToMeasure = 5_000

    private static func firstCapture(of expression: NSRegularExpression?, in line: String) -> String? {
        guard let expression,
            let match = expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
            let range = Range(match.range(at: 1), in: line)
        else { return nil }
        return String(line[range])
    }

    /// The size of a file, or of everything inside a folder.
    private static func fileSize(atPath path: String) -> Int64? {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) else { return nil }
        guard isFolder.boolValue else {
            return (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value
        }
        let contents = FileManager.default.enumerator(
            at: URL(filePath: path), includingPropertiesForKeys: [.fileSizeKey])
        var total: Int64 = 0
        var counted = 0
        while let item = contents?.nextObject() as? URL {
            counted += 1
            // A huge folder isn't worth stalling the window for; its size is simply not shown.
            guard counted <= maximumItemsToMeasure else { return nil }
            total += Int64((try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}

extension FieldValue {
    var firstPath: String? {
        if case .paths(let paths) = self { return paths.first }
        return nil
    }

    var pathList: [String] {
        if case .paths(let paths) = self { return paths }
        return []
    }
}
