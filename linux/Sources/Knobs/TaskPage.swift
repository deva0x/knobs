import Adwaita
import Foundation
import KnobsCore
import KnobsSession

/// One task: its inputs and settings as Adwaita rows, the live command, and Run with progress and output.
struct TaskPage: View {
    let model: LinuxModel
    let session: TaskSession
    let back: () -> Void
    /// The session is shared with KnobsSession and doesn't tell Adwaita when it changes, so every edit and every
    /// tick of a run (see `MainQueuePump`) bumps this to redraw the page.
    @State private var revision = 0

    var view: Body {
        ScrollView {
            VStack {
                Text(session.task.summary)
                    .dimLabel()
                    .halign(.start)
                    .padding(16, .bottom)
                if !fields(.input).isEmpty {
                    section("Input", fields: fields(.input))
                }
                if !fields(.setting).isEmpty {
                    section("Settings", fields: fields(.setting))
                }
                FormSection("Extra arguments") {
                    Form {
                        EntryRow(
                            "Options added to the command as written",
                            text: Binding {
                                session.extraArguments
                            } set: { text in
                                session.extraArguments = text
                                revision += 1
                            })
                    }
                }
                .padding(12, .bottom)
                if let problem = session.extraArgumentsProblem {
                    Text(problem)
                        .error()
                        .halign(.start)
                        .padding(12, .bottom)
                }
                CommandCard(command: session.draft.command)
                RunControls(model: model, session: session) {
                    model.run(session)
                    revision += 1
                    MainQueuePump.pump(while: { session.isRunning }, tick: { revision += 1 })
                } cancel: {
                    session.cancel()
                    revision += 1
                }
                OutcomeView(session: session)
            }
            .padding(24)
            .frame(maxWidth: 760)
        }
        .topToolbar {
            HeaderBar {
                Button(icon: .default(icon: .goPrevious), handler: back)
                    .tooltip("Back to \(session.manifest.name)")
            } end: {
            }
            .headerBarTitle { WindowTitle(subtitle: session.manifest.name, title: session.task.title) }
        }
    }

    private enum FieldGroup {
        case input, setting
    }

    /// Files, folders and required text such as a link go first; everything else is a setting.
    private func fields(_ group: FieldGroup) -> [Field] {
        session.task.fields.filter { field in
            let isInput =
                switch field.kind {
                case .inputFile, .inputFolder: true
                case .text: field.isRequired
                default: false
                }
            return group == .input ? isInput : !isInput
        }
    }

    private func section(_ title: String, fields: [Field]) -> AnyView {
        FormSection(title) {
            List(fields, selection: nil) { field in
                FieldRow(field: field, session: session) { revision += 1 }
            }
            .boxedList()
        }
        .padding(12, .bottom)
    }
}

/// The command exactly as it will run, in a monospaced card the user can select and copy from.
private struct CommandCard: View {
    let command: Command

    var view: Body {
        VStack {
            Text("Command")
                .heading()
                .halign(.start)
                .padding(6, .bottom)
            // The label is the card, so it fills the width and keeps its text at the left edge.
            Text(command.displayString)
                .selectable(true)
                .wrap(true)
                .xalign(0)
                .monospace()
                .hexpand()
                .padding(12)
                .card()
        }
        .padding(12, .bottom)
    }
}

private struct RunControls: View {
    let model: LinuxModel
    let session: TaskSession
    let run: () -> Void
    let cancel: () -> Void

    var view: Body {
        VStack {
            if session.isRunning {
                ProgressBar(value: session.progress ?? 0, total: 1)
                    .padding(8, .bottom)
                Button("Cancel", handler: cancel)
                    .destructive()
                    .pill()
                    .halign(.center)
            } else {
                Button("Run", handler: run)
                    .suggested()
                    .pill()
                    .halign(.center)
                    .insensitive(!model.canRun(session))
                if let reason = blockedReason {
                    Text(reason)
                        .caption()
                        .dimLabel()
                        .padding(6, .top)
                }
            }
        }
        .padding(12, .vertical)
    }

    private var blockedReason: String? {
        if model.location(of: session.manifest) == nil { return "\(session.manifest.name) isn't installed." }
        for problem in session.draft.problems {
            switch problem {
            case .missingValue(_, let label): return "Add \(label.lowercased()) first."
            case .extraArguments: return "Fix the extra arguments first."
            case .outputUnavailable: return "There's no free name for the output file."
            }
        }
        return nil
    }
}

/// The last run: where the result went, or why it stopped, and the tool's own output.
private struct OutcomeView: View {
    let session: TaskSession

    var view: Body {
        VStack {
            if case .finished(let outcome) = session.phase {
                Text(headline(for: outcome))
                    .heading()
                    .success(outcome == .succeeded)
                    .error(outcome != .succeeded && outcome != .cancelled)
                    .halign(.start)
                    .padding(6, .bottom)
                if let output = session.result?.outputURL ?? session.result?.folderURL {
                    HStack {
                        Text(output.path)
                            .ellipsize()
                            .selectable(true)
                            .monospace()
                            .hexpand()
                            .halign(.start)
                        Button("Open") { SystemOpener.open(output) }
                            .valign(.center)
                        Button("Show Folder") { SystemOpener.open(output.deletingLastPathComponent()) }
                            .valign(.center)
                    }
                    .padding(8, .bottom)
                }
            }
            if !session.log.lines.isEmpty {
                Text(session.log.lines.suffix(Self.visibleLines).map(\.text).joined(separator: "\n"))
                    .selectable(true)
                    .wrap(true)
                    .monospace()
                    .caption()
                    .halign(.start)
                    .padding(12)
                    .card()
            }
        }
    }

    /// The console shows the newest lines; the full log stays in the session.
    private static let visibleLines = 200

    private func headline(for outcome: RunOutcome) -> String {
        switch outcome {
        case .succeeded:
            let seconds = Int((session.result?.duration ?? 0).rounded())
            return seconds < 1 ? "Done in under a second" : "Done in \(seconds) s"
        case .cancelled:
            return "Cancelled. A partly written output file may remain."
        case .failed:
            return "\(session.manifest.name) stopped with an error: "
                + (session.log.mostRelevantErrorLine ?? "see its output below.")
        case .couldNotStart(let reason):
            return "\(session.manifest.name) couldn't start: \(reason)"
        }
    }
}

/// Opens a file or folder in the user's default app, through `xdg-open` with an argument list (never a shell).
enum SystemOpener {
    static func open(_ url: URL) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/xdg-open")
        process.arguments = [url.path]
        do {
            try process.run()
        } catch {
            FileHandle.standardError.write(Data("knobs: couldn't open \(url.path) with xdg-open: \(error)\n".utf8))
        }
    }
}
