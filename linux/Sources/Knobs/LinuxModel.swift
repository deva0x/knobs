import Foundation
import KnobsCore
import KnobsSession

/// The Linux app's state: the bundled tools, where each one is installed, one session per task, and the settings
/// remembered between launches. The task sessions are the same `TaskSession` the Mac app uses; only the windows
/// differ.
final class LinuxModel {
    let manifests: [ToolManifest]
    let manifestFailures: [ManifestError]
    private(set) var executables: [String: URL] = [:]
    private var sessions: [String: TaskSession] = [:]
    private let locator: ToolLocator
    private let runner: ToolRunner
    private var library: KnobsLibrary
    private let libraryFile: LibraryFile
    private var isSavingLibraryAllowed = true

    init(manifestsDirectory: URL, dataDirectory: URL, environment: [String: String]) {
        libraryFile = LibraryFile(url: dataDirectory.appending(path: "library.json"))
        do {
            library = try libraryFile.load()
        } catch let readError {
            // Start fresh, but never by overwriting the old file: keep it beside the new one, or don't save at all.
            library = KnobsLibrary()
            do {
                let kept = try libraryFile.setAside(at: Date())
                Self.report("saved settings couldn't be read (\(readError)); kept them as \(kept.lastPathComponent)")
            } catch let moveError {
                isSavingLibraryAllowed = false
                Self.report(
                    "saved settings couldn't be read (\(readError)) or moved aside (\(moveError)); not saving this time"
                )
            }
        }
        let catalog = ManifestLoader.loadCatalog(in: manifestsDirectory)
        manifests = catalog.manifests
        manifestFailures = catalog.failures
        locator = ToolLocator(environmentPath: environment["PATH"])
        runner = ToolRunner(environment: ToolRunner.environment(base: environment, locator: locator))
        refreshAvailability()
    }

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

    /// Looks every tool up again, for "Check again" after the user installs one.
    func refreshAvailability() {
        var found: [String: URL] = [:]
        for manifest in manifests {
            found[manifest.id] = locator.locate(manifest.executable)
        }
        executables = found
    }

    func manifest(withID id: String) -> ToolManifest? {
        manifests.first { $0.id == id }
    }

    func location(of manifest: ToolManifest) -> URL? {
        executables[manifest.id]
    }

    func session(for task: ManifestTask, of manifest: ToolManifest) -> TaskSession {
        let key = KnobsLibrary.key(toolID: manifest.id, taskID: task.id)
        if let session = sessions[key] { return session }
        let session = TaskSession(manifest: manifest, task: task, initialValues: library.lastValues(forTask: key))
        sessions[key] = session
        return session
    }

    func canRun(_ session: TaskSession) -> Bool {
        location(of: session.manifest) != nil && session.draft.isRunnable && !session.isRunning
    }

    func run(_ session: TaskSession) {
        guard canRun(session), let executable = location(of: session.manifest) else { return }
        library.rememberValues(session.rememberableValues, forTask: session.id)
        saveLibrary()
        session.start(executable: executable, runner: runner)
    }

    private func saveLibrary() {
        guard isSavingLibraryAllowed else { return }
        do {
            try libraryFile.save(library)
        } catch {
            Self.report("couldn't save settings: \(error)")
        }
    }

    /// Problems with saved settings go to standard error, which the desktop's journal keeps.
    private static func report(_ problem: String) {
        FileHandle.standardError.write(Data("knobs: \(problem)\n".utf8))
    }

    var hasRunningTasks: Bool {
        sessions.values.contains(where: \.isRunning)
    }
}
