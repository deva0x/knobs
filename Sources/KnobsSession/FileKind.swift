import Foundation

/// The broad kind of a file, told by its extension, for deciding whether two files' sizes can be compared.
/// A file of any other kind, or a folder (output folders are named without an extension), has no kind here.
enum FileKind {
    case video, audio, image, pdf, archive

    private static let extensions: [String: FileKind] = [
        "mp4": .video, "m4v": .video, "mov": .video, "mkv": .video, "webm": .video, "avi": .video,
        "mp3": .audio, "m4a": .audio, "aac": .audio, "wav": .audio, "aiff": .audio, "flac": .audio, "ogg": .audio,
        "opus": .audio,
        "jpg": .image, "jpeg": .image, "png": .image, "webp": .image, "heic": .image, "avif": .image, "tif": .image,
        "tiff": .image, "gif": .image, "bmp": .image,
        "pdf": .pdf,
        "zip": .archive, "7z": .archive, "tar": .archive, "gz": .archive, "tgz": .archive, "xz": .archive,
        "bz2": .archive, "rar": .archive,
    ]

    init?(path: String) {
        guard let kind = Self.extensions[(path as NSString).pathExtension.lowercased()] else { return nil }
        self = kind
    }
}
