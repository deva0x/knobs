import Adwaita
import KnobsCore

/// A tool's page: its name, summary and where it's installed, then the everyday tasks it can do.
struct ToolPage: View {
    let model: LinuxModel
    let manifest: ToolManifest
    let open: (String) -> Void

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
                Text("What do you want to do?")
                    .heading()
                    .halign(.start)
                    .padding(24, .top)
                    .padding(8, .bottom)
                List(
                    manifest.tasks,
                    selection: Binding {
                        ""
                    } set: {
                        open($0)
                    }
                ) { task in
                    TaskRow(task: task)
                }
                .boxedList()
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

private struct TaskRow: View {
    let task: ManifestTask

    var view: Body {
        VStack {
            Text(task.title)
                .heading()
                .halign(.start)
            Text(task.summary)
                .dimLabel()
                .halign(.start)
                .padding(2, .top)
        }
        .padding(12)
    }
}
