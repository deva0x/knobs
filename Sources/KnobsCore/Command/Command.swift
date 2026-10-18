/// A fully built command: what runs, and how to show it. The preview and the run come from the same value,
/// so the preview can't drift from what actually executes.
public struct Command: Sendable, Hashable {
    /// The bare executable name from the manifest, such as `ffmpeg`. `ToolLocator` resolves it to a path.
    public let executable: String
    public let arguments: [CommandPart]
    /// Where the task's output file will be written, when the task has one.
    public let outputPath: String?

    public init(executable: String, arguments: [CommandPart], outputPath: String?) {
        self.executable = executable
        self.arguments = arguments
        self.outputPath = outputPath
    }

    /// The real argument list passed to `Process`. Only meaningful when `isComplete`.
    public var argv: [String] { arguments.map(\.text) }

    /// False while a required value is still missing.
    public var isComplete: Bool { !arguments.contains { $0.role == .missing } }

    /// The command as one line, quoted for a POSIX shell, with secrets hidden. For reading and copying only.
    public var displayString: String {
        ([ShellQuoting.quote(executable)] + arguments.map(\.displayText)).joined(separator: " ")
    }
}

/// One argument, tagged with what it is so the app can color the preview.
public struct CommandPart: Sendable, Hashable {
    public enum Role: Sendable, Hashable {
        /// A literal from the manifest that starts with a dash, such as `-crf`.
        case flag
        /// Any other value.
        case value
        /// A file or folder path, including the output path.
        case path
        /// A word from the "Extra arguments" box.
        case extra
        /// A secret such as a password. Shown masked.
        case secret
        /// A required value that hasn't been set yet. `text` holds the field's label.
        case missing
    }

    public static let secretMask = "••••••"

    public let text: String
    public let role: Role

    public init(text: String, role: Role) {
        self.text = text
        self.role = role
    }

    /// What the preview shows for this part.
    public var displayText: String {
        switch role {
        case .secret: Self.secretMask
        case .missing: "‹\(text)›"
        default: ShellQuoting.quote(text)
        }
    }
}

/// Something that stops a command from being run as it stands.
public enum CommandProblem: Sendable, Hashable {
    case missingValue(fieldID: String, label: String)
    case extraArguments(ArgumentSplitter.SplitError)
    case outputUnavailable(String)
}

/// The result of building a command: always previewable, runnable only when `problems` is empty.
public struct CommandDraft: Sendable, Hashable {
    public let command: Command
    public let problems: [CommandProblem]

    public var isRunnable: Bool { problems.isEmpty && command.isComplete }
}
