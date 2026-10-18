import KnobsCore
import KnobsSession
import SwiftUI

/// One task: the stage shows the input large, the inspector holds the settings, and the command bar floats at
/// the bottom of the stage (docs/DESIGN.md, "App layout").
struct TaskWorkspaceView: View {
    @Bindable var session: TaskSession
    @State private var showsOutput = false
    /// A per-viewer preference, remembered between launches.
    @AppStorage("showsInspector") private var showsInspector = true

    var body: some View {
        TaskStage(session: session, showsOutput: $showsOutput)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CommandBar(session: session, showsOutput: $showsOutput)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    .padding(.top, 6)
            }
            .inspector(isPresented: $showsInspector) {
                TaskInspector(session: session)
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
            }
            .navigationTitle(session.task.title)
            .navigationSubtitle(session.manifest.name)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    PresetsMenu(session: session)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showsInspector.toggle()
                    } label: {
                        Label(showsInspector ? "Hide Settings" : "Show Settings", systemImage: "sidebar.trailing")
                    }
                    .help(showsInspector ? "Hide the settings" : "Show the settings")
                }
            }
            .tint(session.manifest.tint.color)
            .onChange(of: session.phase) { _, phase in
                // A report is shown on the stage itself, so the separate console isn't needed for it.
                if case .finished(.succeeded) = phase, !session.producesResult { showsOutput = false }
            }
    }
}

/// The task's settings in the native inspector: one grouped form with Settings, Output and Extra arguments.
private struct TaskInspector: View {
    @Bindable var session: TaskSession

    private var outputPath: String? { session.draft.command.outputPath }

    var body: some View {
        Form {
            if !session.settingFields.isEmpty {
                Section("Settings") {
                    ForEach(session.settingFields) { field in
                        InspectorField(field: field, session: session)
                    }
                }
            }
            if let outputPath {
                Section("Output") {
                    LabeledContent("Name") {
                        Text(URL(filePath: outputPath).lastPathComponent)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    LabeledContent("Folder") {
                        Text(Self.shortened(URL(filePath: outputPath).deletingLastPathComponent().path))
                            .lineLimit(1)
                            .truncationMode(.head)
                            .help(URL(filePath: outputPath).deletingLastPathComponent().path)
                    }
                }
            }
            Section {
                TextField(
                    "Extra arguments", text: $session.extraArguments, prompt: Text("--option value"), axis: .vertical
                )
                .labelsHidden()
                .font(.system(.body, design: .monospaced))
                .lineLimit(1...4)
                .disabled(session.isRunning)
            } header: {
                Text("Extra arguments")
            } footer: {
                Text(
                    session.extraArgumentsProblem
                        ?? "Options added here go into the command as written. Quotes keep words together. Nothing runs through a shell."
                )
                .font(.helpText)
                .foregroundStyle(session.extraArgumentsProblem == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
            }
        }
        .formStyle(.grouped)
    }

    /// "~/Downloads" rather than "/Users/name/Downloads".
    private static func shortened(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

/// A grouped box of rows, like a section in System Settings.
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.sectionHeader)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { content }
                .background(.background.secondary, in: .rect(cornerRadius: Metrics.cardRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.cardRadius).strokeBorder(Color.hairline, lineWidth: 1)
                }
        }
    }
}

struct ExtraArgumentsSection: View {
    @Bindable var session: TaskSession
    @Binding var isExpanded: Bool

    private var splitError: String? { session.extraArgumentsProblem }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.knobs) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(Font.helpText.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text("Extra arguments")
                        .font(.sectionHeader)
                    if !session.extraArguments.isEmpty && !isExpanded {
                        Text("in use").font(.helpText).foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.secondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .accessibilityLabel("Extra arguments")
            .accessibilityValue(
                [isExpanded ? "Expanded" : "Collapsed", session.extraArguments.isEmpty ? nil : "in use"]
                    .compactMap { $0 }.joined(separator: ", "))

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("--option value", text: $session.extraArguments)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Extra arguments")
                    Text(
                        splitError
                            ?? "Options added here go into the command as written. Quotes keep words together. Nothing runs through a shell."
                    )
                    .font(.helpText)
                    .foregroundStyle(splitError == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 4)
                .knobsTransition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
