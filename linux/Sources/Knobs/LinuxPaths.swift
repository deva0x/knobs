import Foundation

/// Where the Linux app finds its tool descriptions and keeps its settings.
enum LinuxPaths {
    /// The bundled manifests: `KNOBS_MANIFESTS` when set (development), else `share/knobs/manifests` beside the
    /// installed binary's `bin` folder, as the .deb and .rpm lay it out.
    static func manifestsDirectory(environment: [String: String], executable: URL?) -> URL {
        if let override = environment["KNOBS_MANIFESTS"], !override.isEmpty {
            return URL(filePath: override)
        }
        let prefix = (executable ?? URL(filePath: "/usr/bin/knobs")).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent()
        return prefix.appending(path: "share/knobs/manifests")
    }

    /// Where settings are kept: `$XDG_DATA_HOME/knobs`, or `~/.local/share/knobs` when it isn't set.
    static func dataDirectory(environment: [String: String]) -> URL {
        if let dataHome = environment["XDG_DATA_HOME"], dataHome.hasPrefix("/") {
            return URL(filePath: dataHome).appending(path: "knobs")
        }
        return URL(filePath: NSHomeDirectory()).appending(path: ".local/share/knobs")
    }
}
