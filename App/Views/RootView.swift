import KnobsCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 236, max: 300)
        } detail: {
            if let tool = model.selectedTool {
                NavigationStack(path: $model.taskPath) {
                    ToolHomeView(manifest: tool)
                        .navigationDestination(for: String.self) { taskID in
                            if let task = tool.task(withID: taskID) {
                                TaskWorkspaceView(session: model.session(for: task, of: tool))
                            }
                        }
                }
                .id(tool.id)
            } else {
                ContentUnavailableView("Choose a tool", systemImage: "slider.horizontal.3")
            }
        }
        .overlay {
            if model.isPaletteVisible {
                CommandPaletteView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.knobs, value: model.isPaletteVisible)
    }
}
