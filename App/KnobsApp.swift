import KnobsCore
import SwiftUI

@main
struct KnobsApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Knobs reads manifest format version \(ToolManifest.supportedSchemaVersion)")
                .padding()
                .frame(minWidth: 480, minHeight: 320)
        }
    }
}
