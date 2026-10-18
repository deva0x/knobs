import KnobsCore
import SwiftUI
import UniformTypeIdentifiers

/// One labeled control in the Settings group. The control is chosen by the field's kind, never by tool.
struct FieldRow: View {
    let field: Field
    @Bindable var session: TaskSession

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(field.label)
                if let help = field.help {
                    Text(help)
                        .font(.helpText)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
                .disabled(session.isRunning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
    }

    @ViewBuilder private var control: some View {
        switch field.kind {
        case .choice(let options):
            Picker(field.label, selection: textBinding(default: options.first?.value ?? "")) {
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .labelsHidden()
            .fixedSize()
        case .integer(let range):
            IntegerControl(label: field.label, range: range, value: integerBinding(default: range.lowerBound))
        case .number(let range):
            TextField(field.label, value: numberBinding(range: range), format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)
        case .toggle:
            Toggle(field.label, isOn: toggleBinding)
                .labelsHidden()
                .toggleStyle(.switch)
        case .text(let placeholder):
            TextField(field.label, text: textBinding(default: ""), prompt: placeholder.map { Text($0) })
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
        case .secret:
            SecureField(field.label, text: textBinding(default: ""))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
        case .inputFile, .inputFolder, .outputFolder:
            PathPicker(field: field, session: session)
        }
    }

    private func textBinding(default fallback: String) -> Binding<String> {
        Binding {
            if case .text(let text)? = session.value(of: field) { return text }
            return fallback
        } set: { newValue in
            session.setValue(.text(newValue), for: field)
        }
    }

    private func integerBinding(default fallback: Int) -> Binding<Int> {
        Binding {
            if case .integer(let integer)? = session.value(of: field) { return integer }
            return fallback
        } set: { newValue in
            session.setValue(.integer(newValue), for: field)
        }
    }

    private func numberBinding(range: ClosedRange<Double>?) -> Binding<Double> {
        Binding {
            if case .number(let number)? = session.value(of: field) { return number }
            return range?.lowerBound ?? 0
        } set: { newValue in
            let clamped = range.map { min(max(newValue, $0.lowerBound), $0.upperBound) } ?? newValue
            session.setValue(.number(clamped), for: field)
        }
    }

    private var toggleBinding: Binding<Bool> {
        Binding {
            if case .toggle(let isOn)? = session.value(of: field) { return isOn }
            return false
        } set: { newValue in
            session.setValue(.toggle(newValue), for: field)
        }
    }
}

/// A slider for small ranges and a typed number for large ones, always with a stepper and the exact value.
private struct IntegerControl: View {
    let label: String
    let range: ClosedRange<Int>
    @Binding var value: Int

    /// Up to this many steps a slider can still land on every value; beyond it, typing the number is faster.
    private static let maximumSliderSteps = 101

    /// Computed without `range.count`, which overflows for a range as wide as `Int.min...Int.max`.
    private var suitsASlider: Bool {
        let (span, overflow) = range.upperBound.subtractingReportingOverflow(range.lowerBound)
        return !overflow && span < Self.maximumSliderSteps
    }

    var body: some View {
        HStack(spacing: 10) {
            if suitsASlider {
                Slider(
                    value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: 1
                )
                .labelsHidden()
                .frame(width: 180)
                .accessibilityLabel(label)
                .accessibilityValue("\(value)")
                Text("\(value)")
                    .font(.body.monospacedDigit())
                    .frame(minWidth: 34, alignment: .trailing)
                    .accessibilityHidden(true)
            } else {
                TextField(
                    label,
                    value: Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) }),
                    format: .number.grouping(.never)
                )
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospacedDigit())
                .frame(width: 90)
                .help("\(range.lowerBound) to \(range.upperBound)")
            }
            Stepper(label, value: $value, in: range)
                .labelsHidden()
        }
    }
}

/// A compact file or folder chooser for fields other than the big drop zone.
private struct PathPicker: View {
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
        HStack(spacing: 8) {
            if paths.isEmpty {
                Text(field.isRequired ? "Required" : "None")
                    .foregroundStyle(.tertiary)
            } else {
                Label {
                    Text(paths.count == 1 ? URL(filePath: paths[0]).lastPathComponent : "\(paths.count) items")
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                }
                .help(paths.joined(separator: "\n"))
                .frame(maxWidth: 200, alignment: .trailing)
                Button {
                    session.setValue(nil, for: field)
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear \(field.label)")
            }
            Button("Choose…") { isImporting = true }
                .accessibilityLabel("Choose \(field.label.lowercased())")
        }
        .task(id: paths.first) { icon = paths.first.map { NSWorkspace.shared.icon(forFile: $0) } }
        .fileImporter(
            isPresented: $isImporting, allowedContentTypes: allowedTypes, allowsMultipleSelection: allowsMultiple
        ) {
            result in
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
