import KnobsCore
import SwiftUI

/// Every option a tool lists in its help, searchable, built into the same live command as any task.
struct AllOptionsView: View {
    @Environment(AppModel.self) private var model
    let manifest: ToolManifest

    var body: some View {
        Group {
            if !model.isInstalled(manifest) {
                ScrollView {
                    NotInstalledPanel(manifest: manifest)
                        .padding(32)
                        .frame(maxWidth: Metrics.contentMaxWidth)
                        .frame(maxWidth: .infinity)
                }
            } else {
                switch model.allOptions[manifest.id] {
                case .ready(let generated):
                    AllOptionsContent(
                        manifest: manifest, generated: generated,
                        session: model.session(for: generated.task, of: manifest))
                case .unavailable:
                    ContentUnavailableView {
                        Label("No options found", systemImage: "questionmark.text.page")
                    } description: {
                        Text(
                            "\(manifest.name) didn't print a list of options Knobs could read. You can still type options into Extra arguments on any task."
                        )
                    } actions: {
                        Button("Try Again") { Task { await model.loadAllOptions(for: manifest) } }
                    }
                case .loading, nil:
                    ProgressView("Reading \(manifest.name)'s options…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle("All options")
        .navigationSubtitle(manifest.name)
        .task(id: model.isInstalled(manifest)) { await model.loadAllOptions(for: manifest) }
    }
}

private struct AllOptionsContent: View {
    let manifest: ToolManifest
    let generated: HelpTaskBuilder.GeneratedTask
    @Bindable var session: TaskSession
    @State private var query = ""
    @State private var showsOnlyActive = false
    @State private var showsExtraArguments = true
    @State private var showsOutput = false
    /// Built once: big tools list hundreds of options, and the list is filtered on every keystroke.
    private let fieldsByID: [String: Field]

    init(manifest: ToolManifest, generated: HelpTaskBuilder.GeneratedTask, session: TaskSession) {
        self.manifest = manifest
        self.generated = generated
        self.session = session
        fieldsByID = Dictionary(session.task.fields.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Options default to off and empty, so the switched-on ones are exactly the values the user set.
    private var activeFieldIDs: Set<String> {
        Set(session.values.filter { $0.value.isSet }.keys)
    }

    private func visibleOptions(active: Set<String>) -> [(fieldID: String, option: HelpOption)] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        return generated.options.filter { entry in
            if showsOnlyActive && !active.contains(entry.fieldID) { return false }
            guard !words.isEmpty else { return true }
            let haystack = (entry.option.flags.joined(separator: " ") + " " + entry.option.summary).lowercased()
            return words.allSatisfy(haystack.contains)
        }
    }

    var body: some View {
        let active = activeFieldIDs
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                        TextField("Search \(generated.options.count) options", text: $query)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.background.secondary, in: .rect(cornerRadius: Metrics.wellRadius))
                    .overlay { RoundedRectangle(cornerRadius: Metrics.wellRadius).strokeBorder(Color.hairline) }
                    Toggle("Only switched on (\(active.count))", isOn: $showsOnlyActive)
                        .toggleStyle(.checkbox)
                        .fixedSize()
                }

                let options = visibleOptions(active: active)
                if options.isEmpty {
                    Text(showsOnlyActive ? "No options are switched on yet." : "No option matches “\(query)”.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(24)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(options.enumerated()), id: \.element.fieldID) { index, entry in
                            if index > 0 { Divider().padding(.leading, 16) }
                            if let field = fieldsByID[entry.fieldID] {
                                OptionRow(option: entry.option, field: field, session: session)
                            }
                        }
                    }
                    .background(.background.secondary, in: .rect(cornerRadius: Metrics.cardRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: Metrics.cardRadius).strokeBorder(Color.hairline)
                    }
                }

                if let files = fieldsByID[HelpTaskBuilder.filesFieldID] {
                    SettingsGroup(title: "Files") {
                        FieldRow(field: files, session: session)
                    }
                }
                ExtraArgumentsSection(session: session, isExpanded: $showsExtraArguments)
                RunOutcomeView(session: session, showsOutput: $showsOutput)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: Metrics.contentMaxWidth)
            .frame(maxWidth: .infinity)
            .tint(manifest.tint.color)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CommandBar(session: session, showsOutput: $showsOutput)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .padding(.top, 6)
        }
        .onChange(of: session.phase) { _, phase in
            if case .finished = phase { showsOutput = true }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            GlyphTile(symbol: "list.bullet.rectangle", tint: manifest.tint, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("All options").font(.system(size: 22, weight: .semibold))
                    Text("Best effort")
                        .font(Font.helpText.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.primary.opacity(0.07), in: .capsule)
                        .help("Read from \(manifest.name)'s own help text, so some options may be missing or odd.")
                }
                Text(
                    "Everything \(manifest.name) lists in its help. Switch on what you need; the command updates as you go."
                )
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OptionRow: View {
    let option: HelpOption
    let field: Field
    @Bindable var session: TaskSession

    private var otherSpellings: String {
        option.flags.filter { $0 != option.preferredFlag }.joined(separator: "  ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(option.preferredFlag)
                        .font(.system(.body, design: .monospaced).weight(.medium))
                    if !otherSpellings.isEmpty {
                        Text(otherSpellings)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                if !option.summary.isEmpty {
                    Text(option.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if option.valueName != nil {
                TextField(option.preferredFlag, text: textBinding, prompt: Text(option.valueName ?? ""))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 200)
                    .accessibilityHint(option.summary)
            } else {
                Toggle(option.preferredFlag, isOn: toggleBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityHint(option.summary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .disabled(session.isRunning)
        // The control stays its own element, so VoiceOver can switch it on or type into it; the flag and its
        // description reach VoiceOver as the control's label and hint, so the text beside it is skipped.
        .accessibilityElement(children: .contain)
    }

    private var textBinding: Binding<String> {
        Binding {
            if case .text(let text)? = session.value(of: field) { return text }
            return ""
        } set: {
            session.setValue($0.isEmpty ? nil : .text($0), for: field)
        }
    }

    private var toggleBinding: Binding<Bool> {
        Binding {
            if case .toggle(let isOn)? = session.value(of: field) { return isOn }
            return false
        } set: {
            session.setValue($0 ? .toggle(true) : nil, for: field)
        }
    }
}
