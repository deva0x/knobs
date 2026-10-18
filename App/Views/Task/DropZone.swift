import KnobsCore
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// The big target for a task's main input file: drop it, or choose it. Once set, it shows a Quick Look preview.
struct DropZone: View {
    let field: Field
    @Bindable var session: TaskSession
    @State private var isTargeted = false
    @State private var isImporting = false
    @State private var rejectedDrop = false

    private var paths: [String] { session.value(of: field)?.pathList ?? [] }
    private var tint: Color { session.manifest.tint.color }

    private var allowedTypes: [UTType] {
        guard case .inputFile(let identifiers, _) = field.kind else { return [.item] }
        let types = identifiers.compactMap { UTType($0) }
        return types.isEmpty ? [.item, .folder] : types
    }

    private var allowsMultiple: Bool {
        if case .inputFile(_, true) = field.kind { return true }
        return false
    }

    /// "a video", "an image", "a PDF", "PDFs": the field's label as a phrase.
    private var kindName: String {
        LabelPhrase.phrase(for: field.label, isPlural: allowsMultiple)
    }

    var body: some View {
        Group {
            if paths.isEmpty {
                emptyState
            } else {
                filledState
            }
        }
        .animation(.knobs, value: paths)
        .dropDestination(for: URL.self) { urls, _ in
            let accepted = urls.filter { FileTypeCheck.accepts($0, for: field.kind) }
            guard !accepted.isEmpty else {
                flashRejection()
                return false
            }
            let newPaths = accepted.map(\.path)
            session.setValue(.paths(allowsMultiple ? paths + newPaths : [newPaths[0]]), for: field)
            return true
        } isTargeted: { targeted in
            withAnimation(.knobs) { isTargeted = targeted }
        }
        .fileImporter(
            isPresented: $isImporting, allowedContentTypes: allowedTypes, allowsMultipleSelection: allowsMultiple
        ) {
            result in
            if case .success(let urls) = result, !urls.isEmpty {
                session.setValue(.paths(allowsMultiple ? paths + urls.map(\.path) : [urls[0].path]), for: field)
            }
        }
        .disabled(session.isRunning)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: isTargeted ? "arrow.down.circle.fill" : "plus.circle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(isTargeted ? tint : .secondary)
                .symbolEffect(.bounce, value: isTargeted)
                .contentTransition(.symbolEffect(.replace))
            Text(rejectedDrop ? "That isn't \(kindName)" : "Drop \(kindName) here")
                .font(.headline)
                .foregroundStyle(rejectedDrop ? .red : .primary)
            Button("Choose \(field.label)…") { isImporting = true }
                .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 168)
        .background {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(isTargeted ? tint.opacity(0.08) : Color.primary.opacity(0.025))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(
                    isTargeted ? tint : Color.primary.opacity(0.16),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.25, dash: isTargeted ? [] : [6, 5])
                )
        }
        .scaleEffect(isTargeted ? 1.01 : 1)
        .contentShape(.rect)
        .onTapGesture { isImporting = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(field.label): none chosen. Drop \(kindName) here, or choose one.")
        .accessibilityAddTraits(.isButton)
    }

    private var filledState: some View {
        VStack(spacing: 0) {
            ForEach(Array(paths.enumerated()), id: \.element) { index, path in
                if index > 0 { Divider().padding(.leading, 96) }
                FileSummaryRow(path: path, showsRemoveButton: allowsMultiple) {
                    let remaining = paths.filter { $0 != path }
                    session.setValue(remaining.isEmpty ? nil : .paths(remaining), for: field)
                }
            }
            if allowsMultiple {
                Divider()
                Button("Add More…") { isImporting = true }
                    .buttonStyle(.link)
                    .padding(10)
            }
        }
        .background(.background.secondary, in: .rect(cornerRadius: Metrics.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius)
                .strokeBorder(isTargeted ? tint : Color.primary.opacity(0.07), lineWidth: isTargeted ? 2 : 1)
        }
        .overlay(alignment: .topTrailing) {
            if !allowsMultiple {
                HStack(spacing: 6) {
                    Button("Replace…") { isImporting = true }
                    Button {
                        session.setValue(nil, for: field)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .help("Remove")
                    .accessibilityLabel("Remove \(field.label.lowercased())")
                }
                .controlSize(.small)
                .padding(14)
            }
        }
        .transition(.scale(scale: 0.97).combined(with: .opacity))
    }

    private func flashRejection() {
        withAnimation(.knobs) { rejectedDrop = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.knobs) { rejectedDrop = false }
        }
    }
}

/// A chosen file: Quick Look thumbnail, name, size and kind.
struct FileSummaryRow: View {
    let path: String
    let showsRemoveButton: Bool
    let remove: () -> Void

    private var url: URL { URL(filePath: path) }

    private var details: String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .localizedTypeDescriptionKey])
        let size = values?.fileSize.map { ByteCount.string(Int64($0)) }
        return [size, values?.localizedTypeDescription].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 14) {
            FileThumbnail(url: url, size: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(url.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(details)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .padding(.trailing, showsRemoveButton ? 0 : 150)
            Spacer(minLength: 0)
            if showsRemoveButton {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(url.lastPathComponent)")
            }
        }
        .padding(14)
        .draggable(url)
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Open") { NSWorkspace.shared.open(url) }
        }
    }
}

/// A Quick Look thumbnail, falling back to the Finder icon while it loads or when there is none.
struct FileThumbnail: View {
    let url: URL
    let size: CGFloat
    @State private var thumbnail: NSImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(.rect(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
                    }
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .transition(.opacity)
        .task(id: url) {
            thumbnail = nil
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
