import Foundation

/// A manifest that can't be loaded. The message names the file, the JSON path and the problem, so a
/// contributor can fix it without reading Swift.
public struct ManifestError: Error, Sendable, Hashable, LocalizedError {
    /// The manifest's file name, such as `ffmpeg.json`.
    public let source: String
    /// Where in the JSON the problem is, such as `tasks[0].fields[2].default`. Empty for the whole file.
    public let path: String
    public let problem: String

    public init(source: String, path: String, problem: String) {
        self.source = source
        self.path = path
        self.problem = problem
    }

    public var errorDescription: String? {
        path.isEmpty ? "\(source): \(problem)" : "\(source) at \(path): \(problem)"
    }
}
