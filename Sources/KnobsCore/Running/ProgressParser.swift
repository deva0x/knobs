import Foundation

/// Reads progress from a tool's output lines using a manifest's `progress` patterns.
public struct ProgressParser: Sendable {
    private enum Matcher: Sendable {
        case percent(NSRegularExpressionBox)
        case elapsedOfTotal(current: NSRegularExpressionBox, total: NSRegularExpressionBox)
    }

    private let matcher: Matcher
    private var totalSeconds: Double?

    /// Returns nil when a pattern doesn't compile; validated manifests always compile.
    public init?(_ rule: ProgressRule) {
        switch rule {
        case .percent(let pattern):
            guard let expression = NSRegularExpressionBox(pattern) else { return nil }
            matcher = .percent(expression)
        case .elapsedOfTotal(let currentPattern, let totalPattern):
            guard let current = NSRegularExpressionBox(currentPattern), let total = NSRegularExpressionBox(totalPattern)
            else { return nil }
            matcher = .elapsedOfTotal(current: current, total: total)
        }
    }

    /// Feeds one output line. Returns the progress as a fraction from 0 to 1 when the line reports one.
    public mutating func progress(after line: String) -> Double? {
        switch matcher {
        case .percent(let expression):
            guard let percent = expression.numbers(in: line).first else { return nil }
            return Self.clamp(percent / 100)
        case .elapsedOfTotal(let current, let total):
            if let seconds = Self.seconds(from: total.numbers(in: line)), seconds > 0 {
                totalSeconds = seconds
                return nil
            }
            guard let totalSeconds, let seconds = Self.seconds(from: current.numbers(in: line)) else { return nil }
            return Self.clamp(seconds / totalSeconds)
        }
    }

    /// One group is plain seconds; three groups are hours, minutes and seconds.
    private static func seconds(from numbers: [Double]) -> Double? {
        switch numbers.count {
        case 1: numbers[0]
        case 3: numbers[0] * 3600 + numbers[1] * 60 + numbers[2]
        default: nil
        }
    }

    private static func clamp(_ fraction: Double) -> Double {
        min(max(fraction, 0), 1)
    }
}

/// `NSRegularExpression` is immutable and thread-safe but not marked `Sendable`; this box says so once.
struct NSRegularExpressionBox: @unchecked Sendable {
    private let expression: NSRegularExpression

    init?(_ pattern: String) {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        self.expression = expression
    }

    /// The numbers captured by the last match in `line`, in group order. Empty when there's no match or a group
    /// isn't a number. The last match is used because tools often print several updates on one line.
    func numbers(in line: String) -> [Double] {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = expression.matches(in: line, range: range).last else { return [] }
        var numbers: [Double] = []
        for group in 1..<match.numberOfRanges {
            guard let groupRange = Range(match.range(at: group), in: line), let number = Double(line[groupRange])
            else { return [] }
            numbers.append(number)
        }
        return numbers
    }
}
