import FreefieldCore
import SwiftUI

struct VideoRunner: View {
    let tool: VideoTool

    @Environment(AppModel.self) private var app
    @State private var importingProduct = false

    var body: some View {
        if tool.id == "colorGradeVideo" {
            ColorGradeVideoView(tool: tool)
        } else {
            runner
        }
    }

    @ViewBuilder private var runner: some View {
        let state = app.videoState(for: tool)
        let inputs = app.videoInputs(tool, state: state, forRun: false)
        let model = app.resolvedVideoModel(tool, state: state, inputs: inputs)
        let recipe = model.flatMap { VideoRecipes.request(for: tool, state: inputs, model: $0) }
        let steps = stepNumbers(state)
        VideoToolScreen(tool: tool, state: state, model: model) {
            VStack(alignment: .leading, spacing: leadsWithInstructions(state) ? Spacing.l : Spacing.xxl) {
                inputSections(state, inputs: inputs, model: model, recipe: recipe, steps: steps)
                if !Self.hintLast.contains(tool.id) { hint(state) }
                if !instructionsFollowChoices { extraField(state, inputs: inputs, model: model) }
            }
            options(state, inputs: inputs, steps: steps)
            if promptAfterOptions { promptSection(state, inputs: inputs, model: model, steps: steps) }
            if !Self.directionFirst.contains(tool.id) { direction(state, recipe: recipe, step: steps["direction"]) }
            textFields(state, inputs: inputs, model: model, recipe: recipe, fields: shownFields(state).filter { !foldedFields.contains($0.id) },
                       steps: steps)
            if instructionsFollowChoices { extraField(state, inputs: inputs, model: model) }
            if !toolFolds.isEmpty || showsExtras(state, inputs: inputs) {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    ExtrasHeader(topPadding: 0)
                    folds(state, inputs: inputs, model: model, recipe: recipe)
                    extras(state, inputs: inputs)
                }
            }
            if Self.hintLast.contains(tool.id) { hint(state) }
            VideoRunNotes(state: state, recipe: recipe, extra: lockNotes(model: model, inputs: inputs))
        } bar: {
            VideoRunBar(tool: tool, state: state, inputs: inputs, model: model, inputReason: inputReason(state),
                        blockedReason: textIsTooLong(state, inputs: inputs, model: model) ? L("Shorten the text to fit the selected model") : nil,
                        showsAspect: !["upscaleVideo", "reframeVideo", "extendVideo"].contains(tool.id), showsResolution: tool.id != "upscaleVideo",
                        accessory: tool.needsConsent ? AnyView(consent(state)) : nil,
                        clipResolution: clipResolution(inputs, model: model))
        }
        .onChange(of: state.firstFrame != nil) { _, hasImage in
            guard Self.shapeFollowsImage.contains(tool.id), !state.aspectIsPicked else { return }
            state.aspect = hasImage ? nil : tool.defaults.aspect
        }
        .onChange(of: state.productID) { _, id in app.rememberProduct(id) }
        .onChange(of: state.clipIDs.count, initial: true) { _, count in
            if tool.id == "transitions", count >= 2, state.firstFrame == nil, state.lastFrame == nil { state.transitionFromClips = true }
        }
        .task(id: derivedFramesKey(state)) { await app.loadDerivedFrames(tool, state: state) }
        .task(id: subjectKey(state)) { await app.checkPhotoreal(tool, state: state) }
        .sheet(isPresented: $importingProduct) {
            NewProductSheet { product in state.productID = product.id }
        }
    }

    private struct Fold {
        let id: String
        let title: String
        let symbol: String
        var slots: Set<VideoSlot.Kind> = []
        var groups: [String] = []
        var fields: [String] = []
    }

    private static let folds: [String: [Fold]] = [
        "createVideo": [
            Fold(id: "keep", title: L("Same person or product in every clip"), symbol: "person.crop.rectangle.stack",
                 slots: [.character, .product, .imageReferences]),
            Fold(id: "speech", title: L("Dialogue, on-screen text and sound"), symbol: "text.bubble",
                 groups: ["language", "tone"], fields: ["dialogue", "onScreenText", "sound"]),
            Fold(id: "more", title: L("End image, sample video or your own audio"), symbol: "slider.horizontal.3",
                 slots: [.lastFrame, .sourceVideo, .audio]),
        ],
        "videoAd": [
            Fold(id: "person", title: L("Person and start image"), symbol: "person.crop.square", slots: [.character, .firstFrame]),
        ],
        "editVideo": [
            Fold(id: "image", title: L("Style or subject image"), symbol: "photo", slots: [.imageReferences]),
        ],
        "extendVideo": [
            Fold(id: "more", title: L("Method"), symbol: "slider.horizontal.3", groups: ["method"]),
        ],
    ]

    private static let directionFirst: Set<String> = ["createVideo", "animateImage"]
    private static let hintLast: Set<String> = ["animateImage"]
    private static let shapeFollowsImage: Set<String> = ["createVideo"]
    private static let switches: [String: (group: String, on: String, off: String)] = [
        "motionTransfer": ("sound", "Keep original sound", "No sound"),
    ]
    private static let extraPromptTools: Set<String> = ["transitions", "upscaleVideo"]
    private static let gridKinds: Set<VideoSlot.Kind> = [.firstFrame, .lastFrame, .imageReferences, .character, .product, .sourceVideo,
                                                         .drivingVideo, .audio]
    private static let menuGroups: Set<String> = ["language", "targetLanguage", "tone"]

    private var toolFolds: [Fold] { Self.folds[tool.id] ?? [] }
    private var foldedSlots: Set<VideoSlot.Kind> { toolFolds.reduce(into: []) { $0.formUnion($1.slots) } }
    private var foldedGroups: Set<String> { Set(toolFolds.flatMap(\.groups)) }
    private var foldedFields: Set<String> { Set(toolFolds.flatMap(\.fields)) }

    private func showsFrames(_ state: VideoState) -> Bool { tool.id != "transitions" || !state.transitionFromClips }
    private func showsClips(_ state: VideoState) -> Bool { tool.id != "transitions" || state.transitionFromClips }

    private var pairsFrames: Bool { tool.takes(.lastFrame) && !foldedSlots.contains(.lastFrame) }

    private var promptAfterOptions: Bool { tool.inputs.first?.kind != .prompt && tool.slot(.prompt)?.isRequired == false }

    private var gridSlots: [VideoSlot] {
        tool.inputs.filter {
            Self.gridKinds.contains($0.kind) && !foldedSlots.contains($0.kind) && !(pairsFrames && [.firstFrame, .lastFrame].contains($0.kind))
        }
    }

    private var showsPrompt: Bool { tool.slot(.prompt) != nil && !Self.extraPromptTools.contains(tool.id) }

    private func stepKeys(_ state: VideoState) -> [String] {
        var keys: [String] = []
        func add(_ key: String) { if !keys.contains(key) { keys.append(key) } }
        let promptFirst = tool.inputs.first?.kind == .prompt
        let showsDirection = directionShown(state)
        let directionFirst = Self.directionFirst.contains(tool.id)
        if promptFirst {
            if showsPrompt { add("slot.prompt") }
            if directionFirst, showsDirection { add("direction") }
        }
        if tool.slot(.shots) != nil, !foldedSlots.contains(.shots) { add("slot.shots") }
        if tool.slot(.clips) != nil, showsClips(state) { add(tool.id == "transitions" ? "slot.firstFrame" : "slot.clips") }
        if pairsFrames, showsFrames(state), !foldedSlots.contains(.firstFrame), tool.slot(.firstFrame) != nil { add("slot.firstFrame") }
        for slot in gridSlots { add("slot.\(slot.kind.rawValue)") }
        if !promptFirst {
            if directionFirst, showsDirection { add("direction") }
            if !promptAfterOptions, showsPrompt { add("slot.prompt") }
        }
        let groups = shownGroups(state).filter { !foldedGroups.contains($0.id) }
        if groups.count > 4 { add("settings") } else { groups.forEach { add("group.\($0.id)") } }
        if promptAfterOptions, showsPrompt { add("slot.prompt") }
        if !directionFirst, showsDirection { add("direction") }
        shownFields(state).filter { !foldedFields.contains($0.id) }.forEach { add("field.\($0.id)") }
        return keys
    }

    private func stepNumbers(_ state: VideoState) -> [String: Int] {
        let keys = stepKeys(state)
        guard keys.count >= 1 else { return [:] }
        return Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($1, $0 + 1) })
    }

    private func isDone(_ key: String, state: VideoState) -> Bool {
        switch key {
        case "slot.firstFrame":
            if tool.id == "transitions" { return transitionSourcesDone(state) }
            return state.firstFrame != nil && (!pairsFrames || tool.slot(.lastFrame)?.isRequired != true || state.lastFrame != nil)
        case "slot.clips": return state.clipIDs.count >= max(1, tool.slot(.clips)?.minCount ?? 1)
        case "direction": return !state.cameraMoves.isEmpty || state.presetID != nil || state.moodboardID != nil
        default:
            if key.hasPrefix("slot."), let kind = VideoSlot.Kind(rawValue: String(key.dropFirst(5))) { return slotIsFilled(kind, state: state) }
            if key.hasPrefix("field.") { return !state.text(String(key.dropFirst(6))).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return requiredInputsDone(state)
        }
    }

    private func transitionSourcesDone(_ state: VideoState) -> Bool {
        state.transitionFromClips ? state.clipIDs.count >= 2 : state.firstFrame != nil && state.lastFrame != nil
    }

    private func requiredInputsDone(_ state: VideoState) -> Bool {
        if tool.id == "transitions" { return transitionSourcesDone(state) }
        return tool.inputs.allSatisfy { !$0.isRequired || [.script, .drawing].contains($0.kind) || slotIsFilled($0.kind, state: state) }
    }

    private func leadsWithInstructions(_ state: VideoState) -> Bool {
        guard !instructionsFollowChoices else { return false }
        if Self.extraPromptTools.contains(tool.id), tool.slot(.prompt) != nil { return true }
        guard let field = tool.textField(VideoCatalog.extraFieldID) else { return false }
        return tool.isShown(field.shownWhen, choices: state.choices)
    }

    @ViewBuilder private func inputSections(_ state: VideoState, inputs: VideoToolInputs, model: VideoModel?, recipe: VideoRecipe?,
                                            steps: [String: Int]) -> some View {
        @Bindable var state = state
        let promptFirst = tool.inputs.first?.kind == .prompt
        if promptFirst {
            promptSection(state, inputs: inputs, model: model, steps: steps)
            if Self.directionFirst.contains(tool.id) { direction(state, recipe: recipe, step: steps["direction"]) }
        }
        if let slot = tool.slot(.shots), !foldedSlots.contains(.shots) {
            PanelSection(title: VideoSlotTitle.plain(slot.title), systemImage: slot.symbol, step: steps["slot.shots"],
                         isDone: isDone("slot.shots", state: state), isOptional: !slot.isRequired) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(slot.hint).helperTextStyle()
                    VideoShotsEditor(shots: $state.shots, minimum: slot.minCount, maximum: slot.maxCount,
                                     takesImages: tool.id == "storyboardVideo", emotions: tool.group("emotion")?.values ?? [])
                }
            }
        }
        if let slot = tool.slot(.clips), showsClips(state) {
            let isTransition = tool.id == "transitions"
            let key = isTransition ? "slot.firstFrame" : "slot.clips"
            PanelSection(title: isTransition ? L("Two clips") : VideoSlotTitle.plain(slot.title), systemImage: slot.symbol,
                         step: steps[key], isDone: isDone(key, state: state), isOptional: !isTransition && !slot.isRequired) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(slot.hint).helperTextStyle()
                    VideoClipsEditor(clipIDs: $state.clipIDs, minimum: slot.isRequired || isTransition ? slot.minCount : 0, maximum: slot.maxCount)
                    if isTransition { transitionSwitch(state) }
                }
            }
        }
        let pairedFrames = pairsFrames
        if pairedFrames, showsFrames(state), !foldedSlots.contains(.firstFrame), let frames = tool.slot(.firstFrame) {
            VStack(alignment: .leading, spacing: 8) {
                inputCell(frames, state: state, inputs: inputs, model: model, steps: steps)
                if tool.id == "transitions" { transitionSwitch(state) }
            }
        }
        let grid = gridSlots
        if !grid.isEmpty {
            VideoColumns(minimum: 300, maximum: grid.count == 1 ? VideoLayout.singleInputWidth : VideoLayout.inputWidth) {
                ForEach(grid, id: \.kind) { slot in
                    inputCell(slot, state: state, inputs: inputs, model: model, steps: steps)
                }
            }
        }
        if !promptFirst, Self.directionFirst.contains(tool.id) { direction(state, recipe: recipe, step: steps["direction"]) }
        if !promptFirst, !promptAfterOptions { promptSection(state, inputs: inputs, model: model, steps: steps) }
    }

    private func transitionSwitch(_ state: VideoState) -> some View {
        let fromClips = state.transitionFromClips
        return RelatedToolHint(prompt: fromClips ? L("Have two images instead?") : L("Have two clips?"),
                               links: [RelatedToolHint.Link(title: fromClips ? L("Use two images") : L("Use clips")) {
                                   withAnimation(Motion.standard) { state.transitionFromClips.toggle() }
                               }])
    }

    @ViewBuilder private func promptSection(_ state: VideoState, inputs: VideoToolInputs, model: VideoModel?, steps: [String: Int]) -> some View {
        @Bindable var state = state
        if let slot = tool.slot(.prompt), !Self.extraPromptTools.contains(tool.id) {
            PanelSection(title: VideoSlotTitle.plain(slot.title), systemImage: slot.symbol, step: steps["slot.prompt"],
                         isDone: isDone("slot.prompt", state: state), isOptional: tool.id != "createVideo" && !slot.isRequired) {
                TextField(slot.hint, text: $state.prompt, axis: .vertical)
                    .lineLimit(3...8)
                    .inputBox()
                    .characterLimit($state.prompt, promptLimit(inputs, model: model), clampsWhenLimitDrops: false)
                    .frame(maxWidth: VideoLayout.textWidth, alignment: .leading)
            }
        }
    }

    @ViewBuilder private func inputCell(_ slot: VideoSlot, state: VideoState, inputs: VideoToolInputs, model: VideoModel?,
                                        steps: [String: Int], folded: Bool = false) -> some View {
        @Bindable var state = state
        let title = VideoSlotTitle.plain(slot.title)
        let key = "slot.\(slot.kind.rawValue)"
        let step = steps[key]
        let done = step != nil && isDone(key, state: state)
        let optional = !folded && !slot.isRequired
        switch slot.kind {
        case .firstFrame:
            let paired = pairsFrames
            PanelSection(title: paired ? L("Start and end image") : title, systemImage: slot.symbol, step: step, isDone: done, isOptional: optional) {
                FramePicker(first: $state.firstFrame,
                            last: paired ? $state.lastFrame : nil,
                            firstTitle: VideoSlotTitle.plain(slot.title), firstHint: slot.hint,
                            lastTitle: tool.slot(.lastFrame).map { VideoSlotTitle.plain($0.title) } ?? L("End image"),
                            lastHint: tool.slot(.lastFrame)?.hint ?? "",
                            height: tool.id == "createVideo" ? 180 : paired ? 190 : folded ? 170 : 230,
                            maxWellWidth: paired ? VideoLayout.inputWidth : .infinity)
            }
        case .lastFrame:
            PanelSection(title: title, systemImage: slot.symbol, step: step, isDone: done, isOptional: optional) {
                AdaptiveImageWell(title: VideoSlotTitle.plain(slot.title), subtitle: slot.hint, systemImage: slot.symbol,
                                  data: $state.lastFrame, minHeight: 150)
                    .frame(height: 170)
                    .frame(maxWidth: 340)
            }
        case .imageReferences:
            PanelSection(title: title, systemImage: slot.symbol, step: step, isDone: done, isOptional: optional) {
                VStack(alignment: .leading, spacing: 4) {
                    ReferenceStrip(images: $state.references, limit: slot.maxCount, label: slot.title)
                    ElementReferenceButton(images: $state.references, limit: slot.maxCount)
                    Text(slot.hint).helperTextStyle()
                        .fixedSize(horizontal: false, vertical: true)
                        .help(tool.id == "editVideo" ? L("Edits with an image use Runway Aleph 2") : "")
                }
            }
        case .character:
            VideoCharacterSection(title: title, symbol: slot.symbol, step: step, isDone: done, isOptional: optional, hint: slot.hint,
                                  characterID: $state.characterID, photo: $state.characterPhoto, isPhotoreal: state.subjectIsPhotoreal,
                                  height: tool.slot(.sourceVideo)?.isRequired == true || tool.takes(.drivingVideo) ? VideoSourceWell.emptyHeight : 170)
        case .product:
            PanelSection(title: title, systemImage: slot.symbol, step: step, isDone: done, isOptional: optional) {
                VStack(alignment: .leading, spacing: 8) {
                    FlowLayout(spacing: 8) {
                        ProductMenu(selection: $state.productID, placeholder: L("Choose a saved product…"))
                        Button(L("Import from Link…"), systemImage: "link") { importingProduct = true }
                            .buttonStyle(.glass)
                            .fixedSize()
                    }
                    if let product = app.library.product(state.productID) {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(product.photoFileNames.prefix(3), id: \.self) { name in
                                    ThumbnailImage(url: app.library.productPhotoURL(name), maxPixel: 300, contentMode: .fit)
                                        .frame(width: 84, height: 84)
                                        .background(.white.opacity(0.92), in: .rect(cornerRadius: Radius.tile))
                                        .clipShape(.rect(cornerRadius: Radius.tile))
                                }
                            }
                        }
                        .scrollIndicators(.never)
                        Text(L("Up to 3 photos are sent so its label and shape stay exact."))
                            .helperTextStyle()
                    } else if state.productPhotos.isEmpty {
                        ImageWell(title: L("Or photos of the product"), subtitle: L("Up to 3, so its label and shape stay exact"),
                                  systemImage: "shippingbox",
                                  data: Binding(get: { nil }, set: { photo in if let photo { state.productPhotos.append(photo) } }),
                                  minHeight: 150, sources: [.library])
                            .frame(height: 170)
                    } else {
                        ReferenceStrip(images: $state.productPhotos, limit: 3, label: L("Product photos"))
                        Text(L("Up to 3 photos are sent so its label and shape stay exact."))
                            .helperTextStyle()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .sourceVideo:
            PanelSection(title: title, systemImage: slot.symbol, step: step, isDone: done, isOptional: optional) {
                VStack(alignment: .leading, spacing: 8) {
                    VideoSourceWell(pick: $state.source, title: VideoSlotTitle.plain(slot.title), hint: slot.hint,
                                    showsSharingNote: tool.engine == .model && !tool.runsOnDevice(for: state.choices), showsTitle: false)
                    if tool.id == "extendVideo", let frame = state.sourceLastFrame {
                        HStack(spacing: 8) {
                            DataImage(data: frame, maxPixel: 200, contentMode: .fill)
                                .frame(width: 64, height: 40)
                                .clipShape(.rect(cornerRadius: Radius.thumb))
                            Text(L("Continues from the clip's last frame.")).helperTextStyle()
                        }
                    }
                }
            }
        case .drivingVideo:
            PanelSection(title: title, systemImage: slot.symbol, step: step, isDone: done, isOptional: optional) {
                VideoSourceWell(pick: $state.driving, title: VideoSlotTitle.plain(slot.title), hint: slot.hint, showsTitle: false)
            }
        case .audio:
            PanelSection(title: title, systemImage: slot.symbol, step: step, isDone: done, isOptional: optional) {
                AudioWell(file: $state.audioFile, duration: $state.audioDuration, link: $state.audioLink,
                          title: VideoSlotTitle.plain(slot.title), hint: slot.hint)
            }
        default:
            EmptyView()
        }
    }

    private func shownGroups(_ state: VideoState) -> [VideoOptionGroup] {
        tool.optionGroups.filter {
            tool.isShown($0.shownWhen, choices: state.choices) && !["language", "tone"].contains($0.id) && applies($0, state: state)
        }
    }

    private func tileGroups(_ state: VideoState) -> [VideoOptionGroup] {
        shownGroups(state).filter {
            !foldedGroups.contains($0.id) && !Self.menuGroups.contains($0.id)
                && ($0.values.count <= 16 || OptionImages.pictures(videoTool: tool.id, group: $0) != nil)
        }
    }

    @ViewBuilder private func options(_ state: VideoState, inputs: VideoToolInputs, steps: [String: Int]) -> some View {
        let groups = shownGroups(state).filter { !foldedGroups.contains($0.id) }
        if groups.count > 4 {
            PanelSection(title: L("Settings"), systemImage: "slider.horizontal.3", step: steps["settings"], isDone: isDone("settings", state: state)) {
                VideoFlowLayout(spacing: 8) {
                    ForEach(groups) { group in menu(group, state: state, labeled: true) }
                }
            }
        } else {
            ForEach(groups) { group in
                if let toggle = Self.switches[tool.id], toggle.group == group.id {
                    switchSection(group, on: toggle.on, off: toggle.off, state: state, step: steps["group.\(group.id)"])
                } else {
                    groupSection(group, state: state, inputs: inputs, step: steps["group.\(group.id)"])
                }
            }
        }
    }

    private func switchSection(_ group: VideoOptionGroup, on: String, off: String, state: VideoState, step: Int?) -> some View {
        PanelSection(title: group.title, systemImage: group.details[on]?.symbol ?? "switch.2", step: step,
                     isDone: step != nil && requiredInputsDone(state)) {
            Toggle(isOn: Binding(get: { state.choice(group.id, in: tool) == on }, set: { state.pick($0 ? on : off, for: group.id) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.label(on))
                    if let detail = group.details[on]?.subtitle {
                        Text(detail).helperTextStyle()
                    }
                }
            }
            .toggleStyle(.switch)
        }
    }

    private func groupSection(_ group: VideoOptionGroup, state: VideoState, inputs: VideoToolInputs, step: Int?) -> some View {
        let pictures = OptionImages.pictures(videoTool: tool.id, group: group)
        return PanelSection(title: group.title, systemImage: "square.grid.2x2", step: step, isDone: step != nil && requiredInputsDone(state)) {
            VStack(alignment: .leading, spacing: 6) {
                if let pictures {
                    let selection = state.choice(group.id, in: tool)
                    ExpandableOptionGrid(values: group.values, minimum: 160, selection: selection) { value in
                        let detail = group.details[value]
                        OptionTile(title: group.label(value), subtitle: detail?.subtitle,
                                   systemImage: detail?.symbol ?? (value == "My moodboard" ? "paintpalette" : nil),
                                   picture: pictures[value], isSelected: selection == value) {
                            state.pick(value, for: group.id)
                        }
                    }
                } else if Self.menuGroups.contains(group.id) || group.values.count > 16 {
                    menu(group, state: state, labeled: false)
                } else {
                    VideoColumns(minimum: 120, spacing: 8, fillsRowHeight: true) {
                        ForEach(group.values, id: \.self) { value in
                            let detail = group.details[value]
                            OptionTile(title: group.label(value), subtitle: outputSize(group, value: value, inputs: inputs) ?? detail?.subtitle,
                                       systemImage: detail?.symbol,
                                       isSelected: state.choice(group.id, in: tool) == value) {
                                state.pick(value, for: group.id)
                            }
                        }
                    }
                }
            }
        }
    }

    private func applies(_ group: VideoOptionGroup, state: VideoState) -> Bool {
        group.id != "join" || (state.transitionFromClips && state.clipIDs.count >= 2)
    }

    private func menu(_ group: VideoOptionGroup, state: VideoState, labeled: Bool) -> some View {
        let value = state.choice(group.id, in: tool)
        return ChipMenu(systemImage: "chevron.up.chevron.down", title: labeled ? "\(group.title): \(group.label(value))" : group.label(value),
                        help: group.title) {
            Picker(group.title, selection: Binding(get: { value }, set: { state.choices[group.id] = $0 })) {
                ForEach(group.values, id: \.self) { Text(group.label($0)).tag($0) }
            }
            .pickerStyle(.inline)
        }
    }

    private func outputSize(_ group: VideoOptionGroup, value: String, inputs: VideoToolInputs) -> String? {
        guard tool.id == "upscaleVideo", group.id == "factor", let size = inputs.sourceSize, size.width > 0, size.height > 0 else { return nil }
        var factor = VideoPhrases.upscaleFactor(value)
        let cap = 3840 / Double(max(size.width, size.height))
        if factor > cap { factor = max(1.5, cap) }
        return L("Becomes %ld×%ld", Int((size.width * factor).rounded()), Int((size.height * factor).rounded()))
    }

    private static let cameraTools: Set<String> = ["createVideo", "animateImage", "transitions", "drawToVideo", "cinemaStudio"]
    private static let styleTools: Set<String> = ["createVideo", "cinemaStudio"]

    private func usesStyle(_ state: VideoState) -> Bool {
        Self.styleTools.contains(tool.id)
            || (tool.id == "editVideo" && state.choice("mode", in: tool) == "Restyle" && state.choice("restyle", in: tool) == "My moodboard")
    }

    private func directionShown(_ state: VideoState) -> Bool { Self.cameraTools.contains(tool.id) || usesStyle(state) }

    @ViewBuilder private func direction(_ state: VideoState, recipe: VideoRecipe?, step: Int? = nil) -> some View {
        @Bindable var state = state
        let usesCamera = Self.cameraTools.contains(tool.id)
        let usesStyle = usesStyle(state)
        if usesCamera || usesStyle {
            let seconds = recipe.flatMap { OpenRouterClient.videoDuration(for: $0.request) }
            let limit = CameraMoves.maxMoves(forDuration: seconds, allowsThird: tool.id == "animateImage")
            PanelSection(title: usesCamera && usesStyle ? L("Camera and style") : usesCamera ? L("Camera move") : L("Style"),
                         systemImage: "video", step: step, isDone: step != nil && isDone("direction", state: state), isOptional: true) {
                VStack(alignment: .leading, spacing: 6) {
                    FlowLayout(spacing: 8) {
                        if usesCamera { CameraMoveChip(selection: $state.cameraMoves, strength: $state.strength, limit: limit) }
                        if usesStyle { StyleChip(presetID: $state.presetID, moodboardID: $state.moodboardID) }
                    }
                    if usesCamera {
                        Text(limit == 1 ? L("One camera move fits this clip.") : L("Up to %ld camera moves fit this clip; they play in order.", limit))
                            .helperTextStyle()
                    }
                }
            }
        }
    }

    private func shownFields(_ state: VideoState) -> [VideoTextField] {
        tool.textFields.filter { tool.isShown($0.shownWhen, choices: state.choices) && $0.id != VideoCatalog.extraFieldID }
    }

    @ViewBuilder private func textFields(_ state: VideoState, inputs: VideoToolInputs, model: VideoModel?, recipe: VideoRecipe?,
                                         fields: [VideoTextField], steps: [String: Int] = [:]) -> some View {
        ForEach(fields) { field in
            let binding = textBinding(field.id, state: state)
            let isSpoken = field.id == "dialogue" || field.id == "script"
            let key = "field.\(field.id)"
            let step = steps[key]
            let plainTitle = VideoSlotTitle.plain(field.title)
            PanelSection(title: plainTitle, systemImage: field.isLiteral ? "textformat" : "text.cursor", step: step,
                         isDone: step != nil && isDone(key, state: state), isOptional: step != nil && plainTitle != field.title) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField(field.placeholder, text: binding, axis: .vertical)
                        .lineLimit(field.isMultiline ? 2...6 : 1...3)
                        .inputBox()
                        .characterLimit(binding, fieldLimit(field, inputs: inputs, model: model), clampsWhenLimitDrops: false)
                        .frame(maxWidth: VideoLayout.textWidth, alignment: .leading)
                    if field.isLiteral {
                        Text(field.id == "onScreenText" ? L("Shown in the video exactly as you type it.")
                             : L("Spoken exactly as you type it."))
                            .helperTextStyle()
                    }
                    if isSpoken, let budget = VideoTextBudget.wordBudget(state.text(field.id), recipe: recipe) {
                        Text(budget.text).font(.subheadline).foregroundStyle(budget.isOver ? Color.orange : .secondary)
                    }
                    if isSpoken, !state.text(field.id).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        FlowLayout(spacing: 8) {
                            SpokenLanguageMenu(tool: tool, state: state, inputs: inputs)
                            if let tone = tool.group("tone") { menu(tone, state: state, labeled: true) }
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
    }

    private var instructionsFollowChoices: Bool { tool.textField(VideoCatalog.extraFieldID)?.shownWhen != nil }

    @ViewBuilder private func extraField(_ state: VideoState, inputs: VideoToolInputs, model: VideoModel?) -> some View {
        @Bindable var state = state
        if Self.extraPromptTools.contains(tool.id), let slot = tool.slot(.prompt) {
            ExtraInstructionField(text: $state.prompt, placeholder: slot.hint,
                                  title: tool.id == "transitions" ? L("Your instructions (optional)") : slot.title,
                                  limit: promptLimit(inputs, model: model))
        }
        if let field = tool.textField(VideoCatalog.extraFieldID), tool.isShown(field.shownWhen, choices: state.choices) {
            ExtraInstructionField(text: textBinding(field.id, state: state), placeholder: field.placeholder,
                                  limit: fieldLimit(field, inputs: inputs, model: model))
        }
    }

    private func textBinding(_ id: String, state: VideoState) -> Binding<String> {
        Binding(get: { state.texts[id] ?? "" }, set: { state.texts[id] = $0 })
    }

    private func promptLimit(_ inputs: VideoToolInputs, model: VideoModel?) -> Int {
        VideoTextBudget.limit(tool, inputs: inputs, model: model)
    }

    private func fieldLimit(_ field: VideoTextField, inputs: VideoToolInputs, model: VideoModel?) -> Int {
        VideoTextBudget.limit(tool, inputs: inputs, model: model, field: field)
    }

    private func textIsTooLong(_ state: VideoState, inputs: VideoToolInputs, model: VideoModel?) -> Bool {
        if tool.takes(.prompt), state.prompt.utf16.count > promptLimit(inputs, model: model) { return true }
        return tool.textFields.contains { field in
            tool.isShown(field.shownWhen, choices: state.choices) && state.text(field.id).utf16.count > fieldLimit(field, inputs: inputs, model: model)
        }
    }

    @ViewBuilder private func folds(_ state: VideoState, inputs: VideoToolInputs, model: VideoModel?, recipe: VideoRecipe?) -> some View {
        ForEach(toolFolds, id: \.id) { fold in
            let summary = foldSummary(fold, state: state)
            OptionalSection(fold.title, systemImage: fold.symbol, summary: summary.joined(separator: " · "),
                            isFilled: foldIsFilled(fold, state: state), storageKey: "video.\(tool.id).\(fold.id)") {
                let slots = tool.inputs.filter { fold.slots.contains($0.kind) && Self.gridKinds.contains($0.kind) }
                if !slots.isEmpty {
                    VideoColumns(minimum: 300, maximum: slots.count == 1 ? VideoLayout.singleInputWidth : VideoLayout.inputWidth) {
                        ForEach(slots, id: \.kind) { slot in
                            inputCell(slot, state: state, inputs: inputs, model: model, steps: [:], folded: true)
                        }
                    }
                }
                ForEach(shownGroups(state).filter { fold.groups.contains($0.id) }) { group in
                    groupSection(group, state: state, inputs: inputs, step: nil)
                }
                textFields(state, inputs: inputs, model: model, recipe: recipe,
                           fields: shownFields(state).filter { fold.fields.contains($0.id) })
                if fold.slots.contains(.sourceVideo) { referenceModelNote(inputs: inputs, model: model) }
            }
        }
    }

    private func foldSummary(_ fold: Fold, state: VideoState) -> [String] {
        var parts: [String] = []
        for slot in tool.inputs where fold.slots.contains(slot.kind) && slotIsFilled(slot.kind, state: state) {
            switch slot.kind {
            case .character: parts.append(app.library.character(state.characterID)?.name ?? VideoSlotTitle.plain(slot.title))
            case .product: parts.append(app.library.product(state.productID)?.name ?? VideoSlotTitle.plain(slot.title))
            case .imageReferences:
                parts.append(state.references.count == 1 ? L("1 image") : L("%ld images", state.references.count))
            default: parts.append(VideoSlotTitle.plain(slot.title))
            }
        }
        for group in tool.optionGroups where fold.groups.contains(group.id) && !["language", "tone"].contains(group.id) {
            parts.append("\(group.title): \(group.label(state.choice(group.id, in: tool)))")
        }
        for field in tool.textFields where fold.fields.contains(field.id) && !state.text(field.id).trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(VideoSlotTitle.plain(field.title))
        }
        return parts
    }

    private func foldIsFilled(_ fold: Fold, state: VideoState) -> Bool {
        tool.inputs.contains { fold.slots.contains($0.kind) && slotIsFilled($0.kind, state: state) }
            || tool.optionGroups.contains { group in
                fold.groups.contains(group.id) && !["language", "tone"].contains(group.id) && state.choice(group.id, in: tool) != group.initial
            }
            || fold.fields.contains { !state.text($0).trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func slotIsFilled(_ kind: VideoSlot.Kind, state: VideoState) -> Bool {
        switch kind {
        case .prompt: !state.prompt.trimmingCharacters(in: .whitespaces).isEmpty
        case .firstFrame: state.firstFrame != nil
        case .lastFrame: state.lastFrame != nil
        case .imageReferences: !state.references.isEmpty
        case .character: app.library.character(state.characterID) != nil || state.characterPhoto != nil
        case .product: app.library.product(state.productID) != nil || !state.productPhotos.isEmpty
        case .sourceVideo: !state.source.isEmpty
        case .drivingVideo: !state.driving.isEmpty
        case .audio: state.audioFile != nil || !state.audioLink.trimmingCharacters(in: .whitespaces).isEmpty
        case .shots: state.shots.contains { $0.image != nil || !$0.action.isEmpty }
        case .clips: !state.clipIDs.isEmpty
        case .script, .drawing: false
        }
    }

    @ViewBuilder private func referenceModelNote(inputs: VideoToolInputs, model: VideoModel?) -> some View {
        if inputs.firstFrame == nil, inputs.hasSourceVideo || inputs.hasAudio, let model {
            let name = VideoLineup.displayName(for: model.id, fallback: model.name)
            let cost = app.videoToolCost(tool, inputs: inputs, model: model, count: 1).total
            Label(cost.map { L("With a reference video or audio, only some models can make it: this uses %@ (%@ per clip).", name, VideoCostLabel.price($0)) }
                  ?? L("With a reference video or audio, only some models can make it: this uses %@.", name),
                  systemImage: "info.circle")
                .helperTextStyle()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func showsExtras(_ state: VideoState, inputs: VideoToolInputs) -> Bool {
        tool.id == "extendVideo" || (app.offersFrameMode(tool, inputs: inputs) && (!app.sharesClipsFromMac || state.usesFrames))
    }

    @ViewBuilder private func extras(_ state: VideoState, inputs: VideoToolInputs) -> some View {
        @Bindable var state = state
        let framesOffered = app.offersFrameMode(tool, inputs: inputs) && (!app.sharesClipsFromMac || state.usesFrames)
        if showsExtras(state, inputs: inputs) {
            VStack(alignment: .leading, spacing: 8) {
                if tool.id == "extendVideo" {
                    Toggle(L("Also join the clip and its continuation into one video"), isOn: $state.joinsExtension)
                }
                if framesOffered {
                    Toggle(isOn: $state.usesFrames) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Frame-based mode"))
                            Text(VideoFrameMode.explanation)
                                .helperTextStyle()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .help(VideoFrameMode.details)
                }
            }
            .toggleStyle(.checkbox)
        }
    }

    private func consent(_ state: VideoState) -> some View {
        @Bindable var state = state
        return Toggle(L("I have the right to use this person's likeness, and they agreed to it."), isOn: $state.consent)
            .toggleStyle(.checkbox)
            .font(.callout)
    }

    private func lockNotes(model: VideoModel?, inputs: VideoToolInputs) -> [String] {
        guard model == nil, app.hasAnyKey, !app.catalog.loadingVideoModels else { return [] }
        let choices = app.videoModelChoices(tool, inputs: inputs)
        guard !choices.others.contains(where: \.isSelectable),
              let locked = choices.featured.first(where: { !$0.isSelectable }), locked.model.host == .openRouter else { return [] }
        let usesLinks = inputs.hasSourceVideo || inputs.hasAudio || tool.takes(.drivingVideo)
        return [usesLinks
            ? L("This needs an OpenRouter key: clips and sounds reach video models by link, and only OpenRouter's models read them. Add the key in Settings ▸ Account & Keys.")
            : L("The models that can do this need an OpenRouter key. Add it in Settings ▸ Account & Keys.")]
    }

    @ViewBuilder private func hint(_ state: VideoState) -> some View {
        switch tool.id {
        case "createVideo":
            let cinema = RelatedToolHint.Link(title: Self.name("cinemaStudio")) { app.openVideo("cinemaStudio") }
            if state.firstFrame != nil, state.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                RelatedToolHint(links: [
                    RelatedToolHint.Link(title: Self.name("animateImage")) { app.openVideo("animateImage", startImage: state.firstFrame) },
                    cinema,
                ])
            } else {
                RelatedToolHint(prompt: L("Want a director's control?"), links: [cinema])
            }
        case "animateImage":
            RelatedToolHint(links: [
                RelatedToolHint.Link(title: Self.name("videoEffects")) { app.openVideo("videoEffects", startImage: state.firstFrame) },
                RelatedToolHint.Link(title: Self.name("drawToVideo")) { app.openVideo("drawToVideo", startImage: state.firstFrame) },
            ])
        case "editVideo" where Self.mentionsPerson(state.text("change")):
            RelatedToolHint(prompt: L("Changing the person?"), links: [
                RelatedToolHint.Link(title: Self.name("swapVideo")) { app.openVideo("swapVideo", clip: state.source) },
            ])
        default:
            EmptyView()
        }
    }

    private static func name(_ id: String) -> String { VideoCatalog.tool(id)?.name ?? id }

    private static func mentionsPerson(_ text: String) -> Bool {
        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        return words.contains { word in
            ["cara", "caras", "rostro", "rostros", "persona", "personas", "face", "faces", "person", "people"].contains(word)
        }
    }

    private func clipResolution(_ inputs: VideoToolInputs, model: VideoModel?) -> String? {
        guard tool.id == "extendVideo" else { return nil }
        guard let size = inputs.sourceSize, min(size.width, size.height) > 0 else { return "" }
        let label = "\(Int(min(size.width, size.height).rounded()))p"
        return model?.clampedResolution(label) ?? label
    }

    private func inputReason(_ state: VideoState) -> String? {
        if tool.id == "transitions", state.transitionFromClips, state.clipIDs.compactMap(app.library.asset).count < 2 {
            return L("Add two clips.")
        }
        return nil
    }

    private func derivedFramesKey(_ state: VideoState) -> String {
        "\(state.source.assetID?.uuidString ?? "-")|\(state.clipIDs.prefix(2).map(\.uuidString).joined(separator: ","))"
    }

    private func subjectKey(_ state: VideoState) -> String {
        "\(state.characterID?.uuidString ?? "-")|\(state.characterPhoto?.count ?? 0)"
    }
}
