import Foundation

/// Turns manifest JSON into a `ToolManifest`, rejecting wrong types and unknown keys with the exact JSON path.
/// Cross-references (placeholders, defaults, ids) are checked afterwards by `ManifestValidator`.
enum ManifestReader {
    static func read(_ data: Data, source: String) throws(ManifestError) -> ToolManifest {
        let document: JSONValue
        do {
            document = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw ManifestError(source: source, path: "", problem: "isn't valid JSON (\(Self.describe(error)))")
        }
        let root = try ObjectReader(
            document, path: "", source: source,
            allowedKeys: [
                "schemaVersion", "id", "name", "summary", "executable", "alternativeExecutables", "install",
                "homepage", "symbol", "tint", "helpArguments",
                "tasks",
            ])
        let version = try root.integer("schemaVersion")
        guard version == ToolManifest.supportedSchemaVersion else {
            throw root.error(
                at: "schemaVersion",
                "is \(version), but this version of Knobs reads schema \(ToolManifest.supportedSchemaVersion)"
            )
        }
        let install = try root.object("install", allowedKeys: ["brew"])
        let tintName = try root.string("tint")
        guard let tint = Tint(rawValue: tintName) else {
            let names = Tint.allCases.map(\.rawValue).joined(separator: ", ")
            throw root.error(at: "tint", "\"\(tintName)\" isn't one of: \(names)")
        }
        let tasks = try root.array("tasks").map { item throws(ManifestError) in try readTask(item) }
        return ToolManifest(
            id: try root.string("id"),
            name: try root.string("name"),
            summary: try root.string("summary"),
            executable: try root.string("executable"),
            alternativeExecutables: try root.optionalStringArray("alternativeExecutables") ?? [],
            brewFormula: try install.string("brew"),
            homepage: try root.optionalString("homepage"),
            symbol: try root.string("symbol"),
            tint: tint,
            tasks: tasks,
            helpArguments: try root.optionalStringArray("helpArguments") ?? ToolManifest.defaultHelpArguments
        )
    }

    private static func readTask(_ item: JSONElement) throws(ManifestError) -> ManifestTask {
        let task = try item.object(allowedKeys: [
            "id", "title", "summary", "symbol", "fields", "output", "arguments", "progress", "outputPathPattern",
        ])
        return ManifestTask(
            id: try task.string("id"),
            title: try task.string("title"),
            summary: try task.string("summary"),
            symbol: try task.string("symbol"),
            fields: try task.array("fields").map { item throws(ManifestError) in try readField(item) },
            output: try task.optionalObject("output", allowedKeys: ["template", "nextTo", "folder", "newFolder"]).map {
                output throws(ManifestError) in try readOutput(output)
            },
            arguments: try task.array("arguments").map { item throws(ManifestError) in try readArgument(item) },
            progress: try task.optionalObject("progress", allowedKeys: ["percent", "current", "total"]).map {
                progress throws(ManifestError) in try readProgress(progress)
            },
            outputPathPattern: try task.optionalString("outputPathPattern")
        )
    }

    private static let commonFieldKeys: Set<String> = ["id", "label", "kind", "help", "required"]

    private static func readField(_ item: JSONElement) throws(ManifestError) -> Field {
        let kindName = try item.object(allowedKeys: nil).string("kind")
        let kindKeys: Set<String> =
            switch kindName {
            case "inputFile": ["contentTypes", "multiple"]
            case "choice": ["options", "default"]
            case "integer", "number": ["minimum", "maximum", "default"]
            case "toggle": ["default"]
            case "text": ["placeholder", "default"]
            case "inputFolder", "outputFolder": ["default"]
            default: []
            }
        let field = try item.object(allowedKeys: commonFieldKeys.union(kindKeys))
        let kind: FieldKind
        var defaultValue: FieldValue?
        switch kindName {
        case "inputFile":
            kind = .inputFile(
                contentTypes: try field.optionalStringArray("contentTypes") ?? [],
                allowsMultiple: try field.optionalBool("multiple") ?? false
            )
        case "inputFolder", "outputFolder":
            kind = kindName == "inputFolder" ? .inputFolder : .outputFolder
            defaultValue = try field.optionalString("default").map { FieldValue.paths([$0]) }
        case "choice":
            kind = .choice(
                options: try field.array("options").map { option throws(ManifestError) in
                    let reader = try option.object(allowedKeys: ["value", "label"])
                    return ChoiceOption(value: try reader.string("value"), label: try reader.string("label"))
                }
            )
            defaultValue = try field.optionalString("default").map(FieldValue.text)
        case "integer":
            let minimum = try field.integer("minimum")
            let maximum = try field.integer("maximum")
            guard minimum <= maximum else { throw field.error(at: "maximum", "is smaller than minimum") }
            kind = .integer(range: minimum...maximum)
            defaultValue = try field.optionalInteger("default").map(FieldValue.integer)
        case "number":
            let minimum = try field.optionalNumber("minimum")
            let maximum = try field.optionalNumber("maximum")
            var range: ClosedRange<Double>?
            switch (minimum, maximum) {
            case (nil, nil): range = nil
            case (let minimum?, let maximum?):
                guard minimum <= maximum else { throw field.error(at: "maximum", "is smaller than minimum") }
                range = minimum...maximum
            default: throw field.error(at: "", "needs both minimum and maximum, or neither")
            }
            kind = .number(range: range)
            defaultValue = try field.optionalNumber("default").map(FieldValue.number)
        case "toggle":
            kind = .toggle
            defaultValue = try field.optionalBool("default").map(FieldValue.toggle)
        case "text":
            kind = .text(placeholder: try field.optionalString("placeholder"))
            defaultValue = try field.optionalString("default").map(FieldValue.text)
        case "secret": kind = .secret
        default:
            throw field.error(
                at: "kind",
                "\"\(kindName)\" isn't a field kind. Use inputFile, inputFolder, outputFolder, choice, integer, "
                    + "number, toggle, text or secret"
            )
        }
        return Field(
            id: try field.string("id"),
            label: try field.string("label"),
            help: try field.optionalString("help"),
            isRequired: try field.optionalBool("required") ?? kind.holdsPaths,
            kind: kind,
            defaultValue: defaultValue
        )
    }

    private static func readArgument(_ item: JSONElement) throws(ManifestError) -> ArgumentTemplate {
        if case .string(let text) = item.value { return .text(text) }
        let conditional = try item.object(allowedKeys: ["if", "equals", "then", "else"])
        return .conditional(
            Condition(fieldID: try conditional.string("if"), equals: try conditional.optionalString("equals")),
            then: try conditional.array("then").map { item throws(ManifestError) in try readArgument(item) },
            otherwise: try conditional.optionalArray("else")?.map { item throws(ManifestError) in
                try readArgument(item)
            } ?? []
        )
    }

    private static func readOutput(_ output: ObjectReader) throws(ManifestError) -> OutputRule {
        let template = try output.string("template")
        let isNewFolder = try output.optionalBool("newFolder") ?? false
        switch (try output.optionalString("nextTo"), try output.optionalString("folder")) {
        case (let fieldID?, nil):
            return OutputRule(template: template, location: .nextTo(fieldID: fieldID), isNewFolder: isNewFolder)
        case (nil, let fieldID?):
            return OutputRule(template: template, location: .folder(fieldID: fieldID), isNewFolder: isNewFolder)
        default: throw output.error(at: "", "needs exactly one of nextTo or folder")
        }
    }

    private static func readProgress(_ progress: ObjectReader) throws(ManifestError) -> ProgressRule {
        switch (
            try progress.optionalString("percent"), try progress.optionalString("current"),
            try progress.optionalString("total")
        ) {
        case (let percent?, nil, nil): return .percent(pattern: percent)
        case (nil, let current?, let total?): return .elapsedOfTotal(currentPattern: current, totalPattern: total)
        default: throw progress.error(at: "", "needs either percent, or both current and total")
        }
    }

    private static func describe(_ error: any Error) -> String {
        guard case DecodingError.dataCorrupted(let context) = error else { return error.localizedDescription }
        let underlying = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
        return underlying ?? context.debugDescription
    }
}

/// A JSON value together with where it sits in the document, for error messages.
struct JSONElement {
    let value: JSONValue
    let path: String
    let source: String

    func object(allowedKeys: Set<String>?) throws(ManifestError) -> ObjectReader {
        try ObjectReader(value, path: path, source: source, allowedKeys: allowedKeys)
    }
}

/// Reads typed members of one JSON object. Every failure names the member's path.
struct ObjectReader {
    private let members: [String: JSONValue]
    private let path: String
    private let source: String

    /// `allowedKeys` nil skips the unknown-key check, for a first look at a discriminator such as `kind`.
    init(_ value: JSONValue, path: String, source: String, allowedKeys: Set<String>?) throws(ManifestError) {
        self.path = path
        self.source = source
        guard case .object(let members) = value else {
            throw ManifestError(
                source: source, path: path, problem: "should be an object, not \(value.typeDescription)")
        }
        if let allowedKeys, let unknown = members.keys.filter({ !allowedKeys.contains($0) }).sorted().first {
            throw ManifestError(
                source: source,
                path: Self.join(path, unknown),
                problem: "isn't a known key here. Known keys: \(allowedKeys.sorted().joined(separator: ", "))"
            )
        }
        self.members = members
    }

    func error(at key: String, _ problem: String) -> ManifestError {
        ManifestError(source: source, path: key.isEmpty ? path : Self.join(path, key), problem: problem)
    }

    func string(_ key: String) throws(ManifestError) -> String {
        guard let value = try optionalString(key) else { throw error(at: key, "is missing") }
        return value
    }

    func optionalString(_ key: String) throws(ManifestError) -> String? {
        guard let value = members[key] else { return nil }
        guard case .string(let string) = value else { throw mismatch(key, expected: "a string", got: value) }
        return string
    }

    func integer(_ key: String) throws(ManifestError) -> Int {
        guard let value = try optionalInteger(key) else { throw error(at: key, "is missing") }
        return value
    }

    func optionalInteger(_ key: String) throws(ManifestError) -> Int? {
        guard let value = members[key] else { return nil }
        guard case .integer(let integer) = value else { throw mismatch(key, expected: "a whole number", got: value) }
        return integer
    }

    func optionalNumber(_ key: String) throws(ManifestError) -> Double? {
        switch members[key] {
        case nil: return nil
        case .integer(let integer): return Double(integer)
        case .number(let number): return number
        case let value?: throw mismatch(key, expected: "a number", got: value)
        }
    }

    func optionalBool(_ key: String) throws(ManifestError) -> Bool? {
        guard let value = members[key] else { return nil }
        guard case .bool(let bool) = value else { throw mismatch(key, expected: "true or false", got: value) }
        return bool
    }

    func object(_ key: String, allowedKeys: Set<String>) throws(ManifestError) -> ObjectReader {
        guard let reader = try optionalObject(key, allowedKeys: allowedKeys) else { throw error(at: key, "is missing") }
        return reader
    }

    func optionalObject(_ key: String, allowedKeys: Set<String>) throws(ManifestError) -> ObjectReader? {
        guard let value = members[key] else { return nil }
        return try ObjectReader(value, path: Self.join(path, key), source: source, allowedKeys: allowedKeys)
    }

    func array(_ key: String) throws(ManifestError) -> [JSONElement] {
        guard let elements = try optionalArray(key) else { throw error(at: key, "is missing") }
        return elements
    }

    func optionalArray(_ key: String) throws(ManifestError) -> [JSONElement]? {
        guard let value = members[key] else { return nil }
        guard case .array(let items) = value else { throw mismatch(key, expected: "a list", got: value) }
        let base = Self.join(path, key)
        return items.enumerated().map { index, item in
            JSONElement(value: item, path: "\(base)[\(index)]", source: source)
        }
    }

    func optionalStringArray(_ key: String) throws(ManifestError) -> [String]? {
        try optionalArray(key)?.map { element throws(ManifestError) in
            guard case .string(let string) = element.value else {
                throw ManifestError(
                    source: source, path: element.path,
                    problem: "should be a string, not \(element.value.typeDescription)"
                )
            }
            return string
        }
    }

    private func mismatch(_ key: String, expected: String, got value: JSONValue) -> ManifestError {
        error(at: key, "should be \(expected), not \(value.typeDescription)")
    }

    private static func join(_ path: String, _ key: String) -> String {
        path.isEmpty ? key : "\(path).\(key)"
    }
}
