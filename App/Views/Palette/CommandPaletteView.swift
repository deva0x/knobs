import KnobsCore
import SwiftUI

/// ⌘K: find any task in any tool by typing, then press Return.
struct CommandPaletteView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var isSearchFocused: Bool

    private struct Entry: Identifiable {
        let manifest: ToolManifest
        let task: ManifestTask?
        var id: String { "\(manifest.id)/\(task?.id ?? "")" }
        var title: String { task?.title ?? manifest.name }
        var subtitle: String { task == nil ? manifest.summary : manifest.name }
        var symbol: String { task?.symbol ?? manifest.symbol }
        var searchText: String { "\(title) \(manifest.name) \(task?.summary ?? manifest.summary)".lowercased() }
    }

    /// Results are capped so the list stays short and fast to scan.
    private static let maximumResults = 9

    private var entries: [Entry] {
        let all = model.manifests.flatMap { manifest in
            [Entry(manifest: manifest, task: nil)] + manifest.tasks.map { Entry(manifest: manifest, task: $0) }
        }
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return Array(all.filter { $0.task != nil }.prefix(Self.maximumResults)) }
        return Array(
            all.filter { entry in words.allSatisfy { entry.searchText.contains($0) } }
                .sorted { lhs, rhs in
                    lhs.title.lowercased().hasPrefix(words[0]) && !rhs.title.lowercased().hasPrefix(words[0])
                }
                .prefix(Self.maximumResults))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { close() }
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    TextField("Shrink a video, extract audio, compress a PDF…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .focused($isSearchFocused)
                        .onSubmit(openHighlighted)
                        .onKeyPress(.downArrow) {
                            highlighted = min(highlighted + 1, max(entries.count - 1, 0))
                            return .handled
                        }
                        .onKeyPress(.upArrow) {
                            highlighted = max(highlighted - 1, 0)
                            return .handled
                        }
                        .onKeyPress(.escape) {
                            close()
                            return .handled
                        }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

                Divider()

                if entries.isEmpty {
                    Text("No task matches “\(query)”")
                        .foregroundStyle(.secondary)
                        .padding(24)
                } else {
                    VStack(spacing: 2) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            row(entry, isHighlighted: index == highlighted)
                                .onTapGesture { open(entry) }
                                .onHover { if $0 { highlighted = index } }
                        }
                    }
                    .padding(8)
                }
            }
            .frame(width: 560)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .padding(.top, 90)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear { isSearchFocused = true }
        .onChange(of: query) { highlighted = 0 }
    }

    private func row(_ entry: Entry, isHighlighted: Bool) -> some View {
        HStack(spacing: 12) {
            GlyphTile(symbol: entry.symbol, tint: entry.manifest.tint, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).font(.body.weight(.medium))
                Text(entry.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if isHighlighted {
                Image(systemName: "return").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isHighlighted ? Color.primary.opacity(0.08) : .clear, in: .rect(cornerRadius: 10))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isHighlighted ? [.isButton, .isSelected] : .isButton)
    }

    private func openHighlighted() {
        guard entries.indices.contains(highlighted) else { return }
        open(entries[highlighted])
    }

    private func open(_ entry: Entry) {
        model.open(toolID: entry.manifest.id, taskID: entry.task?.id)
        close()
    }

    private func close() {
        model.isPaletteVisible = false
        query = ""
    }
}
