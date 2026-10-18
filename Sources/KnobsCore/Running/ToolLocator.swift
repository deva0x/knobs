import Foundation

/// Finds a tool's executable. Apps opened from Finder don't inherit the shell's PATH, so Knobs searches the
/// usual install folders itself, Homebrew first.
public struct ToolLocator: Sendable {
    public static let standardSearchPaths = [
        "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/sbin", "/opt/local/bin",
        "/usr/bin", "/bin", "/usr/sbin", "/sbin",
    ]

    /// The folders searched, in order: the standard ones, then any extra folders from the launch environment.
    public let searchPaths: [String]
    private let isExecutableFile: @Sendable (String) -> Bool

    /// `environmentPath` is the `PATH` the app was launched with, if any; its folders are searched last.
    public init(
        environmentPath: String?,
        isExecutableFile: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        let extra = (environmentPath ?? "").split(separator: ":").map(String.init).filter { !$0.isEmpty }
        var seen: Set<String> = []
        self.searchPaths = (Self.standardSearchPaths + extra).filter { seen.insert($0).inserted }
        self.isExecutableFile = isExecutableFile
    }

    /// The full path of `executable`, or nil when it isn't installed in any search folder.
    public func locate(_ executable: String) -> URL? {
        guard !executable.isEmpty, !executable.contains("/") else { return nil }
        for folder in searchPaths {
            let candidate = (folder as NSString).appendingPathComponent(executable)
            if isExecutableFile(candidate) { return URL(filePath: candidate) }
        }
        return nil
    }

    /// A `PATH` value for launched tools, so tools that call other tools (ocrmypdf calls Ghostscript and
    /// Tesseract, for example) find them too.
    public var pathEnvironmentValue: String {
        searchPaths.joined(separator: ":")
    }
}
