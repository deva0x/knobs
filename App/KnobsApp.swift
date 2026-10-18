import AppKit
import KnobsCore
import SwiftUI

@main
struct KnobsApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var model = AppModel(
        manifestsDirectory: Bundle.main.url(forResource: "Manifests", withExtension: nil)
            ?? Bundle.main.bundleURL.appending(path: "Contents/Resources/Manifests"),
        dataDirectory: KnobsApp.dataDirectory,
        environment: ProcessInfo.processInfo.environment
    )

    /// Where presets and history live. `-KnobsDataDirectory <path>` overrides it, so tests and development runs
    /// never touch a real user's settings.
    private static var dataDirectory: URL {
        if let override = UserDefaults.standard.string(forKey: "KnobsDataDirectory") {
            return URL(filePath: (override as NSString).expandingTildeInPath)
        }
        return URL.applicationSupportDirectory.appending(path: "Knobs")
    }

    var body: some Scene {
        // One window: every task lives in the one app model, so a second window would only mirror the first.
        // A WindowGroup also opened a new window for every file opened with Knobs.
        Window("Knobs", id: "main") {
            RootView()
                .environment(model)
                .onAppear { appDelegate.connect(model) }
                .modifier(DebugLaunchOptions())
                .frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: 1180, height: 780)
        .windowToolbarStyle(.unified)
        .commands { KnobsCommands(model: model) }
    }
}

struct KnobsCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Knobs") { AboutPanel.show() }
        }
        CommandGroup(after: .sidebar) {
            Button("Go to Task…") { model.isPaletteVisible = true }
                .keyboardShortcut("k")
        }
        // The canonical home of the task shortcuts; buttons in the window don't repeat them. While Go to Task is
        // open, Run and Open Result are off, so the task underneath can't start by accident. Cancel stays on.
        CommandMenu("Task") {
            Button("Run") {
                if let session = model.visibleSession { model.run(session) }
            }
            .keyboardShortcut("r")
            .disabled(model.isPaletteVisible || !(model.visibleSession.map(model.canRun) ?? false))

            Button("Cancel Run") { model.visibleSession?.cancel() }
                .keyboardShortcut(".")
                .disabled(!(model.visibleSession?.isRunning ?? false))

            Button("Open Result") {
                if let url = model.visibleSession?.result?.outputURL { NSWorkspace.shared.open(url) }
            }
            .keyboardShortcut("o")
            .disabled(model.isPaletteVisible || model.visibleSession?.result?.outputURL == nil)

            Divider()

            Button("Copy Command") {
                if let command = model.visibleSession?.draft.command.displayString { Pasteboard.copy(command) }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(model.visibleSession == nil)

            Button("Reset to Defaults") { model.visibleSession?.resetToDefaults() }
                .disabled(model.visibleSession?.isRunning ?? true)
        }
    }
}

/// Receives files opened with Knobs from Finder or the Dock before or after the window exists, and makes sure
/// quitting never leaves a tool running on its own.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?
    private var pendingURLs: [URL] = []

    func connect(_ model: AppModel) {
        self.model = model
        if !pendingURLs.isEmpty {
            model.openFiles(pendingURLs)
            pendingURLs = []
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let model {
            model.openFiles(urls)
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// A child process outlives its parent, so a run must be stopped before Knobs quits. Ask first, because
    /// stopping can leave an incomplete output file.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.hasRunningTasks else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "A task is still running"
        alert.informativeText = "Quitting stops it, and the file it was making may be left incomplete."
        alert.addButton(withTitle: "Stop and Quit")
        alert.addButton(withTitle: "Keep Running")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        Task {
            await model.stopAllRuns()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

/// Debug-build launch switches for screenshot reviews, which can run while the display sleeps and animations
/// can't finish: `-KnobsDisableAnimations YES` and `-KnobsAppearance light|dark`. Release builds ignore them.
private struct DebugLaunchOptions: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
            content
                .transaction { transaction in
                    if UserDefaults.standard.bool(forKey: "KnobsDisableAnimations") {
                        transaction.disablesAnimations = true
                        transaction.animation = nil
                    }
                }
                .onAppear {
                    switch UserDefaults.standard.string(forKey: "KnobsAppearance") {
                    case "light": NSApp.appearance = NSAppearance(named: .aqua)
                    case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
                    default: break
                    }
                }
        #else
            content
        #endif
    }
}
