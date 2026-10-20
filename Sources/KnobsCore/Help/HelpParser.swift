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
        // The indent of the line before when it was prose, neither an option, its description nor a heading.
        var proseIndent: Int?

        func flush() {
            guard let current = pending else { return }
            pending = nil
            guard
                let option = makeOption(
                    specTokens: current.spec, summary: current.summary, specIsSeparate: current.hasGap)
            else { return }
            if seen.isDisjoint(with: option.flags) {
                guard options.count < maximumOptions else { return }
                seen.formUnion(option.flags)
                options.append(option)
            } else if let index = options.firstIndex(where: { $0.flags.contains(option.flags[0]) }),
                let filled = filling(options[index], withValueOf: option)
            {
                options[index] = filled
            }
        }

        for rawLine in helpText.components(separatedBy: .newlines) {
            let line = rawLine.replacingOccurrences(of: "\t", with: "    ")
            let indent = line.prefix { $0 == " " }.count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
                proseIndent = nil
                continue
            }
            // A deeper-indented line with no column gap continues a description already under way, even when it
            // starts with a flag, as in "unlike\n                 --force-ocr)." Without this, wrapped text would
            // become options. An option with no description yet is left alone: pandoc prints a long spelling on
            // its own deeper line ("-o FILE\n     --output=FILE"), and that is a new option.
            if var current = pending, !current.summary.isEmpty, indent > current.indent, !hasColumnGap(trimmed) {
                current.summary = current.summary.isEmpty ? trimmed : current.summary + " " + trimmed
                pending = current
            } else if trimmed.hasPrefix("-"), isFlagStart(trimmed) {
                // Prose can wrap onto a line that starts with a flag, as img2pdf's "--pagesize option is not given,
                // then the page size ...". Such a line carries on the paragraph above at the same indent, and either
                // has no column gap or reads as a sentence. An option right below a heading such as rsync's
                // "Options" has a gap.
                if indent == proseIndent,
                    !hasColumnGap(trimmed) || endsASentence(splitSpecAndSummary(trimmed).spec)
                {
                    continue
                }
                flush()
                proseIndent = nil
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
                // A heading such as "Options:" introduces a list rather than wrapping into it.
                proseIndent = trimmed.hasSuffix(":") ? nil : indent
            }
        }
        flush()
        return options
    }

    /// A flag listed twice keeps its first entry, because a second listing is usually a table that repeats options
    /// (yt-dlp's preset aliases). The exception is qpdf, which names an option in a list ("--rotate: rotate pages")
    /// and spells it out further down ("--rotate=[+|-]angle[:page-range]"): a later spelling of the same option
    /// with its value joined by `=` or glued on gives the earlier entry the value it left out.
    private static func filling(_ earlier: HelpOption, withValueOf later: HelpOption) -> HelpOption? {
        guard earlier.valueName == nil, let valueName = later.valueName, later.valueStyle != .separate,
            Set(later.flags).isSubset(of: earlier.flags)
        else { return nil }
        return HelpOption(
            flags: earlier.flags, valueName: valueName, valueStyle: later.valueStyle, summary: earlier.summary)
    }

    /// Whether spec words read as a sentence: one of them, the flag included, ends in a full stop (`--qdf.`,
    /// `respectively.`). A placeholder such as `...` has no letters and doesn't count.
    private static func endsASentence(_ specWords: [String]) -> Bool {
        specWords.contains { $0.hasSuffix(".") && $0.contains(where: \.isLetter) }
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
    /// two or more spaces or by ` : `; a column that starts with a dash still belongs to the spec. qpdf's lists put
    /// a colon straight after the flag instead: `--linearize: linearize the file`.
    private static func splitSpecAndSummary(_ line: String) -> (spec: [String], summary: String) {
        if let listed = line.wholeMatch(of: /(-{1,2}[^\s:]+):\s+(.+)/) {
            return ([String(listed.1)], String(listed.2).trimmed)
        }
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
