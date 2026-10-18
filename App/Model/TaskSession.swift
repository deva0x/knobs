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
        let inputBytes: Int64?
        let outputBytes: Int64?
        let duration: TimeInterval
    }

    let manifest: ToolManifest
    let task: ManifestTask
    nonisolated var id: String { Self.key(toolID: manifest.id, taskID: task.id) }

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
    private let clock: () -> Date

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
    }

    nonisolated static func key(toolID: String, taskID: String) -> String {
        "\(toolID)/\(taskID)"
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

    /// Values worth remembering between launches and in presets: no secrets, no files.
    var rememberableValues: [String: FieldValue] {
        values.filter { id, _ in
            guard let field = task.field(withID: id) else { return false }
            return field.kind != .secret && !field.kind.holdsPaths
        }
    }

    func applyPreset(_ presetValues: [String: FieldValue]) {
        var merged = values.filter { id, _ in task.field(withID: id)?.kind.holdsPaths == true }
        for (id, value) in presetValues where task.field(withID: id) != nil {
            merged[id] = value
        }
        values = merged
    }

    func resetToDefaults() {
        values = values.filter { id, _ in task.field(withID: id)?.kind.holdsPaths == true }
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
        let startedAt = clock()
        phase = .running(startedAt: startedAt)
        inputBytesAtStart = firstInputPath().flatMap(Self.fileSize(atPath:))

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
        case .progress(let fraction):
            progress = fraction
        case .finished(let outcome):
            toolRun = nil
            if outcome == .succeeded {
                let outputURL = command.outputPath.map { URL(filePath: $0) }
                result = RunResult(
                    outputURL: outputURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil },
                    inputBytes: inputBytesAtStart,
                    outputBytes: command.outputPath.flatMap(Self.fileSize(atPath:)),
                    duration: clock().timeIntervalSince(startedAt)
                )
                progress = 1
            }
            phase = .finished(outcome)
            // The output now exists, so the next run must pick a fresh name.
            rebuildDraft()
        }
    }

    private func rebuildDraft() {
        draft = builder.build(task, of: manifest, values: values, extraArguments: extraArguments)
    }

    private func firstInputPath() -> String? {
        for field in task.fields {
            if case .inputFile = field.kind, let path = value(of: field)?.firstPath { return path }
        }
        return nil
    }

    private static func fileSize(atPath path: String) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value
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
