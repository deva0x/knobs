/// Splits the "Extra arguments" box into words using shell quoting rules, without ever invoking a shell.
///
/// - Whitespace separates words.
/// - `'single quotes'` keep everything literally.
/// - `"double quotes"` keep spaces; inside them a backslash escapes only `"` and `\`.
/// - Outside quotes, a backslash escapes the next character.
public enum ArgumentSplitter {
    public enum SplitError: Error, Sendable, Hashable {
        case unclosedQuote(Character)
        case trailingBackslash
    }

    public static func split(_ text: String) throws(SplitError) -> [String] {
        var words: [String] = []
        var current = ""
        var hasWord = false
        var characters = text.makeIterator()

        while let character = characters.next() {
            switch character {
            case "'":
                hasWord = true
                var closed = false
                while let quoted = characters.next() {
                    if quoted == "'" {
                        closed = true
                        break
                    }
                    current.append(quoted)
                }
                guard closed else { throw .unclosedQuote("'") }
            case "\"":
                hasWord = true
                var closed = false
                while let quoted = characters.next() {
                    if quoted == "\"" {
                        closed = true
                        break
                    }
                    if quoted == "\\" {
                        guard let escaped = characters.next() else { throw .unclosedQuote("\"") }
                        if escaped != "\"" && escaped != "\\" { current.append("\\") }
                        current.append(escaped)
                    } else {
                        current.append(quoted)
                    }
                }
                guard closed else { throw .unclosedQuote("\"") }
            case "\\":
                guard let escaped = characters.next() else { throw .trailingBackslash }
                hasWord = true
                current.append(escaped)
            case _ where character.isWhitespace:
                if hasWord {
                    words.append(current)
                    current = ""
                    hasWord = false
                }
            default:
                hasWord = true
                current.append(character)
            }
        }
        if hasWord { words.append(current) }
        return words
    }
}
