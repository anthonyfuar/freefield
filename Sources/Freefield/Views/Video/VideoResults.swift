import FreefieldCore
import SwiftUI

struct VideoResults: View {
    let tool: VideoTool
    let state: VideoState
    @Binding var selectedID: UUID?
    var record: String?

    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var morph

    var body: some View {
        let jobs = app.engine.jobs.filter { job in
            let belongs = job.videoSpec?.toolID == tool.id || (job.videoSpec == nil && job.tool == .video && job.spec?.appID == tool.id)
            let matches = record == nil || job.videoSpec.map { $0.record == record } ?? true
            return belongs && matches && (job.isRunning || Self.hasFailed(job))
        }
        let clips = app.library.assets.filter { $0.isVideo && $0.appID == tool.id && matches($0) }
        let work = state.localWork
        let morphIDs = reduceMotion ? [:] : Self.morphIDs(clips: clips, jobs: jobs)
        if !jobs.isEmpty || !clips.isEmpty || !work.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L("Results")).groupTitleStyle()
                    Spacer()
                    if !clips.isEmpty {
                        Text(clips.count == 1 ? L("1 clip") : L("%ld clips", clips.count))
                            .fineTextStyle()
                            .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(clips.count)))
                            .animation(Motion.standard, value: clips.count)
                    }
                }
                if let selected = selectedID.flatMap(app.library.asset), selected.isVideo, selected.appID == tool.id, matches(selected) {
                    VideoResultDetail(asset: selected) { selectedID = nil }
                        .transition(Motion.transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top))))
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(work) { item in
                        VideoLocalWorkCard(work: item) { state.localWork.removeAll { $0.id == item.id } }
                            .frame(height: 210)
                    }
                    ForEach(jobs) { job in
                        VideoJobCard(job: job, tool: tool, state: state)
                            .frame(height: 210)
                            .matchedGeometryEffect(id: reduceMotion ? job.id.uuidString : job.remoteID ?? job.id.uuidString, in: morph)
                            .transition(Motion.transition(AnyTransition(.blurReplace)))
                    }
                    ForEach(clips) { asset in
                        AssetCard(asset: asset, isSelected: selectedID == asset.id, maxPixel: 600)
                            .frame(height: 210)
                            .matchedGeometryEffect(id: morphIDs[asset.id] ?? asset.id.uuidString, in: morph)
                            .transition(Motion.transition(AnyTransition(.blurReplace)))
                            .onTapGesture { withAnimation(Motion.emphasized) { selectedID = selectedID == asset.id ? nil : asset.id } }
                            .onTapGesture(count: 2) { app.quickLook(asset) }
                    }
                }
                .animation(Motion.standard, value: work.map(\.id) + jobs.map(\.id) + clips.map(\.id))
            }
            .onChange(of: clips.first?.id) { _, newest in
                if let newest { withAnimation(Motion.emphasized) { selectedID = newest } }
            }
        }
    }

    private static func morphIDs(clips: [Asset], jobs: [Job]) -> [UUID: String] {
        let shown = Set(jobs.compactMap(\.remoteID))
        var taken = Set<String>()
        var ids: [UUID: String] = [:]
        for clip in clips {
            guard let remoteID = clip.remoteJobID, !shown.contains(remoteID), taken.insert(remoteID).inserted else { continue }
            ids[clip.id] = remoteID
        }
        return ids
    }

    private func matches(_ asset: Asset) -> Bool {
        guard let record else { return true }
        return asset.prompt == record || asset.prompt.hasPrefix(record + " · ")
    }

    static func hasFailed(_ job: Job) -> Bool {
        if case .failed = job.status { return true }
        return false
    }

    static let anchor = "results"

    static func hasClips(in app: AppModel, toolID: String, record: String? = nil) -> Bool {
        app.library.assets.contains { asset in
            asset.isVideo && asset.appID == toolID && (record == nil || asset.prompt == record || asset.prompt.hasPrefix((record ?? "") + " · "))
        }
    }

    static func activeCount(in app: AppModel, tool: VideoTool, state: VideoState) -> Int {
        let jobs = app.engine.jobs.filter { job in
            job.isRunning && (job.videoSpec?.toolID == tool.id || (job.videoSpec == nil && job.tool == .video && job.spec?.appID == tool.id))
        }
        return jobs.count + state.localWork.count(where: \.isRunning)
    }
}

struct VideoResultDetail: View {
    let asset: Asset
    let onClose: () -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VideoPlayerView(url: app.library.url(for: asset), autoplay: false)
                .aspectRatio(asset.aspect > 0 ? asset.aspect : 16.0 / 9, contentMode: .fit)
                .frame(maxWidth: 520, maxHeight: 320)
                .clipShape(.rect(cornerRadius: Radius.tile))
            VStack(alignment: .leading, spacing: 8) {
                Text(Self.title(of: asset)).font(.callout.weight(.semibold)).lineLimit(3)
                Text([asset.modelDisplayName, asset.duration.map(VideoPlayback.durationLabel), asset.width > 0 ? asset.pixelSizeLabel : nil,
                      asset.cost.map { AppModel.money($0, decimals: 3) }].compactMap(\.self).joined(separator: " · "))
                    .fineTextStyle()
                if !asset.finalPrompt.isEmpty {
                    DisclosureGroup(L("See the instructions Freefield sent")) {
                        Text(asset.finalPrompt)
                            .font(.subheadline.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                    .font(.subheadline)
                }
                Divider()
                Text(L("Continue with")).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                VideoFlowLayout(spacing: 6) {
                    ForEach(["extendVideo", "editVideo", "upscaleVideo", "reframeVideo"], id: \.self) { id in
                        if let tool = VideoCatalog.tool(id) {
                            Button(tool.name, systemImage: tool.symbol) { app.openVideoTool(id, with: asset) }
                        }
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                HStack(spacing: 6) {
                    Button(L("Quick Look"), systemImage: "eye") { app.quickLook(asset) }
                    Menu(L("More"), systemImage: "ellipsis") { AssetMenu(assets: [asset]) }
                        .menuIndicator(.hidden)
                        .fixedSize()
                    Spacer()
                    Button(L("Close"), action: onClose)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
            .frame(maxWidth: 360, alignment: .leading)
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: .rect(cornerRadius: Radius.card))
    }

    static func title(of asset: Asset) -> String {
        asset.prompt.components(separatedBy: " · ").map { L($0) }.joined(separator: " · ")
    }
}

struct VideoJobCard: View {
    let job: Job
    let tool: VideoTool
    let state: VideoState

    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(job.title).font(.callout.weight(.semibold)).lineLimit(2)
            }
            if job.isRunning {
                running
            } else if case .failed(let message) = job.status {
                failed(message)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background, in: .rect(cornerRadius: Radius.tile))
        .overlay(RoundedRectangle(cornerRadius: Radius.tile).strokeBorder(tint.opacity(0.25)))
    }

    private var isStill: Bool { job.videoSpec == nil }

    private var icon: String {
        if job.isStillAtProvider { return "hourglass" }
        if VideoResults.hasFailed(job) { return "exclamationmark.triangle.fill" }
        return isStill ? "photo" : "film"
    }

    private var tint: Color {
        if job.isStillAtProvider { return .orange }
        return VideoResults.hasFailed(job) ? .orange : .brand
    }

    private var background: Color {
        VideoResults.hasFailed(job) && !job.isStillAtProvider ? Color.red.opacity(0.07) : Color.primary.opacity(0.04)
    }

    @ViewBuilder private var running: some View {
        ProgressView().progressViewStyle(.linear)
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(L("%@ so far", Self.elapsed(since: job.submittedAt ?? job.createdAt, now: context.date)))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        Text(phase).fineTextStyle()
        if app.clipSharing.isSharing(for: job.id) {
            Label(L("Sharing the clip from this Mac"), systemImage: "lock.shield")
                .fineTextStyle()
                .help(L("A temporary link to this Mac, closed as soon as the provider has the file."))
        }
        if let model = job.videoSpec?.request.model {
            Text(VideoWaitTimes.label(for: model)).fineTextStyle()
        } else {
            Text(L("Then the video starts from it.")).fineTextStyle()
        }
        HStack {
            if isStill {
                Button(L("Stop")) { app.engine.cancel(job) }
            } else if job.remoteID != nil || job.isSendingVideo {
                Button(L("Stop waiting")) { app.engine.stopWaiting(job) }
                    .help(L("The provider may still finish and bill this video. It's added to the library when it arrives."))
            } else {
                Button(L("Cancel")) { app.engine.cancel(job) }
            }
        }
        .controlSize(.small)
    }

    private var phase: String {
        if isStill { return L("Making the image the video starts from…") }
        switch job.videoPhase {
        case .submitting: return job.isSendingVideo ? L("Sending to the provider…") : L("Getting ready…")
        case .waiting: return job.remoteState == .inProgress ? L("Rendering at the provider…") : L("Queued at the provider…")
        case .downloading: return L("Downloading…")
        case .stillAtProvider, nil: return ""
        }
    }

    @ViewBuilder private func failed(_ message: String) -> some View {
        Text(message)
            .fineTextStyle()
            .lineLimit(6)
            .textSelection(.enabled)
        VideoFlowLayout(spacing: 6) {
            if job.isStillAtProvider {
                Button(L("Check again")) { app.engine.checkAgain(job) }
                    .help(L("Ask the provider again; the video is added to the library when it's ready."))
            } else if !isStill {
                if let fallback = app.capacityFallback(for: job, tool: tool, state: state) {
                    let name = VideoLineup.displayName(for: fallback.id, fallback: fallback.name)
                    Button(L("Try with %@", name)) {
                        app.retryVideo(job, with: fallback, tool: tool, state: state)
                    }
                    .help(L("Try with %@", name))
                }
                Button(L("Retry")) { app.engine.retry(job) }
                    .help(L("Sends the same request again; it's billed again."))
            }
            Button(L("Close")) { app.engine.dismiss(job) }
        }
        .controlSize(.small)
    }

    static func elapsed(since start: Date, now: Date) -> String {
        VideoPlayback.durationLabel(max(0, now.timeIntervalSince(start)))
    }
}

struct VideoLocalWorkCard: View {
    let work: VideoLocalWork
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: work.failure == nil ? "desktopcomputer" : "exclamationmark.triangle.fill")
                    .foregroundStyle(work.failure == nil ? Color.brand : .orange)
                Text(work.title).font(.callout.weight(.semibold)).lineLimit(2)
            }
            if let failure = work.failure {
                Text(failure).fineTextStyle().lineLimit(6).textSelection(.enabled)
                Button(L("Close"), action: onClose).controlSize(.small)
            } else {
                ProgressView().progressViewStyle(.linear)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(L("%@ so far", VideoJobCard.elapsed(since: work.startedAt, now: context.date)))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(work.step ?? L("On this Mac, free")).fineTextStyle()
                if work.task != nil {
                    Button(L("Cancel")) { work.task?.cancel() }.controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(work.failure == nil ? Color.primary.opacity(0.04) : Color.red.opacity(0.07), in: .rect(cornerRadius: Radius.tile))
    }
}

enum VideoWaitTimes {
    static func typical(for model: VideoModel) -> ClosedRange<Int>? {
        let slug = model.id.lowercased()
        switch VideoFamily(slug: slug) {
        case .grok: return nil
        case .seedance: return slug.contains("2.5") ? 2...5 : 1...3
        case .veo: return 1...3
        case .kling, .hailuo, .runway: return 2...5
        case .wan, .flux, .heygen: return 2...6
        default: return 2...5
        }
    }

    static func label(for model: VideoModel) -> String {
        guard let range = typical(for: model) else { return L("Usually under a minute") }
        return L("Usually %ld–%ld min", range.lowerBound, range.upperBound)
    }
}

struct VideoFlowLayout: Layout {
    var spacing: CGFloat = 8
    var centersInRow = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let widest = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for (index, size) in zip(row.indices, row.sizes) {
                let top = centersInRow ? y + (row.height - size.height) / 2 : y
                subviews[index].place(at: CGPoint(x: x, y: top), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var sizes: [CGSize] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let natural = subviews[index].sizeThatFits(.unspecified)
            var size = natural
            if natural.width > width {
                size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
                size.width = min(size.width, width)
            }
            var row = rows[rows.count - 1]
            if !row.indices.isEmpty, row.width + spacing + size.width > width {
                rows.append(Row())
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            row.sizes.append(size)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
