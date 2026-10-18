import Adwaita
import KnobsCore
import KnobsSession

/// Shown while a tool's "All options" task isn't ready: reading its help, or why there's nothing to show. Once
/// the help is read, the window shows the generated task as an ordinary `TaskPage`.
struct AllOptionsPage: View {
    let model: Toolbox
    let manifest: ToolManifest
    let back: () -> Void
    /// Redraws the window when the help has been read (see `MainQueuePump`).
    @State private var revision = 0

    var view: Body {
        if model.location(of: manifest) == nil {
            StatusPage(
                "\(manifest.name) isn't installed", icon: .default(icon: .dialogWarning),
                description: "Install the \(manifest.executable) command, then reopen Knobs to see its options."
            ) {
                Button("Back to \(manifest.name)", handler: back)
                    .pill()
                    .halign(.center)
            }
        } else {
            switch model.allOptions[manifest.id] {
            case .ready(let generated)?:
                TaskPage(model: model, session: model.session(for: generated.task, of: manifest), back: back)
            case nil, .loading?:
                StatusPage(
                    "Reading \(manifest.name)'s options…", icon: .default(icon: .systemSearch),
                    description: "Knobs asks the tool for its help and turns each option into a switch or a field."
                )
                .onAppear {
                    Task { await model.loadAllOptions(for: manifest) }
                    MainQueuePump.pump(while: { isReading }, tick: { revision += 1 })
                }
            case .unavailable?:
                StatusPage(
                    "No options found", icon: .default(icon: .dialogInformation),
                    description:
                        "\(manifest.name) didn't print a list of options Knobs could read. You can still type options into Extra arguments on any task."
                ) {
                    Button("Back to \(manifest.name)", handler: back)
                        .pill()
                        .halign(.center)
                }
            }
        }
    }

    /// Until the help is read; the read starts on the main actor, which the pump also lets run.
    private var isReading: Bool {
        let state = model.allOptions[manifest.id]
        return state == nil || state == .loading
    }
}
