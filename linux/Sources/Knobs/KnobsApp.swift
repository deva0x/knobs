import Adwaita
import Foundation
import KnobsCore
import KnobsSession

@main
struct KnobsApp: App {
    var app = AdwaitaApp(id: "io.github.deva0x.Knobs")
    let model = Toolbox(
        manifestsDirectory: LinuxPaths.manifestsDirectory(
            environment: ProcessInfo.processInfo.environment, executable: Bundle.main.executableURL),
        dataDirectory: LinuxPaths.dataDirectory(environment: ProcessInfo.processInfo.environment),
        environment: ProcessInfo.processInfo.environment)

    var scene: Scene {
        Window(id: "main") { window in
            RootView(model: model, window: window)
        }
        .defaultSize(width: 1100, height: 760)
        .title("Knobs")
    }
}

/// The window: tools in the sidebar, and the selected tool's page or one of its tasks beside them.
struct RootView: WindowView {
    let model: Toolbox
    let window: AdwaitaWindow
    @State private var selectedToolID = ""
    /// The open task of the selected tool, or empty for the tool's page.
    @State private var openTaskID = ""
    @State private var isAddingTool = false
    @State private var isConfirmingClose = false
    /// Set once every run has stopped, so the close that follows goes through.
    @State private var haveRunsStopped = false

    private var tool: ToolManifest? {
        model.manifest(withID: selectedToolID) ?? model.manifests.first
    }

    var view: Body {
        NavigationSplitView {
            VStack {
                ScrollView {
                    List(
                        model.manifests,
                        selection: Binding {
                            tool?.id ?? ""
                        } set: { id in
                            // A different tool opens on its page, as on the Mac.
                            if id != selectedToolID { openTaskID = "" }
                            selectedToolID = id
                            isAddingTool = false
                        }
                    ) { manifest in
                        ToolRow(manifest: manifest, isInstalled: model.location(of: manifest) != nil)
                    }
                    .sidebarStyle()
                }
                .vexpand()
                Button("Add a Tool") {
                    isAddingTool = true
                }
                .flat()
                .padding(8)
            }
            .topToolbar {
                HeaderBar.empty()
                    .headerBarTitle { WindowTitle(subtitle: "", title: "Knobs") }
            }
        } content: {
            if isAddingTool {
                AddToolPage(model: model) { id in
                    selectedToolID = id
                    openTaskID = HelpTaskBuilder.taskID
                    isAddingTool = false
                } cancel: {
                    isAddingTool = false
                }
            } else if let tool {
                if let task = model.task(withID: openTaskID, in: tool) {
                    TaskPage(model: model, session: model.session(for: task, of: tool)) {
                        openTaskID = ""
                    }
                } else if openTaskID == HelpTaskBuilder.taskID {
                    AllOptionsPage(model: model, manifest: tool) {
                        openTaskID = ""
                    }
                } else {
                    ToolPage(model: model, manifest: tool) { taskID in
                        openTaskID = taskID
                    } remove: {
                        model.removeTool(tool)
                        selectedToolID = model.bundledManifests.first?.id ?? ""
                    }
                }
            } else {
                StatusPage(
                    "No tools found", icon: .default(icon: .dialogWarning),
                    description: "Knobs couldn't read its tool descriptions.")
            }
        }
        .alertDialog(
            visible: $isConfirmingClose, heading: "A task is still running",
            body: "Closing Knobs stops it, and the file it was making may be left incomplete."
        )
        .response("Keep Running", role: .close) {}
        .response("Stop and Close", appearance: .destructive, role: .default, action: stopRunsAndClose)
    }

    /// A tool outlives the app that started it, so a run must be stopped before the window closes. Ask first,
    /// because stopping can leave an incomplete output file.
    func window(_ window: Window) -> Window {
        window.onClose {
            guard model.hasRunningTasks, !haveRunsStopped else { return .close }
            isConfirmingClose = true
            return .cancel
        }
    }

    private func stopRunsAndClose() {
        Task {
            await model.stopAllRuns()
            haveRunsStopped = true
            window.close()
        }
        // The runs report stopping through the main queue, which only the pump drains on Linux.
        MainQueuePump.pump(while: { !haveRunsStopped }, observing: {}, redraw: {})
    }
}

private struct ToolRow: View {
    let manifest: ToolManifest
    let isInstalled: Bool

    var view: Body {
        VStack {
            Text(manifest.name)
                .halign(.start)
            if !isInstalled {
                Text("Not installed")
                    .caption()
                    .dimLabel()
                    .halign(.start)
            }
        }
        .padding(8)
    }
}
