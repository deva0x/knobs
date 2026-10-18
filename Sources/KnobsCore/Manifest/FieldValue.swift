import Foundation

/// The value a user has set for one field.
public enum FieldValue: Sendable, Hashable, Codable {
    case text(String)
    case integer(Int)
    case number(Double)
    case toggle(Bool)
    /// Absolute paths, in the order the user added them. Single-file fields hold one.
    case paths([String])

    /// Whether this value counts as "set" for `if` conditionals and required fields.
    public var isSet: Bool {
        switch self {
        case .text(let text): !text.isEmpty
        case .integer, .number: true
        case .toggle(let isOn): isOn
        case .paths(let paths): !paths.isEmpty
        }
    }

    /// The text that goes into an argument. Paths join with a space only for display of multi-file values,
    /// which validation keeps out of interpolated arguments.
    var argumentText: String {
        switch self {
        case .text(let text): text
        case .integer(let integer): String(integer)
        case .number(let number): Self.format(number)
        case .toggle(let isOn): isOn ? "true" : "false"
        case .paths(let paths): paths.joined(separator: " ")
        }
    }

    var paths: [String] {
        if case .paths(let paths) = self { return paths }
        return []
    }

    /// Formats a number without a trailing `.0`, so 2.0 becomes "2" and 1.5 stays "1.5".
    private static func format(_ number: Double) -> String {
        if number.rounded() == number, abs(number) < 1e15 {
            return String(Int64(number))
        }
        return String(number)
    }
}
