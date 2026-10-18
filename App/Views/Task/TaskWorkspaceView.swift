import KnobsCore
import SwiftUI

/// One task: drop the file, set a few controls, run. The command bar floats at the bottom.
struct TaskWorkspaceView: View {
    @Environment(AppModel.self) private var model
    @Bindable var session: TaskSession
    @State private var showsExtraArguments = false
    @State private var showsOutput = false

    /// The main input gets the big drop zone; any other fields are ordinary rows.
    private var heroField: Field? { session.primaryInputField }

    private var settingFields: [Field] {
        session.task.fields.filter { $0.id != heroField?.id }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if !model.isInstalled(session.manifest) {
                        NotInstalledPanel(manifest: session.manifest)
                    }
                    if let heroField {
                        DropZone(field: heroField, session: session)
                    }
                    if !settingFields.isEmpty {
                        SettingsGroup(title: "Settings") {
                            ForEach(Array(settingFields.enumerated()), id: \.element.id) { index, field in
                                if index > 0 { Divider().padding(.leading, 16) }
                                FieldRow(field: field, session: session)
                            }
                        }
                    }
                    ExtraArgumentsSection(session: session, isExpanded: $showsExtraArguments)
                    RunOutcomeView(session: session, showsOutput: $showsOutput)
                        .id("outcome")
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)
                .padding(.bottom, 32)
                .frame(maxWidth: Metrics.contentMaxWidth)
                .frame(maxWidth: .infinity)
                .tint(session.manifest.tint.color)
            }
            .onChange(of: session.phase) { _, phase in
                if case .finished = phase {
                    withAnimation(.knobs) { proxy.scrollTo("outcome", anchor: .bottom) }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CommandBar(session: session, showsOutput: $showsOutput)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .padding(.top, 6)
        }
        .navigationTitle(session.task.title)
        .navigationSubtitle(session.manifest.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                PresetsMenu(session: session)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            GlyphTile(symbol: session.task.symbol, tint: session.manifest.tint, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.task.title)
                    .font(.system(size: 22, weight: .semibold))
                Text(session.task.summary)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A grouped box of rows, like a section in System Settings.
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { content }
                .background(.background.secondary, in: .rect(cornerRadius: Metrics.cardRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.cardRadius).strokeBorder(
                        .primary.opacity(0.07), lineWidth: 1)
                }
        }
    }
}

private struct ExtraArgumentsSection: View {
    @Bindable var session: TaskSession
    @Binding var isExpanded: Bool

    private var splitError: String? {
        for problem in session.draft.problems {
            if case .extraArguments(let error) = problem {
                return switch error {
                case .unclosedQuote(let quote): "A \(quote) quote isn't closed."
                case .trailingBackslash: "The text ends with a backslash."
                }
            }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.knobs) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text("Extra arguments")
                        .font(.subheadline.weight(.semibold))
                    if !session.extraArguments.isEmpty && !isExpanded {
                        Text("in use").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.secondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .accessibilityLabel("Extra arguments")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("-metadata title=\"Our trip\"", text: $session.extraArguments)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Extra arguments")
                    Text(
                        splitError
                            ?? "Options added here go into the command as written. Quotes keep words together. Nothing runs through a shell."
                    )
                    .font(.caption)
                    .foregroundStyle(splitError == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
