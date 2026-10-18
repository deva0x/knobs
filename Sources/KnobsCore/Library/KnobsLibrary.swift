import Foundation

/// What Knobs remembers between launches: each task's last settings, named presets, and recent runs.
/// A plain value; `LibraryFile` reads and writes it.
public struct KnobsLibrary: Sendable, Hashable, Codable {
    public static let currentVersion = 1
    /// The recent-runs list keeps only this many entries, newest first.
    public static let maximumRecentRuns = 30
    /// Each task keeps at most this many presets.
    public static let maximumPresetsPerTask = 50

    public private(set) var version = Self.currentVersion
    private var tasks: [String: TaskMemory] = [:]
    public private(set) var recentRuns: [RecentRun] = []
    /// Tools the user added by name with "Add a tool", in the order added.
    public private(set) var addedTools: [String] = []

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case version, tasks, recentRuns, addedTools
    }

    /// Missing keys read as empty, so a library saved by an earlier version still loads.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        tasks = try container.decodeIfPresent([String: TaskMemory].self, forKey: .tasks) ?? [:]
        recentRuns = try container.decodeIfPresent([RecentRun].self, forKey: .recentRuns) ?? []
        addedTools = try container.decodeIfPresent([String].self, forKey: .addedTools) ?? []
    }

    /// Adds a tool by its executable name. Returns false when it is already there or the name is a path.
    @discardableResult
    public mutating func addTool(named executable: String) -> Bool {
        let name = executable.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains("/"), !addedTools.contains(name) else { return false }
        addedTools.append(name)
        return true
    }

    public mutating func removeTool(named executable: String) {
        addedTools.removeAll { $0 == executable }
    }

    /// The key for a task, as stored: `ffmpeg/shrink-video`.
    public static func key(toolID: String, taskID: String) -> String {
        "\(toolID)/\(taskID)"
    }

    public func lastValues(forTask key: String) -> [String: FieldValue] {
        tasks[key]?.lastValues ?? [:]
    }

    public func presets(forTask key: String) -> [Preset] {
        tasks[key]?.presets ?? []
    }

    public mutating func rememberValues(_ values: [String: FieldValue], forTask key: String) {
        tasks[key, default: TaskMemory()].lastValues = values
    }

    /// Saves a preset. A preset with the same name (ignoring case) is replaced, so saving again updates it.
    @discardableResult
    public mutating func savePreset(
        named name: String, values: [String: FieldValue], forTask key: String, id: UUID
    ) -> Preset? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var memory = tasks[key, default: TaskMemory()]
        if let index = memory.presets.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            memory.presets[index].values = values
            tasks[key] = memory
            return memory.presets[index]
        }
        guard memory.presets.count < Self.maximumPresetsPerTask else { return nil }
        let preset = Preset(id: id, name: trimmed, values: values)
        memory.presets.append(preset)
        memory.presets.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        tasks[key] = memory
        return preset
    }

    public mutating func deletePreset(_ id: UUID, forTask key: String) {
        tasks[key]?.presets.removeAll { $0.id == id }
    }

    public mutating func recordRun(_ run: RecentRun) {
        recentRuns.insert(run, at: 0)
        if recentRuns.count > Self.maximumRecentRuns {
            recentRuns.removeLast(recentRuns.count - Self.maximumRecentRuns)
        }
    }

    public mutating func clearRecentRuns() {
        recentRuns = []
    }
}

public struct TaskMemory: Sendable, Hashable, Codable {
    public var lastValues: [String: FieldValue] = [:]
    public var presets: [Preset] = []
}

public struct Preset: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public var name: String
    public var values: [String: FieldValue]
}

public struct RecentRun: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public let toolID: String
    public let taskID: String
    public let finishedAt: Date
    public let succeeded: Bool
    /// The file the run produced, when there was one.
    public let outputPath: String?

    public init(id: UUID, toolID: String, taskID: String, finishedAt: Date, succeeded: Bool, outputPath: String?) {
        self.id = id
        self.toolID = toolID
        self.taskID = taskID
        self.finishedAt = finishedAt
        self.succeeded = succeeded
        self.outputPath = outputPath
    }
}

/// Reads and writes the library as JSON at one location, chosen by the caller.
public struct LibraryFile: Sendable {
    public enum LibraryFileError: Error, Sendable, Hashable {
        case unreadable(String)
        case unwritable(String)
        case tooLarge(Int)
    }

    /// The library is small; a file bigger than this is treated as damaged rather than read into memory.
    public static let maximumFileSize = 5_000_000
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// The saved library, or an empty one when nothing has been saved yet.
    public func load() throws(LibraryFileError) -> KnobsLibrary {
        guard FileManager.default.fileExists(atPath: url.path) else { return KnobsLibrary() }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= Self.maximumFileSize else { throw LibraryFileError.tooLarge(size) }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let library = try decoder.decode(KnobsLibrary.self, from: Data(contentsOf: url))
            guard library.version <= KnobsLibrary.currentVersion else {
                throw LibraryFileError.unreadable("it was saved by a newer version of Knobs")
            }
            return library
        } catch let error as LibraryFileError {
            throw error
        } catch {
            throw .unreadable(error.localizedDescription)
        }
    }

    /// Writes atomically, so a crash mid-write never leaves a half-written file.
    public func save(_ library: KnobsLibrary) throws(LibraryFileError) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(library)
            // Never write a file that `load` would then refuse.
            guard data.count <= Self.maximumFileSize else { throw LibraryFileError.tooLarge(data.count) }
            try data.write(to: url, options: .atomic)
        } catch let error as LibraryFileError {
            throw error
        } catch {
            throw .unwritable(error.localizedDescription)
        }
    }

    /// Moves a library that couldn't be read out of the way, next to where it was, so starting fresh never
    /// overwrites the user's presets. Returns where it went. `date` names the copy, so several never collide.
    public func setAside(at date: Date) throws(LibraryFileError) -> URL {
        let stamp = date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacing(":", with: "-")
        let kept = url.deletingPathExtension().appendingPathExtension("unreadable-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: url, to: kept)
            return kept
        } catch {
            throw .unwritable(error.localizedDescription)
        }
    }
}
