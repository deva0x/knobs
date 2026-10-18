import Foundation

/// One option found in a tool's help text, such as `-o, --output TEMPLATE  Output filename template`.
public struct HelpOption: Sendable, Hashable {
    public enum ValueStyle: Sendable, Hashable {
        /// `--output NAME`: the flag and the value are two arguments.
        case separate
        /// `--info=FLAGS`: one argument joined with `=`.
        case equals
        /// `-o{Directory}`, `-g<w>x<h>`: the value is glued to the flag.
        case attached
    }

    /// Every spelling of the option, as written: `["-o", "--output"]`.
    public let flags: [String]
    /// The name of the value it takes, such as `TEMPLATE`, or nil for an on/off option.
    public let valueName: String?
    public let valueStyle: ValueStyle
    public let summary: String
    /// True for options such as jq's `--arg name value`, which take more than one argument after the flag.
    public let takesSeveralValues: Bool

    public init(
        flags: [String], valueName: String?, valueStyle: ValueStyle, summary: String, takesSeveralValues: Bool = false
    ) {
        self.flags = flags
        self.valueName = valueName
        self.valueStyle = valueStyle
        self.summary = summary
        self.takesSeveralValues = takesSeveralValues
    }

    /// The spelling used in the command: the long form when there is one, because it reads better.
    public var preferredFlag: String {
        flags.first { $0.hasPrefix("--") } ?? flags[0]
    }
}

/// Reads options out of `--help` output. Help text has no standard format, so this is best effort and
/// deliberately conservative: a line counts only when it starts with a flag. Help text is untrusted data; it only
/// ever becomes labels and argv entries, never anything that runs.
public enum HelpParser {
    /// Big tools list thousands of options; past this many, the rest are ignored.
    public static let maximumOptions = 600
    /// Long descriptions are cut to keep the list readable.
    public static let maximumSummaryLength = 280

    public static func options(in helpText: String) -> [HelpOption] {
        var options: [HelpOption] = []
        var seen: Set<String> = []
        // `hasGap` is false when the line had no column gap, so description words may be mixed into `spec`.
        var pending: (spec: [String], summary: String, indent: Int, hasGap: Bool)?

        func flush() {
            guard let current = pending else { return }
            pending = nil
            // A flag seen before means a table that repeats options (such as yt-dlp's preset aliases): skip it.
            guard
                let option = makeOption(
                    specTokens: current.spec, summary: current.summary, specIsSeparate: current.hasGap),
                seen.isDisjoint(with: option.flags), options.count < maximumOptions
            else { return }
            seen.formUnion(option.flags)
            options.append(option)
        }

        for rawLine in helpText.components(separatedBy: .newlines) {
            let line = rawLine.replacingOccurrences(of: "\t", with: "    ")
            let indent = line.prefix { $0 == " " }.count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
                continue
            }
            // A deeper-indented line with no column gap continues the description, even when it starts with a
            // flag, as in "unlike\n                 --force-ocr)." Without this, wrapped text would become options.
            if var current = pending, indent > current.indent, !hasColumnGap(trimmed) {
                current.summary = current.summary.isEmpty ? trimmed : current.summary + " " + trimmed
                pending = current
            } else if trimmed.hasPrefix("-"), isFlagStart(trimmed) {
                flush()
                // Some tools print two options per line, separated by " | " (Ghostscript).
                let columns = trimmed.components(separatedBy: " | ").filter { isFlagStart($0.trimmed) }
                for (index, column) in (columns.isEmpty ? [trimmed] : columns).enumerated() {
                    let (spec, summary) = splitSpecAndSummary(column.trimmed)
                    if index > 0 { flush() }
                    pending = (spec, summary, indent, hasColumnGap(column.trimmed))
                }
            } else if var current = pending, indent > current.indent, !trimmed.hasPrefix("-") {
                current.summary = current.summary.isEmpty ? trimmed : current.summary + " " + trimmed
                pending = current
            } else {
                flush()
            }
        }
        flush()
        return options
    }

    /// Whether a line has the gap that separates an option from its description: two or more spaces, or " : ".
    private static func hasColumnGap(_ line: String) -> Bool {
        line.contains(" : ") || line.contains(/\S\s{2,}\S/)
    }

    /// `-x` or `--long`, not a lone dash, a negative number or a divider such as `---`.
    private static func isFlagStart(_ text: String) -> Bool {
        let afterDashes = text.drop { $0 == "-" }
        let dashCount = text.count - afterDashes.count
        guard (1...2).contains(dashCount), let first = afterDashes.first else { return false }
        return first.isLetter || (dashCount == 1 && first.isNumber && afterDashes.dropFirst().first?.isLetter == true)
    }

    /// Splits `-o, --output TEMPLATE   Output filename` into spec words and the summary. Columns are separated by
    /// two or more spaces or by ` : `; a column that starts with a dash still belongs to the spec.
    private static func splitSpecAndSummary(_ line: String) -> (spec: [String], summary: String) {
        var columns = line.components(separatedBy: " : ")
        if columns.count == 1 {
            columns = line.split(separator: /\s{2,}/).map(String.init)
        } else {
            columns = [columns[0], columns.dropFirst().joined(separator: " : ")]
        }
        var specColumns: [String] = []
        var index = 0
        while index < columns.count, index == 0 || isFlagStart(columns[index]) {
            specColumns.append(columns[index])
            index += 1
        }
        var summary = columns[index...].joined(separator: " ")
        // whisper.cpp prints the default in brackets before the description: "[4      ] number of threads".
        if summary.hasPrefix("["), let close = summary.firstIndex(of: "]") {
            summary = String(summary[summary.index(after: close)...])
        }
        let words = specColumns.joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .map(String.init)
        return (joiningAngleBrackets(words), summary.trimmed)
    }

    /// Keeps a value name written over several words, such as curl's `<list of ciphers>`, as one token.
    private static func joiningAngleBrackets(_ words: [String]) -> [String] {
        var tokens: [String] = []
        var open: String?
        for word in words {
            if let started = open {
                open = started + " " + word
                if word.hasSuffix(">") {
                    tokens.append(open ?? word)
                    open = nil
                }
            } else if word.hasPrefix("<") && !word.contains(">") {
                open = word
            } else {
                tokens.append(word)
            }
        }
        if let open { tokens.append(open) }
        return tokens
    }

    private static func makeOption(specTokens: [String], summary: String, specIsSeparate: Bool) -> HelpOption? {
        var flags: [String] = []
        var valueName: String?
        var style = HelpOption.ValueStyle.separate
        // Value words after the last flag, without bracketed defaults such as "[100 ]".
        var valuesAfterLastFlag: [String] = []
        for token in specTokens {
            if token.hasPrefix("-"), isFlagStart(token) {
                valuesAfterLastFlag = []
                let (flag, attachedValue, attachedStyle) = splitFlag(token)
                guard flag.count > 1 else { continue }
                if !flags.contains(flag) { flags.append(flag) }
                if let attachedValue, valueName == nil {
                    valueName = attachedValue
                    style = attachedStyle
                }
            } else if !flags.isEmpty, looksLikeValueName(token) {
                if valueName == nil { valueName = cleanValueName(token) }
                if !token.hasPrefix("[") { valuesAfterLastFlag.append(cleanValueName(token)) }
            }
        }
        // Exactly two value words, as in "--arg name value", mean two arguments. Trusted only when the line had a
        // column gap and the value is separate; more words than that are description run into the spec.
        let takesSeveralValues = specIsSeparate && style == .separate && valuesAfterLastFlag.count == 2
        if takesSeveralValues { valueName = valuesAfterLastFlag.joined(separator: " ") }
        guard !flags.isEmpty else { return nil }
        var summary = summary
        // Some tools repeat the value and its default before the description: "N [30 ] VAD speech padding".
        if let valueName, summary.hasPrefix(valueName + " ["), let close = summary.firstIndex(of: "]") {
            summary = String(summary[summary.index(after: close)...]).trimmed
        }
        let clipped =
            summary.count > maximumSummaryLength ? String(summary.prefix(maximumSummaryLength)) + "…" : summary
        return HelpOption(
            flags: flags, valueName: valueName.flatMap { $0.isEmpty ? nil : $0 }, valueStyle: style, summary: clipped,
            takesSeveralValues: takesSeveralValues)
    }

    /// `--info=FLAGS` → (`--info`, `FLAGS`, equals); `-o{Directory}` → (`-o`, `Directory`, attached);
    /// `-s[true|false]` → (`-s`, nil): an optional value in brackets alone is treated as an on/off option, but
    /// `-i[r[-|0]]{@listfile}` still takes the value that follows its optional brackets.
    private static func splitFlag(_ token: String) -> (String, String?, HelpOption.ValueStyle) {
        let dashes = token.prefix { $0 == "-" }
        let body = token.dropFirst(dashes.count)
        guard let stop = body.firstIndex(where: { "=<{[".contains($0) }) else {
            return (String(token), nil, .separate)
        }
        let flag = String(dashes) + body[..<stop]
        var rest = body[stop...]
        while rest.first == "[", let end = closingBracket(in: rest) {
            rest = rest[rest.index(after: end)...]
        }
        switch rest.first {
        case nil: return (flag, nil, .separate)
        case "=": return (flag, cleanValueName(String(rest.dropFirst())), .equals)
        case "[": return (flag, nil, .separate)
        default: return (flag, cleanValueName(String(rest)), .attached)
        }
    }

    /// The index of the `]` that closes the `[` at the start of `text`, allowing nested brackets.
    private static func closingBracket(in text: Substring) -> Substring.Index? {
        var depth = 0
        for index in text.indices {
            switch text[index] {
            case "[": depth += 1
            case "]":
                depth -= 1
                if depth == 0 { return index }
            default: break
            }
        }
        return nil
    }

    /// `FILE`, `<path>`, `{Directory}`, `N`: but not `(*)`, `--` or other punctuation.
    private static func looksLikeValueName(_ token: String) -> Bool {
        guard let first = token.first else { return false }
        return first.isLetter || first.isNumber || "<{[".contains(first)
    }

    private static func cleanValueName(_ token: String) -> String {
        token.trimmingCharacters(in: CharacterSet(charactersIn: "<>{}[]=\"'"))
    }
}

extension String {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespaces) }
}
