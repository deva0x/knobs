import KnobsCore
import SwiftUI

/// What happened: the live output while running (when shown), then a result, failure or cancelled card.
struct RunOutcomeView: View {
    @Bindable var session: TaskSession
    @Binding var showsOutput: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch session.phase {
            case .idle:
                EmptyView()
            case .running:
                if showsOutput { OutputConsole(log: session.log) }
            case .finished(.succeeded):
                if let result = session.result {
                    if session.producesResult {
                        ResultCard(session: session, result: result, showsOutput: $showsOutput)
                    } else {
                        Label(
                            "Done in \(Duration.seconds(result.duration).formatted(.units(allowed: [.minutes, .seconds], width: .narrow)))",
                            systemImage: "checkmark.circle.fill"
                        )
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.green)
                    }
                }
                if showsOutput { OutputConsole(log: session.log) }
            case .finished(let outcome):
                FailureCard(session: session, outcome: outcome, showsOutput: $showsOutput)
                if showsOutput { OutputConsole(log: session.log) }
            }
        }
        .animation(.knobs, value: session.phase)
        .animation(.knobs, value: showsOutput)
    }
}

private struct ResultCard: View {
    @Bindable var session: TaskSession
    let result: TaskSession.RunResult
    @Binding var showsOutput: Bool
    @State private var appeared = false

    private var sizeChange: String? {
        guard let input = result.inputBytes, let output = result.outputBytes, input > 0 else { return nil }
        let change = Double(output - input) / Double(input)
        guard abs(change) >= 0.01 else { return "same size" }
        return change.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always()))
    }

    var body: some View {
        HStack(spacing: 16) {
            if let url = result.outputURL {
                FileThumbnail(url: url, size: 72)
                    .draggable(url)
                    .help("Drag the result anywhere")
            } else if let folder = result.folderURL {
                FileThumbnail(url: folder, size: 56)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
            }
            VStack(alignment: .leading, spacing: 4) {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: appeared)
                Text(
                    result.outputURL?.lastPathComponent
                        ?? result.folderURL.map { "Saved in \($0.lastPathComponent)" }
                        ?? "\(session.task.title) finished"
                )
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                HStack(spacing: 6) {
                    if let bytes = result.outputBytes { Text(ByteCount.string(bytes)) }
                    if let sizeChange {
                        Text(sizeChange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.primary.opacity(0.07), in: .capsule)
                    }
                    Text(
                        "in \(Duration.seconds(result.duration).formatted(.units(allowed: [.minutes, .seconds], width: .narrow)))"
                    )
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                if let url = result.outputURL {
                    HStack(spacing: 8) {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        Button("Open") { NSWorkspace.shared.open(url) }
                            .keyboardShortcut("o")
                    }
                } else if let folder = result.folderURL {
                    Button("Open Folder") { NSWorkspace.shared.open(folder) }
                }
                Button(showsOutput ? "Hide Output" : "Show Output") { showsOutput.toggle() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .font(.caption)
            }
        }
        .padding(16)
        .background(.green.opacity(0.07), in: .rect(cornerRadius: Metrics.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius).strokeBorder(.green.opacity(0.25), lineWidth: 1)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear { appeared = true }
        .accessibilityElement(children: .contain)
    }
}

private struct FailureCard: View {
    @Bindable var session: TaskSession
    let outcome: RunOutcome
    @Binding var showsOutput: Bool

    private var title: String {
        switch outcome {
        case .cancelled: "Cancelled"
        case .couldNotStart: "\(session.manifest.name) couldn't start"
        case .failed: "\(session.manifest.name) stopped with an error"
        case .succeeded: "Done"
        }
    }

    private var detail: String? {
        switch outcome {
        case .cancelled: "Nothing else will be written. A partly written output file may remain."
        case .couldNotStart(let reason): reason
        case .failed(let code): session.log.mostRelevantErrorLine ?? "It exited with code \(code)."
        case .succeeded: nil
        }
    }

    private var isCancel: Bool { outcome == .cancelled }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: isCancel ? "stop.circle" : "exclamationmark.triangle.fill")
                .font(.system(size: 26))
                .foregroundStyle(isCancel ? Color.secondary : Color.red)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                if let detail {
                    Text(detail)
                        .font(isCancel ? .callout : .system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if !session.log.lines.isEmpty {
                Button(showsOutput ? "Hide Output" : "Show Output") { showsOutput.toggle() }
            }
        }
        .padding(16)
        .background((isCancel ? Color.primary : Color.red).opacity(0.06), in: .rect(cornerRadius: Metrics.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius)
                .strokeBorder((isCancel ? Color.primary : Color.red).opacity(0.18), lineWidth: 1)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// The tool's own output: monospaced, selectable, following the newest line.
struct OutputConsole: View {
    let log: OutputLog

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Output").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if log.droppedLineCount > 0 {
                    Text("Showing the last \(log.lines.count) lines")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Button {
                    Pasteboard.copy(log.lines.map(\.text).joined(separator: "\n"))
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy the output")
                .accessibilityLabel("Copy output")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(log.lines) { line in
                            Text(line.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(line.stream == .standardError ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                    .textSelection(.enabled)
                    .padding(12)
                }
                .frame(height: 220)
                .onChange(of: log.lines.last?.id) { _, last in
                    if let last { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
        .background(.background.secondary, in: .rect(cornerRadius: Metrics.wellRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.wellRadius).strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        }
        .transition(.opacity)
    }
}
