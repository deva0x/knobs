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
                        .font(.caption)
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

/// A slider for small ranges, a stepper for large ones, always with the exact number visible.
private struct IntegerControl: View {
    let label: String
    let range: ClosedRange<Int>
    @Binding var value: Int

    /// Above this many steps a slider gets too fiddly to land on an exact number.
    private static let maximumSliderSteps = 60

    var body: some View {
        HStack(spacing: 10) {
            if range.count <= Self.maximumSliderSteps {
                Slider(
                    value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: 1
                )
                .labelsHidden()
                .frame(width: 180)
                .accessibilityLabel(label)
                .accessibilityValue("\(value)")
            }
            Text("\(value)")
                .font(.body.monospacedDigit())
                .frame(minWidth: 34, alignment: .trailing)
                .accessibilityHidden(true)
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

    private var paths: [String] { session.value(of: field)?.pathList ?? [] }

    private var allowedTypes: [UTType] {
        switch field.kind {
        case .inputFile(let identifiers, _):
            let types = identifiers.compactMap { UTType($0) }
            return types.isEmpty ? [.item] : types
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
                    Image(nsImage: NSWorkspace.shared.icon(forFile: paths[0]))
                        .resizable()
                        .frame(width: 16, height: 16)
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
        }
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
    static func accepts(_ url: URL, for kind: FieldKind) -> Bool {
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        switch kind {
        case .inputFolder, .outputFolder:
            return isFolder
        case .inputFile(let identifiers, _):
            guard !isFolder else { return false }
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
