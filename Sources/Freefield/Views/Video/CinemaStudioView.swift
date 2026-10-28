import AppKit
import AVFoundation
import FreefieldCore
import SwiftUI

struct CinemaStudioView: View {
    let tool: VideoTool

    @Environment(AppModel.self) private var app
    @State private var writingScript = false

    private static let panel: [(title: String, symbol: String, groups: [String])] = [
        (L("Story"), "theatermasks", ["genre", "era", "pacing"]),
        (L("Camera"), "camera.aperture", ["body", "lens", "aperture"]),
        (L("Look"), "sun.max", ["light", "speed"]),
        (L("Performance"), "face.smiling", ["emotion", "intensity"]),
    ]

    var body: some View {
        let state = app.videoState(for: tool)
        let inputs = app.videoInputs(tool, state: state, forRun: false)
        let model = app.resolvedVideoModel(tool, state: state, inputs: inputs)
        let recipe = model.flatMap { VideoRecipes.request(for: tool, state: inputs, model: $0) }
        VideoToolScreen(tool: tool, state: state, model: model) {
            scene(state, inputs: inputs, model: model)
            shots(state, recipe: recipe)
            VStack(alignment: .leading, spacing: Spacing.l) {
                ExtrasHeader(topPadding: 0)
                cast(state)
                directorPanel(state, recipe: recipe)
                dialogue(state, inputs: inputs, model: model, recipe: recipe)
                promptPreview(recipe)
            }
            VideoRunNotes(state: state, recipe: recipe)
        } bar: {
            VideoRunBar(tool: tool, state: state, inputs: inputs, model: model,
                        blockedReason: textIsTooLong(state, inputs: inputs, model: model) ? L("Shorten the text to fit the selected model") : nil,
                        moreOptions: AnyView(studioMax(state, inputs: inputs)))
        }
        .task(id: "\(state.characterID?.uuidString ?? "-")|\(state.characterPhoto?.count ?? 0)") {
            await app.checkPhotoreal(tool, state: state)
        }
    }

    @ViewBuilder private func scene(_ state: VideoState, inputs: VideoToolInputs, model: VideoModel?) -> some View {
        @Bindable var state = state
        if let slot = tool.slot(.prompt) {
            PanelSection(title: slot.title, systemImage: "movieclapper", step: 1,
                         isDone: !state.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                TextField(slot.hint, text: $state.prompt, axis: .vertical)
                    .lineLimit(2...6)
                    .inputBox()
                    .characterLimit($state.prompt, VideoTextBudget.limit(tool, inputs: inputs, model: model), clampsWhenLimitDrops: false)
                    .frame(maxWidth: VideoLayout.textWidth, alignment: .leading)
            }
        }
    }

    @ViewBuilder private func cast(_ state: VideoState) -> some View {
        @Bindable var state = state
        let filled = castSummary(state)
        OptionalSection(L("Character and images"), systemImage: "person.crop.rectangle.stack",
                        summary: filled.joined(separator: " · "), isFilled: !filled.isEmpty, storageKey: "video.cinemaStudio.cast") {
        VideoColumns(minimum: 300, maximum: VideoLayout.inputWidth) {
            if let slot = tool.slot(.character) {
                VideoCharacterSection(title: VideoSlotTitle.plain(slot.title), symbol: slot.symbol, hint: slot.hint,
                                      characterID: $state.characterID, photo: $state.characterPhoto,
                                      isPhotoreal: state.subjectIsPhotoreal)
            }
            if let slot = tool.slot(.firstFrame) {
                PanelSection(title: VideoSlotTitle.plain(slot.title), systemImage: slot.symbol) {
                    AdaptiveImageWell(title: L("Start image"), subtitle: slot.hint, systemImage: slot.symbol, data: $state.firstFrame,
                                      minHeight: 150)
                        .frame(height: 170)
                }
            }
            if let slot = tool.slot(.imageReferences) {
                PanelSection(title: VideoSlotTitle.plain(slot.title), systemImage: slot.symbol) {
                    VStack(alignment: .leading, spacing: 4) {
                        ReferenceStrip(images: $state.references, limit: slot.maxCount, label: slot.title)
                        ElementReferenceButton(images: $state.references, limit: slot.maxCount)
                        Text(slot.hint).helperTextStyle()
                    }
                }
            }
        }
        }
    }

    private func castSummary(_ state: VideoState) -> [String] {
        var parts: [String] = []
        if let character = app.library.character(state.characterID) { parts.append(character.name) } else if state.characterPhoto != nil {
            parts.append(L("Person photo"))
        }
        if state.firstFrame != nil, let slot = tool.slot(.firstFrame) { parts.append(VideoSlotTitle.plain(slot.title)) }
        if !state.references.isEmpty { parts.append(state.references.count == 1 ? L("1 image") : L("%ld images", state.references.count)) }
        return parts
    }

    @ViewBuilder private func shots(_ state: VideoState, recipe: VideoRecipe?) -> some View {
        @Bindable var state = state
        if let slot = tool.slot(.shots) {
            let seconds = recipe.flatMap { OpenRouterClient.videoDuration(for: $0.request) }
            PanelSection(title: VideoSlotTitle.plain(slot.title), systemImage: slot.symbol, step: 2,
                         isDone: state.shots.contains { !$0.action.trimmingCharacters(in: .whitespaces).isEmpty }, isOptional: !slot.isRequired) {
                VStack(alignment: .leading, spacing: 8) {
                    VideoShotsEditor(shots: $state.shots, minimum: slot.minCount, maximum: slot.maxCount,
                                     emotions: tool.group("emotion")?.values ?? [])
                    Text(state.shots.contains { !$0.action.trimmingCharacters(in: .whitespaces).isEmpty }
                         ? L("The shots share the clip's length in order; each plays one action with its camera move.")
                         : L("Leave the shots empty for one continuous shot; its camera is chosen under Camera & look."))
                        .helperTextStyle()
                    let filled = state.shots.filter { !$0.action.trimmingCharacters(in: .whitespaces).isEmpty }.count
                    if let seconds, filled >= 3, seconds < 6 {
                        Label(L("Three shots fit best in clips of 6 seconds or more."), systemImage: "timer")
                            .font(.callout).foregroundStyle(.orange)
                    }
                    Button(L("Write the shots for me…"), systemImage: "wand.and.stars") { writingScript = true }
                        .buttonStyle(.glass)
                        .help(L("Freefield's AI splits your script into shots and picks the camera, lens and light."))
                        .popover(isPresented: $writingScript, arrowEdge: .bottom) {
                            ScriptToShotsPanel(tool: tool, state: state, maxShots: slot.maxCount) { writingScript = false }
                                .environment(app)
                        }
                }
            }
        }
    }

    @ViewBuilder private func directorPanel(_ state: VideoState, recipe: VideoRecipe?) -> some View {
        @Bindable var state = state
        let seconds = recipe.flatMap { OpenRouterClient.videoDuration(for: $0.request) }
        let picked = panelSummary(state)
        OptionalSection(L("Camera & look"), systemImage: "slider.horizontal.3",
                        summary: picked.isEmpty ? L("All on Auto") : picked.joined(separator: " · "),
                        isFilled: !picked.isEmpty, storageKey: "video.cinemaStudio.panel") {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                    ForEach(Self.panel, id: \.title) { card in
                        let groups = card.groups.compactMap(tool.group)
                        VStack(alignment: .leading, spacing: 8) {
                            Label(card.title, systemImage: card.symbol).font(.body.weight(.semibold))
                            ViewThatFits(in: .horizontal) {
                                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                                    ForEach(groups, id: \.id) { group in
                                        GridRow {
                                            Text(group.title).font(.callout).foregroundStyle(.secondary).fixedSize()
                                            choiceControl(group, state: state).fixedSize()
                                        }
                                    }
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(groups, id: \.id) { group in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(group.title).font(.callout).foregroundStyle(.secondary)
                                            choiceControl(group, state: state).frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.035), in: .rect(cornerRadius: Radius.tile))
                    }
                }
                FlowLayout(spacing: 8) {
                    CameraMoveChip(selection: $state.cameraMoves, strength: $state.strength,
                                   limit: CameraMoves.maxMoves(forDuration: seconds))
                    StyleChip(presetID: $state.presetID, moodboardID: $state.moodboardID)
                }
                Text(L("The camera move is used when no shot has its own. A style applies when there's no start image."))
                    .helperTextStyle()
            }
        }
    }

    private func panelSummary(_ state: VideoState) -> [String] {
        let defaults = tool.initialChoices
        var parts = Self.panel.flatMap(\.groups).compactMap { id -> String? in
            let value = state.choice(id, in: tool)
            return value == defaults[id] || value == "Auto" ? nil : L(value)
        }
        parts += state.cameraMoves.compactMap(CameraMoves.move).map(\.name)
        if let preset = state.presetID.flatMap(StylePresets.preset) { parts.append(preset.name) }
        if let board = app.library.moodboard(state.moodboardID) { parts.append(board.name) }
        return parts
    }

    @ViewBuilder private func choiceControl(_ group: VideoOptionGroup, state: VideoState) -> some View {
        let selection = Binding(get: { state.choice(group.id, in: tool) }, set: { state.choices[group.id] = $0 })
        if group.values.count <= 2 {
            Picker(group.title, selection: selection) {
                ForEach(group.values, id: \.self) { Text(L($0)).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
        } else {
            DirectorChoiceButton(group: group, toolID: tool.id, selection: selection)
        }
    }

    @ViewBuilder private func dialogue(_ state: VideoState, inputs: VideoToolInputs, model: VideoModel?, recipe: VideoRecipe?) -> some View {
        let hasDialogue = !state.text("dialogue").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let filled = tool.textFields.filter { !state.text($0.id).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        OptionalSection(L("Dialogue and sound"), systemImage: "text.bubble", summary: filled.map { VideoSlotTitle.plain($0.title) }.joined(separator: " · "),
                        isFilled: !filled.isEmpty, storageKey: "video.cinemaStudio.dialogue") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                ForEach(tool.textFields) { field in
                    let binding = Binding(get: { state.texts[field.id] ?? "" }, set: { state.texts[field.id] = $0 })
                    PanelSection(title: VideoSlotTitle.plain(field.title), systemImage: field.isLiteral ? "textformat" : "speaker.wave.2") {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField(field.placeholder, text: binding, axis: .vertical)
                                .lineLimit(field.isMultiline ? 2...5 : 1...3)
                                .inputBox()
                                .characterLimit(binding, VideoTextBudget.limit(tool, inputs: inputs, model: model, field: field),
                                                clampsWhenLimitDrops: false)
                            if field.id == "dialogue" {
                                Text(L("Spoken exactly as you type it.")).helperTextStyle()
                                if let budget = VideoTextBudget.wordBudget(state.text(field.id), recipe: recipe) {
                                    Text(budget.text).font(.subheadline).foregroundStyle(budget.isOver ? Color.orange : .secondary)
                                }
                                if hasDialogue {
                                    FlowLayout(spacing: 8) {
                                        SpokenLanguageMenu(tool: tool, state: state, inputs: inputs)
                                        if let tone = tool.group("tone") {
                                            ChipMenu(systemImage: "waveform", title: "\(tone.title): \(L(state.choice(tone.id, in: tool)))", help: tone.title) {
                                                Picker(tone.title, selection: Binding(get: { state.choice(tone.id, in: tool) },
                                                                                       set: { state.choices[tone.id] = $0 })) {
                                                    ForEach(tone.values, id: \.self) { Text(L($0)).tag($0) }
                                                }
                                                .pickerStyle(.inline)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func studioMax(_ state: VideoState, inputs: VideoToolInputs) -> some View {
        let maxModel = app.videoModels.first { $0.id == VideoLineup.cinemaMaxModelID }
        let isOn = Binding(get: { state.modelID == VideoLineup.cinemaMaxModelID },
                           set: { state.modelID = $0 ? VideoLineup.cinemaMaxModelID : nil })
        let cost = maxModel.flatMap { app.videoToolCost(tool, inputs: inputs, model: $0, count: 1).total }
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cost.map { L("Maximum quality (%@)", VideoCostLabel.price($0)) } ?? L("Maximum quality"))
                    .font(.callout.weight(.semibold))
                Text(maxModel == nil ? L("Not available right now")
                     : cost == nil ? L("Richer motion and steadier faces, for a higher price") : L("Richer motion and steadier faces, per clip"))
                    .helperTextStyle()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(maxModel == nil)
        .help(maxModel == nil ? L("Seedance 2.5 isn't available right now.")
              : L("Seedance 2.5: richer motion, steadier faces and exact timing for each shot, for a higher price."))
    }

    @ViewBuilder private func promptPreview(_ recipe: VideoRecipe?) -> some View {
        if let prompt = recipe?.request.prompt, !prompt.isEmpty {
            OptionalSection(L("See the exact text sent to the AI"), systemImage: "text.alignleft", storageKey: "video.cinemaStudio.prompt") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(prompt)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: Radius.thumb))
                    Text(L("Your own words are translated to English when you generate; dialogue stays exactly as you typed it."))
                        .helperTextStyle()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func textIsTooLong(_ state: VideoState, inputs: VideoToolInputs, model: VideoModel?) -> Bool {
        if state.prompt.utf16.count > VideoTextBudget.limit(tool, inputs: inputs, model: model) { return true }
        return tool.textFields.contains { state.text($0.id).utf16.count > VideoTextBudget.limit(tool, inputs: inputs, model: model, field: $0) }
    }
}

struct VideoToolScreen<Content: View, Bar: View>: View {
    let tool: VideoTool
    let state: VideoState
    var model: VideoModel?
    @ViewBuilder var content: () -> Content
    @ViewBuilder var bar: () -> Bar

    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedResultID: UUID?
    @State private var pastingLink = false
    @State private var visibleHeight: CGFloat = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    header
                    let hookExample = tool.id == "hookCheck" && HookCheckExample.isAvailable
                    CollapsibleExample(id: "video.\(tool.id)",
                                       hasResults: VideoResults.hasClips(in: app, toolID: tool.id) || VideoExampleSizing.folds(visible: visibleHeight),
                                       hasExample: hookExample || Examples.video(tool.id) != nil) {
                        if hookExample {
                            HookCheckExample(tool: tool, mediaHeight: VideoExampleSizing.mediaHeight(visible: visibleHeight))
                        } else {
                            VideoExample(tool: tool, mediaHeight: VideoExampleSizing.mediaHeight(visible: visibleHeight),
                                         foldsSteps: VideoExampleSizing.foldsSteps(visible: visibleHeight))
                        }
                    }
                    content()
                    VideoResults(tool: tool, state: state, selectedID: $selectedResultID)
                        .id(VideoResults.anchor)
                }
                .padding(24)
                .frame(maxWidth: VideoLayout.columnWidth + 48, alignment: .leading)
            }
            .pinnedActionBar(maxWidth: VideoLayout.columnWidth) { bar() }
            .onVisibleHeightChange { visibleHeight = $0 }
            .onChange(of: VideoResults.activeCount(in: app, tool: tool, state: state)) { old, new in
                guard new > old else { return }
                withAnimation(reduceMotion ? nil : Motion.emphasized) { proxy.scrollTo(VideoResults.anchor, anchor: .top) }
            }
        }
        .navigationTitle(tool.name)
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
        .alert(L("Couldn't share the clip"), isPresented: Binding(get: { state.inputProblem != nil }, set: { if !$0 { state.inputProblem = nil } }),
               presenting: state.inputProblem) { problem in
            if problem.offersFrames {
                Button(L("Use Frame-Based Mode")) {
                    state.inputProblem = nil
                    state.usesFrames = true
                    app.runVideoTool(tool, state: state, model: model)
                }
            }
            Button(L("Paste a Link…")) {
                state.inputProblem = nil
                pastingLink = true
            }
            Button(L("Cancel"), role: .cancel) { state.inputProblem = nil }
        } message: { problem in
            Text(problem.message)
        }
        .sheet(isPresented: $pastingLink) {
            VideoLinkField(link: currentLink) { link in
                setLink(link)
                pastingLink = false
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            FamilyStyle.tile(symbol: tool.symbol, family: VideoLayout.family(of: tool.id), side: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(tool.name).toolTitleStyle()
                Text(tool.subtitle).foregroundStyle(.secondary)
            }
        }
    }

    private var currentLink: String {
        if tool.takes(.drivingVideo) { return state.driving.link }
        if tool.takes(.sourceVideo), !state.source.isEmpty { return state.source.link }
        return state.audioLink
    }

    private func setLink(_ link: String) {
        if tool.takes(.drivingVideo) {
            state.driving.link = link
            if let asset = state.driving.assetID.flatMap(app.library.asset) { try? app.setPastedLink(link, for: asset) }
        } else if tool.takes(.sourceVideo), !state.source.isEmpty {
            state.source.link = link
            if let asset = state.source.assetID.flatMap(app.library.asset) { try? app.setPastedLink(link, for: asset) }
        } else {
            state.audioLink = link
            if !link.isEmpty {
                state.audioFile = nil
                state.audioDuration = nil
            }
        }
    }
}

enum VideoExampleSizing {
    static let tallest: CGFloat = 260
    static let foldsBelow: CGFloat = 540
    static let foldsStepsBelow: CGFloat = 890
    private static let formRoom: CGFloat = 670
    private static let barRoom: CGFloat = 115

    static func mediaHeight(visible screen: CGFloat) -> CGFloat {
        guard screen > 0 else { return tallest }
        return min(tallest, max(110, screen - barRoom - formRoom))
    }

    static func folds(visible screen: CGFloat) -> Bool { screen > 0 && screen - barRoom < foldsBelow }

    static func foldsSteps(visible screen: CGFloat) -> Bool { screen > 0 && screen - barRoom < foldsStepsBelow }
}

extension View {
    func onVisibleHeightChange(_ action: @escaping (CGFloat) -> Void) -> some View {
        onGeometryChange(for: CGFloat.self) { proxy in
            (proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom).rounded()
        } action: { action($0) }
    }
}

struct VideoBarSettings {
    let summary: String
    var details: AnyView?
    var reset: (() -> Void)?
}

struct VideoRunBar: View {
    let tool: VideoTool
    @Bindable var state: VideoState
    let inputs: VideoToolInputs
    let model: VideoModel?
    var inputReason: String?
    var blockedReason: String?
    var showsAspect = true
    var showsResolution = true
    var followsSource = false
    var note: String?
    var accessory: AnyView?
    var moreOptions: AnyView?
    var clipResolution: String?
    var settings: VideoBarSettings?

    @Environment(AppModel.self) private var app
    @State private var showingSettings = false

    var body: some View {
        let estimate = model.map { app.videoRunEstimate(tool, state: state, inputs: inputs, model: $0) }
        let cost = estimate?.cost
        let reason = disabledReason
        let typical = cost?.video == nil ? model.flatMap(typicalRange) : nil
        VideoRunBarLayout {
            VStack(alignment: .leading, spacing: 6) {
                if let accessory { accessory }
                VideoFlowLayout(spacing: 8, centersInRow: true) {
                    if let settings {
                        settingsChip(settings, estimate: estimate)
                        BatchMenu(count: $state.count)
                    } else {
                        if let model { clipChips(model, estimate: estimate) }
                        moreChip()
                    }
                }
            }
            VStack(alignment: .trailing, spacing: 4) {
                if state.isPreparing {
                    HStack(spacing: 6) {
                        Text(state.preparingStep ?? L("Getting ready…")).fineTextStyle()
                        Button(L("Cancel")) { app.cancelVideoPreparation(state) }.controlSize(.small)
                    }
                }
                GenerateButton(title: generateTitle(cost), isEnabled: reason == nil, disabledReason: reason, estimatedCost: cost?.total,
                               costLabel: typical.map { Self.rangeLabel($0, clips: cost?.clips ?? state.count) },
                               isWorking: state.isPreparing) {
                    app.runVideoTool(tool, state: state, model: model)
                }
                if !state.isPreparing, reason != nil {
                    DisabledReasonLabel(reason: reason)
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: VideoLayout.reasonWidth.lowerBound, maxWidth: VideoLayout.reasonWidth.upperBound,
                               alignment: .trailing)
                }
            }
            captions(cost: cost, typical: typical, frameModel: estimate?.frameModel)
        }
        .animation(Motion.standard, value: reason)
    }

    @ViewBuilder private func clipChips(_ model: VideoModel, estimate: (cost: VideoCostEstimate, frameModel: VideoModel?)?) -> some View {
        let durations = availableDurations(model)
        if !durations.isEmpty, !followsSource {
            DurationMenu(selection: $state.duration, available: durations, sent: sentSeconds(estimate))
        }
        let aspects = availableAspects(model)
        if showsAspect, !followsSource, !aspects.isEmpty {
            VideoAspectMenu(selection: Binding(get: { state.aspect }, set: { state.aspect = $0; state.aspectIsPicked = true }),
                            available: aspects, allowsAuto: allowsAutoAspect)
        }
        resolutionChip(model)
        let traits = VideoModelTraits(model)
        if traits.makesSound, !traits.isAvatar, !Self.originalSoundTools.contains(tool.id) {
            AudioToggle(isOn: $state.audio, isAvailable: traits.controlsSound, isAlwaysOn: traits.alwaysMakesSound)
        }
    }

    private static let originalSoundTools: Set<String> = ["motionTransfer", "swapVideo"]

    private func modelPicker(showsEnhance: Bool = true) -> some View {
        let choices = app.videoModelChoices(tool, inputs: inputs)
        return VideoModelPicker(selectionID: $state.modelID, current: model, featured: choices.featured, others: choices.others,
                                summary: { summary(for: $0) }, showsEnhance: showsEnhance)
    }

    @ViewBuilder private func resolutionChip(_ model: VideoModel) -> some View {
        if showsResolution, !model.resolutions.isEmpty, !followsSource {
            VideoResolutionMenu(selection: $state.resolution, options: app.videoSizeOptions(tool, state: state, inputs: inputs),
                                current: model, followsClip: clipResolution, releasesModel: { state.modelID = nil })
        }
    }

    private func moreChip() -> some View {
        MoreOptionsChip(summary: moreSummary, help: moreHelp) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Video model")).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                modelPicker(showsEnhance: false)
            }
            BatchMenu(count: $state.count)
            if AppModel.enhancesDescription(of: tool) {
                AutoEnhanceSwitch(style: .panel)
            }
            if let moreOptions { moreOptions }
        }
    }

    private var moreSummary: String? {
        guard let model else { return nil }
        let name = app.catalog.videoChoice(for: model).displayName
        var parts = [state.modelID == nil ? L("Auto") : name]
        if state.count > 1 { parts.append(L("%ld clips", state.count)) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var moreHelp: String {
        guard let model else { return L("Video model and how many clips") }
        let name = app.catalog.videoChoice(for: model).displayName
        return L("Video model and how many clips") + "\n" + (state.modelID == nil ? L("Auto · %@", name) : name)
    }

    private func settingsChip(_ settings: VideoBarSettings, estimate: (cost: VideoCostEstimate, frameModel: VideoModel?)?) -> some View {
        Button {
            showingSettings.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                Text(L("Settings: %@", settings.summary)).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.glass)
        .fixedSize()
        .help(L("Model, length, size, shape and sound"))
        .popover(isPresented: $showingSettings, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 12) {
                if let details = settings.details { details }
                VideoFlowLayout(spacing: 8, centersInRow: true) {
                    modelPicker()
                    if let model { clipChips(model, estimate: estimate) }
                }
                if let reset = settings.reset {
                    Button(L("Restore the effect's settings"), systemImage: "arrow.counterclockwise") { reset() }
                        .buttonStyle(.glass)
                }
            }
            .padding(16)
            .frame(width: 420, alignment: .leading)
            .environment(app)
        }
    }

    @ViewBuilder private func captions(cost: VideoCostEstimate?, typical: ClosedRange<Double>?, frameModel: VideoModel?) -> some View {
        let wait = (frameModel ?? model).map { VideoWaitTimes.label(for: $0) }
        let parts = [wait, frameModel.map { VideoFrameMode.runsOn($0, in: app) }, cost.flatMap { costDetail($0, typical: typical) }, note]
            .compactMap(\.self)
        if !parts.isEmpty {
            let line = parts.enumerated().map { index, part in
                index < parts.count - 1 && part.hasSuffix(".") ? String(part.dropLast()) : part
            }.joined(separator: " · ")
            Label(line, systemImage: wait == nil ? "info.circle" : "clock")
                .fineTextStyle()
                .fixedSize(horizontal: false, vertical: true)
                .help(L("You can keep working while it's made. Video providers bill each clip, even if you stop waiting for it."))
        }
    }

    private func generateTitle(_ cost: VideoCostEstimate?) -> String {
        let clips = cost?.clips ?? state.count
        return clips > 1 ? L("Generate %ld clips", clips) : L("Generate")
    }

    private func sentSeconds(_ estimate: (cost: VideoCostEstimate, frameModel: VideoModel?)?) -> Double? {
        guard let estimate, estimate.frameModel == nil else { return nil }
        if tool.id == "storyboardVideo", tool.choice("mode", in: state.choices) == "One multi-shot clip" { return nil }
        return estimate.cost.seconds
    }

    private var disabledReason: String? {
        if !app.hasAnyKey { return L("Add an API key in Settings") }
        if !app.canMakeVideos { return GenerationEngine.videoKeyMessage }
        if state.isPreparing { return state.preparingStep ?? L("Getting ready…") }
        if model == nil {
            if app.catalog.loadingVideoModels { return L("Loading video models…") }
            return app.videoModels.isEmpty ? L("No video models available. Check your connection.") : L("No compatible model available")
        }
        if let inputReason { return inputReason }
        if let problem = VideoRecipes.problems(for: tool, state: inputs, model: model).first { return problem }
        return blockedReason
    }

    private func costDetail(_ cost: VideoCostEstimate, typical: ClosedRange<Double>?) -> String? {
        if let keyframe = cost.keyframe { return L("Includes the start image (%@).", VideoCostLabel.price(keyframe)) }
        if cost.keyframeUnpriced { return L("Plus the start image, made first.") }
        if cost.video == nil {
            return typical == nil ? L("The price of this model couldn't be read; it's shown after the run.") : L("Final price when it finishes.")
        }
        return nil
    }

    private func typicalRange(_ model: VideoModel) -> ClosedRange<Double>? {
        let resolution = model.clampedResolution(inputs.resolution ?? clipResolution ?? tool.defaults.resolution ?? "720p")
        let sound = VideoModelTraits(model).makesSound && (inputs.audio ?? tool.defaults.audio)
        let video = (tool.takes(.sourceVideo) || tool.takes(.drivingVideo)) && model.acceptsVideoInput
        let prices = [5.0, 10.0].compactMap {
            VideoPricing.estimate(model, seconds: $0, resolution: resolution, aspectRatio: nil, audio: sound, hasVideoInput: video,
                                  imageInputs: tool.takes(.character) || tool.takes(.imageReferences) ? 1 : 0)
        }
        guard let low = prices.min(), let high = prices.max(), high > 0 else { return nil }
        return low...high
    }

    static func rangeLabel(_ range: ClosedRange<Double>, clips: Int) -> String {
        let low = range.lowerBound * Double(max(1, clips)), high = range.upperBound * Double(max(1, clips))
        if high - low < 0.01 { return VideoCostLabel.price(high) }
        return String(format: "≈\u{00A0}$%.2f–%.2f", low, high)
    }

    private func summary(for model: VideoModel) -> String? {
        let cost = app.videoToolCost(tool, inputs: inputs, model: model, count: 1)
        let resolution = model.clampedResolution(inputs.resolution ?? tool.defaults.resolution)
        let line = VideoCostLabel.summary(cost: cost.total, seconds: cost.seconds, resolution: model.resolutions.isEmpty ? nil : resolution)
        return line.isEmpty ? nil : line
    }

    private func availableDurations(_ model: VideoModel) -> [Int] {
        guard let range = tool.durations else { return model.durations }
        let fitting = model.durations.filter { range.contains($0) }
        return fitting.isEmpty ? model.durations : fitting
    }

    private func availableAspects(_ model: VideoModel) -> [String] {
        guard let offered = tool.aspects else { return model.aspectRatios }
        guard !model.aspectRatios.isEmpty else { return offered }
        let fitting = offered.filter { model.aspectRatios.contains($0) }
        return fitting.isEmpty ? model.aspectRatios : fitting
    }

    private var allowsAutoAspect: Bool {
        tool.defaults.aspect == nil || tool.takes(.firstFrame) || tool.takes(.sourceVideo) || tool.takes(.shots)
    }
}

struct VideoRunBarLayout: Layout {
    var spacing: CGFloat = 14
    var rowSpacing: CGFloat = 6

    private struct Arrangement {
        var size: CGSize
        var main: CGRect
        var side: CGRect
        var caption: CGRect?
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let parts = arrange(width: bounds.width, subviews: subviews)
        let frames = [parts.main, parts.side] + (parts.caption.map { [$0] } ?? [])
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func arrange(width proposed: CGFloat?, subviews: Subviews) -> Arrangement {
        guard subviews.count >= 2 else { return Arrangement(size: .zero, main: .zero, side: .zero) }
        let main = subviews[0], side = subviews[1], caption = subviews.count > 2 ? subviews[2] : nil
        let sideWidth = side.sizeThatFits(.unspecified).width
        let sideHeight = side.sizeThatFits(ProposedViewSize(width: sideWidth, height: nil)).height
        let width = proposed.flatMap { $0.isFinite ? $0 : nil } ?? main.sizeThatFits(.unspecified).width + spacing + sideWidth
        let mainWidth = max(0, width - spacing - sideWidth)
        let mainHeight = main.sizeThatFits(ProposedViewSize(width: mainWidth, height: nil)).height
        let sideX = width - sideWidth
        guard let caption else {
            let height = max(mainHeight, sideHeight)
            return Arrangement(size: CGSize(width: width, height: height),
                               main: CGRect(x: 0, y: (height - mainHeight) / 2, width: mainWidth, height: mainHeight),
                               side: CGRect(x: sideX, y: (height - sideHeight) / 2, width: sideWidth, height: sideHeight))
        }
        if caption.sizeThatFits(.unspecified).width <= mainWidth {
            let captionHeight = caption.sizeThatFits(ProposedViewSize(width: mainWidth, height: nil)).height
            let left = mainHeight + rowSpacing + captionHeight
            let height = max(left, sideHeight)
            let top = (height - left) / 2
            return Arrangement(size: CGSize(width: width, height: height),
                               main: CGRect(x: 0, y: top, width: mainWidth, height: mainHeight),
                               side: CGRect(x: sideX, y: (height - sideHeight) / 2, width: sideWidth, height: sideHeight),
                               caption: CGRect(x: 0, y: top + mainHeight + rowSpacing, width: mainWidth, height: captionHeight))
        }
        let row = max(mainHeight, sideHeight)
        let captionHeight = caption.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        return Arrangement(size: CGSize(width: width, height: row + rowSpacing + captionHeight),
                           main: CGRect(x: 0, y: (row - mainHeight) / 2, width: mainWidth, height: mainHeight),
                           side: CGRect(x: sideX, y: (row - sideHeight) / 2, width: sideWidth, height: sideHeight),
                           caption: CGRect(x: 0, y: row + rowSpacing, width: width, height: captionHeight))
    }
}

struct VideoLocalBar: View {
    let title: String
    var reason: String?
    var isWorking = false
    var label: Label<Text, Image>
    var detail: String?
    var estimatedCost: Double?
    var costLabel: String?
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                label.foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            VStack(alignment: .trailing, spacing: 4) {
                GenerateButton(title: title, isEnabled: reason == nil, disabledReason: reason, estimatedCost: estimatedCost,
                               costLabel: costLabel, isWorking: isWorking, action: action)
                if !isWorking, reason != nil {
                    DisabledReasonLabel(reason: reason)
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: VideoLayout.reasonWidth.lowerBound, maxWidth: VideoLayout.reasonWidth.upperBound,
                               alignment: .trailing)
                }
            }
        }
        .animation(Motion.standard, value: reason)
    }
}

enum VideoLayout {
    static let columnWidth: CGFloat = 972
    static let textWidth: CGFloat = 720
    static let inputWidth: CGFloat = (columnWidth - 16) / 2
    static let singleInputWidth: CGFloat = textWidth
    static let reasonWidth: ClosedRange<CGFloat> = 180...220

    static func family(of id: String) -> String {
        NavCatalog.families.first { $0.items.contains(.video(id)) }?.id ?? "create"
    }
}

struct VideoColumns: Layout {
    var minimum: CGFloat
    var maximum: CGFloat = .infinity
    var spacing: CGFloat = 16
    var rowSpacing: CGFloat?
    var fillsRowHeight = false

    struct Cache {
        var width: CGFloat = -1
        var used: CGFloat = -1
        var column: CGFloat = 0
        var count = 1
        var heights: [CGFloat] = []
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func updateCache(_ cache: inout Cache, subviews: Subviews) { cache = Cache() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
            ?? CGFloat(subviews.count) * minimum + spacing * CGFloat(subviews.count - 1)
        let grid = arrange(width: width, subviews: subviews, cache: &cache)
        let gaps: CGFloat = (rowSpacing ?? spacing) * CGFloat(max(0, grid.heights.count - 1))
        let rows: CGFloat = grid.heights.reduce(0, +)
        return CGSize(width: grid.used, height: rows + gaps)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        guard !subviews.isEmpty else { return }
        let grid = arrange(width: bounds.width, subviews: subviews, cache: &cache)
        var y = bounds.minY
        for (row, height) in grid.heights.enumerated() {
            for column in 0..<grid.count {
                let index = row * grid.count + column
                guard index < subviews.count else { break }
                subviews[index].place(at: CGPoint(x: bounds.minX + CGFloat(column) * (grid.column + spacing), y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(width: grid.column, height: fillsRowHeight ? height : nil))
            }
            y += height + (rowSpacing ?? spacing)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews, cache: inout Cache) -> Cache {
        if cache.width == width || cache.used == width { return cache }
        let fit = max(1, Int((width + spacing) / (minimum + spacing)))
        let rows = (subviews.count + fit - 1) / fit
        let count = max(1, (subviews.count + rows - 1) / rows)
        let gaps: CGFloat = spacing * CGFloat(count - 1)
        let column: CGFloat = max(0, min(maximum, (width - gaps) / CGFloat(count)))
        let proposal = ProposedViewSize(width: column, height: nil)
        var heights: [CGFloat] = []
        for start in stride(from: 0, to: subviews.count, by: count) {
            let cells = subviews[start..<min(start + count, subviews.count)]
            heights.append(cells.map { $0.sizeThatFits(proposal).height }.max() ?? 0)
        }
        cache = Cache(width: width, used: CGFloat(count) * column + gaps, column: column, count: count, heights: heights)
        return cache
    }
}

enum VideoSlotTitle {
    static func plain(_ title: String) -> String {
        let marker = " " + L("(optional)")
        return title.hasSuffix(marker) ? String(title.dropLast(marker.count)) : title
    }
}

struct VideoRunNotes: View {
    let state: VideoState
    let recipe: VideoRecipe?
    var extra: [String] = []

    var body: some View {
        var seen = Set<String>()
        let notes = ((recipe?.notes ?? []) + [recipe?.keyframe?.reason ?? ""] + state.runNotes + extra)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(notes, id: \.self) { note in
                    Label(note, systemImage: "info.circle").helperTextStyle()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

enum VideoTextBudget {
    static func limit(_ tool: VideoTool, inputs: VideoToolInputs, model: VideoModel?, field: VideoTextField? = nil) -> Int {
        var overhead = 0
        if let model {
            var s = inputs
            if let field { s.texts[field.id] = "" } else { s.prompt = "" }
            overhead = VideoRecipes.request(for: tool, state: s, model: model)?.request.prompt.utf16.count ?? 0
        }
        let available = VideoPromptBudget.userLimit(model: model, overhead: overhead)
        return field.map { min($0.limit, available) } ?? available
    }

    static func wordBudget(_ text: String, recipe: VideoRecipe?) -> (text: String, isOver: Bool)? {
        let words = text.split(whereSeparator: \.isNewline)
            .map { VideoDialogueLine.parse(String($0)).map(\.text).joined(separator: " ") }
            .reduce(0) { $0 + VideoRecipes.wordCount($1) }
        guard words > 0, let recipe, let seconds = OpenRouterClient.videoDuration(for: recipe.request) else { return nil }
        let budget = VideoRecipes.dialogueWordBudget(seconds: seconds)
        return (L("%ld words; about %ld fit in %ld seconds.", words, budget, seconds), words > budget)
    }
}

struct LocalSoundPicker: View {
    @Binding var file: URL?
    @Binding var duration: Double?
    var title = L("Music (optional)")
    var hint = L("An m4a, mp3 or wav file, mixed in on this Mac")

    @Environment(AppModel.self) private var app

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                symbol
                words.frame(idealWidth: 180, alignment: .leading)
                Spacer(minLength: 0)
                buttons
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    symbol
                    words
                }
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    buttons
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: Radius.tile))
    }

    private var symbol: some View {
        Image(systemName: file != nil ? "music.note.list" : "music.note")
            .iconSymbol(IconScale.large)
            .foregroundStyle(file != nil ? Color.brand : .secondary)
            .frame(width: 30)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let file {
                Text(AudioWell.displayName(file)).font(.headline).lineLimit(1).truncationMode(.middle)
                if let duration { Text(VideoPlayback.durationLabel(duration)).fineTextStyle() }
            } else {
                Text(title).font(.headline)
                Text(hint).helperTextStyle()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var buttons: some View {
        if file != nil {
            Button {
                file = nil
                duration = nil
            } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold)).frame(width: 20, height: 20)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help(L("Remove sound"))
        }
        Button(file == nil ? L("Choose File…") : L("Replace…"), systemImage: "folder") { choose() }
            .buttonStyle(.glass)
            .fixedSize()
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L("Choose a sound file")
        panel.prompt = L("Use")
        guard panel.runModal() == .OK, let source = panel.url else { return }
        Task {
            let copy: URL
            do {
                copy = try await VideoMedia.scratchCopy(of: source, prefix: "audio")
            } catch {
                app.presentError(error)
                return
            }
            file = copy
            duration = nil
            let seconds = try? await AVURLAsset(url: copy).load(.duration).seconds
            if file == copy { duration = seconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } }
        }
    }
}
