/// Splits the "Extra arguments" box into words using shell quoting rules, without ever invoking a shell.
///
/// - Spaces, tabs and newlines separate words; other Unicode spaces, such as a no-break space, are kept.
/// - `'single quotes'` keep everything literally.
/// - `"double quotes"` keep spaces; inside them a backslash escapes only `"`, `\`, `$` and `` ` ``, as in a POSIX
///   shell.
/// - Outside quotes, a backslash escapes the next character.
/// - A backslash before a newline joins the lines, so a multi-line command pasted from documentation works.
public enum ArgumentSplitter {
    public enum SplitError: Error, Sendable, Hashable {
        case unclosedQuote(Character)
        case trailingBackslash
    }

    /// Swift reads a Windows line ending, "\r\n", as one character, so each spelling is listed.
    private static let lineBreaks: Set<Character> = ["\n", "\r\n", "\r"]
    private static let wordSeparators: Set<Character> = lineBreaks.union([" ", "\t"])
    private static let escapableInDoubleQuotes: Set<Character> = ["\"", "\\", "$", "`"]

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
                        if Self.lineBreaks.contains(escaped) { continue }
                        if !escapableInDoubleQuotes.contains(escaped) { current.append("\\") }
                        current.append(escaped)
                    } else {
                        current.append(quoted)
                    }
                }
                guard closed else { throw .unclosedQuote("\"") }
            case "\\":
                guard let escaped = characters.next() else { throw .trailingBackslash }
                if Self.lineBreaks.contains(escaped) { continue }
                hasWord = true
                current.append(escaped)
            case _ where wordSeparators.contains(character):
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
