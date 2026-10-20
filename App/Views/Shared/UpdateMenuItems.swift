import Combine
import Sparkle
import SwiftUI

/// The Knobs menu's update items (DEC-024): Check for Updates…, and whether Sparkle looks once a day on its own.
/// Sparkle asks that question on the second launch; the toggle is where someone changes their answer later.
struct UpdateMenuItems: View {
    @ObservedObject private var state: UpdaterState
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        state = UpdaterState(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!state.canCheckForUpdates)
        Toggle(
            "Check for Updates Automatically",
            isOn: Binding(
                get: { state.checksAutomatically },
                set: { updater.automaticallyChecksForUpdates = $0 }
            )
        )
    }
}

/// Sparkle publishes its updater's state through key-value observing; this republishes it to SwiftUI, as Sparkle's
/// own SwiftUI example does.
@MainActor
private final class UpdaterState: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var checksAutomatically = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
        updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$checksAutomatically)
    }
}
