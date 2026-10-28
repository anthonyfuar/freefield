import AppKit
import FreefieldCore
import SwiftUI

struct JoinTrimView: View {
    let tool: VideoTool

    @Environment(AppModel.self) private var app
    @State private var selectedClipID: UUID?
    @State private var choosing = false
    @State private var importing = false
    @State private var isTargeted = false

    private var edits: JoinTrimEdits { .shared }
    static let maximum = VideoCatalog.tool("joinClips")?.slot(.clips)?.maxCount ?? 8

    var body: some View {
        let state = app.videoState(for: tool)
        let clips = state.clipIDs.compactMap(app.library.asset).filter(\.isVideo)
        let trimmed = clips.first(where: { $0.id == selectedClipID }) ?? clips.first
        VideoToolScreen(tool: tool, state: state) {
            clipStrip(state, clips: clips)
            if let clip = trimmed {
                JoinTrimEditor(asset: clip, edits: edits, step: 2)
                    .id(clip.id)
            }
            joinOptions(state, firstStep: trimmed == nil ? 2 : 3, isReady: clips.count >= 2)
        } bar: {
            bottomBar(state, clips: clips)
        }
        .sheet(isPresented: $choosing) {
            VideoLibraryPicker(multiple: true) { ids in add(ids, state: state) }
                .environment(app)
        }
    }

    private func clipStrip(_ state: VideoState, clips: [Asset]) -> some View {
        let selected = selectedClipID.flatMap { id in clips.first { $0.id == id } }?.id ?? clips.first?.id
        return PanelSection(title: L("Clips"), systemImage: "film.stack", step: 1, isDone: clips.count >= 2) {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(Array(clips.enumerated()), id: \.element.id) { index, asset in
                            clipTile(asset, index: index, count: clips.count, isSelected: asset.id == selected, state: state)
                        }
                        if clips.count < Self.maximum { addTile(state) }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.never)
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    Task {
                        var urls: [URL] = []
                        for provider in providers {
                            if let url = await ImageIntake.movieURL(from: provider) { urls.append(url) }
                        }
                        await importFiles(urls, state: state)
                    }
                    return true
                }
                Text(clips.count < 2 ? L("%ld to %ld clips — you can also drop them here.", 2, Self.maximum)
                     : L("Drag the clips to change their order. Select one to trim it."))
                    .helperTextStyle()
            }
        }
    }

    private func clipTile(_ asset: Asset, index: Int, count: Int, isSelected: Bool, state: VideoState) -> some View {
        let range = edits.ranges[asset.id]
        return VStack(spacing: 4) {
            VideoTile(url: app.library.url(for: asset), posterURL: app.library.posterURL(for: asset),
                      duration: range.map { $0.upperBound - $0.lowerBound } ?? asset.duration, hasAudio: asset.hasAudio,
                      isSelected: isSelected, maxPixel: 320)
                .frame(width: 150, height: 92)
                .overlay(alignment: .topLeading) {
                    Text("\(index + 1)").font(.caption.weight(.bold)).frame(width: 20, height: 20)
                        .glassEffect(in: .circle).padding(5)
                }
                .overlay(alignment: .topTrailing) {
                    if range != nil {
                        Image(systemName: "scissors").font(.caption2.weight(.bold)).frame(width: 20, height: 20)
                            .glassEffect(in: .circle).padding(5)
                            .help(L("Trimmed"))
                    }
                }
                .contentShape(.rect)
                .onTapGesture { withAnimation(Motion.standard) { selectedClipID = asset.id } }
                .accessibilityLabel(L("Clip %ld", index + 1))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityHint(L("Selects the clip to trim"))
                .accessibilityAction { withAnimation(Motion.standard) { selectedClipID = asset.id } }
                .draggable(asset.id.uuidString) {
                    VideoPoster(url: app.library.url(for: asset), posterURL: app.library.posterURL(for: asset), maxPixel: 200)
                        .frame(width: 120, height: 74)
                        .clipShape(.rect(cornerRadius: Radius.thumb))
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let id = items.first.flatMap(UUID.init(uuidString:)), id != asset.id, state.clipIDs.contains(id) else { return false }
                    withAnimation(Motion.standard) { move(id, to: asset.id, state: state) }
                    return true
                }
            HStack(spacing: 2) {
                Button { shift(asset.id, by: -1, state: state) } label: { Image(systemName: "chevron.left") }
                    .disabled(index == 0).help(L("Move earlier"))
                Button {
                    withAnimation(Motion.standard) {
                        state.clipIDs.removeAll { $0 == asset.id }
                        if selectedClipID == asset.id { selectedClipID = nil }
                    }
                } label: { Image(systemName: "trash") }
                    .help(L("Remove clip"))
                Button { shift(asset.id, by: 1, state: state) } label: { Image(systemName: "chevron.right") }
                    .disabled(index == count - 1).help(L("Move later"))
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }

    private func addTile(_ state: VideoState) -> some View {
        Menu {
            Button(L("Choose Files…"), systemImage: "folder") { chooseFiles(state) }
            Button(L("From Library…"), systemImage: "film.stack") { choosing = true }
        } label: {
            VStack(spacing: 6) {
                if importing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "plus").font(.title3)
                }
                Text(importing ? L("Importing…") : L("Add clips")).font(.subheadline)
            }
            .frame(width: 150, height: 92)
            .background {
                RoundedRectangle(cornerRadius: Radius.tile)
                    .fill(isTargeted ? Color.appAccent.opacity(0.10) : .clear)
                RoundedRectangle(cornerRadius: Radius.tile)
                    .strokeBorder(isTargeted ? Color.appAccent : .secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(importing)
    }

    private func add(_ ids: [UUID], state: VideoState) {
        let room = max(0, Self.maximum - state.clipIDs.count)
        let added = ids.filter { !state.clipIDs.contains($0) }.prefix(room)
        state.clipIDs.append(contentsOf: added)
        if selectedClipID == nil { selectedClipID = added.first }
    }

    private func chooseFiles(_ state: VideoState) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = L("Choose videos")
        panel.prompt = L("Use")
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task { await importFiles(urls, state: state) }
    }

    private func importFiles(_ urls: [URL], state: VideoState) async {
        guard !urls.isEmpty else { return }
        importing = true
        defer { importing = false }
        var ids: [UUID] = []
        for url in urls.prefix(max(0, Self.maximum - state.clipIDs.count)) {
            if let asset = await app.library.importVideo(url: url) { ids.append(asset.id) } else {
                app.presentError(VideoMediaError.unreadable)
            }
        }
        withAnimation(Motion.standard) { add(ids, state: state) }
    }

    private func move(_ id: UUID, to target: UUID, state: VideoState) {
        guard let from = state.clipIDs.firstIndex(of: id), let to = state.clipIDs.firstIndex(of: target) else { return }
        state.clipIDs.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    private func shift(_ id: UUID, by offset: Int, state: VideoState) {
        guard let index = state.clipIDs.firstIndex(of: id), state.clipIDs.indices.contains(index + offset) else { return }
        withAnimation(Motion.standard) { state.clipIDs.swapAt(index, index + offset) }
    }

    @ViewBuilder private func joinOptions(_ state: VideoState, firstStep: Int, isReady: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                between(step: firstStep, isReady: isReady).frame(maxWidth: .infinity, alignment: .leading)
                music(state, step: firstStep + 1).frame(minWidth: 340, maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 16) {
                between(step: firstStep, isReady: isReady)
                music(state, step: firstStep + 1).frame(maxWidth: 560, alignment: .leading)
            }
        }
    }

    private func between(step: Int, isReady: Bool) -> some View {
        @Bindable var edits = self.edits
        return PanelSection(title: L("Between clips"), systemImage: "rectangle.2.swap", step: step, isDone: isReady) {
            VStack(alignment: .leading, spacing: 8) {
                Picker(L("Crossfade"), selection: $edits.crossfade) {
                    Text(L("Cut")).tag(0.0)
                    ForEach([0.3, 0.6], id: \.self) { seconds in
                        Text(L("Crossfade %@ s", seconds.formatted(.number.precision(.fractionLength(1))))).tag(seconds)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Toggle(isOn: $edits.trimsSeams) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Smooth the jump between clips"))
                        Text(L("Use it when one clip continues the one before, so the jump doesn't show."))
                            .helperTextStyle()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(idealWidth: 300, alignment: .leading)
                }
                .toggleStyle(.checkbox)
                .help(L("Drops the frames AI clips repeat where they meet: 6 at the end of a clip, 1 at the start of the next. For shots that continue each other."))
            }
        }
    }

    @ViewBuilder private func music(_ state: VideoState, step: Int) -> some View {
        @Bindable var state = state
        if let slot = tool.slot(.audio) {
            PanelSection(title: VideoSlotTitle.plain(slot.title), systemImage: slot.symbol, step: step, isDone: state.audioFile != nil,
                         isOptional: !slot.isRequired) {
                VStack(alignment: .leading, spacing: 4) {
                    LocalSoundPicker(file: $state.audioFile, duration: $state.audioDuration, title: L("Choose a song or track"))
                    Text(L("Replaces the clips' own sound, cut to the video's length.")).helperTextStyle()
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(idealWidth: 300, alignment: .leading)
                }
            }
        }
    }

    private func bottomBar(_ state: VideoState, clips: [Asset]) -> some View {
        let parts = clips.map { VideoJoinPart(asset: $0, range: edits.ranges[$0.id]) }
        let seconds = Self.length(of: parts, crossfade: edits.crossfade)
        let isWorking = state.localWork.contains(where: \.isRunning)
        let reason: String? = clips.count < 2 ? L("Add at least %ld clips.", 2) : isWorking ? L("Joining the clips…") : nil
        return VideoLocalBar(title: L("Join Clips"), reason: reason, isWorking: isWorking,
                             label: Label(L("Runs on this Mac, free"), systemImage: "desktopcomputer"),
                             detail: clips.count >= 2 ? L("%ld clips · about %@ in all", clips.count, VideoPlayback.durationLabel(seconds)) : nil,
                             costLabel: L("Free")) {
            app.joinOnMac(parts, crossfade: edits.crossfade, trimSeams: edits.trimsSeams, music: state.audioFile,
                          title: tool.name, record: english(tool.name) + " · " + E("%ld clips", parts.count), tool: tool, state: state)
        }
    }

    static func length(of parts: [VideoJoinPart], crossfade: Double) -> Double {
        let kept = parts.map { part in part.range.map { $0.upperBound - $0.lowerBound } ?? part.asset.duration ?? 0 }
        return max(0, kept.reduce(0, +) - crossfade * Double(max(0, parts.count - 1)))
    }
}

private struct JoinTrimEditor: View {
    let asset: Asset
    @Bindable var edits: JoinTrimEdits
    var step: Int?

    @Environment(AppModel.self) private var app
    @State private var strip: [Data] = []
    @State private var startFrame: Data?
    @State private var endFrame: Data?

    private static let stripCount = 10
    private static let minimumLength = 0.3

    var body: some View {
        let duration = max(0, asset.duration ?? 0)
        let range = edits.ranges[asset.id] ?? 0...duration
        PanelSection(title: L("Trim"), systemImage: "scissors", step: step, isDone: edits.ranges[asset.id] != nil, isOptional: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 14) {
                    VideoPlayerView(url: app.library.url(for: asset), autoplay: false)
                        .aspectRatio(asset.aspect > 0 ? asset.aspect : 16.0 / 9, contentMode: .fit)
                        .frame(maxWidth: 420, maxHeight: 240)
                        .clipShape(.rect(cornerRadius: Radius.tile))
                    HStack(spacing: 10) {
                        endFrameView(startFrame, title: L("First frame kept"), time: range.lowerBound)
                        endFrameView(endFrame, title: L("Last frame kept"), time: range.upperBound)
                    }
                }
                if duration >= Self.minimumLength * 2 {
                    filmstrip(range: range, duration: duration)
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                        GridRow {
                            Text(L("Start")).foregroundStyle(.secondary)
                            Slider(value: Binding(get: { range.lowerBound }, set: { setRange($0...range.upperBound, duration: duration, moving: .start) }),
                                   in: 0...duration)
                                .accessibilityLabel(L("Start"))
                                .accessibilityValue(Self.timeLabel(range.lowerBound))
                            Text(Self.timeLabel(range.lowerBound)).font(.callout.monospacedDigit()).frame(width: 64, alignment: .trailing)
                        }
                        GridRow {
                            Text(L("End")).foregroundStyle(.secondary)
                            Slider(value: Binding(get: { range.upperBound }, set: { setRange(range.lowerBound...$0, duration: duration, moving: .end) }),
                                   in: 0...duration)
                                .accessibilityLabel(L("End"))
                                .accessibilityValue(Self.timeLabel(range.upperBound))
                            Text(Self.timeLabel(range.upperBound)).font(.callout.monospacedDigit()).frame(width: 64, alignment: .trailing)
                        }
                    }
                    HStack {
                        Text(L("Keeps %@ of %@", Self.timeLabel(range.upperBound - range.lowerBound), Self.timeLabel(duration)))
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Reset Trim")) { edits.ranges[asset.id] = nil }
                            .disabled(edits.ranges[asset.id] == nil)
                    }
                } else {
                    Text(L("This clip is too short to trim.")).helperTextStyle()
                }
            }
        }
        .task { await loadStrip(duration: duration) }
        .task(id: range.lowerBound) { startFrame = await frame(at: range.lowerBound, duration: duration) }
        .task(id: range.upperBound) { endFrame = await frame(at: range.upperBound, duration: duration) }
    }

    private enum Handle { case start, end }

    private func setRange(_ proposed: ClosedRange<Double>, duration: Double, moving handle: Handle) {
        var lower = min(max(0, proposed.lowerBound), duration)
        var upper = min(max(0, proposed.upperBound), duration)
        if upper - lower < Self.minimumLength {
            switch handle {
            case .start: lower = max(0, upper - Self.minimumLength)
            case .end: upper = min(duration, lower + Self.minimumLength)
            }
        }
        edits.ranges[asset.id] = lower <= 0.01 && upper >= duration - 0.01 ? nil : lower...upper
    }

    private func filmstrip(range: ClosedRange<Double>, duration: Double) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let start = width * range.lowerBound / duration, end = width * range.upperBound / duration
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(Array(strip.enumerated()), id: \.offset) { _, data in
                        DataImage(data: data, maxPixel: 200, contentMode: .fill)
                            .frame(width: width / CGFloat(max(1, strip.count)), height: proxy.size.height)
                            .clipped()
                    }
                }
                .frame(width: width, height: proxy.size.height, alignment: .leading)
                .background(Color.primary.opacity(0.06))
                Rectangle().fill(.black.opacity(0.55)).frame(width: max(0, start))
                Rectangle().fill(.black.opacity(0.55)).frame(width: max(0, width - end)).offset(x: end)
                RoundedRectangle(cornerRadius: Radius.small)
                    .strokeBorder(Color.yellow, lineWidth: 3)
                    .frame(width: max(6, end - start))
                    .offset(x: start)
            }
            .clipShape(.rect(cornerRadius: Radius.thumb))
        }
        .frame(height: 54)
        .accessibilityElement()
        .accessibilityLabel(L("Keeps %@ of %@", Self.timeLabel(range.upperBound - range.lowerBound), Self.timeLabel(duration)))
    }

    private func endFrameView(_ data: Data?, title: String, time: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.thumb).fill(Color.primary.opacity(0.05))
                if let data { DataImage(data: data, maxPixel: 400, contentMode: .fit) }
            }
            .frame(width: 150, height: 100)
            .clipShape(.rect(cornerRadius: Radius.thumb))
            Text(title).font(.subheadline.weight(.semibold))
            Text(Self.timeLabel(time)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func loadStrip(duration: Double) async {
        if let cached = edits.strips[asset.id] {
            strip = cached
            return
        }
        guard duration > 0 else { return }
        let url = app.library.url(for: asset)
        var frames: [Data] = []
        for index in 0..<Self.stripCount {
            let seconds = duration * (Double(index) + 0.5) / Double(Self.stripCount)
            guard !Task.isCancelled else { return }
            if let data = try? await VideoMedia.frame(url, at: seconds, maxPixel: 200) { frames.append(data) }
        }
        strip = frames
        edits.strips[asset.id] = frames
    }

    private func frame(at seconds: Double, duration: Double) async -> Data? {
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return nil }
        let time = seconds >= duration - 0.01 ? max(0, duration - 0.05) : seconds
        return try? await VideoMedia.frame(app.library.url(for: asset), at: time, maxPixel: 400)
    }

    static func timeLabel(_ seconds: Double) -> String {
        let value = max(0, seconds)
        let minutes = Int(value) / 60
        return String(format: "%d:%04.1f", minutes, value - Double(minutes * 60))
    }
}

@Observable
final class JoinTrimEdits {
    static let shared = JoinTrimEdits()

    var ranges: [UUID: ClosedRange<Double>] = [:]
    var crossfade = 0.0
    var trimsSeams = false
    @ObservationIgnored var strips: [UUID: [Data]] = [:]
}

struct VideoJoinPart {
    let asset: Asset
    var range: ClosedRange<Double>?
}

extension AppModel {
    func joinOnMac(_ parts: [VideoJoinPart], crossfade: Double, trimSeams: Bool, music: URL?, title: String, record: String,
                   tool: VideoTool, state: VideoState) {
        guard parts.count >= 2 else {
            presentError(FreefieldError.unsupported(L("Add at least two clips.")))
            return
        }
        let work = VideoLocalWork(title: title, step: L("Getting ready…"))
        state.localWork.insert(work, at: 0)
        let library = self.library
        let files = parts.map { (library.url(for: $0.asset), $0.range) }
        let first = parts.first?.asset
        work.task = Task {
            var scratch: [URL] = []
            defer { for url in scratch { try? FileManager.default.removeItem(at: url) } }
            do {
                var inputs: [URL] = []
                for (index, (file, range)) in files.enumerated() {
                    if let range {
                        work.step = L("Trimming clip %ld of %ld…", index + 1, files.count)
                        let cut = try await VideoMedia.trim(file, start: range.lowerBound, end: range.upperBound)
                        scratch.append(cut)
                        inputs.append(cut)
                    } else {
                        inputs.append(file)
                    }
                    try Task.checkCancellation()
                }
                work.step = L("Joining the clips…")
                var url = try await VideoMedia.join(inputs, trimSeams: trimSeams, crossfade: crossfade)
                if let music {
                    work.step = L("Adding the music…")
                    scratch.append(url)
                    url = try await VideoMedia.muxAudio(from: music, into: url)
                }
                guard !Task.isCancelled else {
                    scratch.append(url)
                    throw CancellationError()
                }
                work.step = L("Saving to the library…")
                let template = Asset(
                    id: UUID(), fileName: "", createdAt: .now, width: 0, height: 0, tool: .video, prompt: record, finalPrompt: "",
                    modelID: "local", modelName: E("On this Mac"), provider: .openRouter, aspectRatio: .auto, resolution: .oneK,
                    batchID: UUID(), appID: tool.id, inputFileNames: [], cost: 0, isFavorite: false, mediaKind: .video,
                    parentAssetID: first?.id
                )
                guard let asset = await library.addVideo(file: url, template: template) else {
                    scratch.append(url)
                    throw VideoMediaError.unreadable
                }
                self.engine.recordLocal(title: record, tool: .video, modelName: E("On this Mac"), assetIDs: [asset.id], appID: tool.id)
                work.isDone = true
                state.localWork.removeAll { $0.id == work.id }
            } catch is CancellationError {
                state.localWork.removeAll { $0.id == work.id }
            } catch {
                work.failure = error.localizedDescription
            }
        }
    }
}
