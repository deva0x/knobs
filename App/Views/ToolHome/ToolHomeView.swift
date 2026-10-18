import KnobsCore
import KnobsSession
import SwiftUI

/// A tool's front page: a hero washed in the tool's tint, then the everyday tasks it can do. Dropping files
/// anywhere on it offers the tasks that take them (docs/DESIGN.md, "Tool home").
struct ToolHomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(Toolbox.self) private var toolbox
    @Environment(\.openURL) private var openURL
    let manifest: ToolManifest
    @State private var isTargeted = false
    @State private var rejectedDrop = false

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                ToolHero(
                    manifest: manifest, isInstalled: toolbox.isInstalled(manifest),
                    location: toolbox.location(of: manifest)
                )
                if !toolbox.isInstalled(manifest) {
                    NotInstalledPanel(manifest: manifest)
                }
                if !manifest.tasks.isEmpty {
                    section(title: rejectedDrop ? "No task here takes that file" : "What do you want to do?") {
                        ForEach(manifest.tasks) { task in
                            TaskCard(
                                title: task.title, summary: task.summary, symbol: task.symbol, tint: manifest.tint,
                                takes: InputKind.summary(of: task)
                            ) {
                                model.taskPath = [task.id]
                            }
                        }
                    }
                }
                section(title: manifest.tasks.isEmpty ? "Build a command" : "Or build your own command") {
                    TaskCard(
                        title: "All options",
                        summary: "Every option \(manifest.name) lists in its own help, searchable.",
                        symbol: "list.bullet.rectangle", tint: .gray, takes: nil, isSecondary: true
                    ) {
                        model.taskPath = [HelpTaskBuilder.taskID]
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 28)
            .padding(.bottom, 36)
            .frame(maxWidth: 1080, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(alignment: .top) {
            HeroBackdrop(tint: manifest.tint.color)
                .frame(height: 340)
                .ignoresSafeArea(edges: .top)
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(manifest.tint.color, lineWidth: 3)
                    .padding(10)
                    .allowsHitTesting(false)
                    .knobsTransition(.opacity)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard model.canOpen(urls, in: manifest) else {
                withAnimation(.knobs) { rejectedDrop = true }
                return false
            }
            model.openFiles(urls, in: manifest)
            return true
        } isTargeted: { targeted in
            withAnimation(.knobs) { isTargeted = targeted }
        }
        .task {
            model.openPendingTask(of: manifest.id)
        }
        .task(id: rejectedDrop) {
            guard rejectedDrop, (try? await Task.sleep(for: .seconds(2.5))) != nil else { return }
            withAnimation(.knobs) { rejectedDrop = false }
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

    private func section<Cards: View>(title: String, @ViewBuilder cards: () -> Cards) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.sectionHeader)
                .foregroundStyle(rejectedDrop ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .contentTransition(.opacity)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                cards()
            }
        }
    }
}

/// The tool's name, summary and where it's installed, over the tint wash.
private struct ToolHero: View {
    let manifest: ToolManifest
    let isInstalled: Bool
    let location: URL?

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            GlyphTile(symbol: manifest.symbol, tint: manifest.tint, size: 76)
                .shadow(color: manifest.tint.color.opacity(0.35), radius: 18, y: 8)
            VStack(alignment: .leading, spacing: 6) {
                Text(manifest.name)
                    .font(.system(size: 30, weight: .bold))
                Text(manifest.summary)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if isInstalled, let location {
                    Label {
                        Text(location.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(Font.helpText.monospaced())
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    .font(.helpText)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                    .help("Knobs runs the copy of \(manifest.name) installed here")
                }
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A soft mesh of the tool's tint that fades into the window, behind the hero and the toolbar.
private struct HeroBackdrop: View {
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let strength = colorScheme == .dark ? 1.0 : 0.7
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.55], [0.45, 0.5], [1, 0.45],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                tint.opacity(0.42 * strength), tint.opacity(0.26 * strength), tint.opacity(0.12 * strength),
                tint.opacity(0.20 * strength), tint.opacity(0.10 * strength), tint.opacity(0.03 * strength),
                .clear, .clear, .clear,
            ]
        )
        .accessibilityHidden(true)
    }
}

private struct TaskCard: View {
    let title: String
    let summary: String
    let symbol: String
    let tint: Tint
    /// What the task takes, such as "Video", shown as a quiet chip.
    let takes: String?
    var isSecondary = false
    let open: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    GlyphTile(symbol: symbol, tint: tint, size: 42)
                    Spacer()
                    if let takes {
                        Text(takes)
                            .font(Font.helpText.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary.opacity(0.6), in: .capsule)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSecondary ? AnyShapeStyle(.clear) : AnyShapeStyle(.background.secondary.opacity(0.75)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isHovered
                            ? tint.color.opacity(0.6) : isSecondary ? Color.primary.opacity(0.16) : Color.hairline,
                        style: StrokeStyle(lineWidth: isHovered ? 1.5 : 1, dash: isSecondary ? [5, 4] : []))
            }
            .shadow(color: tint.color.opacity(isHovered ? 0.22 : 0), radius: 16, y: 6)
            .offset(y: isHovered && !reduceMotion ? -2 : 0)
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.knobs) { isHovered = hovering }
        }
        .accessibilityLabel(title)
        .accessibilityHint([summary, takes.map { "Takes: \($0)" }].compactMap { $0 }.joined(separator: ". "))
    }
}
