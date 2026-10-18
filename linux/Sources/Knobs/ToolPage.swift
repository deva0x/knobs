import Adwaita
import CAdw
import KnobsCore

/// A tool's page: its name, summary and where it's installed, then the everyday tasks it can do.
struct ToolPage: View {
    let model: LinuxModel
    let manifest: ToolManifest
    let open: (String) -> Void
    let remove: () -> Void

    var view: Body {
        ScrollView {
            VStack {
                Text(manifest.name)
                    .title1()
                    .halign(.start)
                Text(manifest.summary)
                    .dimLabel()
                    .halign(.start)
                    .padding(4, .top)
                Text(installStatus)
                    .caption()
                    .monospace(model.location(of: manifest) != nil)
                    .dimLabel()
                    .halign(.start)
                    .padding(6, .top)
                // A tool added by name has no everyday tasks, only All options.
                if !manifest.tasks.isEmpty {
                    Text("What do you want to do?")
                        .heading()
                        .halign(.start)
                        .padding(24, .top)
                        .padding(8, .bottom)
                    List(manifest.tasks, selection: nil) { task in
                        NavigationRow(title: task.title, summary: task.summary) { open(task.id) }
                    }
                    .boxedList()
                }
                Text(manifest.tasks.isEmpty ? "Options" : "Anything else")
                    .heading()
                    .halign(.start)
                    .padding(24, .top)
                    .padding(8, .bottom)
                List([HelpTaskBuilder.taskID], id: \.self, selection: nil) { _ in
                    NavigationRow(
                        title: "All options",
                        summary: "Every option \(manifest.name) lists in its help, as switches and fields."
                    ) { open(HelpTaskBuilder.taskID) }
                }
                .boxedList()
                if manifest.isAddedByUser {
                    Button("Remove \(manifest.name) from Knobs", handler: remove)
                        .destructive()
                        .pill()
                        .halign(.center)
                        .insensitive(!model.canRemoveTool(manifest))
                        .padding(24, .top)
                }
            }
            .padding(24)
            .frame(maxWidth: 720)
        }
        .topToolbar {
            HeaderBar.empty()
                .headerBarTitle { WindowTitle(subtitle: "", title: manifest.name) }
        }
    }

    private var installStatus: String {
        if let location = model.location(of: manifest) {
            return "Installed at \(location.path)"
        }
        return "\(manifest.name) isn't installed. Install the \(manifest.executable) command with your "
            + "distribution's package manager, then reopen Knobs."
    }
}

/// A row that opens a page. Activation, not list selection, opens it: a selected row stays selected when the
/// toolkit reuses the list, and clicking it again would do nothing.
private struct NavigationRow: View {
    let title: String
    let summary: String
    let open: () -> Void

    var view: Body {
        ActionRow(title)
            .subtitle(summary)
            .useMarkup(false)
            .suffix {
                Image(icon: .default(icon: .goNext))
                    .valign(.center)
            }
            .activated(open)
            // An action row only reacts to clicks and Enter when it is activatable, which libadwaita otherwise
            // turns on only for a row with an activatable widget.
            .inspectOnAppear { storage in
                gtk_list_box_row_set_activatable(storage.opaquePointer?.cast(), 1)
            }
    }
}
