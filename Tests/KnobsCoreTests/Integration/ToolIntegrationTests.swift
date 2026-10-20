import Foundation
import KnobsCore
import Testing

/// Every task of every tool, run for real on small fixtures made by the tests themselves. Each suite skips when
/// its tool isn't installed, unless KNOBS_REQUIRE_TOOLS=1 (see docs/WORKFLOW.md).

private func expectSucceeded(
    _ result: (outcome: RunOutcome, outputPath: String?, events: [RunEvent]),
    _ taskID: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(result.outcome == .succeeded, "\(taskID): \(lastLines(result.events))", sourceLocation: sourceLocation)
    if let output = result.outputPath {
        #expect(
            FileManager.default.fileExists(atPath: output), "\(taskID) wrote no \(output)",
            sourceLocation: sourceLocation)
    }
}

private func lastLines(_ events: [RunEvent]) -> String {
    events.compactMap { if case .line(let text, _) = $0 { text } else { nil } }.suffix(6).joined(separator: " | ")
}

private func write(_ text: String, to url: URL) throws {
    try Data(text.utf8).write(to: url)
}

@Suite struct ImageMagickIntegrationTests {
    @Test func everyTaskRunsOnARealImage() async throws {
        guard let magick = Integration.tool("magick") else { return }
        let folder = try Integration.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appending(path: "sunset photo.png").path
        try await Integration.prepare(magick, ["-size", "800x500", "gradient:orange-purple", image], in: folder)
        let manifest = try loadRepositoryManifest("imagemagick")

        for task in manifest.tasks {
            var values: [String: FieldValue] = ["input": .paths([image])]
            if task.id == "watermark" { values["text"] = .text("© Knobs") }
            if task.id == "square" { values["mode"] = .text("pad") }
            expectSucceeded(
                try await Integration.run(task.id, of: manifest, executable: magick, values: values, in: folder),
                task.id)
        }
    }
}

@Suite struct PandocIntegrationTests {
    @Test func everyTaskRunsOnRealDocuments() async throws {
        guard let pandoc = Integration.tool("pandoc") else { return }
        let folder = try Integration.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let markdown = folder.appending(path: "notes.md")
        try write("# Trip notes\n\nWe went to **Goa**.\n\n- Beach\n- Food\n", to: markdown)
        let manifest = try loadRepositoryManifest("pandoc")
        let values: [String: FieldValue] = ["input": .paths([markdown.path])]

        for taskID in ["markdown-to-word", "markdown-to-html", "to-epub"] {
            expectSucceeded(
                try await Integration.run(taskID, of: manifest, executable: pandoc, values: values, in: folder), taskID)
        }
        let word = folder.appending(path: "notes.docx").path
        expectSucceeded(
            try await Integration.run(
                "word-to-markdown", of: manifest, executable: pandoc, values: ["input": .paths([word])], in: folder),
            "word-to-markdown")
    }
}

@Suite struct ExifToolIntegrationTests {
    @Test func everyTaskRunsOnARealPhoto() async throws {
        guard let exiftool = Integration.tool("exiftool"), let magick = Integration.tool("magick") else { return }
        let folder = try Integration.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = folder.appending(path: "IMG_0001.jpg").path
        try await Integration.prepare(magick, ["-size", "320x200", "plasma:", photo], in: folder)
        try await Integration.prepare(
            exiftool,
            [
                "-overwrite_original", "-GPSLatitude=15.5", "-GPSLatitudeRef=N", "-GPSLongitude=73.8",
                "-GPSLongitudeRef=E", "-DateTimeOriginal=2026:01:02 03:04:05", photo,
            ], in: folder)
        let manifest = try loadRepositoryManifest("exiftool")

        for taskID in ["show-metadata", "remove-all", "remove-location"] {
            expectSucceeded(
                try await Integration.run(
                    taskID, of: manifest, executable: exiftool, values: ["input": .paths([photo])], in: folder), taskID)
        }
        expectSucceeded(
            try await Integration.run(
                "rename-by-date", of: manifest, executable: exiftool, values: ["photos": .paths([photo])], in: folder),
            "rename-by-date")
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "2026-01-02 03.04.05.jpg").path))
    }
}

@Suite struct OCRmyPDFIntegrationTests {
    @Test func everyTaskRunsOnARealScan() async throws {
        guard let ocrmypdf = Integration.tool("ocrmypdf"), let magick = Integration.tool("magick") else { return }
        let folder = try Integration.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let scan = folder.appending(path: "scan.pdf").path
        try await Integration.prepare(
            magick,
            [
                "-size", "1240x1754", "xc:white", "-font", "/System/Library/Fonts/Helvetica.ttc", "-fill", "black",
                "-pointsize", "64",
                "-annotate", "+120+300", "Hello from Knobs", "-units", "PixelsPerInch", "-density", "150", scan,
            ], in: folder)
        let manifest = try loadRepositoryManifest("ocrmypdf")

        for task in manifest.tasks {
            expectSucceeded(
                try await Integration.run(
                    task.id, of: manifest, executable: ocrmypdf, values: ["input": .paths([scan])], in: folder), task.id
            )
        }
    }
}

@Suite struct GhostscriptIntegrationTests {
    @Test func everyTaskRunsOnRealPDFs() async throws {
        guard let gs = Integration.tool("gs"), let magick = Integration.tool("magick") else { return }
        let folder = try Integration.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appending(path: "part one.pdf").path
        let second = folder.appending(path: "part two.pdf").path
        try await Integration.prepare(magick, ["-size", "600x800", "gradient:red-blue", first], in: folder)
        try await Integration.prepare(magick, ["-size", "600x800", "gradient:green-yellow", second], in: folder)
        let manifest = try loadRepositoryManifest("ghostscript")

        for taskID in ["compress-pdf", "grayscale", "extract-pages"] {
            expectSucceeded(
                try await Integration.run(
                    taskID, of: manifest, executable: gs, values: ["input": .paths([first])], in: folder),
                taskID)
        }
        let merged = try await Integration.run(
            "merge-pdfs", of: manifest, executable: gs, values: ["pages": .paths([first, second])], in: folder)
        expectSucceeded(merged, "merge-pdfs")
        #expect(merged.outputPath?.hasSuffix("part one merged.pdf") == true)
    }
}

/// A PDF with real text on three pages, made by Ghostscript, so page counts and extracted text can be checked.
private func makeThreePagePDF(_ gs: URL, at path: String, in folder: URL) async throws {
    let pages = ["Hello Knobs one", "Page two", "Page three"]
        .map { "72 700 moveto (\($0)) show showpage" }.joined(separator: " ")
    try await Integration.prepare(
        gs,
        ["-q", "-dSAFER", "-sDEVICE=pdfwrite", "-o", path, "-c", "/Helvetica findfont 24 scalefont setfont \(pages)"],
        in: folder)
}

@Suite struct QpdfIntegrationTests {
    @Test func everyTaskRunsOnARealPDF() async throws {
        guard let qpdf = Integration.tool("qpdf"), let gs = Integration.tool("gs") else { return }
        let folder = try Integration.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let pdf = folder.appending(path: "three pages.pdf").path
        try await makeThreePagePDF(gs, at: pdf, in: folder)
        let manifest = try loadRepositoryManifest("qpdf")
        let input: [String: FieldValue] = ["input": .paths([pdf])]

        expectSucceeded(
            try await Integration.run("rotate-pages", of: manifest, executable: qpdf, values: input, in: folder),
            "rotate-pages")

        let picked = try await Integration.run(
            "pick-pages", of: manifest, executable: qpdf, values: input.merging(["pages": .text("3,1")]) { $1 },
            in: folder)
        expectSucceeded(picked, "pick-pages")
        let pickedPath = try #require(picked.outputPath)
        #expect(try await Integration.prepare(qpdf, ["--show-npages", pickedPath], in: folder) == ["2"])

        let locked = try await Integration.run(
            "protect", of: manifest, executable: qpdf,
            values: input.merging(["password": .text("s3cret pass")]) { $1 }, in: folder)
        expectSucceeded(locked, "protect")
        let lockedPath = try #require(locked.outputPath)
        let wrongPassword = try await Integration.run(
            "remove-password", of: manifest, executable: qpdf,
            values: ["input": .paths([lockedPath]), "password": .text("nope")], in: folder)
        #expect(wrongPassword.outcome != .succeeded)
        expectSucceeded(
            try await Integration.run(
                "remove-password", of: manifest, executable: qpdf,
                values: ["input": .paths([lockedPath]), "password": .text("s3cret pass")], in: folder),
            "remove-password")

        // Cut short, as by an interrupted download: qpdf rebuilds what it can and only warns.
        let damaged = folder.appending(path: "cut short.pdf")
        let whole = try Data(contentsOf: URL(filePath: pdf))
        try whole.prefix(whole.count * 2 / 3).write(to: damaged)
        expectSucceeded(
            try await Integration.run(
                "repair", of: manifest, executable: qpdf, values: ["input": .paths([damaged.path])], in: folder),
            "repair")
    }
}

@Suite struct Img2pdfIntegrationTests {
    @Test func aPhotoAndATransparentImageBecomeTwoPages() async throws {
        guard let img2pdf = Integration.tool("img2pdf"), let magick = Integration.tool("magick"),
            let qpdf = Integration.tool("qpdf")
        else { return }
        let folder = try Integration.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = folder.appending(path: "photo.jpg").path
        let logo = folder.appending(path: "logo.png").path
        try await Integration.prepare(magick, ["-size", "640x480", "gradient:orange-purple", photo], in: folder)
        try await Integration.prepare(
            magick, ["-size", "200x200", "xc:none", "-fill", "red", "-draw", "circle 100,100 100,20", logo], in: folder)
        let manifest = try loadRepositoryManifest("img2pdf")

        let result = try await Integration.run(
            "images-to-pdf", of: manifest, executable: img2pdf,
            values: ["images": .paths([photo, logo]), "pageSize": .text("A4")], in: folder)

        expectSucceeded(result, "images-to-pdf")
        let pdf = try #require(result.outputPath)
        #expect(try await Integration.prepare(qpdf, ["--show-npages", pdf], in: folder) == ["2"])
    }
}

@Suite struct PopplerIntegrationTests {
    @Test func aPageBecomesAPNGAndAJPEG() async throws {
        guard let pdftoppm = Integration.tool("pdftoppm"), let gs = Integration.tool("gs") else { return }
        let folder = try Integration.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let pdf = folder.appending(path: "three pages.pdf").path
        try await makeThreePagePDF(gs, at: pdf, in: folder)
        let manifest = try loadRepositoryManifest("pdftoppm")

        for format in ["png", "jpg"] {
            let result = try await Integration.run(
                "page-to-image", of: manifest, executable: pdftoppm,
                values: ["input": .paths([pdf]), "page": .integer(2), "format": .text(format)], in: folder)
            expectSucceeded(result, "page-to-image as \(format)")
        }
    }

    @Test func everyPageBecomesAnImageInANewFolder() async throws {
        guard let pdftoppm = Integration.tool("pdftoppm"), let gs = Integration.tool("gs") else { return }
        let folder = try Integration.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let pdf = folder.appending(path: "three pages.pdf").path
        try await makeThreePagePDF(gs, at: pdf, in: folder)
        let manifest = try loadRepositoryManifest("pdftoppm")

        for format in ["png", "jpg"] {
            let result = try await Integration.run(
                "every-page-to-images", of: manifest, executable: pdftoppm,
                values: ["input": .paths([pdf]), "format": .text(format), "resolution": .text("72")], in: folder)
            expectSucceeded(result, "every-page-to-images as \(format)")
            let pages = try FileManager.default.contentsOfDirectory(atPath: try #require(result.outputPath))
            #expect(pages.sorted() == ["page-1.\(format)", "page-2.\(format)", "page-3.\(format)"])
        }
    }

    @Test func aPDFsTextBecomesATextFile() async throws {
        guard let pdftotext = Integration.tool("pdftotext"), let gs = Integration.tool("gs") else { return }
        let folder = try Integration.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let pdf = folder.appending(path: "three pages.pdf").path
        try await makeThreePagePDF(gs, at: pdf, in: folder)
        let manifest = try loadRepositoryManifest("pdftotext")

        let result = try await Integration.run(
            "pdf-to-text", of: manifest, executable: pdftotext, values: ["input": .paths([pdf])], in: folder)

        expectSucceeded(result, "pdf-to-text")
        let text = try String(contentsOfFile: try #require(result.outputPath), encoding: .utf8)
        #expect(text.contains("Hello Knobs one"))
        #expect(text.contains("Page three"))
    }
}

@Suite struct WhisperIntegrationTests {
    /// The test model downloaded into .cache/models (docs/DECISIONS.md, DEC-009).
    private let model = manifestsDirectory.deletingLastPathComponent().appending(path: ".cache/models/ggml-tiny.en.bin")

    @Test func everyTaskRunsOnRealSpeech() async throws {
        guard let whisper = Integration.tool("whisper-cli"), let ffmpeg = Integration.tool("ffmpeg") else { return }
        guard FileManager.default.fileExists(atPath: model.path) else {
            Issue.record("The whisper test model is missing at \(model.path)")
            return
        }
        let folder = try Integration.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let speech = folder.appending(path: "speech.aiff").path
        let recording = folder.appending(path: "speech.wav").path
        try await Integration.prepare(
            URL(filePath: "/usr/bin/say"), ["-o", speech, "Hello, this is a test of the Knobs app."], in: folder)
        try await Integration.prepare(
            ffmpeg, ["-hide_banner", "-nostdin", "-i", speech, "-ar", "16000", "-ac", "1", recording], in: folder)
        let manifest = try loadRepositoryManifest("whisper-cpp")

        for task in manifest.tasks {
            let result = try await Integration.run(
                task.id, of: manifest, executable: whisper,
                values: ["input": .paths([recording]), "model": .paths([model.path])], in: folder)
            expectSucceeded(result, task.id)
        }
        let transcript = try String(
            contentsOfFile: folder.appending(path: "speech transcript.txt").path, encoding: .utf8)
        #expect(transcript.lowercased().contains("hello"))
    }
}

@Suite struct RsyncIntegrationTests {
    @Test func everyTaskRunsOnRealFolders() async throws {
        guard let rsync = Integration.tool("rsync") else { return }
        let folder = try Integration.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "Photos")
        let destination = folder.appending(path: "Backup")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try write("one", to: source.appending(path: "a.txt"))
        try write("two", to: source.appending(path: ".hidden"))
        try write("stale", to: destination.appending(path: "old.txt"))
        let manifest = try loadRepositoryManifest("rsync")
        let values: [String: FieldValue] = ["source": .paths([source.path]), "destination": .paths([destination.path])]

        for taskID in ["copy-folder", "compare-folders", "backup"] {
            expectSucceeded(
                try await Integration.run(taskID, of: manifest, executable: rsync, values: values, in: folder), taskID)
        }
        #expect(FileManager.default.fileExists(atPath: destination.appending(path: "Photos/a.txt").path))

        let preview = try await Integration.run(
            "mirror-folder", of: manifest, executable: rsync, values: values, in: folder)
        expectSucceeded(preview, "mirror-folder preview")
        #expect(FileManager.default.fileExists(atPath: destination.appending(path: "old.txt").path))

        let mirror = try await Integration.run(
            "mirror-folder", of: manifest, executable: rsync,
            values: values.merging(["preview": .toggle(false)]) { $1 },
            in: folder)
        expectSucceeded(mirror, "mirror-folder")
        #expect(!FileManager.default.fileExists(atPath: destination.appending(path: "old.txt").path))
        #expect(FileManager.default.fileExists(atPath: destination.appending(path: "a.txt").path))
    }
}

@Suite struct SevenZipIntegrationTests {
    @Test func everyTaskRunsOnRealFiles() async throws {
        guard let sevenZip = Integration.tool("7zz") else { return }
        let folder = try Integration.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let documents = folder.appending(path: "Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try write(String(repeating: "Knobs ", count: 2_000), to: documents.appending(path: "notes.txt"))
        let manifest = try loadRepositoryManifest("7zip")
        let items: [String: FieldValue] = ["items": .paths([documents.path])]

        let zip = try await Integration.run("create", of: manifest, executable: sevenZip, values: items, in: folder)
        expectSucceeded(zip, "create")
        let locked = try await Integration.run(
            "create-encrypted", of: manifest, executable: sevenZip,
            values: items.merging(["password": .text("s3cret pass")]) { $1 }, in: folder)
        expectSucceeded(locked, "create-encrypted")

        let archive = try #require(locked.outputPath)
        let withPassword: [String: FieldValue] = ["archive": .paths([archive]), "password": .text("s3cret pass")]
        expectSucceeded(
            try await Integration.run("test", of: manifest, executable: sevenZip, values: withPassword, in: folder),
            "test")
        let extracted = try await Integration.run(
            "extract", of: manifest, executable: sevenZip, values: withPassword, in: folder)
        expectSucceeded(extracted, "extract")
        let wrongPassword = try await Integration.run(
            "test", of: manifest, executable: sevenZip,
            values: ["archive": .paths([archive]), "password": .text("nope")], in: folder)
        #expect(wrongPassword.outcome != .succeeded)
    }
}

@Suite struct YtDlpIntegrationTests {
    @Test func downloadsFromALocalFileWithoutTheNetwork() async throws {
        guard let ytDlp = Integration.tool("yt-dlp"), let ffmpeg = Integration.tool("ffmpeg") else { return }
        let folder = try Integration.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clip = folder.appending(path: "clip.mp4").path
        try await Integration.prepare(
            ffmpeg,
            [
                "-hide_banner", "-nostdin", "-f", "lavfi", "-i", "testsrc=duration=1:size=320x240:rate=10",
                "-pix_fmt", "yuv420p", clip,
            ], in: folder)
        let downloads = folder.appending(path: "Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let manifest = try loadRepositoryManifest("yt-dlp")
        let task = try #require(manifest.task(withID: "download-video"))

        let result = try await Integration.run(
            "download-video", of: manifest, executable: ytDlp,
            values: [
                "url": .text(URL(filePath: clip).absoluteString), "folder": .paths([downloads.path]),
                "quality": .text("b"),
            ],
            extraArguments: "--enable-file-urls", in: folder)

        #expect(result.outcome == .succeeded, "\(lastLines(result.events))")
        let pattern = try #require(task.outputPathPattern)
        let printed = result.events.compactMap { event -> String? in
            guard case .line(let text, .standardOutput) = event,
                let match = try? NSRegularExpression(pattern: pattern).firstMatch(
                    in: text, range: NSRange(text.startIndex..., in: text)),
                let range = Range(match.range(at: 1), in: text)
            else { return nil }
            return String(text[range])
        }
        #expect(printed.contains { FileManager.default.fileExists(atPath: $0) }, "\(printed)")
    }
}
