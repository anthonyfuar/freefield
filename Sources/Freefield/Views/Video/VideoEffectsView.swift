import FreefieldCore
import SwiftUI

struct VideoEffectsView: View {
    @Environment(AppModel.self) private var app
    @State private var path: [String] = []
    @State private var search = ""
    @State private var category = Self.allCategory

    static var tool: VideoTool? { VideoCatalog.tool("videoEffects") }

    static let allCategory = L("All")

    private static var categoryNames: [String] { [allCategory] + VideoEffectCategory.allCases.map(\.title) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Video Effects")).pageTitleStyle()
                        Text(L("One-click effects for photos and products: add an image, pick an effect and generate. Nothing to write."))
                            .foregroundStyle(.secondary)
                    }
                    if !app.canMakeVideos { keyNotice }
                    CategoryChips(categories: Self.categoryNames, selection: $category)

                    let selected = VideoEffectCategory.allCases.first { $0.title == category }
                    let items = VideoEffects.filtered(category: selected, search: search)
                    if selected == nil, search.trimmingCharacters(in: .whitespaces).isEmpty {
                        ForEach(VideoEffectCategory.allCases) { group in
                            let effects = items.filter { $0.category == group }
                            if !effects.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(group.title).sectionTitleStyle()
                                    grid(effects)
                                }
                            }
                        }
                    } else {
                        grid(items)
                    }
                    if items.isEmpty { ContentUnavailableView.search(text: search) }
                }
                .padding(24)
            }
            .searchable(text: $search, placement: .toolbar, prompt: L("Search effects"))
            .navigationTitle(L("Video Effects"))
            .navigationSubtitle(L("%ld effects", VideoEffects.all.count))
            .navigationDestination(for: String.self) { id in
                if let effect = VideoEffects.effect(id), let tool = Self.tool {
                    VideoEffectRunner(effect: effect, tool: tool)
                }
            }
        }
        .onAppear(perform: openPending)
        .onChange(of: app.pendingVideoEffect) { openPending() }
    }

    private func openPending() {
        guard let id = app.pendingVideoEffect else { return }
        app.pendingVideoEffect = nil
        if VideoEffects.effect(id) != nil { path = [id] }
    }

    private func grid(_ effects: [VideoEffect]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14, alignment: .top)], spacing: 14) {
            ForEach(effects) { effect in
                VideoEffectCard(effect: effect) { path.append(effect.id) }
            }
        }
    }

    private var keyNotice: some View {
        HStack(spacing: 10) {
            Label(GenerationEngine.videoKeyMessage, systemImage: "key")
                .font(.callout)
            Spacer()
            SettingsLink { Text(L("Open Settings")) }
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1), in: .rect(cornerRadius: Radius.tile))
    }

    static func record(for effect: VideoEffect, tool: VideoTool) -> String {
        english(tool.name) + " · " + english(effect.name)
    }

    static func latestClip(for effect: VideoEffect, in app: AppModel) -> Asset? {
        guard let tool else { return nil }
        let record = record(for: effect, tool: tool)
        return app.library.assets.first { $0.isVideo && $0.appID == tool.id && $0.prompt == record }
    }

    static func estimate(for effect: VideoEffect, in app: AppModel) -> VideoCostEstimate? {
        guard let tool, let model = app.catalog.videoModel(id: effect.model) else { return nil }
        var inputs = VideoToolInputs(tool: tool)
        inputs.effectID = effect.id
        inputs.firstFrame = InputImage(data: Data(), mimeType: "image/jpeg", role: "first frame")
        inputs.duration = effect.duration
        inputs.resolution = effect.resolution
        inputs.aspect = effect.aspect
        inputs.audio = effect.audio
        return app.videoToolCost(tool, inputs: inputs, model: model, count: 1)
    }

    static func modelName(for effect: VideoEffect, in app: AppModel) -> String {
        VideoLineup.displayName(for: effect.model, fallback: app.catalog.videoModel(id: effect.model)?.name
            ?? effect.model.split(separator: "/").last.map(String.init) ?? effect.model)
    }

    static func quickStyleName(for effect: VideoEffect) -> String? {
        effect.quickStyleID.flatMap(AppCatalog.item)?.name
    }
}

struct VideoEffectCard: View {
    let effect: VideoEffect
    let action: () -> Void

    @Environment(AppModel.self) private var app

    private var focus: UnitPoint {
        switch effect.input {
        case .photo: UnitPoint(x: 0.5, y: 0.25)
        case .image: UnitPoint(x: 0.5, y: 0.4)
        case .product: .center
        }
    }

    private var latestLabel: some View {
        Text(L("Your latest clip"))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .glassEffect(in: .capsule)
    }

    var body: some View {
        let latest = VideoEffectsView.latestClip(for: effect, in: app)
        let example = Examples.video(effect.id)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Color.primary.opacity(0.04)
                    if let example, let clip = example.after.first {
                        VideoTile(url: clip, posterURL: example.poster, hasAudio: effect.audio ? true : nil, maxPixel: 500, cornerRadius: 0,
                                  focus: focus)
                    } else if let latest {
                        VideoTile(url: app.library.url(for: latest), posterURL: app.library.thumbnailURL(for: latest),
                                  hasAudio: latest.hasAudio, maxPixel: 500, cornerRadius: 0, focus: focus,
                                  aspect: latest.aspect > 0 ? latest.aspect : nil)
                            .overlay(alignment: .topLeading) { latestLabel }
                    } else if let still = effect.previewStill {
                        ThumbnailImage(url: still, maxPixel: 500, focus: focus)
                    } else {
                        VideoEffectSymbolTile(effect: effect)
                    }
                }
                .frame(height: 140)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if let style = VideoEffectsView.quickStyleName(for: effect) {
                        VideoEffectBadge(text: L("Photo effect"), color: .brand)
                            .glassEffect(in: .capsule)
                            .help(L("Makes the %@ image first, then animates it.", style))
                            .padding(8)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if let example, example.after.first != nil, let before = example.before, !example.beforeIsVideo {
                        ThumbnailImage(url: before, maxPixel: 160)
                            .frame(width: 38, height: 38)
                            .clipShape(.rect(cornerRadius: Radius.thumb))
                            .overlay(RoundedRectangle(cornerRadius: Radius.thumb).strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                            .shadow(radius: 3)
                            .padding(8)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if let latest, example?.after.first != nil {
                        VStack(alignment: .trailing, spacing: 3) {
                            latestLabel
                            VideoPoster(url: app.library.url(for: latest), posterURL: app.library.posterURL(for: latest), maxPixel: 200)
                                .frame(width: 56, height: 56)
                                .clipShape(.rect(cornerRadius: Radius.thumb))
                                .overlay(RoundedRectangle(cornerRadius: Radius.thumb).strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                                .shadow(radius: 3)
                        }
                        .padding(8)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L("Your latest clip"))
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(effect.name).font(.headline).lineLimit(2).minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(effect.summary).helperTextStyle().lineLimit(2, reservesSpace: true)
                    HStack(alignment: .top, spacing: 8) {
                        FlowLayout(spacing: 8) {
                            Label(effect.input.title, systemImage: effect.input.symbol)
                            Label(L("%ld s", effect.duration), systemImage: "timer")
                        }
                        if effect.audio { Image(systemName: "speaker.wave.2").fixedSize().help(L("With sound")) }
                        if let total = VideoEffectsView.estimate(for: effect, in: app)?.total {
                            Text(GenerateButton.format(total)).monospacedDigit()
                                .fixedSize()
                                .help(L("Approximate cost of one clip with this effect's settings"))
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                }
                .padding(12)
            }
            .background(.background.secondary)
            .clipShape(.rect(cornerRadius: Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(.primary.opacity(0.07)))
            .contentShape(.rect(cornerRadius: Radius.card))
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityLabel(Text(effect.name))
        .accessibilityHint(Text(effect.summary))
        .help(effect.hint)
    }
}

struct VideoEffectSymbolTile: View {
    let effect: VideoEffect

    var body: some View {
        let tint = effect.category.tint
        ZStack {
            LinearGradient(colors: [tint.opacity(0.26), tint.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: effect.symbol)
                .font(.system(size: 46, weight: IconScale.weight))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        }
        .accessibilityHidden(true)
    }
}

struct VideoEffectBadge: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
            .fixedSize()
    }
}

struct VideoEffectRunner: View {
    let effect: VideoEffect
    let tool: VideoTool

    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedResultID: UUID?
    @State private var visibleHeight: CGFloat = 0

    private static let textLimit = 120

    var body: some View {
        let state = app.videoState(for: tool)
        let inputs = app.videoInputs(tool, state: state, forRun: false)
        let model = app.resolvedVideoModel(tool, state: state, inputs: inputs)
        let recipe = model.flatMap { VideoRecipes.request(for: tool, state: inputs, model: $0) }
        let record = VideoEffectsView.record(for: effect, tool: tool)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    header
                    CollapsibleExample(id: "videoEffect.\(effect.id)",
                                       hasResults: VideoResults.hasClips(in: app, toolID: tool.id, record: record)
                                           || VideoExampleSizing.folds(visible: visibleHeight),
                                       hasExample: Examples.video(effect.id) != nil) {
                        VideoExample(tool: exampleTool, mediaHeight: VideoExampleSizing.mediaHeight(visible: visibleHeight),
                                     foldsSteps: VideoExampleSizing.foldsSteps(visible: visibleHeight))
                    }
                    inputSection(state, inputs: inputs, model: model)
                    VideoRunNotes(state: state, recipe: recipe)
                    VideoResults(tool: tool, state: state, selectedID: $selectedResultID, record: record)
                        .id(VideoResults.anchor)
                }
                .padding(24)
                .frame(maxWidth: VideoLayout.columnWidth + 48, alignment: .leading)
            }
            .pinnedActionBar(maxWidth: VideoLayout.columnWidth) {
                VideoRunBar(tool: tool, state: state, inputs: inputs, model: model,
                            blockedReason: textIsTooLong(state, inputs: inputs, model: model) ? L("Shorten the text to fit the selected model") : nil,
                            settings: VideoBarSettings(summary: settingsSummary(state), details: AnyView(tuning(model)),
                                                       reset: { withAnimation(Motion.standard) { state.apply(effect) } }))
            }
            .onVisibleHeightChange { visibleHeight = $0 }
            .onChange(of: VideoResults.activeCount(in: app, tool: tool, state: state)) { old, new in
                guard new > old else { return }
                withAnimation(reduceMotion ? nil : Motion.emphasized) { proxy.scrollTo(VideoResults.anchor, anchor: .top) }
            }
        }
        .navigationTitle(effect.name)
        .navigationSubtitle(L("Video Effects"))
        .onAppear {
            if state.effectID != effect.id {
                state.apply(effect)
                state.firstFrameIsKeyframe = false
            }
        }
        .alert(state.confirmation?.title ?? "", isPresented: Binding(get: { state.confirmation != nil }, set: { if !$0 { state.confirmation = nil } }),
               presenting: state.confirmation) { _ in
            Button(L("Generate")) {
                state.confirmation = nil
                app.runVideoTool(tool, state: state, model: model, confirmed: true)
            }
            Button(L("Cancel"), role: .cancel) { state.confirmation = nil }
        } message: { confirmation in
            Text(confirmation.message)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            FamilyStyle.tile(symbol: effect.symbol, family: VideoLayout.family(of: tool.id), side: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(effect.name).toolTitleStyle()
                Text(effect.summary).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                VideoEffectBadge(text: effect.category.title)
                if effect.audio { VideoEffectBadge(text: L("Sound"), color: .appAccent) }
                if let style = VideoEffectsView.quickStyleName(for: effect) {
                    VideoEffectBadge(text: L("Photo effect"), color: .brand)
                        .help(L("Makes the %@ image first, then animates it.", style))
                }
            }
        }
    }

    private var exampleTool: VideoTool {
        VideoTool(id: effect.id, name: effect.name, subtitle: effect.hint, symbol: effect.symbol,
                  section: .create, inputs: [effect.input == .product ? .product(required: true) : .firstFrame(required: true)],
                  steps: steps)
    }

    private var steps: [String] {
        var steps = [L("Add %@.", effect.input.title.lowercased())]
        if let style = VideoEffectsView.quickStyleName(for: effect) {
            steps.append(L("Freefield first makes the %@ image from it, then animates that image.", style))
        }
        if effect.takesText, let title = effect.textTitle {
            steps.append(L("Optionally fill in “%@”; left empty, Freefield picks something.", title))
        }
        steps.append(L("Press Generate. Freefield writes the motion for the model the effect was tuned for."))
        return steps
    }

    @ViewBuilder private func inputSection(_ state: VideoState, inputs: VideoToolInputs, model: VideoModel?) -> some View {
        @Bindable var state = state
        HStack(alignment: .top, spacing: 20) {
            PanelSection(title: effect.input.title, systemImage: effect.input.symbol, step: 1, isDone: state.firstFrame != nil) {
                let frame = Binding(get: { state.firstFrame }, set: { state.firstFrame = $0; state.firstFrameIsKeyframe = false })
                FramePicker(first: frame, last: nil, firstTitle: effect.input.title, firstHint: effect.hint, height: 260,
                            sources: wellSources)
            }
            .frame(maxWidth: 360, alignment: .leading)
            VStack(alignment: .leading, spacing: 16) {
                if effect.takesText {
                    let text = textBinding(VideoEffects.textFieldID, state: state)
                    PanelSection(title: VideoSlotTitle.plain(effect.textTitle ?? L("Details (optional)")), systemImage: "text.cursor", step: 2,
                                 isDone: !state.text(VideoEffects.textFieldID).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                 isOptional: true) {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField(effect.textPlaceholder ?? "", text: text)
                                .textFieldStyle(.roundedBorder)
                                .characterLimit(text, Self.textLimit)
                            Text(L("Optional. Left empty, Freefield picks something.")).helperTextStyle()
                        }
                    }
                }
                if let style = VideoEffectsView.quickStyleName(for: effect) {
                    Label(L("Starts with the %@ photo effect image.", style), systemImage: Tool.app.systemImage)
                        .helperTextStyle()
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let field = tool.textField(VideoCatalog.extraFieldID) {
                    ExtraInstructionField(text: textBinding(field.id, state: state), placeholder: field.placeholder,
                                          limit: VideoTextBudget.limit(tool, inputs: inputs, model: model, field: field))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var wellSources: WellSources? {
        switch effect.input {
        case .product: .standard
        case .photo: .person
        case .image: nil
        }
    }

    private func settingsSummary(_ state: VideoState) -> String {
        let seconds = state.duration ?? effect.duration
        let parts = [L("%ld s", seconds), state.resolution ?? effect.resolution, state.aspect ?? L("Auto")]
        return parts.joined(separator: " · ")
    }

    private func tuning(_ model: VideoModel?) -> some View {
        let tuned = VideoEffectsView.modelName(for: effect, in: app)
        let parts = [tuned, L("%ld s", effect.duration), effect.resolution, effect.aspect ?? L("Auto"),
                     effect.audio ? L("Sound") : L("No sound")]
        return VStack(alignment: .leading, spacing: 6) {
            Label(L("Tuned for"), systemImage: "dial.medium").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Text(parts.joined(separator: " · ")).font(.callout)
            if let model, model.id != effect.model {
                Label(L("You picked another model; it may follow this effect less closely."), systemImage: "info.circle")
                    .helperTextStyle()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func textBinding(_ id: String, state: VideoState) -> Binding<String> {
        Binding(get: { state.texts[id] ?? "" }, set: { state.texts[id] = $0 })
    }

    private func textIsTooLong(_ state: VideoState, inputs: VideoToolInputs, model: VideoModel?) -> Bool {
        if effect.takesText, state.text(VideoEffects.textFieldID).utf16.count > Self.textLimit { return true }
        guard let field = tool.textField(VideoCatalog.extraFieldID) else { return false }
        return state.text(field.id).utf16.count > VideoTextBudget.limit(tool, inputs: inputs, model: model, field: field)
    }
}
