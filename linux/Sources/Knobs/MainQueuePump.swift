import Adwaita
import Foundation
import Observation
import Synchronization

/// Lets Swift concurrency's main-actor work run inside GTK's main loop.
///
/// A run's events reach `TaskSession` as jobs on the main dispatch queue. On macOS the app's run loop drains that
/// queue; on Linux GLib's loop owns the main thread and never does, so the jobs would wait forever. While there is
/// work to deliver, this lets Foundation's main run loop take whatever is pending, on each tick of a GLib timeout.
enum MainQueuePump {
    /// Short enough that progress and output feel live; each tick only takes jobs already waiting.
    static let interval = Duration.milliseconds(50)
    /// After a run ends, its result's sizes are measured in the background and arrive a moment later.
    static let settleTicks = 40

    /// Pumps until `isActive` turns false and the settle time has passed. `redraw` is called after a tick that
    /// changed anything `observe` reads, since redrawing the whole window on every tick slows a long run down.
    static func pump(
        while isActive: @escaping () -> Bool, observing observe: @escaping () -> Void,
        redraw: @escaping () -> Void
    ) {
        let changes = ChangeFlag()
        func watch() {
            withObservationTracking(observe, onChange: { changes.raise() })
        }
        watch()
        var ticksSinceInactive = 0
        Idle(delay: interval) {
            // False only means nothing was waiting, which is fine.
            _ = RunLoop.main.run(mode: .default, before: Date())
            if changes.lower() {
                // Observation reports one change per watch, so watch again before the next tick.
                watch()
                redraw()
            }
            if isActive() {
                ticksSinceInactive = 0
                return true
            }
            ticksSinceInactive += 1
            return ticksSinceInactive < settleTicks
        }
    }
}

/// Set by Observation, from whichever thread made the change, and cleared by the pump.
nonisolated private final class ChangeFlag: Sendable {
    private let isRaised = Mutex(false)

    func raise() {
        isRaised.withLock { $0 = true }
    }

    /// Clears the flag and returns whether it was set.
    func lower() -> Bool {
        isRaised.withLock { isRaised in
            defer { isRaised = false }
            return isRaised
        }
    }
}
