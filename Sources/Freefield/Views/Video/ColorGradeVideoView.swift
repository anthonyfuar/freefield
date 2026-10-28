import FreefieldCore
import SwiftUI

struct ColorGradeVideoView: View {
    let tool: VideoTool

    @Environment(AppModel.self) private var app
    @State private var frame: Data?
    @State private var previews: [String: URL] = [:]
    @State private var large: URL?
    @State private var showsOriginal = false
    @State private var showsPalettes = false

    var body: some View {
        let state = app.videoState(for: tool)
        let source = state.source.assetID.flatMap(app.library.asset).flatMap { $0.isVideo ? $0 : nil }
        let look = state.choice("look", in: tool)
        let strength = state.choice("strength", in: tool)
        VideoToolScreen(tool: tool, state: state) {
            HStack(alignment: .top, spacing: 16) {
                clip(state, isDone: source != nil)
                    .frame(maxWidth: source == nil ? VideoLayout.singleInputWidth : 420)
                if let source {
                    preview(source)
                        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 300)
                }
            }
            looks(state, source: source, selection: look)
            strengths(state, isDone: source != nil)
        } bar: {
            bar(state, source: source)
        }
        .task(id: source?.id) {
            frame = nil
            previews = [:]
            large = nil
            guard let source else { return }
            let url = app.library.url(for: source)
            let at = min(1.0, max(0, (source.duration ?? 2) / 3))
            frame = try? await VideoMedia.frame(url, at: at, maxPixel: 1200)
        }
        .task(id: "\(source?.id.uuidString ?? "-")|\(strength)|\(frame?.count ?? 0)") {
            guard let frame, let source else { return }
            let folder = Self.folder(source.id)
            let plans = VideoGradeLooks.all.map { ($0.id, VideoGradeLooks.plan(look: $0.id, strength: strength)) }
            let found = await VideoGrade.previews(frame: frame, plans: plans, strength: strength, folder: folder, maxPixel: 360)
            guard !Task.isCancelled else { return }
            previews = found
        }
        .task(id: "\(source?.id.uuidString ?? "-")|\(look)|\(strength)|\(frame?.count ?? 0)") {
            guard let frame, let source else { return }
            let plan = VideoGradeLooks.plan(look: look, strength: strength)
            let found = await VideoGrade.previews(frame: frame, plans: [(look, plan)], strength: strength,
                                                  folder: Self.folder(source.id).appendingPathComponent("large", isDirectory: true),
                                                  maxPixel: 1200)
            guard !Task.isCancelled else { return }
            large = found[look]
        }
    }

    private static func folder(_ id: UUID) -> URL {
        VideoMedia.workFolder.appendingPathComponent("grade-\(id.uuidString)", isDirectory: true)
    }

    @ViewBuilder private func clip(_ state: VideoState, isDone: Bool) -> some View {
        @Bindable var state = state
        if let slot = tool.slot(.sourceVideo) {
            PanelSection(title: slot.title, systemImage: slot.symbol, step: 1, isDone: isDone) {
                VideoSourceWell(pick: $state.source, title: slot.title, hint: slot.hint, showsSharingNote: false, showsTitle: false)
            }
        }
    }

    private func preview(_ source: Asset) -> some View {
        ZStack {
            if showsOriginal || large == nil {
                VideoPoster(url: app.library.url(for: source), posterURL: app.library.posterURL(for: source), maxPixel: 1200,
                            contentMode: .fit)
            } else if let large {
                ThumbnailImage(url: large, maxPixel: 1200, contentMode: .fit)
            }
        }
        .clipShape(.rect(cornerRadius: Radius.tile))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            Button {
            } label: {
                Label(L("Hold to See Original"), systemImage: "eye")
            }
            .buttonStyle(.glass)
            .fixedSize()
            .onLongPressGesture(minimumDuration: 0, maximumDistance: 50, pressing: { showsOriginal = $0 }, perform: {})
            .padding(10)
            .disabled(large == nil)
        }
    }

    @ViewBuilder private func looks(_ state: VideoState, source: Asset?, selection: String) -> some View {
        if let group = tool.group("look") {
            let aspect: CGFloat = source.map { $0.aspect > 0 ? CGFloat($0.aspect) : 16.0 / 9 } ?? 4.0 / 3
            PanelSection(title: group.title, systemImage: "camera.filters", step: 2, isDone: source != nil) {
                let paletteIsSelected = VideoGradeLooks.palettes.contains { $0.id == selection }
                VStack(alignment: .leading, spacing: Spacing.l) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Film looks")).groupTitleStyle()
                        lookGrid(VideoGradeLooks.photoLooks, state: state, group: group, source: source, selection: selection, aspect: aspect)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Color palettes")).groupTitleStyle()
                        if showsPalettes || paletteIsSelected {
                            lookGrid(VideoGradeLooks.palettes, state: state, group: group, source: source, selection: selection, aspect: aspect)
                        }
                        if !paletteIsSelected {
                            Button {
                                withAnimation(Motion.standard) { showsPalettes.toggle() }
                            } label: {
                                Label(showsPalettes ? L("Show fewer") : L("See all (%ld)", VideoGradeLooks.palettes.count),
                                      systemImage: showsPalettes ? "chevron.up" : "chevron.down")
                                    .font(.callout)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    Text(source == nil ? L("Add a clip to see each look on your own video.")
                         : L("Each tile shows the look on a frame of your clip."))
                        .helperTextStyle()
                }
            }
        }
    }

    private func lookGrid(_ looks: [VideoGradeLook], state: VideoState, group: VideoOptionGroup, source: Asset?, selection: String,
                          aspect: CGFloat) -> some View {
        OptionGrid(minimum: 132, spacing: 8) {
            ForEach(looks) { look in
                OptionTile(title: look.name, subtitle: look.detail, systemImage: "camera.filters",
                           picture: picture(look.id, hasClip: source != nil, aspect: aspect),
                           isSelected: selection == look.id, compact: true) {
                    state.pick(look.id, for: group.id)
                }
            }
        }
    }

    private func picture(_ id: String, hasClip: Bool, aspect: CGFloat) -> OptionPicture {
        if hasClip { return OptionPicture(url: previews[id], aspect: aspect) }
        return OptionPicture(url: OptionImages.url(family: "grade", key: id), aspect: 4.0 / 3)
    }

    @ViewBuilder private func strengths(_ state: VideoState, isDone: Bool) -> some View {
        if let group = tool.group("strength") {
            PanelSection(title: group.title, systemImage: "dial.medium", step: 3, isDone: isDone) {
                Picker(group.title, selection: Binding(get: { state.choice(group.id, in: tool) },
                                                       set: { state.pick($0, for: group.id) })) {
                    ForEach(group.values, id: \.self) { value in
                        Text(L(value)).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360, alignment: .leading)
            }
        }
    }

    private func bar(_ state: VideoState, source: Asset?) -> some View {
        let isWorking = state.localWork.contains(where: \.isRunning)
        let reason: String? = source == nil
            ? (state.source.isEmpty ? L("Add a clip.") : L("Color grading needs a clip on this Mac, not a link."))
            : isWorking ? L("Applying the look…") : nil
        return VideoLocalBar(title: L("Apply Look"), reason: reason, isWorking: isWorking,
                             label: Label(L("Colored on this Mac, free; the sound stays"), systemImage: "desktopcomputer"),
                             costLabel: L("Free")) {
            app.runVideoTool(tool, state: state)
        }
    }
}
