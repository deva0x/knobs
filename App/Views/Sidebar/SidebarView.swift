import KnobsCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    private static let visibleRecentRuns = 6

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedToolID) {
            Section("Tools") {
                ForEach(model.manifests) { manifest in
                    ToolRow(
                        manifest: manifest,
                        isInstalled: model.isInstalled(manifest),
                        isRunning: model.isRunningAnything(of: manifest)
                    )
                    .tag(manifest.id)
                }
            }
            if !model.library.recentRuns.isEmpty {
                Section("Recent") {
                    ForEach(model.library.recentRuns.prefix(Self.visibleRecentRuns)) { run in
                        if let (manifest, task) = model.resolve(run) {
                            RecentRunRow(run: run, manifest: manifest, task: task) {
                                model.open(toolID: manifest.id, taskID: task.id)
                            }
                        }
                    }
                }
            }
            if !model.manifestFailures.isEmpty {
                Section("Couldn't load") {
                    ForEach(model.manifestFailures, id: \.self) { failure in
                        Label(failure.source, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                            .help(failure.localizedDescription)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            Button {
                model.isPaletteVisible = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                    Text("Find a task")
                    Spacer()
                    Text("⌘K").font(.caption.monospaced()).foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 9))
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 6)
            .accessibilityLabel("Find a task")
            .accessibilityHint("Opens a search across every tool and task")
        }
    }
}

private struct ToolRow: View {
    let manifest: ToolManifest
    let isInstalled: Bool
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 9) {
            GlyphTile(symbol: manifest.symbol, tint: manifest.tint, size: 24)
                .saturation(isInstalled ? 1 : 0.15)
            VStack(alignment: .leading, spacing: 1) {
                Text(manifest.name)
                if !isInstalled {
                    Text("Not installed").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if isRunning {
                ProgressView().controlSize(.mini)
                    .accessibilityLabel("Running")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct RecentRunRow: View {
    let run: RecentRun
    let manifest: ToolManifest
    let task: ManifestTask
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 9) {
                Image(systemName: run.succeeded ? task.symbol : "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(run.succeeded ? manifest.tint.color : .red)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title).lineLimit(1)
                    Text(run.finishedAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let path = run.outputPath, FileManager.default.fileExists(atPath: path) {
                Button("Show Result in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
                }
            }
        }
        .accessibilityLabel("\(task.title), \(manifest.name), \(run.succeeded ? "finished" : "failed")")
    }
}
