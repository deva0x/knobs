import KnobsCore
import SwiftUI

/// The toolbar menu for a task's saved settings: apply, save, rename, delete, reset.
struct PresetsMenu: View {
    @Environment(AppModel.self) private var model
    @Bindable var session: TaskSession
    @State private var isNaming = false
    @State private var newName = ""
    @State private var presetBeingRenamed: Preset?
    @State private var renamedName = ""

    /// A rename is allowed when the name isn't blank and no other preset of this task already has it.
    private func isAvailable(_ name: String, besides preset: Preset, in presets: [Preset]) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && !presets.contains { $0.id != preset.id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    var body: some View {
        let presets = model.presets(for: session)
        Menu {
            if presets.isEmpty {
                Text("No presets yet")
            } else {
                Section("Apply") {
                    ForEach(presets) { preset in
                        Button(preset.name) { session.applyPreset(preset.values) }
                    }
                }
            }
            Divider()
            Button("Save Current Settings…") {
                newName = ""
                isNaming = true
            }
            if !presets.isEmpty {
                Menu("Rename") {
                    ForEach(presets) { preset in
                        Button(preset.name) {
                            renamedName = preset.name
                            presetBeingRenamed = preset
                        }
                    }
                }
                Menu("Delete") {
                    ForEach(presets) { preset in
                        Button(preset.name, role: .destructive) { model.deletePreset(preset, of: session) }
                    }
                }
            }
            Divider()
            Button("Reset to Defaults") { session.resetToDefaults() }
        } label: {
            Label("Presets", systemImage: "slider.horizontal.below.square.and.square.filled")
        }
        .disabled(session.isRunning)
        .help("Presets")
        .alert("Save as a preset", isPresented: $isNaming) {
            TextField("Name", text: $newName, prompt: Text("For WhatsApp"))
            Button("Save") { model.savePreset(named: newName, from: session) }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves this task's settings, except the file and any password. Using an existing name updates it.")
        }
        .alert(
            "Rename preset",
            isPresented: Binding(
                get: { presetBeingRenamed != nil }, set: { if !$0 { presetBeingRenamed = nil } }),
            presenting: presetBeingRenamed
        ) { preset in
            TextField("Name", text: $renamedName)
            Button("Rename") { model.renamePreset(preset, to: renamedName, of: session) }
                .disabled(!isAvailable(renamedName, besides: preset, in: presets))
            Button("Cancel", role: .cancel) {}
        } message: { preset in
            Text("A new name for “\(preset.name)”. It can't be the name of another preset of this task.")
        }
    }
}
