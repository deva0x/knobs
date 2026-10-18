/// A parsed JSON document. Manifests are read through this instead of `Codable` models so that every
/// error can name the exact JSON path, and so unknown keys are rejected instead of silently ignored.
enum JSONValue: Sendable, Hashable, Decodable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case integer(Int)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let integer = try? container.decode(Int.self) {
            self = .integer(integer)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    var typeDescription: String {
        switch self {
        case .object: "an object"
        case .array: "a list"
        case .string: "a string"
        case .integer: "a whole number"
        case .number: "a number"
        case .bool: "true or false"
        case .null: "null"
        }
    }
}
