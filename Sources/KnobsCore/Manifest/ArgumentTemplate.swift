import Foundation

/// One item in a task's `arguments` list. See "Arguments template" in docs/MANIFEST_FORMAT.md.
public indirect enum ArgumentTemplate: Sendable, Hashable {
    /// Becomes exactly one argument after placeholders are filled in, or none when it is only a
    /// placeholder for an unset optional value. `{extra}` and multi-file fields can expand to several.
    case text(String)
    /// Includes `then` when the condition holds, otherwise `otherwise`.
    case conditional(Condition, then: [ArgumentTemplate], otherwise: [ArgumentTemplate])
}

/// `{ "if": "field" }` holds when the field is set; with `"equals": "value"` it holds when the field's value is
/// exactly that text (for choices such as crop versus pad).
public struct Condition: Sendable, Hashable {
    public let fieldID: String
    public let equals: String?

    public init(fieldID: String, equals: String? = nil) {
        self.fieldID = fieldID
        self.equals = equals
    }
}

/// A piece of an argument template string: literal text or a `{placeholder}`.
enum TemplateSegment: Sendable, Hashable {
    case literal(String)
    case placeholder(Placeholder)
}

/// A `{...}` reference inside a template string.
enum Placeholder: Sendable, Hashable {
    case field(id: String, part: PathPart)
    case output(part: PathPart)
    case extra

    static let outputName = "output"
    static let extraName = "extra"
}

/// Which part of a path a placeholder takes. For `/a/clip.mov`: whole `/a/clip.mov`, stem `clip`, name `clip.mov`,
/// ext `mov`, dir `/a`, and base `/a/clip` (the whole path without its extension).
enum PathPart: String, Sendable, Hashable, CaseIterable {
    case whole = ""
    case stem
    case name
    case ext
    case dir
    case base

    func of(_ path: String) -> String {
        let path = path as NSString
        return switch self {
        case .whole: path as String
        case .name: path.lastPathComponent
        case .stem: (path.lastPathComponent as NSString).deletingPathExtension
        case .ext: path.pathExtension
        case .dir: path.deletingLastPathComponent
        case .base: path.deletingPathExtension
        }
    }
}

enum TemplateParseError: Error, Equatable {
    case unclosedBrace
    case unexpectedClosingBrace
    case emptyPlaceholder
    case unknownPathPart(String)
}

/// Splits a template string into literal text and placeholders. `{{` and `}}` stand for literal braces.
enum TemplateParser {
    static func segments(of template: String) throws(TemplateParseError) -> [TemplateSegment] {
        var segments: [TemplateSegment] = []
        var literal = ""
        var index = template.startIndex

        func flushLiteral() {
            if !literal.isEmpty {
                segments.append(.literal(literal))
                literal = ""
            }
        }

        while index < template.endIndex {
            let character = template[index]
            let next = template.index(after: index)
            if character == "{", next < template.endIndex, template[next] == "{" {
                literal.append("{")
                index = template.index(after: next)
            } else if character == "}", next < template.endIndex, template[next] == "}" {
                literal.append("}")
                index = template.index(after: next)
            } else if character == "{" {
                guard let close = template[next...].firstIndex(of: "}") else { throw .unclosedBrace }
                flushLiteral()
                segments.append(.placeholder(try placeholder(from: String(template[next..<close]))))
                index = template.index(after: close)
            } else if character == "}" {
                throw .unexpectedClosingBrace
            } else {
                literal.append(character)
                index = next
            }
        }
        flushLiteral()
        return segments
    }

    private static func placeholder(from body: String) throws(TemplateParseError) -> Placeholder {
        guard !body.isEmpty else { throw .emptyPlaceholder }
        if body == Placeholder.extraName { return .extra }
        let pieces = body.split(separator: ".", maxSplits: 1).map(String.init)
        var part = PathPart.whole
        if pieces.count == 2 {
            guard let named = PathPart(rawValue: pieces[1]), named != .whole else { throw .unknownPathPart(pieces[1]) }
            part = named
        }
        return pieces[0] == Placeholder.outputName ? .output(part: part) : .field(id: pieces[0], part: part)
    }
}
