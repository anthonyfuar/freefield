import AVFoundation
import AVKit
import AppKit
import SwiftUI

@Observable
final class VideoPreviewCoordinator {
    static let shared = VideoPreviewCoordinator()

    private(set) var activeID: UUID?

    func activate(_ id: UUID) { activeID = id }

    func deactivate(_ id: UUID) {
        if activeID == id { activeID = nil }
    }
}

enum VideoPlayback {
    static func allowsMotion(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    static func durationLabel(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600, minutes = total / 60 % 60, rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    static func accessibilityLabel(duration: Double?, hasAudio: Bool?) -> String {
        var parts = [L("Video")]
        if let duration { parts.append(durationLabel(duration)) }
        if hasAudio == true { parts.append(L("with sound")) }
        return parts.joined(separator: ", ")
    }

    static func aspect(of url: URL) async -> Double? {
        if let known = aspects[url] { return known }
        guard let info = try? await VideoMedia.probe(url), info.size.width > 0, info.size.height > 0 else { return nil }
        aspects[url] = info.aspect
        return info.aspect
    }

    private static var aspects: [URL: Double] = [:]
}

struct VideoTile: View {
    let url: URL
    var posterURL: URL?
    var duration: Double?
    var hasAudio: Bool?
    var isSelected = false
    var maxPixel = 640
    var cornerRadius: CGFloat = Radius.tile
    var focus: UnitPoint = .center
    var aspect: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tileID = UUID()
    @State private var isHovering = false
    @State private var loadedAspect: Double?

    private var coordinator: VideoPreviewCoordinator { .shared }

    var body: some View {
        let isPlaying = coordinator.activeID == tileID
        VideoPoster(url: url, posterURL: posterURL, maxPixel: maxPixel, contentMode: .fill, focus: focus)
            .overlay {
                if isPlaying {
                    player
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(isSelected ? Color.appAccent : .primary.opacity(0.06), lineWidth: isSelected ? 3 : 1)
            }
            .overlay(alignment: .bottomTrailing) {
                VideoBadge(duration: duration, hasAudio: hasAudio).padding(6)
            }
            .onHover { hovering in isHovering = hovering }
            .task(id: isHovering) {
                guard isHovering, VideoPlayback.allowsMotion(reduceMotion: reduceMotion) else {
                    withAnimation(Motion.fade) { coordinator.deactivate(tileID) }
                    return
                }
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled, isHovering else { return }
                if focus != .center, aspect == nil, loadedAspect == nil { loadedAspect = await VideoPlayback.aspect(of: url) }
                guard !Task.isCancelled, isHovering else { return }
                withAnimation(Motion.fade) { coordinator.activate(tileID) }
            }
            .onScrollVisibilityChange(threshold: 0.2) { visible in
                if !visible { coordinator.deactivate(tileID) }
            }
            .onDisappear { coordinator.deactivate(tileID) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(VideoPlayback.accessibilityLabel(duration: duration, hasAudio: hasAudio)))
            .accessibilityAddTraits(.isImage)
    }

    @ViewBuilder private var player: some View {
        if focus != .center, let shape = aspect ?? loadedAspect {
            FocusedFill(aspect: shape, focus: focus) {
                LoopingPlayerLayer(url: url, gravity: .resizeAspect)
            }
        } else {
            LoopingPlayerLayer(url: url, gravity: .resizeAspectFill)
        }
    }
}

struct VideoBadge: View {
    var duration: Double?
    var hasAudio: Bool?

    var body: some View {
        HStack(spacing: 4) {
            if hasAudio == true {
                Image(systemName: "speaker.wave.2.fill").help(L("Has sound"))
            }
            if let duration {
                Text(VideoPlayback.durationLabel(duration)).monospacedDigit()
            } else if hasAudio != true {
                Image(systemName: "play.fill")
            }
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .glassEffect(in: .capsule)
    }
}

struct VideoPoster: View {
    let url: URL
    var posterURL: URL?
    var maxPixel = 640
    var contentMode: ContentMode = .fill
    var focus: UnitPoint = .center

    @State private var generated: Data?

    var body: some View {
        if let posterURL {
            ThumbnailImage(url: posterURL, maxPixel: maxPixel, contentMode: contentMode, focus: focus)
        } else {
            Group {
                if let generated {
                    DataImage(data: generated, maxPixel: maxPixel, contentMode: contentMode, focus: focus)
                } else {
                    Rectangle().fill(.quaternary.opacity(0.5))
                        .overlay { Image(systemName: "film").font(.title2).foregroundStyle(.tertiary) }
                }
            }
            .task(id: "\(url.path)#\(maxPixel)") {
                generated = await Self.poster(for: url, maxPixel: maxPixel)
            }
        }
    }

    private static let cache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 200
        return cache
    }()

    private static func poster(for url: URL, maxPixel: Int) async -> Data? {
        let key = "\(url.path)#\(maxPixel)" as NSString
        if let hit = cache.object(forKey: key) { return hit as Data }
        guard let data = try? await VideoMedia.poster(url, maxPixel: maxPixel) else { return nil }
        cache.setObject(data as NSData, forKey: key)
        return data
    }
}

struct LoopingVideo: View {
    let url: URL
    var posterURL: URL?
    var gravity: AVLayerVideoGravity = .resizeAspect
    var offersSound = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playsOnRequest = false
    @State private var isOnScreen = true
    @State private var isMuted = true

    var body: some View {
        let autoplay = VideoPlayback.allowsMotion(reduceMotion: reduceMotion)
        let isPlaying = (autoplay || playsOnRequest) && isOnScreen
        ZStack {
            VideoPoster(url: url, posterURL: posterURL, maxPixel: 1200, contentMode: gravity == .resizeAspectFill ? .fill : .fit)
            if isPlaying {
                LoopingPlayerLayer(url: url, gravity: gravity, isMuted: isMuted).allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if offersSound, isPlaying {
                Button {
                    isMuted.toggle()
                } label: {
                    Label(isMuted ? L("Turn sound on") : L("Mute"), systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .labelStyle(.iconOnly)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .padding(8)
                .help(isMuted ? L("Turn sound on") : L("Mute"))
            }
        }
        .overlay(alignment: playsOnRequest ? .bottomTrailing : .center) {
            if !autoplay {
                Button {
                    playsOnRequest.toggle()
                } label: {
                    Label(playsOnRequest ? L("Pause") : L("Play"), systemImage: playsOnRequest ? "pause.fill" : "play.fill")
                        .labelStyle(.iconOnly)
                        .frame(width: playsOnRequest ? 16 : 28, height: playsOnRequest ? 16 : 28)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(playsOnRequest ? .small : .large)
                .padding(playsOnRequest ? 8 : 0)
                .help(playsOnRequest ? L("Pause") : L("Play example"))
            }
        }
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        .onScrollVisibilityChange(threshold: 0.1) { visible in isOnScreen = visible }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(L("Example video")))
    }
}

struct LoopingPlayerLayer: NSViewRepresentable {
    let url: URL
    var gravity: AVLayerVideoGravity = .resizeAspectFill
    var isMuted = true

    func makeNSView(context: Context) -> LoopingPlayerNSView {
        let view = LoopingPlayerNSView()
        view.videoGravity = gravity
        view.load(url)
        view.isMuted = isMuted
        return view
    }

    func updateNSView(_ view: LoopingPlayerNSView, context: Context) {
        view.videoGravity = gravity
        view.load(url)
        view.isMuted = isMuted
    }

    static func dismantleNSView(_ view: LoopingPlayerNSView, coordinator: ()) {
        view.stop()
    }
}

final class LoopingPlayerNSView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var url: URL?

    var isMuted = true {
        didSet { player?.isMuted = isMuted }
    }
    private weak var observedWindow: NSWindow?

    var videoGravity: AVLayerVideoGravity {
        get { playerLayer.videoGravity }
        set { if playerLayer.videoGravity != newValue { playerLayer.videoGravity = newValue } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        playerLayer.backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func makeBackingLayer() -> CALayer { playerLayer }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func load(_ url: URL) {
        guard url != self.url else { return }
        stop()
        self.url = url
        let player = AVQueuePlayer()
        player.isMuted = isMuted
        player.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        playerLayer.player = player
        self.player = player
        updatePlayback()
    }

    func stop() {
        looper?.disableLooping()
        player?.pause()
        player?.removeAllItems()
        playerLayer.player = nil
        looper = nil
        player = nil
        url = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let center = NotificationCenter.default
        if let observedWindow {
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didChangeOcclusionStateNotification] {
                center.removeObserver(self, name: name, object: observedWindow)
            }
        }
        observedWindow = window
        if let window {
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didChangeOcclusionStateNotification] {
                center.addObserver(self, selector: #selector(windowStateChanged), name: name, object: window)
            }
        }
        updatePlayback()
    }

    @objc private func windowStateChanged(_ notification: Notification) {
        updatePlayback()
    }

    private func updatePlayback() {
        guard let player else { return }
        if let window, window.isKeyWindow, window.occlusionState.contains(.visible) {
            player.play()
        } else {
            player.pause()
        }
    }
}

struct VideoPlayerView: NSViewRepresentable {
    let url: URL
    var autoplay = true
    var loops = false

    final class Coordinator {
        var url: URL?
        var looper: AVPlayerLooper?
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
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        coordinator.looper?.disableLooping()
        view.player?.pause()
        view.player = nil
        coordinator.looper = nil
        coordinator.url = nil
    }

    private func load(into view: AVPlayerView, context: Context) {
        let coordinator = context.coordinator
        coordinator.looper?.disableLooping()
        coordinator.looper = nil
        view.player?.pause()
        let player: AVPlayer
        if loops {
            let queue = AVQueuePlayer()
            coordinator.looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
            player = queue
        } else {
            player = AVPlayer(url: url)
        }
        view.player = player
        coordinator.url = url
        if autoplay, VideoPlayback.allowsMotion(reduceMotion: context.environment.accessibilityReduceMotion) {
            player.play()
        }
    }
}
