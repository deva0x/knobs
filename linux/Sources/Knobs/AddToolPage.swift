import Adwaita
import Foundation
import KnobsCore

/// Adds any installed command-line tool by name. Its "All options" page comes from its own help.
struct AddToolPage: View {
    let model: LinuxModel
    /// Called with the new tool's id once it is added.
    let added: (String) -> Void
    let cancel: () -> Void
    @State private var name = ""

    var view: Body {
        ScrollView {
            VStack {
                Text("Add a tool")
                    .title1()
                    .halign(.start)
                Text("Any command-line tool on this computer. Knobs reads its options from its own help.")
                    .wrap(true)
                    .xalign(0)
                    .dimLabel()
                    .halign(.start)
                    .padding(4, .top)
                Form {
                    EntryRow("Tool name, such as jq or curl", text: $name)
                        .useMarkup(false)
                        .onSubmit(add)
                }
                .padding(20, .top)
                Text(status)
                    .wrap(true)
                    .xalign(0)
                    .caption()
                    .dimLabel()
                    .halign(.start)
                    .padding(8, .top)
                HStack {
                    Button("Cancel", handler: cancel)
                        .pill()
                    Button("Add Tool", handler: add)
                        .suggested()
                        .pill()
                        .insensitive(!canAdd)
                        .padding(12, .leading)
                }
                .halign(.center)
                .padding(24, .top)
            }
            .padding(24)
            .frame(maxWidth: 560)
        }
        .topToolbar {
            HeaderBar.empty()
                .headerBarTitle { WindowTitle(subtitle: "", title: "Add a Tool") }
        }
    }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var isAlreadyAdded: Bool {
        model.manifests.contains { $0.executable == trimmed }
    }

    private var location: URL? {
        trimmed.contains("/") ? nil : model.locate(trimmed)
    }

    private var canAdd: Bool {
        location != nil && !isAlreadyAdded
    }

    private var status: String {
        if trimmed.isEmpty { return "Type the name you'd use in a terminal." }
        if trimmed.contains("/") { return "Type just the name, not a path." }
        if isAlreadyAdded { return "\(trimmed) is already in Knobs." }
        if let location { return "Found at \(location.path)" }
        return "No tool named \(trimmed) was found."
    }

    private func add() {
        guard canAdd, let id = model.addTool(named: trimmed) else { return }
        added(id)
    }
}
