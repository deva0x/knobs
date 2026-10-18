import AppKit
import KnobsCore
import SwiftUI

@main
struct KnobsApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var model = AppModel(
        manifestsDirectory: Bundle.main.url(forResource: "Manifests", withExtension: nil)
            ?? Bundle.main.bundleURL.appending(path: "Contents/Resources/Manifests"),
        environment: ProcessInfo.processInfo.environment
    )

    var body: some Scene {
        WindowGroup("Knobs") {
            RootView()
                .environment(model)
                .onAppear { appDelegate.connect(model.openFiles) }
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
        CommandGroup(after: .sidebar) {
            Button("Go to Task…") { model.isPaletteVisible = true }
                .keyboardShortcut("k")
        }
        CommandMenu("Task") {
            Button("Run") {
                if let session = model.visibleSession { model.run(session) }
            }
            .keyboardShortcut("r")
            .disabled(!(model.visibleSession?.draft.isRunnable ?? false) || (model.visibleSession?.isRunning ?? true))

            Button("Cancel Run") { model.visibleSession?.cancel() }
                .keyboardShortcut(".")
                .disabled(!(model.visibleSession?.isRunning ?? false))

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

/// Receives files opened with Knobs from Finder or the Dock before or after the window exists.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var openHandler: (([URL]) -> Void)?
    private var pendingURLs: [URL] = []

    func connect(_ handler: @escaping ([URL]) -> Void) {
        openHandler = handler
        if !pendingURLs.isEmpty {
            handler(pendingURLs)
            pendingURLs = []
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let openHandler {
            openHandler(urls)
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
