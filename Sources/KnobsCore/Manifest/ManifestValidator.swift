import Foundation

/// Checks the rules in "Validation errors" of docs/MANIFEST_FORMAT.md that span more than one key:
/// ids, defaults, placeholders, `{extra}`, `{output}` and progress patterns.
enum ManifestValidator {
    /// Tool and task ids: lowercase letters and digits in groups joined by single dashes.
    private static func isValidID(_ id: String) -> Bool {
        id.wholeMatch(of: /[a-z0-9]+(-[a-z0-9]+)*/) != nil
    }

    /// Field ids appear in `{placeholders}`, so they start with a letter and use only letters and digits.
    private static func isValidFieldID(_ id: String) -> Bool {
        id.wholeMatch(of: /[a-zA-Z][a-zA-Z0-9]*/) != nil
    }
    private static let reservedFieldIDs: Set<String> = [Placeholder.extraName, Placeholder.outputName]

    static func validate(_ manifest: ToolManifest, source: String) throws(ManifestError) {
        func fail(_ path: String, _ problem: String) -> ManifestError {
            ManifestError(source: source, path: path, problem: problem)
        }

        guard isValidID(manifest.id) else {
            throw fail("id", "\"\(manifest.id)\" should use only lowercase letters, digits and single dashes")
        }
        guard !manifest.executable.isEmpty, !manifest.executable.contains("/") else {
            throw fail("executable", "should be a bare name such as \"ffmpeg\", not a path")
        }
        guard !manifest.tasks.isEmpty else { throw fail("tasks", "needs at least one task") }

        var taskIDs: Set<String> = []
        for (taskIndex, task) in manifest.tasks.enumerated() {
            let taskPath = "tasks[\(taskIndex)]"
            guard isValidID(task.id) else {
                throw fail(
                    "\(taskPath).id", "\"\(task.id)\" should use only lowercase letters, digits and single dashes")
            }
            guard taskIDs.insert(task.id).inserted else {
                throw fail("\(taskPath).id", "\"\(task.id)\" is used by another task")
            }
            try validateFields(task.fields, taskPath: taskPath, fail: fail)
            try validateArguments(task, taskPath: taskPath, fail: fail)
            try validateOutput(task, taskPath: taskPath, fail: fail)
            try validateProgress(task.progress, path: "\(taskPath).progress", fail: fail)
        }
    }

    private static func validateFields(
        _ fields: [Field],
        taskPath: String,
        fail: (String, String) -> ManifestError
    ) throws(ManifestError) {
        var fieldIDs: Set<String> = []
        for (index, field) in fields.enumerated() {
            let path = "\(taskPath).fields[\(index)]"
            guard isValidFieldID(field.id) else {
                throw fail("\(path).id", "\"\(field.id)\" should start with a letter and use only letters and digits")
            }
            guard !reservedFieldIDs.contains(field.id) else {
                throw fail("\(path).id", "\"\(field.id)\" is reserved. Choose another id")
            }
            guard fieldIDs.insert(field.id).inserted else {
                throw fail("\(path).id", "\"\(field.id)\" is used by another field in this task")
            }
            try validateDefault(of: field, path: path, fail: fail)
        }
    }

    private static func validateDefault(
        of field: Field,
        path: String,
        fail: (String, String) -> ManifestError
    ) throws(ManifestError) {
        switch (field.kind, field.defaultValue) {
        case (.choice(let options), let value):
            guard !options.isEmpty else { throw fail("\(path).options", "needs at least one option") }
            let values = options.map(\.value)
            guard Set(values).count == values.count else {
                throw fail("\(path).options", "has two options with the same value")
            }
            if case .text(let defaultValue)? = value, !values.contains(defaultValue) {
                throw fail("\(path).default", "\"\(defaultValue)\" isn't one of the option values")
            }
        case (.integer(let range), .integer(let defaultValue)?):
            guard range.contains(defaultValue) else {
                throw fail("\(path).default", "\(defaultValue) is outside \(range.lowerBound) to \(range.upperBound)")
            }
        case (.number(let range?), .number(let defaultValue)?):
            guard range.contains(defaultValue) else {
                throw fail("\(path).default", "\(defaultValue) is outside \(range.lowerBound) to \(range.upperBound)")
            }
        default:
            break
        }
    }

    private static func validateArguments(
        _ task: ManifestTask,
        taskPath: String,
        fail: (String, String) -> ManifestError
    ) throws(ManifestError) {
        var extraCount = 0
        var usesOutput = false

        func walk(_ items: [ArgumentTemplate], path: String) throws(ManifestError) {
            for (index, item) in items.enumerated() {
                let itemPath = "\(path)[\(index)]"
                switch item {
                case .conditional(let fieldID, let then, let otherwise):
                    guard task.field(withID: fieldID) != nil else {
                        throw fail("\(itemPath).if", "refers to \"\(fieldID)\", which isn't a field of this task")
                    }
                    try walk(then, path: "\(itemPath).then")
                    try walk(otherwise, path: "\(itemPath).else")
                case .text(let template):
                    let segments = try parse(template, path: itemPath, fail: fail)
                    let isWholePlaceholder = segments.count == 1
                    for case .placeholder(let placeholder) in segments {
                        switch placeholder {
                        case .extra:
                            guard isWholePlaceholder else {
                                throw fail(
                                    itemPath, "{extra} must be a list item of its own, not part of a longer string")
                            }
                            extraCount += 1
                        case .output:
                            guard task.output != nil else {
                                throw fail(itemPath, "uses {output}, but the task has no output rule")
                            }
                            usesOutput = true
                        case .field(let id, let part):
                            try validateFieldReference(
                                id: id, part: part, in: task, isWholePlaceholder: isWholePlaceholder,
                                path: itemPath, fail: fail
                            )
                        }
                    }
                }
            }
        }

        try walk(task.arguments, path: "\(taskPath).arguments")
        guard extraCount == 1 else {
            throw fail("\(taskPath).arguments", "must contain \"{extra}\" exactly once, but has it \(extraCount) times")
        }
        if task.output != nil, !usesOutput {
            throw fail("\(taskPath).output", "is defined, but no argument uses {output}")
        }
    }

    private static func validateFieldReference(
        id: String,
        part: PathPart,
        in task: ManifestTask,
        isWholePlaceholder: Bool,
        path: String,
        fail: (String, String) -> ManifestError
    ) throws(ManifestError) {
        guard let field = task.field(withID: id) else {
            throw fail(path, "refers to {\(id)}, which isn't a field of this task")
        }
        if part != .whole, !field.kind.holdsPaths {
            throw fail(path, "uses .\(part.rawValue) on {\(id)}, but only file and folder fields have path parts")
        }
        if case .inputFile(_, allowsMultiple: true) = field.kind, !isWholePlaceholder {
            throw fail(path, "{\(id)} holds several files, so it must be a list item of its own")
        }
    }

    private static func validateOutput(
        _ task: ManifestTask,
        taskPath: String,
        fail: (String, String) -> ManifestError
    ) throws(ManifestError) {
        guard let output = task.output else { return }
        let path = "\(taskPath).output"
        switch output.location {
        case .nextTo(let fieldID):
            guard case .inputFile(_, let allowsMultiple)? = task.field(withID: fieldID)?.kind else {
                throw fail("\(path).nextTo", "should name an inputFile field of this task")
            }
            guard !allowsMultiple else {
                throw fail("\(path).nextTo", "names a field that holds several files. Use a single-file field")
            }
        case .folder(let fieldID):
            guard case .outputFolder? = task.field(withID: fieldID)?.kind else {
                throw fail("\(path).folder", "should name an outputFolder field of this task")
            }
        }
        for case .placeholder(let placeholder) in try parse(output.template, path: "\(path).template", fail: fail) {
            switch placeholder {
            case .output, .extra:
                throw fail("\(path).template", "can't use {output} or {extra}")
            case .field(let id, let part):
                try validateFieldReference(
                    id: id, part: part, in: task, isWholePlaceholder: false, path: "\(path).template", fail: fail
                )
            }
        }
    }

    private static func validateProgress(
        _ progress: ProgressRule?,
        path: String,
        fail: (String, String) -> ManifestError
    ) throws(ManifestError) {
        let patterns: [(key: String, pattern: String, groupCounts: Set<Int>)]
        switch progress {
        case nil: return
        case .percent(let pattern): patterns = [("percent", pattern, [1])]
        case .elapsedOfTotal(let current, let total):
            patterns = [("current", current, [1, 3]), ("total", total, [1, 3])]
        }
        for (key, pattern, groupCounts) in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else {
                throw fail("\(path).\(key)", "isn't a valid regular expression")
            }
            guard groupCounts.contains(expression.numberOfCaptureGroups) else {
                let allowed = groupCounts.sorted().map(String.init).joined(separator: " or ")
                throw fail("\(path).\(key)", "should have \(allowed) capture groups")
            }
        }
    }

    private static func parse(
        _ template: String,
        path: String,
        fail: (String, String) -> ManifestError
    ) throws(ManifestError) -> [TemplateSegment] {
        do {
            return try TemplateParser.segments(of: template)
        } catch {
            let problem =
                switch error {
                case .unclosedBrace: "has a { without a matching }"
                case .unexpectedClosingBrace: "has a } without a matching {. Write }} for a literal brace"
                case .emptyPlaceholder: "has an empty {}"
                case .unknownPathPart(let part): "uses .\(part), but only .stem, .name, .ext and .dir exist"
                }
            throw fail(path, problem)
        }
    }
}
