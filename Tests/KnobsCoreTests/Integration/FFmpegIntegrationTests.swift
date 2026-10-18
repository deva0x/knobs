import Foundation
import KnobsCore
import Testing

@Suite struct FFmpegIntegrationTests {
    /// Makes a two-second test video with a tone, entirely offline.
    private func makeClip(using ffmpeg: URL, in folder: URL) async throws -> String {
        let clip = folder.appending(path: "test clip.mov").path
        try await Integration.prepare(
            ffmpeg,
            [
                "-hide_banner", "-nostdin", "-f", "lavfi", "-i", "testsrc=duration=2:size=640x360:rate=24",
                "-f", "lavfi", "-i", "sine=frequency=440:duration=2", "-shortest", "-pix_fmt", "yuv420p", clip,
            ], in: folder)
        return clip
    }

    @Test func shrinkVideoProducesAPlayableFileAndReportsProgress() async throws {
        guard let ffmpeg = Integration.tool("ffmpeg") else { return }
        let folder = try Integration.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clip = try await makeClip(using: ffmpeg, in: folder)

        let result = try await Integration.run(
            "shrink-video", of: try loadRepositoryManifest("ffmpeg"), executable: ffmpeg,
            values: ["input": .paths([clip]), "size": .text("854")], in: folder)

        #expect(result.outcome == .succeeded)
        let output = try #require(result.outputPath)
        #expect(output.hasSuffix("test clip small.mp4"))
        #expect(FileManager.default.fileExists(atPath: output))
        #expect(result.events.contains { if case .progress = $0 { true } else { false } })
    }

    @Test func everyFFmpegTaskRunsSuccessfullyOnARealClip() async throws {
        guard let ffmpeg = Integration.tool("ffmpeg") else { return }
        let folder = try Integration.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clip = try await makeClip(using: ffmpeg, in: folder)
        let manifest = try loadRepositoryManifest("ffmpeg")

        for task in manifest.tasks {
            var values: [String: FieldValue] = ["input": .paths([clip])]
            if task.id == "trim" { values["end"] = .text("1") }
            let result = try await Integration.run(
                task.id, of: manifest, executable: ffmpeg, values: values, in: folder)
            #expect(result.outcome == .succeeded, "\(task.id) failed: \(result.events.suffix(4))")
            #expect(result.outputPath.map { FileManager.default.fileExists(atPath: $0) } == true, "\(task.id)")
        }
    }
}
