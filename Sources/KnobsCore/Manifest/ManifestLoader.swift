import Foundation

/// Loads and validates manifests. This is the only public way to get a `ToolManifest` from JSON.
public enum ManifestLoader {
    /// The manifests in a folder, plus the files that failed. One bad file never hides the good ones.
    public struct Catalog: Sendable {
        public let manifests: [ToolManifest]
        public let failures: [ManifestError]
    }

    public static let fileExtension = "json"
    /// Manifests are small; anything bigger than this is refused rather than read into memory.
    public static let maximumFileSize = 1_000_000

    public static func load(_ data: Data, source: String) throws(ManifestError) -> ToolManifest {
        let manifest = try ManifestReader.read(data, source: source)
        try ManifestValidator.validate(manifest, source: source)
        return manifest
    }

    /// Checks a manifest built in code (such as a generated "All options" task) against the same rules as files.
    public static func validate(_ manifest: ToolManifest, source: String) throws(ManifestError) {
        try ManifestValidator.validate(manifest, source: source)
    }

    /// Reads every `.json` file in `directory`, sorted by tool name. Duplicate tool ids count as failures.
    public static func loadCatalog(in directory: URL) -> Catalog {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension == fileExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            let problem = "couldn't be read (\(error.localizedDescription))"
            return Catalog(manifests: [], failures: [ManifestError(source: directory.path, path: "", problem: problem)])
        }

        var manifests: [ToolManifest] = []
        var failures: [ManifestError] = []
        var seenIDs: Set<String> = []
        for file in files {
            let source = file.lastPathComponent
            do {
                let manifest = try load(try readData(file, source: source), source: source)
                guard seenIDs.insert(manifest.id).inserted else {
                    failures.append(
                        ManifestError(
                            source: source, path: "id", problem: "\"\(manifest.id)\" is used by another manifest")
                    )
                    continue
                }
                manifests.append(manifest)
            } catch {
                failures.append(error)
            }
        }
        let sorted = manifests.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return Catalog(manifests: sorted, failures: failures)
    }

    private static func readData(_ file: URL, source: String) throws(ManifestError) -> Data {
        do {
            // Measure what will actually be read: a symlink's own size says nothing about its target, and a
            // FIFO or device would block the read forever.
            let target = file.resolvingSymlinksInPath()
            let values = try target.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else {
                throw ManifestError(source: source, path: "", problem: "isn't a regular file")
            }
            guard (values.fileSize ?? 0) <= maximumFileSize else {
                throw ManifestError(source: source, path: "", problem: "is larger than \(maximumFileSize) bytes")
            }
            return try Data(contentsOf: target)
        } catch let error as ManifestError {
            throw error
        } catch {
            throw ManifestError(source: source, path: "", problem: "couldn't be read (\(error.localizedDescription))")
        }
    }
}
