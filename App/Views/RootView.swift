import KnobsCore
import KnobsSession
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(Toolbox.self) private var toolbox

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
                            if taskID == HelpTaskBuilder.taskID {
                                AllOptionsView(manifest: tool)
                            } else if let task = tool.task(withID: taskID) {
                                TaskWorkspaceView(session: toolbox.session(for: task, of: tool))
                            }
                        }
                }
                // A fresh stack per tool, so switching tools never animates one tool's pages over another's.
                .id(tool.id)
            } else {
                ContentUnavailableView("Choose a tool", systemImage: "slider.horizontal.3")
            }
        }
        .overlay {
            if model.isPaletteVisible {
                CommandPaletteView()
                    .knobsTransition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.knobs, value: model.isPaletteVisible)
        .sheet(item: Binding(get: { model.pendingFiles }, set: { model.pendingFiles = $0 })) { pending in
            OpenWithSheet(pending: pending)
        }
        .alert(
            "Settings problem",
            isPresented: Binding(
                get: { toolbox.libraryProblem != nil }, set: { if !$0 { toolbox.libraryProblem = nil } })
        ) {
            Button("OK") { toolbox.libraryProblem = nil }
        } message: {
            Text(toolbox.libraryProblem ?? "")
        }
    }
}
