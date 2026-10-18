import AVFoundation
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Plain facts about a chosen file for the task stage, such as "3:00", "1920 × 1080", "12 pages", "350.5 MB" and
/// "QuickTime movie". They are read by file type with the system's own frameworks, never by tool, and always off
/// the main thread: a file may be large or on a slow drive.
enum FileFacts {
    /// Folders are counted only this far; past it the count is shown as "5,000+ items".
    private static let maximumItemsToCount = 5_000

    static func facts(for url: URL) async -> [String] {
        let values = try? url.resourceValues(forKeys: [
            .fileSizeKey, .localizedTypeDescriptionKey, .contentTypeKey, .isDirectoryKey,
        ])
        var facts: [String] = []
        if values?.isDirectory == true {
            facts.append(await Task.detached(priority: .utility) { itemCount(in: url) }.value)
        } else if let type = values?.contentType {
            if type.conforms(to: .audiovisualContent) {
                facts += await mediaFacts(for: url)
            } else if type.conforms(to: .image) {
                facts += await Task.detached(priority: .utility) { imageFacts(for: url) }.value
            } else if type.conforms(to: .pdf) {
                facts += await Task.detached(priority: .utility) { pdfFacts(for: url) }.value
            }
        }
        if let size = values?.fileSize { facts.append(ByteCount.string(Int64(size))) }
        if let kind = values?.localizedTypeDescription { facts.append(kind) }
        return facts
    }

    /// Duration, picture size and frame rate for video; duration alone for audio.
    private static func mediaFacts(for url: URL) async -> [String] {
        let asset = AVURLAsset(url: url)
        var facts: [String] = []
        if let duration = try? await asset.load(.duration), duration.isNumeric, duration.seconds > 0 {
            facts.append(durationText(seconds: duration.seconds))
        }
        if let video = try? await asset.loadTracks(withMediaType: .video).first,
            let (size, transform, frameRate) = try? await video.load(
                .naturalSize, .preferredTransform, .nominalFrameRate)
        {
            // A phone video filmed upright is stored sideways with a rotation; show it the way it plays.
            let shown = size.applying(transform)
            facts.append("\(Int(abs(shown.width))) × \(Int(abs(shown.height)))")
            if frameRate > 0 { facts.append("\(Int(frameRate.rounded())) fps") }
        }
        return facts
    }

    private static func imageFacts(for url: URL) -> [String] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return [] }
        return ["\(width) × \(height)"]
    }

    private static func pdfFacts(for url: URL) -> [String] {
        guard let pages = PDFDocument(url: url)?.pageCount else { return [] }
        return [pages == 1 ? "1 page" : "\(pages.formatted()) pages"]
    }

    private static func itemCount(in folder: URL) -> String {
        let contents = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        var count = 0
        while contents?.nextObject() != nil {
            count += 1
            if count >= maximumItemsToCount { return "\(maximumItemsToCount.formatted())+ items" }
        }
        return count == 1 ? "1 item" : "\(count.formatted()) items"
    }

    /// "0:42", "3:00", "1:02:05".
    static func durationText(seconds: Double) -> String {
        let pattern: Duration.TimeFormatStyle.Pattern = seconds >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(seconds.rounded()).formatted(.time(pattern: pattern))
    }
}
