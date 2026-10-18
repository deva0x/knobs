/// One item in a task's `arguments` list. See "Arguments template" in docs/MANIFEST_FORMAT.md.
public indirect enum ArgumentTemplate: Sendable, Hashable {
    /// Becomes exactly one argument after placeholders are filled in, or none when it is only a
    /// placeholder for an unset optional value. `{extra}` and multi-file fields can expand to several.
    case text(String)
    /// Includes `then` when the field is set, otherwise `otherwise`.
    case conditional(fieldID: String, then: [ArgumentTemplate], otherwise: [ArgumentTemplate])
}

/// A piece of an argument template string: literal text or a `{placeholder}`.
enum TemplateSegment: Sendable, Hashable {
    case literal(String)
    case placeholder(Placeholder)
}

/// A `{...}` reference inside a template string.
enum Placeholder: Sendable, Hashable {
    case field(id: String, part: PathPart)
    case output
    case extra

    static let outputName = "output"
    static let extraName = "extra"
}

/// Which part of a path a placeholder takes: `{input}`, `{input.stem}`, `{input.name}`, `{input.ext}` or `{input.dir}`.
enum PathPart: String, Sendable, Hashable, CaseIterable {
    case whole = ""
    case stem
    case name
    case ext
    case dir
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
        if body == Placeholder.outputName { return .output }
        if body == Placeholder.extraName { return .extra }
        let pieces = body.split(separator: ".", maxSplits: 1).map(String.init)
        guard pieces.count == 2 else { return .field(id: body, part: .whole) }
        guard let part = PathPart(rawValue: pieces[1]), part != .whole else {
            throw .unknownPathPart(pieces[1])
        }
        return .field(id: pieces[0], part: part)
    }
}
