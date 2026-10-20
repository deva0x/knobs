import Foundation
import KnobsCore
import Observation

/// Everything about one task of one tool: the user's values, the live command, and the current or last run.
/// Each (tool, task) pair has its own session, so a run keeps going while the user looks at other tasks.
@MainActor
@Observable
public final class TaskSession: Identifiable {
    public enum Phase: Equatable, Sendable {
        case idle
        case running(startedAt: Date)
        case finished(RunOutcome)
    }

    /// What a successful run produced, for the result card.
    public struct RunResult: Equatable, Sendable {
        public let outputURL: URL?
        /// Where results went when the task has no single output file, such as yt-dlp's download folder.
        public let folderURL: URL?
        /// Sizes are measured off the main thread after the run ends, so they arrive a moment later.
        public var inputBytes: Int64?
        public var outputBytes: Int64?
        public let duration: TimeInterval
        /// Whether the output is the same kind of file as the one input, as when a video is shrunk into another
        /// video. Only then does the change in size say something; a PDF turned into text is always smaller.
        public let sizesAreComparable: Bool

        /// How much larger (positive) or smaller (negative) the output is, as a fraction of the input's size, once
        /// both are measured. Nil when the sizes aren't comparable.
        public var sizeChange: Double? {
            guard sizesAreComparable, let inputBytes, let outputBytes, inputBytes > 0 else { return nil }
            return Double(outputBytes - inputBytes) / Double(inputBytes)
        }
    }

    public let manifest: ToolManifest
    public let task: ManifestTask
    public nonisolated var id: String { KnobsLibrary.key(toolID: manifest.id, taskID: task.id) }

    public var values: [String: FieldValue] {
        didSet { rebuildDraft() }
    }
    public var extraArguments = "" {
        didSet { rebuildDraft() }
    }

    public private(set) var draft: CommandDraft
    public private(set) var phase: Phase = .idle
    /// From 0 to 1 when the tool reports progress, otherwise nil.
    public private(set) var progress: Double?
    public private(set) var log = OutputLog()
    public private(set) var result: RunResult?

    private let builder: CommandBuilder
    private var toolRun: ToolRun?
    /// Counts runs, so sizes measured in the background land only on the run they belong to.
    private var runNumber = 0
    private var reportedOutputPath: String?
    private let outputPathExpression: NSRegularExpression?
    private let clock: () -> Date
    /// Called once per run when it ends, with the outcome and the file it produced.
    public var onFinish: ((RunOutcome, URL?) -> Void)?

    public init(
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
    public var producesResult: Bool {
        task.output != nil || task.outputPathPattern != nil || outputFolderField != nil
    }

    private var outputFolderField: Field? {
        task.fields.first { $0.kind == .outputFolder }
    }

    /// The task's main input: the first single- or multi-file field, shown as the big drop zone.
    public var primaryInputField: Field? {
        task.fields.first { if case .inputFile = $0.kind { true } else { false } }
    }

    /// Tasks without an input file but with a required text field, such as a link, show that field large instead.
    public var heroTextField: Field? {
        guard primaryInputField == nil else { return nil }
        return task.fields.first { field in
            if case .text = field.kind { return field.isRequired }
            return false
        }
    }

    /// Everything that isn't shown large on the stage, for the inspector.
    public var settingFields: [Field] {
        task.fields.filter { $0.id != primaryInputField?.id && $0.id != heroTextField?.id }
    }

    /// A plain-words reason the Extra arguments can't be used, or nil.
    public var extraArgumentsProblem: String? {
        for problem in draft.problems {
            if case .extraArguments(let error) = problem {
                return switch error {
                case .unclosedQuote(let quote): "A \(quote) quote isn't closed."
                case .trailingBackslash: "The text ends with a backslash."
                }
            }
        }
        return nil
    }

    public var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    /// The value a field shows: what the user set, else the manifest default.
    public func value(of field: Field) -> FieldValue? {
        values[field.id] ?? field.defaultValue
    }

    public func setValue(_ value: FieldValue?, for field: Field) {
        values[field.id] = value
    }

    /// Values worth remembering between launches and in presets: everything except the main input file, which
    /// changes every time, and secrets, which are never stored.
    public var rememberableValues: [String: FieldValue] {
        values.filter { id, _ in
            guard let field = task.field(withID: id) else { return false }
            return field.kind != .secret && field.id != primaryInputField?.id
        }
    }

    /// Applies a preset's settings, keeping the main input file the user already chose.
    public func applyPreset(_ presetValues: [String: FieldValue]) {
        var merged = values.filter { id, _ in id == primaryInputField?.id }
        for (id, value) in presetValues where task.field(withID: id) != nil {
            merged[id] = value
        }
        values = merged
    }

    public func resetToDefaults() {
        values = values.filter { id, _ in id == primaryInputField?.id }
        extraArguments = ""
    }

    public func start(executable: URL, runner: ToolRunner) {
        guard !isRunning else { return }
        rebuildDraft()
        guard draft.isRunnable else { return }
        let command = draft.command
        log = OutputLog()
        progress = nil
        result = nil
        reportedOutputPath = nil
        if let problem = makeNewOutputFolder(for: command) {
            phase = .finished(.couldNotStart(problem))
            onFinish?(.couldNotStart(problem), nil)
            return
        }
        let startedAt = clock()
        phase = .running(startedAt: startedAt)
        runNumber += 1

        let workingDirectory = command.outputPath.map { URL(filePath: $0).deletingLastPathComponent() }
        let run = runner.start(
            executable: executable, arguments: command.argv, workingDirectory: workingDirectory, progress: task.progress
        )
        toolRun = run
        // The input is measured in the background as the tool starts, for the result card.
        let inputPaths = primaryInputField.flatMap { value(of: $0)?.pathList } ?? []
        let inputSize = Task.detached(priority: .utility) {
            inputPaths.count == 1 ? Self.fileSize(atPath: inputPaths[0]) : nil
        }
        let thisRun = runNumber
        Task { [weak self] in
            for await event in run.events {
                self?.handle(event, command: command, startedAt: startedAt)
            }
            await self?.measureResult(of: thisRun, inputSize: inputSize)
        }
    }

    public func cancel() {
        toolRun?.cancel()
    }

    public func dismissResult() {
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
                let inputPaths = primaryInputField.flatMap { value(of: $0)?.pathList } ?? []
                let inputKind = inputPaths.count == 1 ? FileKind(path: inputPaths[0]) : nil
                let outputKind = outputPath.flatMap(FileKind.init(path:))
                result = RunResult(
                    outputURL: outputPath.map { URL(filePath: $0) },
                    folderURL: folderPath.map { URL(filePath: $0) },
                    inputBytes: nil,
                    outputBytes: nil,
                    duration: clock().timeIntervalSince(startedAt),
                    sizesAreComparable: inputKind != nil && inputKind == outputKind
                )
                progress = 1
            } else {
                removeNewOutputFolderIfEmpty(for: command)
            }
            phase = .finished(outcome)
            onFinish?(outcome, result?.outputURL)
            // The output now exists, so the next run must pick a fresh name.
            rebuildDraft()
        }
    }

    /// Fills in the result's sizes once they're measured, unless another run has started since.
    private func measureResult(of run: Int, inputSize: Task<Int64?, Never>) async {
        guard let outputPath = result?.outputURL?.path else { return }
        let inputBytes = await inputSize.value
        let outputBytes = await Task.detached(priority: .utility) { Self.fileSize(atPath: outputPath) }.value
        guard run == runNumber, result != nil else { return }
        result?.inputBytes = inputBytes
        result?.outputBytes = outputBytes
    }

    private func rebuildDraft() {
        draft = builder.build(task, of: manifest, values: values, extraArguments: extraArguments)
    }

    /// Makes the empty folder that a `newFolder` output names, for the tool to write into, and returns why it
    /// couldn't in plain words. Intermediate folders are off, so this fails rather than reuse a folder that appeared
    /// since the name was picked, or make a missing parent.
    private func makeNewOutputFolder(for command: Command) -> String? {
        guard task.output?.isNewFolder == true, let path = command.outputPath else { return nil }
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
            return nil
        } catch {
            let folder = URL(filePath: path)
            return "Knobs couldn't make the folder “\(folder.lastPathComponent)” in "
                + "\(folder.deletingLastPathComponent().path) for the results. (\(error.localizedDescription))"
        }
    }

    /// Takes away the folder this run made when the tool left nothing in it, so a failed run leaves no litter and
    /// the next run gets the same name. `rmdir` removes only an empty folder; one with anything in it, even a
    /// half-finished file, is kept, and so is the folder when removing it fails for any other reason.
    private func removeNewOutputFolderIfEmpty(for command: Command) {
        guard task.output?.isNewFolder == true, let path = command.outputPath else { return }
        _ = rmdir(path)
    }

    nonisolated private static let maximumItemsToMeasure = 5_000

    private static func firstCapture(of expression: NSRegularExpression?, in line: String) -> String? {
        guard let expression,
            let match = expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
            let range = Range(match.range(at: 1), in: line)
        else { return nil }
        return String(line[range])
    }

    /// The size of a file, or of everything inside a folder. Runs off the main thread: a big folder on a network
    /// drive can take seconds.
    nonisolated private static func fileSize(atPath path: String) -> Int64? {
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
    public var firstPath: String? {
        if case .paths(let paths) = self { return paths.first }
        return nil
    }

    public var pathList: [String] {
        if case .paths(let paths) = self { return paths }
        return []
    }
}
