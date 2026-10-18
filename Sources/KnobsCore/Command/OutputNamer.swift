import Foundation

/// Picks an output path that doesn't exist yet, so Knobs never overwrites a file.
/// `report.pdf` becomes `report 2.pdf`, then `report 3.pdf`, and so on.
public struct OutputNamer: Sendable {
    /// Gives up after this many candidates rather than probing forever.
    public static let maximumAttempts = 9_999

    public enum NamingError: Error, Sendable, Hashable {
        case noFreeName(String)
    }

    private let fileExists: @Sendable (String) -> Bool

    /// `fileExists` is injected so the logic can be tested without touching the disk.
    public init(fileExists: @escaping @Sendable (String) -> Bool) {
        self.fileExists = fileExists
    }

    public func availablePath(for desiredPath: String) throws(NamingError) -> String {
        guard fileExists(desiredPath) else { return desiredPath }
        let path = desiredPath as NSString
        let folder = path.deletingLastPathComponent
        let fileExtension = path.pathExtension
        let stem = (path.lastPathComponent as NSString).deletingPathExtension
        for number in 2...Self.maximumAttempts {
            let name = fileExtension.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(fileExtension)"
            let candidate = (folder as NSString).appendingPathComponent(name)
            if !fileExists(candidate) { return candidate }
        }
        throw .noFreeName(desiredPath)
    }
}
