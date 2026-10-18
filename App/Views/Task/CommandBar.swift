import KnobsCore
import SwiftUI

/// The floating Liquid Glass bar: the live command and Run, which turns into progress and Cancel while running.
struct CommandBar: View {
    @Environment(AppModel.self) private var model
    @Bindable var session: TaskSession
    @Binding var showsOutput: Bool
    @State private var showsFullCommand = false
    @State private var didCopy = false

    var body: some View {
        HStack(spacing: 12) {
            if case .running(let startedAt) = session.phase {
                runningContent(startedAt: startedAt)
            } else {
                idleContent
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .glassEffect(.regular, in: .capsule)
        .animation(.knobs, value: session.isRunning)
    }

    private var idleContent: some View {
        Group {
            Button {
                showsFullCommand.toggle()
            } label: {
                Text(CommandText.attributed(session.draft.command, tint: session.manifest.tint.color))
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Show the whole command")
            .accessibilityLabel("Command")
            .accessibilityValue(session.draft.command.displayString)
            .popover(isPresented: $showsFullCommand, arrowEdge: .top) {
                FullCommandPopover(command: session.draft.command, tint: session.manifest.tint.color)
            }

            Button {
                Pasteboard.copy(session.draft.command.displayString)
                withAnimation(.knobs) { didCopy = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation(.knobs) { didCopy = false }
                }
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 18)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Copy the command")
            .accessibilityLabel(didCopy ? "Copied" : "Copy command")

            Button {
                model.run(session)
            } label: {
                Label("Run", systemImage: "play.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(.signal)
            .controlSize(.large)
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!session.draft.isRunnable || !model.isInstalled(session.manifest))
            .help(runHelp)
        }
    }

    private var runHelp: String {
        if !model.isInstalled(session.manifest) { return "\(session.manifest.name) isn't installed" }
        for problem in session.draft.problems {
            switch problem {
            case .missingValue(_, let label): return "Add \(label.lowercased()) first"
            case .extraArguments: return "Fix the extra arguments first"
            case .outputUnavailable: return "No free name for the output file"
            }
        }
        return "Run (⌘R)"
    }

    private func runningContent(startedAt: Date) -> some View {
        Group {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Running \(session.task.title.lowercased())…")
                        .font(.callout.weight(.medium))
                    Spacer()
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        Text(
                            Duration.seconds(context.date.timeIntervalSince(startedAt)).formatted(
                                .time(pattern: .minuteSecond))
                        )
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    if let progress = session.progress {
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .font(.callout.monospacedDigit().weight(.medium))
                            .contentTransition(.numericText())
                    }
                }
                if let progress = session.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(session.manifest.tint.color)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(session.manifest.tint.color)
                }
            }
            .accessibilityElement(children: .combine)

            Button {
                withAnimation(.knobs) { showsOutput.toggle() }
            } label: {
                Image(systemName: "text.alignleft")
            }
            .buttonStyle(.borderless)
            .help(showsOutput ? "Hide output" : "Show output")
            .accessibilityLabel(showsOutput ? "Hide output" : "Show output")

            Button("Cancel", role: .cancel) { session.cancel() }
                .buttonStyle(.glass)
                .controlSize(.large)
                .keyboardShortcut(".", modifiers: .command)
        }
    }
}

private struct FullCommandPopover: View {
    let command: Command
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The command Knobs will run")
                .font(.headline)
            ScrollView {
                Text(CommandText.attributed(command, tint: tint, oneArgumentPerLine: true))
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)
            Text("Each line is one argument, passed to the tool exactly as shown. No shell is involved.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 520)
    }
}

/// Colors a command by part, following docs/DESIGN.md: executable bold, flags in the tool's tint, paths quieter.
enum CommandText {
    static func attributed(_ command: Command, tint: Color, oneArgumentPerLine: Bool = false) -> AttributedString {
        var text = AttributedString(ShellQuoting.quote(command.executable))
        text.font = .system(size: 12, weight: .semibold, design: .monospaced)
        let separator = oneArgumentPerLine ? " \\\n    " : " "
        for part in command.arguments {
            text += AttributedString(separator)
            var piece = AttributedString(part.displayText)
            switch part.role {
            case .flag:
                piece.foregroundColor = tint
            case .value:
                break
            case .path:
                piece.foregroundColor = .secondary
            case .extra:
                piece.underlineStyle = Text.LineStyle(pattern: .dot)
            case .secret:
                piece.foregroundColor = .secondary
            case .missing:
                piece.foregroundColor = .orange
                piece.font = .system(size: 12, design: .monospaced).italic()
            }
            text += piece
        }
        return text
    }
}
