import AppKit
import AVFoundation
import AVKit
import FreefieldCore
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

struct AssetThumbnail: View {
    let asset: Asset
    var maxPixel = 640
    var contentMode: ContentMode = .fill

    @Environment(AppModel.self) private var app

    var body: some View {
        if asset.isVideo {
            VideoPoster(url: app.library.url(for: asset), posterURL: app.library.posterURL(for: asset),
                        maxPixel: maxPixel, contentMode: contentMode)
        } else {
            ThumbnailImage(url: app.library.url(for: asset), maxPixel: maxPixel, contentMode: contentMode)
        }
    }
}

struct AssetCard: View {
    let asset: Asset
    var isSelected = false
    var showsCaption = false
    var maxPixel = 640

    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        let url = app.library.url(for: asset)
        Group {
            if asset.isVideo {
                VideoTile(url: url, posterURL: app.library.posterURL(for: asset), duration: asset.duration,
                          hasAudio: asset.hasAudio, isSelected: isSelected, maxPixel: maxPixel)
            } else {
                ThumbnailImage(url: url, maxPixel: maxPixel)
                    .clipShape(.rect(cornerRadius: Radius.tile))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.tile)
                            .strokeBorder(isSelected ? Color.appAccent : .primary.opacity(0.06), lineWidth: isSelected ? 3 : 1)
                    }
            }
        }
        .aspectRatio(asset.aspect > 0 ? asset.aspect : 1, contentMode: .fit)
        .overlay(alignment: .topTrailing) {
            if asset.isFavorite || isHovering {
                Button {
                    app.library.toggleFavorite([asset.id])
                } label: {
                    Image(systemName: asset.isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(asset.isFavorite ? .pink : .primary)
                        .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                        .symbolEffect(.bounce, value: reduceMotion ? false : asset.isFavorite)
                        .animation(Motion.select, value: asset.isFavorite)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .padding(6)
                .help(asset.isFavorite ? L("Remove from Favorites") : L("Add to Favorites"))
            }
        }
        .overlay(alignment: .bottomLeading) {
            if isHovering {
                Text(asset.modelDisplayName)
                    .fineTextStyle()
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .glassEffect(in: .capsule)
                    .padding(6)
                    .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(Motion.fade) { isHovering = hovering }
        }
        .onDrag {
            NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }
        .contextMenu { AssetMenu(assets: [asset]) }
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var accessibilityLabel: String {
        guard asset.isVideo else { return asset.prompt.isEmpty ? L("Image") : asset.prompt }
        let kind = VideoPlayback.accessibilityLabel(duration: asset.duration, hasAudio: asset.hasAudio)
        return asset.prompt.isEmpty ? kind : "\(asset.prompt), \(kind)"
    }
}

struct AssetMenu: View {
    let assets: [Asset]
    @Environment(AppModel.self) private var app

    var body: some View {
        if let asset = assets.first, assets.count == 1 {
            if !asset.isVideo {
                Menu(L("Open In"), systemImage: "arrow.up.forward.app") {
                    ForEach(Tool.editingTools) { tool in
                        Button(tool.title, systemImage: tool.systemImage) { app.open(tool, with: asset) }
                    }
                }
                Menu(L("Make a Video"), systemImage: "video.badge.plus") {
                    MakeVideoItems(asset: asset)
                }
                Button(L("Use as Reference"), systemImage: "photo.badge.plus") {
                    app.useAsReference(asset)
                }
                if !asset.prompt.isEmpty, asset.tool != .imported {
                    Button(L("Reuse Prompt"), systemImage: "arrow.counterclockwise") { app.reuse(asset) }
                }
                Divider()
            } else {
                Menu(L("Open In"), systemImage: "film") {
                    ForEach(VideoFollowUp.tools) { tool in
                        Button(tool.name, systemImage: tool.symbol) { app.openVideoTool(tool.id, with: asset) }
                    }
                }
                Button(L("Save Frame as Image"), systemImage: "photo") {
                    Task { await app.saveVideoFrame(asset, at: .poster) }
                }
                Button(L("Save Last Frame as Image"), systemImage: "photo.badge.checkmark") {
                    Task { await app.saveVideoFrame(asset, at: .last) }
                }
                Divider()
            }
            Button(asset.isVideo ? L("Copy Video") : L("Copy Image"), systemImage: "doc.on.doc") { app.copyToPasteboard(asset) }
            if !asset.finalPrompt.isEmpty {
                Button(L("Copy Prompt"), systemImage: "text.quote") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(asset.prompt, forType: .string)
                }
            }
            Button(L("Show in Finder"), systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([app.library.url(for: asset)])
            }
            ShareLink(item: app.library.url(for: asset)) {
                Label(L("Share…"), systemImage: "square.and.arrow.up")
            }
        }
        Button(L("Export…"), systemImage: "square.and.arrow.down") { app.export(assets) }
        Button(assets.allSatisfy(\.isFavorite) ? L("Remove from Favorites") : L("Add to Favorites"), systemImage: "heart") {
            app.library.toggleFavorite(Set(assets.map(\.id)))
        }
        Divider()
        Button(assets.count == 1 ? L("Move to Trash") : L("Move %ld to Trash", assets.count), systemImage: "trash", role: .destructive) {
            app.library.delete(Set(assets.map(\.id)))
        }
    }
}

struct MakeVideoItems: View {
    let asset: Asset
    @Environment(AppModel.self) private var app

    var body: some View {
        videoButton(L("Animate"), "animateImage")
        videoButton(L("Use as Start Frame"), "createVideo")
        videoButton(L("Add a Video Effect…"), "videoEffects")
        videoButton(nil, "talkingAvatar")
        videoButton(L("Swap Into a Video"), "swapVideo")
        videoButton(nil, "motionTransfer")
    }

    @ViewBuilder private func videoButton(_ title: String?, _ toolID: String) -> some View {
        if let tool = VideoCatalog.tool(toolID) {
            Button(title ?? tool.name, systemImage: tool.symbol) { app.makeVideo(from: asset, in: toolID) }
        }
    }
}

struct PendingCard: View {
    let aspect: Double
    var label = L("Generating…")

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let sweep = 1.3

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.tile)
            .fill(.quaternary.opacity(0.6))
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                            let width = proxy.size.width
                            let progress = context.date.timeIntervalSinceReferenceDate
                                .truncatingRemainder(dividingBy: Self.sweep) / Self.sweep
                            LinearGradient(colors: [.clear, .white.opacity(0.18), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: width * 0.5)
                                .offset(x: width * (progress * 1.5 - 0.5))
                        }
                    }
                    .clipShape(.rect(cornerRadius: Radius.tile))
                    .allowsHitTesting(false)
                }
            }
            .overlay {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    if !label.isEmpty {
                        Text(label).helperTextStyle()
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                }
            }
            .accessibilityLabel(L("Generating image"))
    }
}

struct FailedCard: View {
    let message: String
    let aspect: Double
    var onRetry: (() -> Void)?
    var onDismiss: () -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.tile)
            .fill(Color.red.opacity(0.08))
            .strokeBorder(Color.red.opacity(0.25))
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                ViewThatFits(in: .vertical) {
                    content(lines: 6, showsIcon: true)
                    content(lines: 3, showsIcon: true)
                    content(lines: 2, showsIcon: false)
                    content(lines: 1, showsIcon: false)
                }
                .padding(12)
            }
            .help(message)
    }

    private func content(lines: Int, showsIcon: Bool) -> some View {
        VStack(spacing: 8) {
            if showsIcon {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
            }
            Text(message)
                .helperTextStyle()
                .multilineTextAlignment(.center)
                .lineLimit(lines)
                .textSelection(.enabled)
            FlowLayout(spacing: 6, centered: true) {
                if let onRetry { Button(L("Retry"), action: onRetry).controlSize(.small) }
                Button(L("Close"), action: onDismiss).controlSize(.small)
            }
        }
    }
}

struct FeedSlotView<Result: View>: View {
    let slot: FeedSlot
    let batch: FeedBatch
    var pendingLabel = L("Generating…")
    var failedAspect: Double?
    var height: CGFloat?
    var keepsShape = true
    @ViewBuilder var result: (Asset) -> Result

    @Environment(AppModel.self) private var app

    var body: some View {
        if keepsShape {
            content.aspectRatio(aspect, contentMode: .fit)
        } else {
            content
        }
    }

    private var content: some View {
        ZStack {
            switch slot.content {
            case .asset(let asset):
                result(asset)
                    .transition(Motion.transition(AnyTransition(.blurReplace)))
            case .pending:
                PendingCard(aspect: batch.aspect, label: pendingLabel)
                    .frame(height: height)
                    .transition(.opacity)
            case .failed(let message):
                FailedCard(message: message, aspect: failedAspect ?? batch.aspect,
                           onRetry: batch.job?.spec == nil ? nil : { if let job = batch.job { app.engine.retry(job) } }) {
                    if let job = batch.job { app.engine.dismiss(job) }
                }
                .frame(height: height)
                .transition(Motion.transition(.opacity.combined(with: .scale(scale: 0.97))))
            }
        }
    }

    private var aspect: Double {
        switch slot.content {
        case .asset(let asset): asset.aspect > 0 ? asset.aspect : 1
        case .pending: batch.aspect
        case .failed: failedAspect ?? batch.aspect
        }
    }
}

struct AssetInspector: View {
    let asset: Asset
    @Environment(AppModel.self) private var app
    @State private var playhead = VideoPlayhead()
    @State private var savingFrame = false
    @State private var savedFrame: Asset?
    @State private var showsSavedNote = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if asset.isVideo {
                    InspectorVideoPlayer(url: app.library.url(for: asset), playhead: playhead)
                        .aspectRatio(asset.aspect > 0 ? asset.aspect : 16.0 / 9, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: Radius.tile))
                        .overlay(alignment: .top) {
                            ConfirmationCapsule(text: L("Saved to the library"), isShown: $showsSavedNote)
                                .padding(.top, 10)
                        }
                    videoActions
                } else {
                    ThumbnailImage(url: app.library.url(for: asset), maxPixel: 900, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: Radius.tile))
                        .onTapGesture(count: 2) { app.quickLook(asset) }
                }

                if !asset.isVideo {
                    quickActions
                }

                if !asset.prompt.isEmpty {
                    PanelSection(title: L("Prompt"), systemImage: "text.quote") {
                        Text(asset.prompt)
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if !asset.finalPrompt.isEmpty, asset.finalPrompt != asset.prompt {
                    DisclosureGroup(L("Prompt sent to the model")) {
                        Text(asset.finalPrompt)
                            .helperTextStyle()
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.callout)
                }

                PanelSection(title: L("Details"), systemImage: "info.circle") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                        row(L("Tool"), asset.appID.flatMap(VideoCatalog.tool)?.name ?? asset.tool.title)
                        if let appID = asset.appID, let item = AppCatalog.item(appID) { row(L("App"), item.name) }
                        if asset.tool != .imported {
                            row(L("AI model"), asset.modelDisplayName)
                            row(L("Provider"), asset.provider.displayName)
                        }
                        if let preset = asset.presetID.flatMap(StylePresets.preset) { row(L("Style"), preset.name) }
                        if let character = app.library.character(asset.characterID) { row(L("Character"), character.name) }
                        row(L("Size"), asset.pixelSizeLabel)
                        if asset.isVideo {
                            if let duration = asset.duration { row(L("Duration"), VideoPlayback.durationLabel(duration)) }
                            if let fps = asset.fps { row(L("Frame Rate"), L("%@ fps", fps.formatted(.number.precision(.fractionLength(0...2))))) }
                            if let hasAudio = asset.hasAudio { row(L("Sound"), hasAudio ? L("Yes") : L("No")) }
                            if let resolution = asset.videoResolution { row(L("Resolution"), resolution) }
                            if let parent = asset.parentAssetID.flatMap(app.library.asset) {
                                row(L("Made from"), parent.prompt.isEmpty ? L("A clip in the library") : parent.prompt)
                            }
                        }
                        if asset.aspectRatio != .auto { row(L("Aspect Ratio"), asset.aspectRatio.label) }
                        if let cost = asset.cost { row(L("Cost"), AppModel.money(cost, decimals: cost < 0.01 ? 4 : 3)) }
                        if let seed = asset.seed { row(L("Seed"), "\(seed)") }
                        row(L("Created"), asset.createdAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }

                if !asset.inputFileNames.isEmpty {
                    PanelSection(title: L("Input Images"), systemImage: "photo.stack") {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(asset.inputFileNames, id: \.self) { name in
                                    ThumbnailImage(url: app.library.inputURL(name), maxPixel: 200)
                                        .frame(width: 56, height: 56)
                                        .clipShape(.rect(cornerRadius: Radius.thumb))
                                }
                            }
                        }
                        .scrollIndicators(.never)
                    }
                }
                if let note = asset.modelNote, !note.isEmpty {
                    PanelSection(title: L("Model Note"), systemImage: "bubble.left") {
                        Text(note).helperTextStyle().textSelection(.enabled)
                    }
                }
            }
            .padding(16)
        }
        .onChange(of: asset.id) {
            savedFrame = nil
            showsSavedNote = false
        }
        .toolbar {
            ToolbarItem {
                Menu(L("Actions"), systemImage: "ellipsis.circle") { AssetMenu(assets: [asset]) }
            }
        }
    }

    private var quickActions: some View {
        let canReuse = !asset.prompt.isEmpty && asset.tool != .imported
        return Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                Button { app.open(.edit, with: asset) } label: {
                    actionLabel(L("Edit"), Tool.edit.systemImage)
                }
                Button { app.open(.upscale, with: asset) } label: {
                    actionLabel(Tool.upscale.title, Tool.upscale.systemImage)
                }
            }
            GridRow {
                Menu {
                    MakeVideoItems(asset: asset)
                } label: {
                    actionLabel(L("Make a Video") + " ▾", "video.badge.plus")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                Button { app.reuse(asset) } label: {
                    actionLabel(L("Reuse"), "arrow.counterclockwise")
                }
                .disabled(!canReuse)
                .help(canReuse ? L("Opens the tool with this image's description and settings")
                      : L("Only images made with a description can be reused"))
            }
        }
        .buttonStyle(.glass)
        .controlSize(.regular)
    }

    private func actionLabel(_ title: String, _ symbol: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.body)
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 36)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).groupTitleStyle().fixedSize()
            Text(value).font(.body).textSelection(.enabled).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var videoActions: some View {
        VideoFlowLayout(spacing: 6) {
            ForEach(VideoFollowUp.main) { tool in
                Button(tool.name, systemImage: tool.symbol) { app.openVideoTool(tool.id, with: asset) }
            }
        }
        .buttonStyle(.glass)
        .controlSize(.regular)
        FlowLayout(spacing: 6) {
            Button(L("Save Frame"), systemImage: "photo") { save(playhead.currentTime.map { .time($0) } ?? .poster) }
                .help(L("Saves the frame shown in the player to the library as an image"))
            Button(L("Save Last Frame"), systemImage: "photo.badge.checkmark") { save(.last) }
                .help(L("Saves the clip's final frame to the library as an image, e.g. to continue from it"))
            if savingFrame { ProgressView().controlSize(.small) }
        }
        .buttonStyle(.glass)
        .controlSize(.regular)
        .disabled(savingFrame)
        if let savedFrame, app.library.asset(savedFrame.id) != nil {
            HStack(spacing: 8) {
                ThumbnailImage(url: app.library.url(for: savedFrame), maxPixel: 120)
                    .frame(width: 36, height: 36)
                    .clipShape(.rect(cornerRadius: Radius.thumb))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        savedNote
                        Spacer(minLength: 4)
                        useFrameMenu(savedFrame)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        savedNote
                        useFrameMenu(savedFrame)
                    }
                }
            }
        }
    }

    private var savedNote: some View {
        Text(L("Saved to the library")).fineTextStyle()
            .fixedSize(horizontal: false, vertical: true)
    }

    private func useFrameMenu(_ savedFrame: Asset) -> some View {
        Menu(L("Use In"), systemImage: "arrow.up.forward.app") {
            Button(Tool.create.title, systemImage: Tool.create.systemImage) { app.useAsReference(savedFrame) }
            if let animate = VideoCatalog.tool("animateImage") {
                Button(animate.name, systemImage: animate.symbol) { app.useFrame(savedFrame, in: animate.id) }
            }
            Divider()
            ForEach(Tool.editingTools) { tool in
                Button(tool.title, systemImage: tool.systemImage) { app.open(tool, with: savedFrame) }
            }
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .controlSize(.small)
    }

    private func save(_ pick: VideoFramePick) {
        savingFrame = true
        Task {
            let saved = await app.saveVideoFrame(asset, at: pick)
            savingFrame = false
            if let saved {
                withAnimation(Motion.standard) { savedFrame = saved }
                showsSavedNote = true
            }
        }
    }
}

enum VideoFollowUp {
    static let mainIDs = ["extendVideo", "editVideo", "upscaleVideo", "reframeVideo"]

    static var main: [VideoTool] { mainIDs.compactMap(VideoCatalog.tool) }

    static var tools: [VideoTool] {
        main + VideoCatalog.all.filter { $0.takes(.sourceVideo) && !mainIDs.contains($0.id) }
    }
}

enum VideoFramePick {
    case time(CMTime)
    case poster
    case last
}

extension AppModel {
    @discardableResult
    func saveVideoFrame(_ asset: Asset, at pick: VideoFramePick) async -> Asset? {
        guard asset.isVideo else { return nil }
        let url = library.url(for: asset)
        do {
            let data: Data
            let label: String
            switch pick {
            case .time(let time):
                data = try await VideoMedia.frame(url, at: time)
                label = E("frame at %@", VideoPlayback.durationLabel(time.seconds))
            case .poster:
                let seconds = min(0.5, (asset.duration ?? 1) / 2)
                data = try await VideoMedia.frame(url, at: seconds)
                label = E("frame at %@", VideoPlayback.durationLabel(seconds))
            case .last:
                data = try await VideoMedia.lastFrame(url)
                label = E("last frame")
            }
            let base = asset.prompt.isEmpty ? E("Video") : String(asset.prompt.prefix(100))
            guard let image = library.importImage(data: data, name: "\(base) · \(label).jpg") else {
                throw VideoMediaError.frame
            }
            return image
        } catch {
            presentError(error)
            return nil
        }
    }

    func useFrame(_ image: Asset, in toolID: String) {
        guard let tool = VideoCatalog.tool(toolID), let data = library.imageData(for: image) else { return }
        videoState(for: tool).firstFrame = data
        openVideo(toolID)
    }
}

final class VideoPlayhead {
    weak var player: AVPlayer?

    var currentTime: CMTime? {
        guard let time = player?.currentTime(), time.isValid, time.isNumeric else { return nil }
        return time
    }
}

struct InspectorVideoPlayer: NSViewRepresentable {
    let url: URL
    let playhead: VideoPlayhead

    final class Coordinator {
        var url: URL?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.showsFrameSteppingButtons = true
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = true
        view.videoGravity = .resizeAspect
        load(into: view, context: context)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if context.coordinator.url != url { load(into: view, context: context) }
        playhead.player = view.player
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        view.player?.pause()
        view.player = nil
        coordinator.url = nil
    }

    private func load(into view: AVPlayerView, context: Context) {
        view.player?.pause()
        let player = AVPlayer(url: url)
        view.player = player
        context.coordinator.url = url
        playhead.player = player
    }
}

struct LibraryPicker: View {
    let multiple: Bool
    let onPick: ([Data]) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Group {
                if app.library.images.isEmpty {
                    ContentUnavailableView(L("The library is empty"), systemImage: "photo.on.rectangle",
                                           description: Text(L("Images you generate will appear here.")))
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                            ForEach(app.library.images) { asset in
                                ThumbnailImage(url: app.library.url(for: asset), maxPixel: 300)
                                    .frame(height: 110)
                                    .clipShape(.rect(cornerRadius: Radius.thumb))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: Radius.thumb)
                                            .strokeBorder(selection.contains(asset.id) ? Color.appAccent : .clear, lineWidth: 3)
                                    }
                                    .overlay(alignment: .topTrailing) {
                                        if selection.contains(asset.id) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, Color.appAccent)
                                                .padding(5)
                                        }
                                    }
                                    .contentShape(.rect)
                                    .onTapGesture { toggle(asset.id) }
                                    .onTapGesture(count: 2) {
                                        selection = [asset.id]
                                        confirm()
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(multiple ? L("Choose Images") : L("Choose Image"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(multiple && selection.count > 1 ? L("Use %ld", selection.count) : L("Use"), action: confirm)
                        .disabled(selection.isEmpty)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 460)
    }

    private func toggle(_ id: UUID) {
        if multiple {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else {
            selection = [id]
        }
    }

    private func confirm() {
        let picked = app.library.images
            .filter { selection.contains($0.id) }
            .compactMap { app.library.imageData(for: $0) }
        onPick(picked)
        dismiss()
    }
}
