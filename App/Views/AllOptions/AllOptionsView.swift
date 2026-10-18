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

    private var activeFieldIDs: Set<String> {
        Set(generated.options.map(\.fieldID).filter { session.value(of: field($0))?.isSet == true })
    }

    private var visibleOptions: [(fieldID: String, option: HelpOption)] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        let active = activeFieldIDs
        return generated.options.filter { entry in
            if showsOnlyActive && !active.contains(entry.fieldID) { return false }
            guard !words.isEmpty else { return true }
            let haystack = (entry.option.flags.joined(separator: " ") + " " + entry.option.summary).lowercased()
            return words.allSatisfy(haystack.contains)
        }
    }

    private func field(_ id: String) -> Field {
        session.task.field(withID: id)!
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search \(generated.options.count) options", text: $query)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.background.secondary, in: .rect(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.08)) }
                    Toggle("Only switched on (\(activeFieldIDs.count))", isOn: $showsOnlyActive)
                        .toggleStyle(.checkbox)
                        .fixedSize()
                }

                let options = visibleOptions
                if options.isEmpty {
                    Text(showsOnlyActive ? "No options are switched on yet." : "No option matches “\(query)”.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(24)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(options.enumerated()), id: \.element.fieldID) { index, entry in
                            if index > 0 { Divider().padding(.leading, 16) }
                            OptionRow(option: entry.option, field: field(entry.fieldID), session: session)
                        }
                    }
                    .background(.background.secondary, in: .rect(cornerRadius: Metrics.cardRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: Metrics.cardRadius).strokeBorder(.primary.opacity(0.07))
                    }
                }

                SettingsGroup(title: "Files") {
                    FieldRow(field: field(HelpTaskBuilder.filesFieldID), session: session)
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
                        .font(.caption.weight(.medium))
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
                            .font(.system(.caption, design: .monospaced))
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
            } else {
                Toggle(option.preferredFlag, isOn: toggleBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .disabled(session.isRunning)
        .accessibilityElement(children: .combine)
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
