import KnobsCore
import SwiftUI

/// A tool's front page: what it is, and a gallery of the everyday tasks it can do.
struct ToolHomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let manifest: ToolManifest

    private let columns = [GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if !model.isInstalled(manifest) {
                    NotInstalledPanel(manifest: manifest)
                }
                if !manifest.tasks.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What do you want to do?")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                            ForEach(manifest.tasks) { task in
                                TaskCard(
                                    title: task.title, summary: task.summary, symbol: task.symbol, tint: manifest.tint
                                ) {
                                    model.taskPath = [task.id]
                                }
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text(manifest.tasks.isEmpty ? "Build a command" : "Or build your own command")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        TaskCard(
                            title: "All options",
                            summary: "Every option \(manifest.name) lists in its own help, searchable.",
                            symbol: "list.bullet.rectangle", tint: .gray, isSecondary: true
                        ) {
                            model.taskPath = [HelpTaskBuilder.taskID]
                        }
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(manifest.name)
        .toolbar {
            if let homepage = manifest.homepage, let url = URL(string: homepage) {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openURL(url)
                    } label: {
                        Label("\(manifest.name) Website", systemImage: "safari")
                    }
                    .help("Open the \(manifest.name) website")
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            GlyphTile(symbol: manifest.symbol, tint: manifest.tint, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(manifest.name)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text(manifest.summary)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TaskCard: View {
    let title: String
    let summary: String
    let symbol: String
    let tint: Tint
    var isSecondary = false
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 12) {
                GlyphTile(symbol: symbol, tint: tint, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(isSecondary ? AnyShapeStyle(.clear) : AnyShapeStyle(.background.secondary))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(
                        isHovered ? tint.color.opacity(0.55) : Color.primary.opacity(isSecondary ? 0.16 : 0.08),
                        style: StrokeStyle(lineWidth: 1, dash: isSecondary ? [5, 4] : []))
            }
            .shadow(color: .black.opacity(isHovered ? 0.10 : 0), radius: 10, y: 4)
            .offset(y: isHovered ? -2 : 0)
            .contentShape(.rect(cornerRadius: Metrics.cardRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.knobs) { isHovered = hovering }
        }
        .accessibilityLabel(title)
        .accessibilityHint(summary)
    }
}
