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

    /// `environmentPath` is the `PATH` the app was launched with, if any; its folders are searched last. Relative
    /// folders such as `.` are left out: they would depend on whatever folder a tool happens to run in.
    public init(
        environmentPath: String?,
        isExecutableFile: @escaping @Sendable (String) -> Bool = ToolLocator.isExecutableRegularFile
    ) {
        let extra = (environmentPath ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        var seen: Set<String> = []
        self.searchPaths = (Self.standardSearchPaths + extra).filter { seen.insert($0).inserted }
        self.isExecutableFile = isExecutableFile
    }

    /// The full path of `executable`, or nil when it isn't installed in any search folder.
    public func locate(_ executable: String) -> URL? {
        guard !executable.isEmpty, !executable.contains("/"), executable != ".", executable != ".." else { return nil }
        for folder in searchPaths {
            let candidate = (folder as NSString).appendingPathComponent(executable)
            if isExecutableFile(candidate) { return URL(filePath: candidate) }
        }
        return nil
    }

    /// The manifest under the first of its names that is installed, so the command shown is the one that runs.
    /// Unchanged when the tool isn't installed under any of them.
    public func resolve(_ manifest: ToolManifest) -> ToolManifest {
        let installedName = ([manifest.executable] + manifest.alternativeExecutables).first { locate($0) != nil }
        return installedName.map(manifest.runningAs) ?? manifest
    }

    /// `FileManager.isExecutableFile` is also true for folders, which can't be run.
    @Sendable public static func isExecutableRegularFile(_ path: String) -> Bool {
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) && !isFolder.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }

    /// A `PATH` value for launched tools, so tools that call other tools (ocrmypdf calls Ghostscript and
    /// Tesseract, for example) find them too.
    public var pathEnvironmentValue: String {
        searchPaths.joined(separator: ":")
    }
}
