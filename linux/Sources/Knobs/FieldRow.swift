import Adwaita
import CAdw
import Foundation
import KnobsCore
import KnobsSession

/// One manifest field as an Adwaita row. Every edit goes to the shared session, then `changed` redraws the page.
struct FieldRow: View {
    let field: Field
    let session: TaskSession
    let changed: () -> Void

    var view: Body {
        switch field.kind {
        case .choice(let options):
            ComboRow(
                field.label,
                selection: Binding {
                    textValue
                } set: {
                    set(.text($0))
                },
                values: options, id: \.value, description: \.label
            )
            .subtitle(field.help ?? "")
            .useMarkup(false)
        case .integer(let range):
            SpinRow(
                field.label,
                value: Binding {
                    integerValue(in: range)
                } set: {
                    set(.integer($0))
                },
                min: range.lowerBound, max: range.upperBound
            )
            .subtitle(field.help ?? "")
            .useMarkup(false)
        case .number(let range):
            SpinRow(
                field.label,
                value: Binding {
                    numberValue
                } set: {
                    set(.number($0))
                },
                min: range?.lowerBound ?? -Self.unboundedNumberMaximum,
                max: range?.upperBound ?? Self.unboundedNumberMaximum
            )
            .step(Self.numberStep)
            .subtitle(field.help ?? "")
            .useMarkup(false)
        case .toggle:
            SwitchRow(
                field.label,
                isOn: Binding {
                    toggleValue
                } set: {
                    set(.toggle($0))
                }
            )
            .subtitle(field.help ?? "")
            .useMarkup(false)
        case .text:
            EntryRow(
                field.label,
                text: Binding {
                    textValue
                } set: {
                    set($0.isEmpty ? nil : .text($0))
                }
            )
            .useMarkup(false)
            .tooltip(helpMarkup)
        case .secret:
            let text = Binding {
                textValue
            } set: {
                set($0.isEmpty ? nil : .text($0))
            }
            EntryRow(field.label, text: text)
                .useMarkup(false)
                .secure(text: text)
                .tooltip(helpMarkup)
        case .inputFile, .inputFolder, .outputFolder:
            PathRow(field: field, session: session, changed: changed)
        }
    }

    /// A number field without a range still needs limits for its spin button; it goes this far either way.
    private static let unboundedNumberMaximum = 1_000_000.0
    private static let numberStep = 0.1

    /// Entry rows have no subtitle, so their help is a tooltip. GTK reads tooltips as Pango markup, and help
    /// text comes from the tool (All options), so it is escaped rather than trusted.
    private var helpMarkup: String {
        guard let escaped = g_markup_escape_text(field.help ?? "", -1) else { return "" }
        defer { g_free(escaped) }
        return String(cString: escaped)
    }

    private var textValue: String {
        if case .text(let text)? = session.value(of: field) { return text }
        return ""
    }

    private func integerValue(in range: ClosedRange<Int>) -> Int {
        if case .integer(let value)? = session.value(of: field) { return value }
        return range.lowerBound
    }

    private var numberValue: Double {
        if case .number(let value)? = session.value(of: field) { return value }
        return 0
    }

    private var toggleValue: Bool {
        if case .toggle(let isOn)? = session.value(of: field) { return isOn }
        return false
    }

    private func set(_ value: FieldValue?) {
        session.setValue(value, for: field)
        changed()
    }
}

/// A file or folder field: what's chosen, and Choose to pick it with the system's file dialog.
private struct PathRow: View {
    let field: Field
    let session: TaskSession
    let changed: () -> Void

    var view: Body {
        let chosen = session.value(of: field)?.pathList ?? []
        ActionRow(field.label)
            .subtitle(chosen.isEmpty ? (field.help ?? emptyText) : chosen.map(Self.displayPath).joined(separator: ", "))
            .useMarkup(false)
            .suffix {
                HStack {
                    if allowsMultiple && !chosen.isEmpty {
                        Button(icon: .default(icon: .editClear)) { clear() }
                            .flat()
                            .valign(.center)
                            .tooltip("Remove all")
                    }
                    Button(allowsMultiple && !chosen.isEmpty ? "Add…" : "Choose…") { choose() }
                        .valign(.center)
                }
            }
    }

    private func choose() {
        FileChooser.choose(
            isFolder ? .folder : .file, title: "Choose \(field.label.lowercased())",
            filters: FileTypeFilter.filters(for: field.kind), chosen: pick)
    }

    private var isFolder: Bool {
        field.kind == .inputFolder || field.kind == .outputFolder
    }

    /// The file dialog takes one file at a time, so a field that takes several adds each pick to the list.
    private var allowsMultiple: Bool {
        if case .inputFile(_, true) = field.kind { return true }
        return false
    }

    private var emptyText: String {
        isFolder ? "No folder chosen" : "No file chosen"
    }

    private func pick(_ url: URL) {
        let existing = allowsMultiple ? session.value(of: field)?.pathList ?? [] : []
        guard !existing.contains(url.path) else { return }
        session.setValue(.paths(existing + [url.path]), for: field)
        changed()
    }

    private func clear() {
        session.setValue(nil, for: field)
        changed()
    }

    /// Paths under the home folder read as "~/…", as in the Mac app.
    private static func displayPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
