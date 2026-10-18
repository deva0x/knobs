import KnobsCore

/// Manifests name file types with Apple's type identifiers, such as `public.movie`. GTK's file dialog filters by
/// MIME type, so each identifier the manifests use maps to the MIME types that mean the same thing. An unknown
/// identifier adds no filter, so the dialog then shows every file rather than hiding the right one.
enum FileTypeFilter {
    private static let mimeTypes: [String: [String]] = [
        "public.movie": ["video/*"],
        "public.audio": ["audio/*"],
        "public.audiovisual-content": ["video/*", "audio/*"],
        "public.image": ["image/*"],
        "com.adobe.pdf": ["application/pdf"],
        "public.plain-text": ["text/plain"],
        "net.daringfireball.markdown": ["text/markdown"],
        "org.openxmlformats.wordprocessingml.document": [
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        ],
    ]

    /// GTK lists each filter as a choice in the dialog, so each needs a name.
    private static let names: [String: String] = [
        "video/*": "Videos", "audio/*": "Audio", "image/*": "Images", "application/pdf": "PDFs",
        "text/plain": "Text files", "text/markdown": "Markdown files",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "Word documents",
    ]

    static func filters(for kind: FieldKind) -> [FileChooser.Filter] {
        guard case .inputFile(let identifiers, _) = kind, !identifiers.isEmpty else { return [] }
        let known = identifiers.compactMap { mimeTypes[$0] }
        // One identifier the map doesn't know means some files of that kind would be hidden; show everything.
        guard known.count == identifiers.count else { return [] }
        return known.joined().map { FileChooser.Filter(mimeType: $0, name: names[$0]) }
    }
}
