import KnobsCore
import SwiftUI

/// Shown when a tool's executable can't be found. Knobs never installs tools itself; it shows the command.
struct NotInstalledPanel: View {
    @Environment(AppModel.self) private var model
    let manifest: ToolManifest
    @State private var didCopy = false

    private var installCommand: String { "brew install \(manifest.brewFormula)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(manifest.name) isn't installed", systemImage: "shippingbox")
                .font(.headline)
            Text(
                "Knobs runs the copy of \(manifest.name) installed on your Mac. Install it with Homebrew in Terminal, then check again."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Text(installCommand)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.background.tertiary, in: .rect(cornerRadius: 8))
                Button(didCopy ? "Copied" : "Copy") {
                    Pasteboard.copy(installCommand)
                    withAnimation(.knobs) { didCopy = true }
                }
                Button("Check Again") { model.refreshAvailability() }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.08), in: .rect(cornerRadius: Metrics.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius).strokeBorder(.orange.opacity(0.25), lineWidth: 1)
        }
    }
}
