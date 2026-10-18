/// One command-line tool and the everyday tasks Knobs offers for it. See docs/MANIFEST_FORMAT.md.
public struct ToolManifest: Sendable, Hashable, Identifiable {
    public static let supportedSchemaVersion = 1

    public let id: String
    public let name: String
    public let summary: String
    /// A bare executable name such as `ffmpeg`, resolved by `ToolLocator`. Never a path.
    public let executable: String
    public let brewFormula: String
    public let homepage: String?
    public let symbol: String
    public let tint: Tint
    public let tasks: [ManifestTask]
    /// The arguments that make the tool print its options, for "All options". Usually `--help`.
    public let helpArguments: [String]

    public static let defaultHelpArguments = ["--help"]

    public init(
        id: String,
        name: String,
        summary: String,
        executable: String,
        brewFormula: String,
        homepage: String?,
        symbol: String,
        tint: Tint,
        tasks: [ManifestTask],
        helpArguments: [String] = ToolManifest.defaultHelpArguments
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.executable = executable
        self.brewFormula = brewFormula
        self.homepage = homepage
        self.symbol = symbol
        self.tint = tint
        self.tasks = tasks
        self.helpArguments = helpArguments
    }

    public func task(withID taskID: String) -> ManifestTask? {
        tasks.first { $0.id == taskID }
    }
}

/// The color family of a tool's glyph tile. The app maps each case to a system color.
public enum Tint: String, Sendable, Hashable, CaseIterable, Codable {
    case purple, red, teal, indigo, orange, blue, gray, green, cyan, brown, pink, yellow, mint
}

/// One everyday job a tool can do, such as "Shrink a video".
public struct ManifestTask: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let symbol: String
    public let fields: [Field]
    public let output: OutputRule?
    public let arguments: [ArgumentTemplate]
    public let progress: ProgressRule?
    /// A regular expression with one group that captures the output file's path from the tool's own output,
    /// for tools that name their files themselves (yt-dlp, whisper.cpp).
    public let outputPathPattern: String?

    public init(
        id: String,
        title: String,
        summary: String,
        symbol: String,
        fields: [Field],
        output: OutputRule?,
        arguments: [ArgumentTemplate],
        progress: ProgressRule?,
        outputPathPattern: String? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.symbol = symbol
        self.fields = fields
        self.output = output
        self.arguments = arguments
        self.progress = progress
        self.outputPathPattern = outputPathPattern
    }

    public func field(withID fieldID: String) -> Field? {
        fields.first { $0.id == fieldID }
    }
}

/// One control in a task's form.
public struct Field: Sendable, Hashable, Identifiable {
    public let id: String
    public let label: String
    public let help: String?
    public let isRequired: Bool
    public let kind: FieldKind
    public let defaultValue: FieldValue?

    public init(
        id: String,
        label: String,
        help: String?,
        isRequired: Bool,
        kind: FieldKind,
        defaultValue: FieldValue?
    ) {
        self.id = id
        self.label = label
        self.help = help
        self.isRequired = isRequired
        self.kind = kind
        self.defaultValue = defaultValue
    }
}

public enum FieldKind: Sendable, Hashable {
    /// `contentTypes` holds UTType identifiers such as `public.movie`; empty means any file.
    case inputFile(contentTypes: [String], allowsMultiple: Bool)
    case inputFolder
    case outputFolder
    case choice(options: [ChoiceOption])
    case integer(range: ClosedRange<Int>)
    case number(range: ClosedRange<Double>?)
    case toggle
    case text(placeholder: String?)
    /// A secret such as an archive password: never saved in presets or shown in the command preview.
    case secret

    /// File and folder kinds hold paths, which `{id.stem}`, `{id.name}` and `{id.dir}` can take apart.
    public var holdsPaths: Bool {
        switch self {
        case .inputFile, .inputFolder, .outputFolder: true
        default: false
        }
    }
}

public struct ChoiceOption: Sendable, Hashable, Codable {
    public let value: String
    public let label: String

    public init(value: String, label: String) {
        self.value = value
        self.label = label
    }
}

/// How a task names its output file.
public struct OutputRule: Sendable, Hashable {
    public enum Location: Sendable, Hashable {
        /// Next to the file in this `inputFile` field.
        case nextTo(fieldID: String)
        /// Inside the folder chosen in this `outputFolder` field.
        case folder(fieldID: String)
    }

    /// A file name template using the same placeholders as arguments, such as `{input.stem} small.mp4`.
    public let template: String
    public let location: Location

    public init(template: String, location: Location) {
        self.template = template
        self.location = location
    }
}

/// How to read progress from a tool's output lines. Patterns are regular expressions whose groups hold numbers.
public enum ProgressRule: Sendable, Hashable {
    case percent(pattern: String)
    case elapsedOfTotal(currentPattern: String, totalPattern: String)
}
