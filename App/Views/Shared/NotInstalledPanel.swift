import KnobsCore
import KnobsSession
import SwiftUI

/// Shown when a tool's executable can't be found. Knobs never installs tools itself; it shows the command, and one
/// command for every missing tool when there are several.
struct NotInstalledPanel: View {
    @Environment(Toolbox.self) private var toolbox
    let manifest: ToolManifest

    private static let homebrewSite = URL(string: "https://brew.sh")!

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(manifest.name) isn't installed", systemImage: "shippingbox")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(
                "Knobs runs the copy of \(manifest.name) installed on your Mac. Install it with Homebrew in Terminal, then check again."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if !toolbox.isHomebrewInstalled {
                HStack(spacing: 10) {
                    Text("Homebrew isn't installed yet. It's free; install it first, from its website.")
                        .fixedSize(horizontal: false, vertical: true)
                    Link("Open brew.sh", destination: Self.homebrewSite)
                }
            }
            HStack(spacing: 10) {
                CommandToCopy(command: "brew install \(manifest.brewFormula)")
                Button("Check Again") { toolbox.refreshAvailability() }
            }
            let missing = toolbox.missingFormulas
            if missing.count > 1 {
                Text("\(missing.count) tools aren't installed. To install all of them at once:")
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                CommandToCopy(command: "brew install " + missing.joined(separator: " "))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: Metrics.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius).strokeBorder(Color.hairline, lineWidth: 1)
        }
    }
}

/// A Terminal command in a well, with a Copy button that says "Copied" for a moment.
private struct CommandToCopy: View {
    let command: String
    @State private var didCopy = false

    var body: some View {
        HStack(spacing: 10) {
            Text(command)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.background.tertiary, in: .rect(cornerRadius: Metrics.wellRadius))
            Button(didCopy ? "Copied" : "Copy") {
                Pasteboard.copy(command)
                withAnimation(.knobs) { didCopy = true }
            }
            .task(id: didCopy) {
                guard didCopy, (try? await Task.sleep(for: .seconds(1.5))) != nil else { return }
                withAnimation(.knobs) { didCopy = false }
            }
        }
    }
}
