import KnobsCore
import SwiftUI

/// The toolbar menu for a task's saved settings: apply, save, delete, reset.
struct PresetsMenu: View {
    @Environment(AppModel.self) private var model
    @Bindable var session: TaskSession
    @State private var isNaming = false
    @State private var newName = ""

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
    }
}
