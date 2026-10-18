import Foundation

/// A tool's output, kept to the most recent lines so a chatty tool can't grow memory without bound.
public struct OutputLog: Sendable, Hashable {
    public enum Stream: Sendable, Hashable {
        case standardOutput
        case standardError
    }

    public struct Line: Sendable, Hashable, Identifiable {
        /// Counts every line ever appended, so ids stay unique after old lines are dropped.
        public let id: Int
        public let text: String
        public let stream: Stream
    }

    public static let defaultLineLimit = 5_000
    /// Longer lines are cut, since a single line of binary junk can be megabytes long.
    public static let maximumLineLength = 4_000

    public private(set) var lines: [Line] = []
    public private(set) var droppedLineCount = 0
    private let lineLimit: Int
    private var nextID = 0

    public init(lineLimit: Int = defaultLineLimit) {
        self.lineLimit = max(1, lineLimit)
    }

    public mutating func append(_ text: String, from stream: Stream) {
        let clipped = text.count > Self.maximumLineLength ? String(text.prefix(Self.maximumLineLength)) + "…" : text
        lines.append(Line(id: nextID, text: clipped, stream: stream))
        nextID += 1
        if lines.count > lineLimit {
            let overflow = lines.count - lineLimit
            lines.removeFirst(overflow)
            droppedLineCount += overflow
        }
    }

    /// The last line that looks like an error, for the failure card. Falls back to the last line of any kind.
    public var mostRelevantErrorLine: String? {
        let errorWords = ["error", "invalid", "no such", "not found", "failed", "unable", "cannot", "denied"]
        let meaningful = lines.reversed().filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        let flagged = meaningful.first { line in
            let lowered = line.text.lowercased()
            return errorWords.contains { lowered.contains($0) }
        }
        return (flagged ?? meaningful.first)?.text.trimmingCharacters(in: .whitespaces)
    }
}
