import QuickLookThumbnailing
import SwiftUI

/// A Quick Look thumbnail, falling back to the Finder icon while it loads or when there is none.
struct FileThumbnail: View {
    let url: URL
    let size: CGFloat
    @State private var thumbnail: NSImage?
    @State private var icon: NSImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        // The ZStack always has content, so the view exists and its `.task` runs to load the icon and preview.
        // An empty Group here would render nothing and never load anything.
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.quaternary.opacity(thumbnail == nil && icon == nil ? 1 : 0))
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(.rect(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.hairline, lineWidth: 0.5)
                    }
            } else if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .transition(.opacity)
        .task(id: url) {
            thumbnail = nil
            icon = NSWorkspace.shared.icon(forFile: url.path)
            let request = QLThumbnailGenerator.Request(
                fileAt: url, size: CGSize(width: size, height: size), scale: displayScale,
                representationTypes: .thumbnail)
            if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                withAnimation(.knobs) { thumbnail = representation.nsImage }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Turns a field label into a phrase for sentences such as "Drop a video here".
enum LabelPhrase {
    /// Letters whose names start with a vowel sound, so acronyms take "an": an MP3, an SRT, an HTML page.
    private static let vowelSoundingLetters = Set("AEFHILMNORSX")

    static func phrase(for label: String, isPlural: Bool) -> String {
        guard let firstWord = label.split(separator: " ").first else { return label }
        let isAcronym = firstWord.filter(\.isUppercase).count >= 2
        let text = isAcronym ? label : label.prefix(1).lowercased() + label.dropFirst()
        guard !isPlural else { return text }
        let first = text.first ?? "x"
        let takesAn =
            isAcronym ? vowelSoundingLetters.contains(Character(first.uppercased())) : "aeiou".contains(first)
        return "\(takesAn ? "an" : "a") \(text)"
    }
}
