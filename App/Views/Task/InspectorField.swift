import KnobsCore
import SwiftUI
import UniformTypeIdentifiers

/// One field as a row of the inspector's grouped form. The control is chosen by the field's kind, never by tool:
/// label and help on the leading side, the control trailing, and sliders on their own full-width line.
struct InspectorField: View {
    let field: Field
    @Bindable var session: TaskSession

    var body: some View {
        control
            .disabled(session.isRunning)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(field.label)
            if let help = field.help {
                Text(help)
                    .font(.helpText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var control: some View {
        switch field.kind {
        case .choice(let options):
            Picker(selection: session.textBinding(for: field, default: options.first?.value ?? "")) {
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            } label: {
                label
            }
            .pickerStyle(.menu)
        case .integer(let range):
            IntegerControl(
                range: range, value: session.integerBinding(for: field, default: range.lowerBound)
            ) { label }
        case .number(let range):
            LabeledContent {
                TextField(field.label, value: session.numberBinding(for: field, range: range), format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
            } label: {
                label
            }
        case .toggle:
            Toggle(isOn: session.toggleBinding(for: field)) { label }
                .toggleStyle(.switch)
        case .text(let placeholder):
            TextField(text: session.textBinding(for: field, default: ""), prompt: placeholder.map { Text($0) }) {
                label
            }
        case .secret:
            SecureField(text: session.textBinding(for: field, default: "")) { label }
        case .inputFile, .inputFolder, .outputFolder:
            LabeledContent {
                PathPicker(field: field, session: session)
            } label: {
                label
            }
        }
    }
}

extension TaskSession {
    func textBinding(for field: Field, default fallback: String) -> Binding<String> {
        Binding {
            if case .text(let text)? = self.value(of: field) { return text }
            return fallback
        } set: { newValue in
            self.setValue(.text(newValue), for: field)
        }
    }

    func integerBinding(for field: Field, default fallback: Int) -> Binding<Int> {
        Binding {
            if case .integer(let integer)? = self.value(of: field) { return integer }
            return fallback
        } set: { newValue in
            self.setValue(.integer(newValue), for: field)
        }
    }

    func numberBinding(for field: Field, range: ClosedRange<Double>?) -> Binding<Double> {
        Binding {
            if case .number(let number)? = self.value(of: field) { return number }
            return range?.lowerBound ?? 0
        } set: { newValue in
            let clamped = range.map { min(max(newValue, $0.lowerBound), $0.upperBound) } ?? newValue
            self.setValue(.number(clamped), for: field)
        }
    }

    func toggleBinding(for field: Field) -> Binding<Bool> {
        Binding {
            if case .toggle(let isOn)? = self.value(of: field) { return isOn }
            return false
        } set: { newValue in
            self.setValue(.toggle(newValue), for: field)
        }
    }
}

/// A full-width slider under its label for small ranges, a typed number for large ones; always the exact value
/// and a stepper.
private struct IntegerControl<Label: View>: View {
    let range: ClosedRange<Int>
    @Binding var value: Int
    @ViewBuilder let label: Label

    /// Up to this many steps a slider can still land on every value; beyond it, typing the number is faster.
    private static var maximumSliderSteps: Int { 101 }

    /// Computed without `range.count`, which overflows for a range as wide as `Int.min...Int.max`.
    private var suitsASlider: Bool {
        let (span, overflow) = range.upperBound.subtractingReportingOverflow(range.lowerBound)
        return !overflow && span < Self.maximumSliderSteps
    }

    var body: some View {
        if suitsASlider {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    label
                    Spacer(minLength: 12)
                    Text("\(value)")
                        .font(.body.monospacedDigit().weight(.medium))
                        .accessibilityHidden(true)
                    Stepper("", value: $value, in: range)
                        .labelsHidden()
                }
                Slider(
                    value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                    in: Double(range.lowerBound)...Double(range.upperBound), step: 1
                ) {
                    label
                }
                .labelsHidden()
                .accessibilityValue("\(value)")
            }
        } else {
            LabeledContent {
                HStack(spacing: 6) {
                    TextField(
                        "",
                        value: Binding(
                            get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) }),
                        format: .number.grouping(.never)
                    )
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .font(.body.monospacedDigit())
                    .frame(width: 80)
                    .help("\(range.lowerBound) to \(range.upperBound)")
                    Stepper("", value: $value, in: range)
                        .labelsHidden()
                }
            } label: {
                label
            }
        }
    }
}

/// A compact file or folder chooser: the chosen item's icon and name (click to change), or Choose.
struct PathPicker: View {
    let field: Field
    @Bindable var session: TaskSession
    @State private var isImporting = false
    @State private var icon: NSImage?

    /// Paths as shown: a default such as `~/Downloads` is expanded, the way the command builder expands it.
    private var paths: [String] {
        (session.value(of: field)?.pathList ?? []).map { ($0 as NSString).expandingTildeInPath }
    }

    private var allowedTypes: [UTType] {
        switch field.kind {
        case .inputFile(let identifiers, _):
            let types = identifiers.compactMap { UTType($0) }
            return types.isEmpty ? [.item, .folder] : types
        default:
            return [.folder]
        }
    }

    private var allowsMultiple: Bool {
        if case .inputFile(_, true) = field.kind { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 6) {
            if paths.isEmpty {
                Button("Choose…") { isImporting = true }
                    .accessibilityLabel("Choose \(field.label.lowercased())")
            } else {
                Button {
                    isImporting = true
                } label: {
                    HStack(spacing: 5) {
                        if let icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                        }
                        Text(paths.count == 1 ? URL(filePath: paths[0]).lastPathComponent : "\(paths.count) items")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: 150)
                }
                .help(paths.joined(separator: "\n") + "\nClick to choose another")
                .accessibilityLabel(
                    "\(field.label): \(paths.map { URL(filePath: $0).lastPathComponent }.joined(separator: ", ")). Choose another"
                )
                if !field.isRequired || field.defaultValue != nil {
                    Button {
                        session.setValue(nil, for: field)
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help(field.defaultValue == nil ? "Clear" : "Back to the default")
                    .accessibilityLabel("Clear \(field.label.lowercased())")
                }
            }
        }
        .task(id: paths.first) { icon = paths.first.map { NSWorkspace.shared.icon(forFile: $0) } }
        .fileImporter(
            isPresented: $isImporting, allowedContentTypes: allowedTypes, allowsMultipleSelection: allowsMultiple
        ) { result in
            if case .success(let urls) = result, !urls.isEmpty {
                session.setValue(.paths(urls.map(\.path)), for: field)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let accepted = urls.filter { FileTypeCheck.accepts($0, for: field.kind) }
            guard !accepted.isEmpty else { return false }
            session.setValue(.paths(allowsMultiple ? accepted.map(\.path) : [accepted[0].path]), for: field)
            return true
        }
    }
}

/// Decides whether a dropped file fits a field, using the field's content types.
enum FileTypeCheck {
    /// Whether a field names the file types it takes, rather than taking anything. Type names that macOS doesn't
    /// know don't count, matching `accepts`. Folder fields don't count either, so an opened folder is offered to
    /// both folder tasks (rsync) and any-file tasks (making an archive).
    static func namesSpecificTypes(_ kind: FieldKind) -> Bool {
        guard case .inputFile(let identifiers, _) = kind else { return false }
        return identifiers.contains { UTType($0) != nil }
    }

    static func accepts(_ url: URL, for kind: FieldKind) -> Bool {
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        switch kind {
        case .inputFolder, .outputFolder:
            return isFolder
        case .inputFile(let identifiers, _):
            // No content types means anything, folders included (for archives). Otherwise a folder only fits
            // when one of the types is a folder type.
            let allowed = identifiers.compactMap { UTType($0) }
            guard !allowed.isEmpty else { return true }
            guard
                let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
                    ?? UTType(filenameExtension: url.pathExtension)
            else { return false }
            return allowed.contains { type.conforms(to: $0) }
        default:
            return false
        }
    }
}
