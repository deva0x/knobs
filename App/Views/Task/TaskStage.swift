import KnobsCore
import KnobsSession
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// The task's stage: its main input, large, in every state of a run (docs/DESIGN.md, "Task stage"). Settings live in
/// the inspector; the command bar floats over the bottom edge.
struct TaskStage: View {
    @Environment(Toolbox.self) private var toolbox
    @Bindable var session: TaskSession
    @Binding var showsOutput: Bool

    private var tint: Color { session.manifest.tint.color }

    var body: some View {
        ZStack {
            StageBackdrop(tint: tint)
            content
                .padding(.horizontal, 32)
                .padding(.top, 20)
                // Room for the floating command bar.
                .padding(.bottom, 84)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottom) {
            if showsOutput && !isShowingReport {
                OutputConsole(log: session.log)
                    .frame(maxWidth: Metrics.contentMaxWidth)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 84)
                    .knobsTransition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.knobs, value: session.phase)
        .animation(.knobs, value: showsOutput)
    }

    /// Tasks that only report something (such as listing metadata) show their output as the result.
    private var isShowingReport: Bool {
        session.phase == .finished(.succeeded) && session.result != nil && !session.producesResult
    }

    @ViewBuilder private var content: some View {
        switch session.phase {
        case .finished(.succeeded):
            if let result = session.result, session.producesResult {
                ResultStage(session: session, result: result)
            } else if session.result != nil {
                ReportStage(session: session)
            } else {
                input
            }
        case .finished(let outcome):
            FailureStage(session: session, outcome: outcome, showsOutput: $showsOutput)
        case .idle, .running:
            input
        }
    }

    private var input: some View {
        VStack(spacing: 18) {
            if !toolbox.isInstalled(session.manifest) {
                NotInstalledPanel(manifest: session.manifest)
                    .frame(maxWidth: Metrics.contentMaxWidth)
            }
            if let field = session.primaryInputField {
                InputStage(field: field, session: session)
            } else if let field = session.heroTextField {
                HeroTextField(field: field, session: session)
                    .frame(maxWidth: 560)
                    .overlay {
                        if case .running(let startedAt) = session.phase {
                            DialGauge(progress: session.progress, tint: tint, startedAt: startedAt)
                        }
                    }
            } else {
                TaskEmblem(session: session)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

/// A soft wash of the tool's tint behind the stage, so each tool's screens feel like its own space.
private struct StageBackdrop: View {
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RadialGradient(
            colors: [tint.opacity(colorScheme == .dark ? 0.16 : 0.10), .clear],
            center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: 460
        )
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Input

/// The main input: a large drop target when empty, then a big preview (or a stack of them) with the file's facts.
/// A task that takes one file can be given several; it then runs once per file.
private struct InputStage: View {
    let field: Field
    @Bindable var session: TaskSession
    @State private var isTargeted = false
    @State private var isImporting = false
    /// Whether the file dialog's choice joins the files already there ("Add More…") or takes their place.
    @State private var importAppends = false
    @State private var rejectedDrop = false

    private var paths: [String] { session.value(of: field)?.pathList ?? [] }
    private var tint: Color { session.manifest.tint.color }

    private var allowedTypes: [UTType] {
        guard case .inputFile(let identifiers, _) = field.kind else { return [.folder] }
        let types = identifiers.compactMap { UTType($0) }
        return types.isEmpty ? [.item, .folder] : types
    }

    private var allowsMultiple: Bool {
        if case .inputFile(_, true) = field.kind { return true }
        return false
    }

    var body: some View {
        Group {
            if paths.isEmpty {
                DropTarget(
                    field: field, session: session, isTargeted: isTargeted, rejectedDrop: rejectedDrop,
                    choose: chooseFilesToReplace)
            } else if paths.count == 1 {
                SingleFile(
                    url: URL(filePath: paths[0]), session: session, isTargeted: isTargeted,
                    replaceOrAdd: allowsMultiple ? chooseFilesToAdd : chooseFilesToReplace,
                    remove: { session.setValue(nil, for: field) })
            } else {
                SeveralFiles(
                    paths: paths, runsOncePerFile: !allowsMultiple, session: session, isTargeted: isTargeted
                ) {
                    chooseFilesToAdd()
                } remove: { path in
                    let remaining = paths.filter { $0 != path }
                    session.setValue(remaining.isEmpty ? nil : .paths(remaining), for: field)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .dropDestination(for: URL.self) { urls, _ in
            let accepted = urls.filter { FileTypeCheck.accepts($0, for: field.kind) }
            guard !accepted.isEmpty else {
                withAnimation(.knobs) { rejectedDrop = true }
                return false
            }
            // Files dropped onto a list join it; onto one file of a one-file task, they take its place.
            if allowsMultiple || paths.count > 1 { append(accepted) } else { replace(with: accepted) }
            return true
        } isTargeted: { targeted in
            withAnimation(.knobs) { isTargeted = targeted }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: allowedTypes, allowsMultipleSelection: true) {
            result in
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            if importAppends { append(urls) } else { replace(with: urls) }
        }
        .disabled(session.isRunning)
        .task(id: rejectedDrop) {
            guard rejectedDrop, (try? await Task.sleep(for: .seconds(2))) != nil else { return }
            withAnimation(.knobs) { rejectedDrop = false }
        }
        .animation(.knobs, value: paths)
    }

    private func chooseFilesToReplace() {
        importAppends = false
        isImporting = true
    }

    private func chooseFilesToAdd() {
        importAppends = true
        isImporting = true
    }

    /// Adds files to the list, leaving out ones already in it.
    private func append(_ urls: [URL]) {
        var combined = paths
        for path in urls.map(\.path) where !combined.contains(path) { combined.append(path) }
        session.setValue(.paths(combined), for: field)
    }

    private func replace(with urls: [URL]) {
        session.setValue(.paths(urls.map(\.path)), for: field)
    }
}

/// The empty state: one generous target that says what it wants.
private struct DropTarget: View {
    let field: Field
    @Bindable var session: TaskSession
    let isTargeted: Bool
    let rejectedDrop: Bool
    let choose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color { session.manifest.tint.color }

    private var allowsMultiple: Bool {
        if case .inputFile(_, true) = field.kind { return true }
        return false
    }

    private var kindName: String { LabelPhrase.phrase(for: field.label, isPlural: allowsMultiple) }

    /// "Video", "Image", "PDF": plain names for the types the field takes.
    private var acceptedKinds: String? {
        guard case .inputFile(let identifiers, _) = field.kind else { return nil }
        let names = InputKind.names(for: identifiers)
        return names.isEmpty ? nil : names.formatted(.list(type: .or))
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(tint.opacity(isTargeted ? 0.22 : 0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: isTargeted ? "arrow.down" : session.task.symbol)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(tint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .scaleEffect(isTargeted && !reduceMotion ? 1.06 : 1)
            .accessibilityHidden(true)
            VStack(spacing: 5) {
                Text(rejectedDrop ? "That isn't \(kindName)" : "Drop \(kindName) here")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(rejectedDrop ? .red : .primary)
                Text(session.task.summary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Choose \(field.label)…", action: choose)
                .buttonStyle(.glass)
                .controlSize(.large)
            if let acceptedKinds {
                Text(acceptedKinds)
                    .font(.helpText)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(36)
        .frame(maxWidth: 560, minHeight: 300)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(isTargeted ? tint.opacity(0.07) : Color.primary.opacity(0.02))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    isTargeted ? tint : Color.primary.opacity(0.14),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: isTargeted ? [] : [7, 6]))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(field.label): none chosen. Drop \(kindName) here, or choose one.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { choose() }
        .knobsTransition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

/// One chosen file: a large preview, its name and facts, and Replace and Remove.
private struct SingleFile: View {
    let url: URL
    @Bindable var session: TaskSession
    let isTargeted: Bool
    let replaceOrAdd: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            FilePreview(url: url, maximumSize: CGSize(width: 560, height: 330), isTargeted: isTargeted)
                .overlay {
                    if case .running(let startedAt) = session.phase {
                        DialGauge(progress: session.progress, tint: session.manifest.tint.color, startedAt: startedAt)
                    }
                }
            FileCaption(url: url)
            if !session.isRunning {
                // Quiet text buttons: the screen's one accent belongs to Run.
                HStack(spacing: 14) {
                    Button("Replace…", action: replaceOrAdd)
                    Button("Remove", action: remove)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.callout)
            }
        }
    }
}

/// Several chosen files: a fanned stack, a count, and the list to trim.
private struct SeveralFiles: View {
    let paths: [String]
    /// The task takes one file and goes through these one after another, rather than using them all at once.
    let runsOncePerFile: Bool
    @Bindable var session: TaskSession
    let isTargeted: Bool
    let add: () -> Void
    let remove: (String) -> Void
    @State private var totalSize: Int64?

    /// Only the first few are drawn in the stack; the rest are counted.
    private static let stackDepth = 3

    /// "12 files", "12 files · one after another", or "File 3 of 12" while they run.
    private var countLine: String {
        if let step = session.batchStep { return "File \(step.number) of \(step.count)" }
        return runsOncePerFile ? "\(paths.count) files · one after another" : "\(paths.count) files"
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                ForEach(Array(paths.prefix(Self.stackDepth).enumerated().reversed()), id: \.element) { index, path in
                    FilePreview(
                        url: URL(filePath: path), maximumSize: CGSize(width: 300, height: 220),
                        isTargeted: isTargeted && index == 0
                    )
                    .rotationEffect(.degrees(Double(index) * 5))
                    .offset(x: CGFloat(index) * 18, y: CGFloat(index) * -6)
                }
            }
            .overlay {
                if case .running(let startedAt) = session.phase {
                    DialGauge(progress: session.progress, tint: session.manifest.tint.color, startedAt: startedAt)
                }
            }
            .padding(.bottom, 4)
            VStack(spacing: 4) {
                Text(countLine)
                    .font(.system(size: 17, weight: .semibold))
                    .contentTransition(.numericText())
                if let totalSize {
                    Text(ByteCount.string(totalSize)).foregroundStyle(.secondary)
                }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(paths, id: \.self) { path in
                        HStack(spacing: 5) {
                            Text(URL(filePath: path).lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 180)
                            if !session.isRunning {
                                Button {
                                    remove(path)
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(URL(filePath: path).lastPathComponent)")
                            }
                        }
                        .font(.callout)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.quaternary.opacity(0.6), in: .capsule)
                    }
                    if !session.isRunning {
                        Button("Add More…", action: add)
                            .buttonStyle(.glass)
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.never)
            .frame(maxWidth: 640)
        }
        .animation(.knobs, value: session.batchStep)
        .task(id: paths) {
            let urls = paths.map { URL(filePath: $0) }
            totalSize = await Task.detached(priority: .utility) {
                urls.reduce(Int64(0)) { sum, url in
                    sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                }
            }.value
        }
    }
}

/// A file's name with its facts as quiet chips beneath.
private struct FileCaption: View {
    let url: URL
    @State private var facts: [String] = []

    var body: some View {
        VStack(spacing: 8) {
            Text(url.lastPathComponent)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 6) {
                ForEach(facts, id: \.self) { fact in
                    Text(fact)
                        .font(Font.helpText.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.6), in: .capsule)
                }
            }
            .frame(minHeight: 20)
        }
        .frame(maxWidth: 560)
        .task(id: url) { facts = await FileFacts.facts(for: url) }
        .accessibilityElement(children: .combine)
    }
}

/// A large Quick Look preview that keeps the file's own shape, with its Finder icon while it loads.
struct FilePreview: View {
    let url: URL
    let maximumSize: CGSize
    var isTargeted = false
    @State private var image: NSImage?
    @State private var isThumbnail = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            if let image, isThumbnail {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.hairline),
                                lineWidth: isTargeted ? 3 : 0.5)
                    }
                    .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
            } else {
                Image(nsImage: image ?? NSImage())
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: min(maximumSize.height, 160), height: min(maximumSize.height, 160))
            }
        }
        .frame(maxWidth: maximumSize.width, maxHeight: maximumSize.height)
        .draggable(url)
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Open") { NSWorkspace.shared.open(url) }
        }
        .task(id: url) {
            isThumbnail = false
            image = NSWorkspace.shared.icon(forFile: url.path)
            let request = QLThumbnailGenerator.Request(
                fileAt: url, size: maximumSize, scale: displayScale, representationTypes: .thumbnail)
            if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                withAnimation(.knobs) {
                    image = representation.nsImage
                    isThumbnail = true
                }
            }
        }
        .accessibilityLabel(url.lastPathComponent)
        .accessibilityAddTraits(.isImage)
    }
}

/// For tasks with no file or text input: the task's symbol and summary.
private struct TaskEmblem: View {
    @Bindable var session: TaskSession

    var body: some View {
        VStack(spacing: 14) {
            GlyphTile(symbol: session.task.symbol, tint: session.manifest.tint, size: 72)
            Text(session.task.summary)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .overlay {
            if case .running(let startedAt) = session.phase {
                DialGauge(progress: session.progress, tint: session.manifest.tint.color, startedAt: startedAt)
            }
        }
    }
}

// MARK: - Running

/// Progress as a dial, like the app icon: a 270° arc of tick marks that fill with the tool's tint. Without
/// progress from the tool, a highlight sweeps round the ticks (still, under Reduce Motion).
struct DialGauge: View {
    let progress: Double?
    let tint: Color
    let startedAt: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let tickCount = 40
    private static let sweepStart = 225.0
    private static let sweep = 270.0
    private static let diameter: CGFloat = 196

    var body: some View {
        // Only the sweep needs frames; the clock below keeps its own time.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: progress != nil || reduceMotion)) { context in
            ZStack {
                Canvas { canvas, size in
                    drawTicks(in: canvas, size: size, time: context.date.timeIntervalSince(startedAt))
                }
                VStack(spacing: 2) {
                    if let progress {
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText(value: progress))
                    } else {
                        Text("Working")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                    }
                    // Ticks on the same schedule as the command bar's clock, counted from the start, so the two
                    // always show the same second.
                    TimelineView(.periodic(from: startedAt, by: 1)) { clock in
                        Text(FileFacts.durationText(seconds: clock.date.timeIntervalSince(startedAt).rounded(.down)))
                            .font(Font.helpText.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
        // Always dark glass: it sits over a preview whose colors are anything, and must stay readable on all of them.
        .glassEffect(.regular.tint(.black.opacity(0.45)), in: .circle)
        .environment(\.colorScheme, .dark)
        .animation(.knobs, value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Running")
        .accessibilityValue(progress.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "In progress")
        .knobsTransition(.opacity.combined(with: .scale(scale: 0.92)))
    }

    private func drawTicks(in canvas: GraphicsContext, size: CGSize, time: TimeInterval) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let outer = size.width / 2 - 14
        let lit = progress.map { Int(($0 * Double(Self.tickCount)).rounded()) } ?? 0
        // The sweeping highlight for unknown progress: one bright tick that travels, with a fading tail.
        let head = Int(time * 18) % Self.tickCount
        for index in 0..<Self.tickCount {
            let degrees = Self.sweepStart - Double(index) / Double(Self.tickCount - 1) * Self.sweep
            let radians = degrees * .pi / 180
            let isMajor = index % 5 == 0
            let inner = outer - (isMajor ? 12 : 8)
            var path = Path()
            path.move(to: CGPoint(x: center.x + cos(radians) * inner, y: center.y - sin(radians) * inner))
            path.addLine(to: CGPoint(x: center.x + cos(radians) * outer, y: center.y - sin(radians) * outer))
            let shading: GraphicsContext.Shading
            if progress != nil {
                shading = index < lit ? .color(tint) : .color(.white.opacity(0.28))
            } else if reduceMotion {
                shading = .color(.white.opacity(0.4))
            } else {
                let distance = (head - index + Self.tickCount) % Self.tickCount
                shading =
                    distance < 8 ? .color(tint.opacity(1 - Double(distance) / 8)) : .color(.white.opacity(0.28))
            }
            canvas.stroke(path, with: shading, style: StrokeStyle(lineWidth: isMajor ? 3.5 : 2.5, lineCap: .round))
        }
    }
}

// MARK: - Finished

/// How long a finished run took, for the result and report stages.
private enum RunTime {
    /// "in 24s", "in 3m 5s"; a run that took less than a second says so rather than "in 0s".
    static func phrase(seconds: TimeInterval) -> String {
        guard seconds >= 1 else { return "in under a second" }
        return "in " + Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .narrow))
    }
}

/// Success with an output file: before and after, with the size change as the hero number.
private struct ResultStage: View {
    @Bindable var session: TaskSession
    let result: TaskSession.RunResult

    private var tint: Color { session.manifest.tint.color }

    var body: some View {
        VStack(spacing: 18) {
            if let url = result.outputURL {
                FilePreview(url: url, maximumSize: CGSize(width: 520, height: 300))
                    .help("Drag the result anywhere")
            } else if let folder = result.folderURL {
                FilePreview(url: folder, maximumSize: CGSize(width: 160, height: 160))
            }
            VStack(spacing: 6) {
                if let sizeChange = result.sizeChange, abs(sizeChange) >= 0.01 {
                    Text(sizeChange.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always())))
                        .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(tint)
                        .contentTransition(.numericText(value: sizeChange))
                        .accessibilityLabel(sizeChangePhrase(sizeChange))
                } else {
                    Label(doneHeadline, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                }
                Text(
                    result.outputURL?.lastPathComponent
                        ?? result.folderURL.map { "Saved in \($0.lastPathComponent)" }
                        ?? (result.fileCount > 1 ? "Saved next to each file" : "\(session.task.title) finished")
                )
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                Text(detail)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                if !result.failedFiles.isEmpty {
                    Text(failedLine)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
            }
            .animation(.knobs, value: result.outputBytes)
            HStack(spacing: 10) {
                if let url = result.outputURL {
                    Button("Open") { NSWorkspace.shared.open(url) }
                        .buttonStyle(.glassProminent)
                        .help("Open the result (⌘O)")
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        .secondaryGlassButton()
                } else if let folder = result.folderURL {
                    Button("Open Folder") { NSWorkspace.shared.open(folder) }
                        .buttonStyle(.glassProminent)
                }
                Button("Run Again…") { session.dismissResult() }
                    .secondaryGlassButton()
                    .help("Back to the input and settings")
            }
            .controlSize(.large)
        }
        .frame(maxWidth: 600)
        .accessibilityElement(children: .contain)
        .knobsTransition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    /// "Done", or for several files "12 files done" and "11 of 12 done".
    private var doneHeadline: String {
        guard result.fileCount > 1 else { return "Done" }
        let done = result.fileCount - result.failedFiles.count
        return result.failedFiles.isEmpty ? "\(done) files done" : "\(done) of \(result.fileCount) done"
    }

    /// The files that didn't work, by name; the output shows why.
    private var failedLine: String {
        let names = result.failedFiles.map { URL(filePath: $0).lastPathComponent }.formatted(.list(type: .and))
        return "Didn't work: \(names). The output shows why."
    }

    /// "53% smaller" rather than "minus 53 percent" for VoiceOver.
    private func sizeChangePhrase(_ change: Double) -> String {
        let amount = abs(change).formatted(.percent.precision(.fractionLength(0)))
        return change < 0 ? "\(amount) smaller" : "\(amount) larger"
    }

    /// "350.5 MB → 22.7 MB · 19 s"
    private var detail: String {
        var parts: [String] = []
        switch (result.inputBytes, result.outputBytes) {
        case (let input?, let output?): parts.append("\(ByteCount.string(input)) → \(ByteCount.string(output))")
        case (nil, let output?): parts.append(ByteCount.string(output))
        default: break
        }
        parts.append(RunTime.phrase(seconds: result.duration))
        return parts.joined(separator: " · ")
    }
}

/// Success for tasks that only report something: the report is the result.
private struct ReportStage: View {
    @Bindable var session: TaskSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    "Done \(RunTime.phrase(seconds: session.result?.duration ?? 0))",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.headline)
                .foregroundStyle(session.manifest.tint.color)
                Spacer()
                Button("Run Again…") { session.dismissResult() }
                    .secondaryGlassButton()
            }
            OutputConsole(log: session.log, height: nil)
        }
        .frame(maxWidth: 820, maxHeight: .infinity)
        .knobsTransition(.opacity)
    }
}

/// A run that failed or was cancelled: calm words, the useful error line, and the way back.
private struct FailureStage: View {
    @Bindable var session: TaskSession
    let outcome: RunOutcome
    @Binding var showsOutput: Bool

    private var isCancel: Bool { outcome == .cancelled }

    private var title: String {
        switch outcome {
        case .cancelled, .succeeded: "Cancelled"
        case .couldNotStart: "\(session.manifest.name) couldn't start"
        case .failed: "\(session.manifest.name) stopped with an error"
        }
    }

    private var detail: String? {
        switch outcome {
        case .cancelled, .succeeded: "Nothing else will be written. A partly written output file may remain."
        case .couldNotStart(let reason): reason
        case .failed(let code): session.log.mostRelevantErrorLine ?? "It exited with code \(code)."
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: isCancel ? "stop.circle" : "exclamationmark.triangle.fill")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(isCancel ? Color.secondary : Color.red)
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.weight(.semibold))
            if let detail {
                Text(detail)
                    .font(isCancel ? .body : .system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            HStack(spacing: 10) {
                Button("Change Settings") { session.dismissResult() }
                    .buttonStyle(.glassProminent)
                if !session.log.lines.isEmpty {
                    Button(showsOutput ? "Hide Output" : "Show Output") { showsOutput.toggle() }
                        .secondaryGlassButton()
                }
            }
            .controlSize(.large)
        }
        .padding(28)
        .frame(maxWidth: 560)
        .knobsTransition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}

// MARK: - Text input

/// A large, address-bar-like field for a task's main text input, such as a video link, with a Paste button.
struct HeroTextField: View {
    let field: Field
    @Bindable var session: TaskSession
    @FocusState private var isFocused: Bool

    private var text: Binding<String> {
        Binding {
            if case .text(let text)? = session.value(of: field) { return text }
            return ""
        } set: {
            session.setValue(.text($0), for: field)
        }
    }

    private var placeholder: String {
        if case .text(let placeholder?) = field.kind { return placeholder }
        return field.label
    }

    /// Read from the manifest's own placeholder, so no tool is named in Swift: a web address means a link.
    private var takesALink: Bool {
        placeholder.hasPrefix("https://") || placeholder.hasPrefix("http://")
    }

    var body: some View {
        VStack(spacing: 18) {
            GlyphTile(symbol: session.task.symbol, tint: session.manifest.tint, size: 64)
            VStack(spacing: 5) {
                Text(takesALink ? "Paste a link" : field.label)
                    .font(.title2.weight(.semibold))
                Text(session.task.summary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                Image(systemName: takesALink ? "link" : "character.cursor.ibeam")
                    .font(.title3)
                    .foregroundStyle(isFocused ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .accessibilityHidden(true)
                TextField(field.label, text: text, prompt: Text(placeholder))
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isFocused)
                    .accessibilityLabel(field.label)
                if text.wrappedValue.isEmpty {
                    Button("Paste") {
                        if let pasted = NSPasteboard.general.string(forType: .string) {
                            text.wrappedValue = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    .secondaryGlassButton()
                    .help(takesALink ? "Paste a link from the clipboard" : "Paste from the clipboard")
                } else {
                    Button {
                        text.wrappedValue = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear \(field.label.lowercased())")
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .background(.background.secondary, in: .rect(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isFocused ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.hairline),
                        lineWidth: isFocused ? 2 : 1)
            }
        }
        .disabled(session.isRunning)
        .onAppear { if text.wrappedValue.isEmpty && !session.isRunning { isFocused = true } }
    }
}
