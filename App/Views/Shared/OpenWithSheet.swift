import KnobsCore
import SwiftUI

/// "What do you want to do with this file?": shown when a file opened with Knobs fits several tasks.
struct OpenWithSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let pending: AppModel.PendingFiles

    private var title: String {
        pending.urls.count == 1
            ? "What do you want to do with “\(pending.urls[0].lastPathComponent)”?"
            : "What do you want to do with these \(pending.urls.count) files?"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                if let first = pending.urls.first {
                    FileThumbnail(url: first, size: 56)
                }
                Text(title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(pending.choices, id: \.task.id.self) { choice in
                        Button {
                            model.use(pending.urls, for: choice.task, of: choice.manifest)
                        } label: {
                            HStack(spacing: 12) {
                                GlyphTile(symbol: choice.task.symbol, tint: choice.manifest.tint, size: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(choice.task.title).font(.body.weight(.medium))
                                    Text(choice.manifest.name).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .contentShape(.rect)
                        }
                        .buttonStyle(ChoiceRowStyle())
                    }
                }
            }
            .frame(maxHeight: 380)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.pendingFiles = nil }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(width: 460)
    }
}

/// A list row that highlights on hover and press, like a menu.
private struct ChoiceRowStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.12 : isHovered ? 0.07 : 0),
                in: .rect(cornerRadius: 9)
            )
            .onHover { isHovered = $0 }
    }
}
