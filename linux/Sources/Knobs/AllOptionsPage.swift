import Adwaita
import KnobsCore

/// Shown while a tool's "All options" task isn't ready: reading its help, or why there's nothing to show. Once
/// the help is read, the window shows the generated task as an ordinary `TaskPage`.
struct AllOptionsPage: View {
    let model: LinuxModel
    let manifest: ToolManifest
    let back: () -> Void
    /// Redraws the window when the help has been read (see `MainQueuePump`).
    @State private var revision = 0

    var view: Body {
        switch model.allOptionsState(of: manifest) {
        case .ready(let task):
            TaskPage(model: model, session: model.session(for: task, of: manifest), back: back)
        case .notRead, .reading:
            StatusPage(
                "Reading \(manifest.name)'s options…", icon: .default(icon: .systemSearch),
                description: "Knobs asks the tool for its help and turns each option into a switch or a field."
            )
            .onAppear {
                model.readAllOptions(of: manifest)
                MainQueuePump.pump(
                    while: {
                        if case .reading = model.allOptionsState(of: manifest) { return true }
                        return false
                    },
                    tick: { revision += 1 })
            }
        case .unavailable:
            StatusPage(
                "No options found", icon: .default(icon: .dialogInformation),
                description:
                    "\(manifest.name) didn't print a list of options Knobs could read. You can still type options into Extra arguments on any task."
            ) {
                Button("Back to \(manifest.name)", handler: back)
                    .pill()
                    .halign(.center)
            }
        case .notInstalled:
            StatusPage(
                "\(manifest.name) isn't installed", icon: .default(icon: .dialogWarning),
                description: "Install the \(manifest.executable) command, then reopen Knobs to see its options."
            ) {
                Button("Back to \(manifest.name)", handler: back)
                    .pill()
                    .halign(.center)
            }
        }
    }
}
