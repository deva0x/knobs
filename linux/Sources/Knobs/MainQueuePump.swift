import Adwaita
import Foundation

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

    /// Pumps, and calls `tick` after each pump so the page can redraw, until `isActive` turns false and the
    /// settle time has passed.
    static func pump(while isActive: @escaping () -> Bool, tick: @escaping () -> Void) {
        var ticksSinceInactive = 0
        Idle(delay: interval) {
            // False only means nothing was waiting, which is fine.
            _ = RunLoop.main.run(mode: .default, before: Date())
            tick()
            if isActive() {
                ticksSinceInactive = 0
                return true
            }
            ticksSinceInactive += 1
            return ticksSinceInactive < settleTicks
        }
    }
}
