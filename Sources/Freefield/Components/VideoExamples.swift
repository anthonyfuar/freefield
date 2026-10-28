import FreefieldCore
import SwiftUI

extension Examples {
    struct VideoToolExample {
        var before: URL?
        var beforeIsVideo = false
        var after: [URL]
        var extra: URL?
        var poster: URL?
    }

    private static func videoFile(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Examples/video")
    }

    private static let beforeAliases = [
        "editVideo": "dancer-source", "motionTransfer": "dancer-source", "reframeVideo": "createVideo-after",
        "swapVideo": "cinemaStudio-after", "upscaleVideo": "animateImage-after", "extendVideo": "animateImage-after",
        "joinClips": "animateImage-after",
    ]

    static func videoPoster(for clip: URL) -> URL? {
        let name = clip.deletingPathExtension().lastPathComponent
        guard name.hasSuffix("-after") else { return nil }
        return videoFile(String(name.dropLast("-after".count)) + "-poster", "heic")
    }

    static func video(_ id: String) -> VideoToolExample? {
        let gallery = (1...3).compactMap { videoFile("\(id)-after\($0)", "mp4") }
        let after = [videoFile("\(id)-after", "mp4")].compactMap(\.self) + gallery
        guard !after.isEmpty else { return nil }
        let beforeClip = videoFile("\(id)-before", "mp4") ?? beforeAliases[id].flatMap { videoFile($0, "mp4") }
        return VideoToolExample(before: beforeClip ?? videoFile("\(id)-before", "heic"), beforeIsVideo: beforeClip != nil,
                                after: after, extra: videoFile("\(id)-extra", "heic"), poster: videoFile("\(id)-poster", "heic"))
    }
}

struct VideoExample: View {
    let tool: VideoTool
    var mediaHeight: CGFloat = 260
    var foldsSteps = false

    @State private var media: [URL: ExampleMedia] = [:]
    @State private var showsSteps = false

    init(tool: VideoTool, mediaHeight: CGFloat = 260, foldsSteps: Bool = false) {
        self.tool = tool
        self.mediaHeight = mediaHeight
        self.foldsSteps = foldsSteps
    }

    init(toolID: String) {
        tool = VideoCatalog.tool(toolID) ?? VideoTool(id: toolID, name: "", subtitle: "", symbol: "film", section: .create,
                                                      inputs: [], steps: [])
    }

    var body: some View {
        if let example = Examples.video(tool.id) {
            ExampleCardLayout(minimumMediaHeight: min(170, mediaHeight)) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L("Real example"), systemImage: "checkmark.seal")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ExampleMediaRow(spacing: 10, maxHeight: mediaHeight, minTileWidth: 100) {
                        ForEach(inputs(example), id: \.url) { input in
                            tile(input.url, isVideo: input.isVideo, poster: input.poster, title: input.title, isResult: false)
                        }
                        if example.before != nil || example.extra != nil {
                            Image(systemName: "arrow.right").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        ForEach(Array(example.after.enumerated()), id: \.offset) { index, url in
                            tile(url, isVideo: true, poster: index == 0 ? example.poster : nil, title: L("Result"), isResult: true,
                                 shapeFrom: example.poster)
                        }
                    }
                    .animation(Motion.standard, value: media.count)
                }
                if foldsSteps, !showsSteps {
                    Button(L("How it works"), systemImage: "list.number") {
                        withAnimation(Motion.standard) { showsSteps = true }
                    }
                    .buttonStyle(.glass)
                    .fixedSize()
                } else {
                    steps
                }
            }
            .task(id: tool.id) { await load(example) }
        } else if !tool.steps.isEmpty {
            steps
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.035), in: .rect(cornerRadius: Radius.card))
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("How it works")).sectionTitleStyle()
            VideoColumns(minimum: 260, maximum: 420, spacing: 18, rowSpacing: 10) {
                ForEach(Array(tool.steps.enumerated()), id: \.offset) { index, text in
                    ExampleStep(number: index + 1, text: text)
                }
            }
        }
    }

    private struct Input {
        let url: URL
        let isVideo: Bool
        var poster: URL?
        let title: String
    }

    private func inputs(_ example: Examples.VideoToolExample) -> [Input] {
        var inputs: [Input] = []
        if let before = example.before {
            inputs.append(Input(url: before, isVideo: example.beforeIsVideo,
                                poster: example.beforeIsVideo ? Examples.videoPoster(for: before) : nil, title: inputTitle))
        }
        if let extra = example.extra { inputs.append(Input(url: extra, isVideo: false, title: extraTitle)) }
        return tool.takes(.drivingVideo) ? inputs.reversed() : inputs
    }

    private func tile(_ url: URL, isVideo: Bool, poster: URL?, title: String, isResult: Bool, shapeFrom still: URL? = nil) -> some View {
        let info = media[url]
        return Group {
            if isVideo {
                LoopingVideo(url: url, posterURL: poster, offersSound: isResult && info?.hasAudio == true)
            } else {
                ThumbnailImage(url: url, maxPixel: 900, contentMode: .fit)
            }
        }
        .background(Color.primary.opacity(0.05))
        .clipShape(.rect(cornerRadius: Radius.tile))
        .overlay(alignment: .bottomLeading) {
            Text(title).font(.callout.weight(.semibold))
                .lineLimit(2).minimumScaleFactor(0.7)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .glassEffect(in: .capsule).padding(6)
        }
        .layoutValue(key: ExampleMediaAspect.self,
                     value: info?.aspect ?? ExampleMedia.stillAspect(isVideo ? (still ?? poster) : url) ?? (isVideo ? 16.0 / 9 : 1))
    }

    private func load(_ example: Examples.VideoToolExample) async {
        var found: [URL: ExampleMedia] = [:]
        if let before = example.before { found[before] = await ExampleMedia.read(before, isVideo: example.beforeIsVideo) }
        if let extra = example.extra { found[extra] = await ExampleMedia.read(extra, isVideo: false) }
        for url in example.after { found[url] = await ExampleMedia.read(url, isVideo: true) }
        media = found
    }

    private var inputTitle: String {
        switch tool.id {
        case "storyboardVideo": return L("Image 1")
        case "talkingAvatar": return L("Photo")
        default: break
        }
        if tool.takes(.sourceVideo) { return L("Original") }
        if tool.takes(.product), !tool.takes(.firstFrame) || tool.section == .ad { return L("Product") }
        if tool.takes(.drivingVideo) { return L("Motion") }
        if tool.takes(.firstFrame), tool.takes(.lastFrame) { return L("Start image") }
        if tool.takes(.firstFrame) { return L("Image") }
        if tool.takes(.character) { return L("Character") }
        return L("Input")
    }

    private var extraTitle: String {
        if tool.id == "storyboardVideo" { return L("Image 2") }
        if tool.takes(.drivingVideo) { return L("Character") }
        if tool.takes(.lastFrame) { return L("End image") }
        if tool.takes(.character) { return L("Person") }
        return L("Second input")
    }
}

struct ExampleCardLayout: Layout {
    var spacing: CGFloat = 18
    var steps: ClosedRange<CGFloat> = 240...420
    var minimumMediaHeight: CGFloat = 170
    var stepsTopInset: CGFloat = 24

    private struct Arrangement {
        var sideBySide: Bool
        var media: CGSize
        var steps: CGSize
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 900
        let parts = arrange(width: width, subviews: subviews)
        if parts.sideBySide {
            return CGSize(width: parts.media.width + spacing + parts.steps.width,
                          height: max(parts.media.height, stepsTopInset + parts.steps.height))
        }
        return CGSize(width: max(parts.media.width, parts.steps.width), height: parts.media.height + spacing + parts.steps.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let parts = arrange(width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? bounds.width, subviews: subviews)
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(parts.media))
        let origin = parts.sideBySide
            ? CGPoint(x: bounds.minX + parts.media.width + spacing, y: bounds.minY + stepsTopInset)
            : CGPoint(x: bounds.minX, y: bounds.minY + parts.media.height + spacing)
        subviews[1].place(at: origin, anchor: .topLeading, proposal: ProposedViewSize(width: parts.steps.width, height: nil))
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> Arrangement {
        let media = subviews[0], steps = subviews[1]
        let besideMedia = media.sizeThatFits(ProposedViewSize(width: max(0, width - spacing - self.steps.lowerBound), height: nil))
        let stepsWidth = min(self.steps.upperBound, max(self.steps.lowerBound, width - spacing - besideMedia.width))
        let besideSteps = steps.sizeThatFits(ProposedViewSize(width: stepsWidth, height: nil))
        if besideMedia.height >= minimumMediaHeight, stepsTopInset + besideSteps.height <= besideMedia.height + 80 {
            return Arrangement(sideBySide: true, media: besideMedia, steps: CGSize(width: stepsWidth, height: besideSteps.height))
        }
        let fullMedia = media.sizeThatFits(ProposedViewSize(width: width, height: nil))
        let underSteps = steps.sizeThatFits(ProposedViewSize(width: width, height: nil))
        return Arrangement(sideBySide: false, media: fullMedia, steps: CGSize(width: min(width, underSteps.width), height: underSteps.height))
    }
}

struct ExampleMedia {
    var aspect: Double
    var hasAudio = false

    private static var cache: [URL: ExampleMedia] = [:]
    private static var stills: [URL: Double] = [:]

    static func stillAspect(_ url: URL?) -> Double? {
        guard let url else { return nil }
        if let known = stills[url] { return known }
        guard let size = ImageCoding.pixelSize(at: url), size.width > 0, size.height > 0 else { return nil }
        stills[url] = size.width / size.height
        return stills[url]
    }

    static func read(_ url: URL, isVideo: Bool) async -> ExampleMedia {
        if let known = cache[url] { return known }
        var media = ExampleMedia(aspect: isVideo ? 16.0 / 9 : 1)
        if isVideo {
            if let info = try? await VideoMedia.probe(url), info.size.width > 0 {
                media = ExampleMedia(aspect: info.aspect, hasAudio: info.hasAudio)
            }
        } else if let image = await Thumbnails.load(url, maxPixel: 900), image.size.height > 0 {
            media.aspect = image.size.width / image.size.height
        }
        cache[url] = media
        return media
    }
}

nonisolated struct ExampleMediaAspect: LayoutValueKey {
    static let defaultValue: Double? = nil
}

struct ExampleMediaRow: Layout {
    var spacing: CGFloat = 10
    var maxHeight: CGFloat = 260
    var minTileWidth: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = rowHeight(width: proposal.width, subviews: subviews)
        return CGSize(width: width(at: height, subviews: subviews), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let height = rowHeight(width: bounds.width, subviews: subviews)
        var x = bounds.minX
        for subview in subviews {
            let size = size(of: subview, height: height)
            subview.place(at: CGPoint(x: x, y: bounds.minY + (height - size.height) / 2), proposal: ProposedViewSize(size))
            x += size.width + spacing
        }
    }

    private func size(of subview: LayoutSubview, height: CGFloat) -> CGSize {
        if let aspect = subview[ExampleMediaAspect.self] { return CGSize(width: max(minTileWidth, height * aspect), height: height) }
        return subview.sizeThatFits(.unspecified)
    }

    private func width(at height: CGFloat, subviews: Subviews) -> CGFloat {
        let widths = subviews.map { size(of: $0, height: height).width }
        return widths.reduce(0, +) + spacing * CGFloat(max(0, subviews.count - 1))
    }

    private func rowHeight(width: CGFloat?, subviews: Subviews) -> CGFloat {
        guard let width, width.isFinite else { return maxHeight }
        let aspects = subviews.compactMap { $0[ExampleMediaAspect.self] }
        guard aspects.reduce(0, +) > 0 else { return maxHeight }
        let fixed = subviews.filter { $0[ExampleMediaAspect.self] == nil }.map { $0.sizeThatFits(.unspecified).width }.reduce(0, +)
        let room = width - fixed - spacing * CGFloat(max(0, subviews.count - 1))
        var height = min(maxHeight, room / aspects.reduce(0, +))
        for _ in aspects.indices {
            let held = aspects.filter { $0 * height < minTileWidth }
            let free = aspects.filter { $0 * height >= minTileWidth }.reduce(0, +)
            guard !held.isEmpty, free > 0 else { break }
            let next = min(maxHeight, (room - CGFloat(held.count) * minTileWidth) / free)
            if abs(next - height) < 0.5 { break }
            height = next
        }
        return max(80, height)
    }
}
