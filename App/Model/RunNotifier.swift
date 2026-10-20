import AppKit
import KnobsCore
import KnobsSession
import OSLog
import UserNotifications

/// Tells the user about runs while they're in another app: a notification when a run ends, and a progress bar on
/// the Dock icon while one reports progress. macOS asks for permission to notify the first time a run ends in the
/// background, which is the first moment the notification is useful.
@MainActor
final class RunNotifier: NSObject, UNUserNotificationCenterDelegate {
    private weak var model: AppModel?
    private let center = UNUserNotificationCenter.current()
    private let dockView = DockProgressView()
    /// The progress last drawn, in whole percent, so the Dock is redrawn only when the bar visibly moves.
    private var drawnPercent: Int?

    private nonisolated static let toolIDKey = "toolID"
    private static let log = Logger(subsystem: "io.github.deva0x.Knobs", category: "notifications")
    private nonisolated static let taskIDKey = "taskID"

    init(model: AppModel) {
        self.model = model
        super.init()
        center.delegate = self
        model.toolbox.onRunFinished = { [weak self] session, outcome in self?.runFinished(session, outcome) }
        watchProgress()
    }

    // MARK: Notifications

    private func runFinished(_ session: TaskSession, _ outcome: RunOutcome) {
        updateDock()
        guard !NSApp.isActive, outcome != .cancelled else { return }
        let content = UNMutableNotificationContent()
        content.title = session.task.title
        content.body = Self.message(for: session, outcome)
        content.userInfo = [Self.toolIDKey: session.manifest.id, Self.taskIDKey: session.task.id]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        Task {
            let settings = await center.notificationSettings()
            do {
                switch settings.authorizationStatus {
                case .notDetermined:
                    guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                        Self.log.info("Notifications not allowed; the run's end isn't announced")
                        return
                    }
                case .authorized, .provisional:
                    break
                default:
                    Self.log.info("Notifications are turned off for Knobs; the run's end isn't announced")
                    return
                }
                try await center.add(request)
                Self.log.info("Announced the end of a run of \(session.task.title, privacy: .public)")
            } catch {
                Self.log.error("Couldn't announce the end of a run: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func message(for session: TaskSession, _ outcome: RunOutcome) -> String {
        switch outcome {
        case .succeeded:
            if let name = session.result?.outputURL?.lastPathComponent { return "Done: \(name)" }
            return "Done."
        case .failed:
            return "\(session.manifest.name) stopped with an error. Open Knobs to see what it said."
        case .couldNotStart(let reason):
            return reason
        case .cancelled:
            return "Stopped."
        }
    }

    /// Clicking a notification brings Knobs forward on the task that finished.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let toolID = info[Self.toolIDKey] as? String, let taskID = info[Self.taskIDKey] as? String else { return }
        await MainActor.run {
            NSApp.activate()
            model?.open(toolID: toolID, taskID: taskID)
        }
    }

    // MARK: Dock

    /// Redraws the Dock whenever a running task's progress changes, for as long as the app runs.
    private func watchProgress() {
        withObservationTracking {
            updateDock()
        } onChange: { [weak self] in
            Task { @MainActor in self?.watchProgress() }
        }
    }

    /// The mean progress of the running tasks that report it, or no bar when none do.
    private func updateDock() {
        let fractions = (model?.toolbox.runningSessions ?? []).compactMap(\.progress)
        let percent = fractions.isEmpty ? nil : Int(fractions.reduce(0, +) / Double(fractions.count) * 100)
        guard percent != drawnPercent else { return }
        drawnPercent = percent
        let tile = NSApp.dockTile
        if let percent {
            dockView.fraction = Double(percent) / 100
            tile.contentView = dockView
        } else {
            tile.contentView = nil
        }
        tile.display()
    }
}

/// The app icon with a progress bar along its bottom, drawn into the Dock tile.
private final class DockProgressView: NSView {
    var fraction = 0.0

    override func draw(_ dirtyRect: NSRect) {
        NSApp.applicationIconImage?.draw(in: bounds)
        let track = NSRect(
            x: bounds.width * 0.1, y: bounds.height * 0.08, width: bounds.width * 0.8, height: bounds.height * 0.1)
        let radius = track.height / 2
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()
        var filled = track.insetBy(dx: 2, dy: 2)
        filled.size.width = max(filled.height, filled.width * fraction)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: filled, xRadius: filled.height / 2, yRadius: filled.height / 2).fill()
    }
}
