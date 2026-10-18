import KnobsCore
import SwiftUI

/// The toolbar menu for a task's saved settings.
struct PresetsMenu: View {
    @Bindable var session: TaskSession

    var body: some View {
        Menu {
            Button("Reset to Defaults") { session.resetToDefaults() }
                .disabled(session.isRunning)
        } label: {
            Label("Presets", systemImage: "slider.horizontal.below.square.and.square.filled")
        }
        .help("Presets")
    }
}
