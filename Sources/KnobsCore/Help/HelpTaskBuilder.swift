/// Turns parsed help options into an ordinary `ManifestTask`, so "All options" reuses the same command building,
/// preview and running as hand-written tasks.
public enum HelpTaskBuilder {
    public static let taskID = "all-options"
    public static let filesFieldID = "files"

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

    /// Every option becomes an optional field: a toggle when it takes no value, otherwise a text field. Files
    /// chosen by the user go last, after any extra arguments.
    public static func task(from options: [HelpOption], toolName: String) -> GeneratedTask {
        var fields: [Field] = []
        var arguments: [ArgumentTemplate] = []
        var mapping: [(fieldID: String, option: HelpOption)] = []

        for (index, option) in options.enumerated() {
            let fieldID = "option\(index + 1)"
            let flag = escapeBraces(option.preferredFlag)
            if let valueName = option.valueName {
                fields.append(
                    Field(
                        id: fieldID, label: option.preferredFlag, help: option.summary.nonEmpty, isRequired: false,
                        kind: .text(placeholder: valueName), defaultValue: nil))
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

    private static func escapeBraces(_ text: String) -> String {
        text.replacing("{", with: "{{").replacing("}", with: "}}")
    }
}

extension String {
    fileprivate var nonEmpty: String? { isEmpty ? nil : self }
}
