/// Turns parsed help options into an ordinary `ManifestTask`, so "All options" reuses the same command building,
/// preview and running as hand-written tasks.
public enum HelpTaskBuilder {
    public static let taskID = "all-options"
    public static let filesFieldID = "files"
    /// Options that only print help or a version are left out; they would just replace the real work.
    static let informationalFlags: Set<String> = [
        "-h", "--help", "-help", "-?", "--usage", "-usage", "--version", "-version",
    ]
    /// Words in a flag that mark its value as a secret, so it is masked and never remembered or saved in presets.
    static let secretWords = [
        "password", "passwd", "passphrase", "phrase", "secret", "token", "apikey", "api-key", "twofactor",
    ]

    /// A generated task plus which field belongs to which option, for the searchable list.
    public struct GeneratedTask: Sendable, Hashable {
        public let task: ManifestTask
        public let options: [(fieldID: String, option: HelpOption)]

        public static func == (lhs: GeneratedTask, rhs: GeneratedTask) -> Bool {
            lhs.task == rhs.task && lhs.options.map(\.fieldID) == rhs.options.map(\.fieldID)
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(task)
        }
    }

    /// Every option becomes an optional field: a toggle when it takes no value, otherwise a text field, or a
    /// secret field for passwords and tokens. Options that take several values (jq's `--arg name value`) are left
    /// to Extra arguments: one field can only give one argument. Files chosen by the user go last, after any
    /// extra arguments.
    public static func task(from options: [HelpOption], toolName: String) -> GeneratedTask {
        var fields: [Field] = []
        var arguments: [ArgumentTemplate] = []
        var mapping: [(fieldID: String, option: HelpOption)] = []

        let useful = options.filter { informationalFlags.isDisjoint(with: $0.flags) && !$0.takesSeveralValues }
        for (index, option) in useful.enumerated() {
            let fieldID = "option\(index + 1)"
            let flag = escapeBraces(option.preferredFlag)
            if let valueName = option.valueName {
                fields.append(
                    Field(
                        id: fieldID, label: option.preferredFlag, help: option.summary.nonEmpty, isRequired: false,
                        kind: isSecret(option) ? .secret : .text(placeholder: valueName), defaultValue: nil))
                let then: [ArgumentTemplate] =
                    switch option.valueStyle {
                    case .separate: [.text(flag), .text("{\(fieldID)}")]
                    case .equals: [.text("\(flag)={\(fieldID)}")]
                    case .attached: [.text("\(flag){\(fieldID)}")]
                    }
                arguments.append(.conditional(Condition(fieldID: fieldID), then: then, otherwise: []))
            } else {
                fields.append(
                    Field(
                        id: fieldID, label: option.preferredFlag, help: option.summary.nonEmpty, isRequired: false,
                        kind: .toggle, defaultValue: .toggle(false)))
                arguments.append(.conditional(Condition(fieldID: fieldID), then: [.text(flag)], otherwise: []))
            }
            mapping.append((fieldID, option))
        }

        fields.append(
            Field(
                id: filesFieldID, label: "Files", help: "Added at the end of the command.", isRequired: false,
                kind: .inputFile(contentTypes: [], allowsMultiple: true), defaultValue: nil))
        arguments.append(.text("{extra}"))
        arguments.append(.text("{\(filesFieldID)}"))

        let task = ManifestTask(
            id: taskID, title: "All options",
            summary: "Every option \(toolName) lists in its help, to switch on as needed.",
            symbol: "list.bullet.rectangle", fields: fields, output: nil, arguments: arguments, progress: nil)
        return GeneratedTask(task: task, options: mapping)
    }

    /// A password or token, judged by the flag and by the value's name (7-Zip's `-p{Password}`, curl's
    /// `-u user:password`, curl's `--pass <phrase>`). A value that names a file, such as rsync's
    /// `--password-file=FILE`, is a path, not a secret. Deliberately cautious: curl's `--cert
    /// <certificate[:password]>` is masked too, because its value can carry a password.
    private static func isSecret(_ option: HelpOption) -> Bool {
        let valueName = option.valueName?.lowercased() ?? ""
        guard !valueName.isEmpty, !valueName.contains("file") else { return false }
        let flags = option.flags.map { $0.lowercased() }
        let isPassFlag = flags.contains { $0.split(separator: "-").contains("pass") }
        return isPassFlag
            || (flags + [valueName]).contains { text in secretWords.contains { text.contains($0) } }
    }

    private static func escapeBraces(_ text: String) -> String {
        text.replacing("{", with: "{{").replacing("}", with: "}}")
    }
}

extension String {
    fileprivate var nonEmpty: String? { isEmpty ? nil : self }
}
