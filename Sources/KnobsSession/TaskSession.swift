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
        /// How many files the run went through: 1, or more when a one-file task was given several.
        public let fileCount: Int
        /// The input files whose run failed, when the task went through several; the others still ran.
        public let failedFiles: [String]

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

    /// Where a run over several files stands: which file comes next and which have failed.
    private struct Batch {
        let files: [String]
        let field: Field
        let executable: URL
        let runner: ToolRunner
        let startedAt: Date
        var nextIndex = 0
        var failedFiles: [String] = []
        var lastFailure: RunOutcome?
        var outputFolders: [String] = []
    }

    /// The file a run over several files is on, counted from 1, and how many there are.
    public struct BatchStep: Equatable, Sendable {
        public let number: Int
        public let count: Int
    }

    private let builder: CommandBuilder
    private var batch: Batch?
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

    /// The files Run goes through one after another, when a one-file task was given several; otherwise empty.
    public var filesRunOneByOne: [String] {
        guard let field = primaryInputField, case .inputFile(_, false) = field.kind else { return [] }
        let paths = value(of: field)?.pathList ?? []
        return paths.count > 1 ? paths : []
    }

    /// The file a run over several files is on, while it runs.
    public var batchStep: BatchStep? {
        guard let batch, isRunning else { return nil }
        return BatchStep(number: batch.nextIndex, count: batch.files.count)
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
        log = OutputLog()
        progress = nil
        result = nil
        let files = filesRunOneByOne
        if let field = primaryInputField, !files.isEmpty {
            batch = Batch(files: files, field: field, executable: executable, runner: runner, startedAt: clock())
            startNextFile()
        } else {
            batch = nil
            run(draft.command, executable: executable, runner: runner)
        }
    }

    /// Starts the batch's next file with a command built for that file alone, just before it runs, so its output
    /// name is picked knowing the files the earlier ones wrote.
    private func startNextFile() {
        guard var batch, batch.nextIndex < batch.files.count else { return }
        let file = batch.files[batch.nextIndex]
        batch.nextIndex += 1
        self.batch = batch
        var fileValues = values
        fileValues[batch.field.id] = .paths([file])
        let fileDraft = builder.build(task, of: manifest, values: fileValues, extraArguments: extraArguments)
        let header = "— \(URL(filePath: file).lastPathComponent) (\(batch.nextIndex) of \(batch.files.count)) —"
        log.append(header, from: .standardOutput)
        guard fileDraft.isRunnable else {
            runEnded(.couldNotStart("Knobs couldn't make the command for this file."), command: fileDraft.command)
            return
        }
        run(fileDraft.command, executable: batch.executable, runner: batch.runner)
    }

    private func run(_ command: Command, executable: URL, runner: ToolRunner) {
        reportedOutputPath = nil
        if let problem = makeNewOutputFolder(for: command) {
            runEnded(.couldNotStart(problem), command: command)
            return
        }
        let startedAt = clock()
        // A run over several files stays running from its first file to its last.
        if !isRunning { phase = .running(startedAt: batch?.startedAt ?? startedAt) }
        runNumber += 1

        let workingDirectory = command.outputPath.map { URL(filePath: $0).deletingLastPathComponent() }
        let run = runner.start(
            executable: executable, arguments: command.argv, workingDirectory: workingDirectory, progress: task.progress
        )
        toolRun = run
        // The input is measured in the background as the tool starts, for the result card.
        let inputPaths = batch == nil ? primaryInputField.flatMap { value(of: $0)?.pathList } ?? [] : []
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
            if let batch {
                progress = (Double(batch.nextIndex - 1) + fraction) / Double(batch.files.count)
            } else {
                progress = fraction
            }
        case .finished(let outcome):
            toolRun = nil
            if outcome != .succeeded { removeNewOutputFolderIfEmpty(for: command) }
            runEnded(outcome, command: command, startedAt: startedAt)
        }
    }

    /// What happens after one run of the tool: the result of a single run, or the next file of several.
    private func runEnded(_ outcome: RunOutcome, command: Command, startedAt: Date? = nil) {
        if batch != nil {
            fileEnded(outcome, command: command)
            return
        }
        if outcome == .succeeded, let startedAt {
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
                sizesAreComparable: inputKind != nil && inputKind == outputKind,
                fileCount: 1,
                failedFiles: []
            )
            progress = 1
        }
        phase = .finished(outcome)
        onFinish?(outcome, result?.outputURL)
        // The output now exists, so the next run must pick a fresh name.
        rebuildDraft()
    }

    /// One file of several is done: note how it went, then go on to the next unless the user cancelled. A failed
    /// file doesn't stop the others; the result says which failed.
    private func fileEnded(_ outcome: RunOutcome, command: Command) {
        guard var batch else { return }
        let file = batch.files[batch.nextIndex - 1]
        switch outcome {
        case .succeeded:
            let output = [reportedOutputPath, command.outputPath].compactMap { $0 }
                .first { FileManager.default.fileExists(atPath: $0) }
            if let folder = output.map({ ($0 as NSString).deletingLastPathComponent }),
                !batch.outputFolders.contains(folder)
            {
                batch.outputFolders.append(folder)
            }
        case .cancelled:
            break
        case .failed, .couldNotStart:
            batch.failedFiles.append(file)
            batch.lastFailure = outcome
        }
        progress = Double(batch.nextIndex) / Double(batch.files.count)
        self.batch = batch
        if outcome != .cancelled, batch.nextIndex < batch.files.count {
            startNextFile()
        } else {
            batchEnded(batch, cancelled: outcome == .cancelled)
        }
    }

    private func batchEnded(_ batch: Batch, cancelled: Bool) {
        let outcome: RunOutcome
        if cancelled {
            outcome = .cancelled
        } else if batch.failedFiles.count == batch.files.count {
            outcome = batch.lastFailure ?? .failed(exitCode: 1)
        } else {
            outcome = .succeeded
            let folderPath =
                outputFolderField.flatMap { value(of: $0)?.firstPath }.map { ($0 as NSString).expandingTildeInPath }
                ?? (batch.outputFolders.count == 1 ? batch.outputFolders[0] : nil)
            result = RunResult(
                outputURL: nil,
                folderURL: folderPath.map { URL(filePath: $0) },
                inputBytes: nil,
                outputBytes: nil,
                duration: clock().timeIntervalSince(batch.startedAt),
                sizesAreComparable: false,
                fileCount: batch.files.count,
                failedFiles: batch.failedFiles
            )
        }
        self.batch = nil
        phase = .finished(outcome)
        onFinish?(outcome, nil)
        rebuildDraft()
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
