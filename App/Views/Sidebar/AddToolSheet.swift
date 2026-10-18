import KnobsCore
import KnobsSession
import SwiftUI

/// Adds any installed command-line tool by name. Its "All options" view comes from its own help.
struct AddToolSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(Toolbox.self) private var toolbox
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var isFocused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private var location: URL? { trimmed.contains("/") ? nil : toolbox.locate(trimmed) }
    private var isAlreadyAdded: Bool {
        toolbox.manifests.contains { $0.executable == trimmed }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                GlyphTile(symbol: "terminal", tint: .gray, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add a tool").font(.title2.weight(.semibold))
                    Text("Any command-line tool on your Mac. Knobs reads its options from its own help.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            TextField("Tool name", text: $name, prompt: Text("jq, curl, fd…"))
                .textFieldStyle(.roundedBorder)
                .font(.system(.title3, design: .monospaced))
                .focused($isFocused)
                .onSubmit(add)
            status
                .font(.callout)
                .frame(minHeight: 20, alignment: .leading)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Tool", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(location == nil || isAlreadyAdded)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear { isFocused = true }
    }

    @ViewBuilder private var status: some View {
        if trimmed.isEmpty {
            Text("Type the name you'd use in Terminal.").foregroundStyle(.secondary)
        } else if trimmed.contains("/") {
            Label("Type just the name, not a path.", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
        } else if isAlreadyAdded {
            Label("\(trimmed) is already in Knobs.", systemImage: "checkmark.circle").foregroundStyle(.secondary)
        } else if let location {
            Label("Found at \(location.path)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            Label("No tool named \(trimmed) was found.", systemImage: "questionmark.circle").foregroundStyle(.secondary)
        }
    }

    private func add() {
        guard location != nil, !isAlreadyAdded else { return }
        model.addTool(named: trimmed)
        dismiss()
    }
}
