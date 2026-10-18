import KnobsCore
import UniformTypeIdentifiers

/// Plain names for what a task takes, read from its main input's declared types, never from the tool:
/// "Video", "Image", "PDF", "Audio", "Folder", "Link", "Any file".
enum InputKind {
    /// The task's main input in a word or two, or nil when it has none.
    static func summary(of task: ManifestTask) -> String? {
        guard let field = task.fields.first(where: isMainInput) else { return nil }
        switch field.kind {
        case .inputFile(let identifiers, _):
            let names = names(for: identifiers)
            return names.isEmpty ? "Any file" : names.formatted(.list(type: .or))
        case .inputFolder:
            return "Folder"
        case .text(let placeholder):
            let isLink = placeholder.map { $0.hasPrefix("https://") || $0.hasPrefix("http://") } ?? false
            return isLink ? "Link" : nil
        default:
            return nil
        }
    }

    /// One name per kind, in the order declared, without repeats.
    static func names(for identifiers: [String]) -> [String] {
        var names: [String] = []
        for type in identifiers.compactMap({ UTType($0) }) {
            let name = name(for: type)
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    private static func name(for type: UTType) -> String {
        if type.conforms(to: .movie) { return "Video" }
        if type.conforms(to: .audio) { return "Audio" }
        if type.conforms(to: .audiovisualContent) { return "Video or audio" }
        if type.conforms(to: .image) { return "Image" }
        if type.conforms(to: .pdf) { return "PDF" }
        let description = type.localizedDescription ?? type.identifier
        return description.prefix(1).uppercased() + description.dropFirst()
    }

    /// File and folder inputs first, then a required text field such as a link.
    private static func isMainInput(_ field: Field) -> Bool {
        switch field.kind {
        case .inputFile, .inputFolder: true
        case .text: field.isRequired
        default: false
        }
    }
}
