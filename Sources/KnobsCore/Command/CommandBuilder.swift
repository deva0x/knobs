import Foundation

/// Builds the argv for a task from the user's field values. Every value becomes exactly one argument, so file
/// names with spaces, quotes or semicolons are never split or interpreted (DEC-006).
public struct CommandBuilder: Sendable {
    private let outputNamer: OutputNamer
    private let homeDirectory: String

    /// `homeDirectory` replaces a leading `~` in paths, such as a folder default of `~/Downloads`.
    public init(outputNamer: OutputNamer, homeDirectory: String) {
        self.outputNamer = outputNamer
        self.homeDirectory = homeDirectory
    }

    /// Builds a command that can always be previewed. Missing values become `.missing` parts and are listed
    /// in `problems`. `values` holds what the user set; fields without a value use their manifest default.
    public func build(
        _ task: ManifestTask,
        of manifest: ToolManifest,
        values: [String: FieldValue],
        extraArguments: String
    ) -> CommandDraft {
        var context = Context(task: task, values: values, homeDirectory: homeDirectory)

        for field in task.fields where field.isRequired && context.value(of: field)?.isSet != true {
            context.problems.append(.missingValue(fieldID: field.id, label: field.label))
        }

        do {
            context.extraWords = try ArgumentSplitter.split(extraArguments)
        } catch {
            context.problems.append(.extraArguments(error))
            context.extraWords = [extraArguments.trimmingCharacters(in: .whitespacesAndNewlines)]
        }

        context.outputPath = resolveOutputPath(context: &context)
        let parts = context.expand(task.arguments)
        return CommandDraft(
            command: Command(executable: manifest.executable, arguments: parts, outputPath: context.outputPath),
            problems: context.problems
        )
    }

    private func resolveOutputPath(context: inout Context) -> String? {
        guard let rule = context.task.output else { return nil }
        let folder: String?
        switch rule.location {
        case .nextTo(let fieldID):
            folder = context.firstPath(of: fieldID).map { ($0 as NSString).deletingLastPathComponent }
        case .folder(let fieldID):
            folder = context.firstPath(of: fieldID)
        }
        guard let folder, let name = context.interpolate(rule.template) else { return nil }
        let safeName = Self.fileName(from: name)
        let desired = (folder as NSString).appendingPathComponent(safeName)
        // An empty name would point at the folder itself, and the namer would then pick a sibling folder.
        guard !safeName.isEmpty else {
            context.problems.append(.outputUnavailable(desired))
            return nil
        }
        do {
            return try outputNamer.availablePath(for: desired)
        } catch {
            context.problems.append(.outputUnavailable(desired))
            return desired
        }
    }
}

extension CommandBuilder {
    /// Makes a rendered output name safe to use as one file name: no slashes, and no dots or spaces at either end.
    /// An input with no extension would otherwise give `notes clean.`, and a hidden input `.profile` would give a
    /// hidden output.
    static func fileName(from name: String) -> String {
        name.replacing("/", with: "-").trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }
}

/// The state of one build: the task, the values, and what has been worked out so far.
private struct Context {
    let task: ManifestTask
    let values: [String: FieldValue]
    let homeDirectory: String
    var problems: [CommandProblem] = []
    var extraWords: [String] = []
    var outputPath: String?

    init(task: ManifestTask, values: [String: FieldValue], homeDirectory: String) {
        self.task = task
        self.values = values
        self.homeDirectory = homeDirectory
    }

    /// The user's value, else the manifest default, with `~` in paths expanded.
    func value(of field: Field) -> FieldValue? {
        guard let value = values[field.id] ?? field.defaultValue else { return nil }
        guard case .paths(let paths) = value else { return value }
        return .paths(paths.map(expandingTilde))
    }

    private func expandingTilde(_ path: String) -> String {
        if path == "~" { return homeDirectory }
        guard path.hasPrefix("~/") else { return path }
        return (homeDirectory as NSString).appendingPathComponent(String(path.dropFirst(2)))
    }

    func holds(_ condition: Condition) -> Bool {
        guard let field = task.field(withID: condition.fieldID), let value = value(of: field) else { return false }
        if let expected = condition.equals { return value.argumentText == expected }
        return value.isSet
    }

    func firstPath(of fieldID: String) -> String? {
        guard let field = task.field(withID: fieldID) else { return nil }
        return value(of: field)?.paths.first
    }

    func expand(_ items: [ArgumentTemplate]) -> [CommandPart] {
        items.flatMap { item -> [CommandPart] in
            switch item {
            case .conditional(let condition, let then, let otherwise):
                return expand(holds(condition) ? then : otherwise)
            case .text(let template):
                return expand(template)
            }
        }
    }

    private func expand(_ template: String) -> [CommandPart] {
        guard let segments = try? TemplateParser.segments(of: template) else {
            return [CommandPart(text: template, role: .value)]
        }
        if segments.count == 1, case .placeholder(let placeholder) = segments[0] {
            return expandWhole(placeholder)
        }
        let label = missingLabel(in: segments)
        if let label { return [CommandPart(text: label, role: .missing)] }
        let text = interpolate(segments) ?? ""
        let role: CommandPart.Role =
            segments.contains(where: isSecretReference) ? .secret : Self.isFlag(text) ? .flag : .value
        return [CommandPart(text: text, role: role)]
    }

    /// A template that is just one placeholder can expand to zero, one or several arguments.
    private func expandWhole(_ placeholder: Placeholder) -> [CommandPart] {
        switch placeholder {
        case .extra:
            return extraWords.map { CommandPart(text: $0, role: .extra) }
        case .output(let part):
            return [
                outputPath.map { CommandPart(text: part.of($0), role: .path) }
                    ?? CommandPart(text: "Output", role: .missing)
            ]
        case .field(let id, let part):
            guard let field = task.field(withID: id) else { return [] }
            let value = value(of: field)
            guard let value, value.isSet else {
                return field.isRequired ? [CommandPart(text: field.label, role: .missing)] : []
            }
            switch field.kind {
            case .secret:
                return [CommandPart(text: value.argumentText, role: .secret)]
            case .inputFile, .inputFolder, .outputFolder:
                return value.paths.map { CommandPart(text: part.of($0), role: .path) }
            default:
                return [CommandPart(text: value.argumentText, role: .value)]
            }
        }
    }

    /// Fills a template string, or returns nil when a required value it needs is missing.
    func interpolate(_ template: String) -> String? {
        guard let segments = try? TemplateParser.segments(of: template) else { return template }
        guard missingLabel(in: segments) == nil else { return nil }
        return interpolate(segments)
    }

    private func interpolate(_ segments: [TemplateSegment]) -> String? {
        var text = ""
        for segment in segments {
            switch segment {
            case .literal(let literal):
                text += literal
            case .placeholder(.output(let part)):
                guard let outputPath else { return nil }
                text += part.of(outputPath)
            case .placeholder(.extra):
                text += extraWords.joined(separator: " ")
            case .placeholder(.field(let id, let part)):
                guard let field = task.field(withID: id), let value = value(of: field) else { continue }
                text +=
                    field.kind.holdsPaths
                    ? value.paths.first.map(part.of) ?? "" : value.argumentText
            }
        }
        return text
    }

    private func missingLabel(in segments: [TemplateSegment]) -> String? {
        for case .placeholder(let placeholder) in segments {
            switch placeholder {
            case .output where outputPath == nil:
                return "Output"
            case .field(let id, _):
                guard let field = task.field(withID: id), field.isRequired else { continue }
                if value(of: field)?.isSet != true { return field.label }
            default:
                continue
            }
        }
        return nil
    }

    private func isSecretReference(_ segment: TemplateSegment) -> Bool {
        guard case .placeholder(.field(let id, _)) = segment, let field = task.field(withID: id) else { return false }
        return field.kind == .secret
    }

    private static func isFlag(_ text: String) -> Bool {
        text.count > 1 && text.hasPrefix("-")
    }

}
