import FreefieldCore
import SwiftUI

struct StoryboardView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedAssetID: UUID?
    @State private var showStyles = false
    @State private var isWriting = false
    @State private var writeError: String?
    @State private var showControls = true
    @State private var canvasWidth: CGFloat = 0

    static let templates: [(id: String, name: String, summary: String, symbol: String, style: String)] = [
        ("movie", L("Movie"), L("Live-action film look"), "film", "live-action cinematic film stills, anamorphic, filmic color grade"),
        ("animated", L("Animated Movie"), L("3D animation, like a family film"), "sparkles.tv", "3D animated feature film stills, expressive characters, soft colorful key light"),
        ("motivational", L("Motivational"), L("Sports ad with epic light"), "flame", "sports commercial stills, hard low sunlight with strong rim light, peak-action moments"),
        ("product", L("Product Promo"), L("Clean commercial shots"), "shippingbox", "product commercial stills, clean art direction, hero shots"),
        ("custom", L("Freeform"), L("No fixed look: your story decides"), "pencil", ""),
    ]

    private var state: ComposerState { app.composer(for: .storyboard) }

    var body: some View {
        StoryboardResults(selectedAssetID: $selectedAssetID)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { canvasWidth = $0 }
            .navigationTitle(Tool.storyboard.title)
            .canvasSubtitle(L("Consistent scenes with the same character and style"), canvasWidth: canvasWidth)
            .inspector(isPresented: $showControls) {
                controls
                    .toolPanelWidth()
            }
            .toolbar {
                ToolbarItem {
                    Button(L("Controls"), systemImage: "sidebar.right") { showControls.toggle() }
                        .help(L("Show or hide controls (⌥⌘I)"))
                        .keyboardShortcut("i", modifiers: [.command, .option])
                }
            }
            .onAppear {
                if state.aspectRatio == .auto { state.aspectRatio = .landscape16x9 }
            }
    }

    private var controls: some View {
        @Bindable var state = state
        let character = app.library.character(state.characterID)
        let requirement = ModelRequirement(images: (character == nil ? 0 : 1) + state.references.count)
        let model = app.resolvedModel(for: state, requirement: requirement)
        let filled = state.storyScenes.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        let writesFirst = filled.isEmpty && !trimmedStory.isEmpty
        let frames = writesFirst ? state.storyFrames : filled.count
        let reason = disabledReason(model: model, filled: filled.count)
        let hasStory = !trimmedStory.isEmpty || !filled.isEmpty
        let cost = frames == 0 ? nil : app.estimatedCost(model: model, count: frames, resolution: state.resolution)
        let title = writesFirst ? L("Write and Create %ld Scenes", frames)
            : filled.isEmpty ? L("Generate Scenes")
            : filled.count == 1 ? L("Generate 1 Scene") : L("Generate %ld Scenes", filled.count)
        let create = {
            guard let model, reason == nil, !isWriting else { return }
            if writesFirst {
                writeScenes(thenCreateWith: model)
            } else {
                app.runStoryboard(state, scenes: filled.map(\.text), model: model)
            }
        }

        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 28) {
                        PanelSection(title: L("The story"), step: 1, isDone: hasStory) {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField(L("E.g. A Mexico City barista discovers that her café is a portal to other worlds"),
                                          text: $state.story, axis: .vertical)
                                    .lineLimit(3...5)
                                    .inputBox()
                                    .characterLimit($state.story, 800)
                                FlowLayout(spacing: 6) {
                                    Button {
                                        writeScenes()
                                    } label: {
                                        if isWriting {
                                            HStack(spacing: 6) {
                                                ProgressView().controlSize(.small)
                                                Text(L("Writing scenes…"))
                                            }
                                        } else {
                                            Label(L("Write with AI"), systemImage: "wand.and.sparkles")
                                        }
                                    }
                                    .buttonStyle(.glass)
                                    .fixedSize()
                                    .disabled(trimmedStory.isEmpty || isWriting || !app.hasAnyKey)
                                    .help(trimmedStory.isEmpty
                                          ? L("Write the story first, then the AI splits it into scenes")
                                          : L("Replaces the scenes below with new ones written from your story"))
                                    ChipMenu(systemImage: "list.number", title: L("AI writes: %ld scenes", state.storyFrames),
                                             help: L("How many scenes the AI writes")) {
                                        Picker(L("Scenes to write"), selection: $state.storyFrames) {
                                            ForEach(2...8, id: \.self) { Text("\($0)").tag($0) }
                                        }
                                        .pickerStyle(.inline)
                                    }
                                }
                                if let writeError {
                                    Text(writeError).font(.callout).foregroundStyle(.orange)
                                }
                                RelatedToolHint(prompt: L("Already have the images?"), links: [app.relatedLink(.video("storyboardVideo"), image: nil)])
                            }
                        }
                        PanelSection(title: L("Scenes"), step: 2, isDone: hasStory) {
                            VStack(spacing: 8) {
                                ForEach($state.storyScenes) { $scene in
                                    let index = state.storyScenes.firstIndex(of: scene) ?? 0
                                    HStack(alignment: .center, spacing: 8) {
                                        Text("\(index + 1)")
                                            .font(.callout.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .frame(minWidth: 16)
                                        TextField(L("What happens in scene %ld", index + 1), text: $scene.text, axis: .vertical)
                                            .lineLimit(1...3)
                                            .inputBox()
                                            .characterLimit($scene.text, 300)
                                        Button {
                                            state.storyScenes.removeAll { $0.id == scene.id }
                                        } label: {
                                            Image(systemName: "minus.circle")
                                        }
                                        .buttonStyle(.borderless)
                                        .disabled(state.storyScenes.count <= 1)
                                        .help(L("Remove scene"))
                                    }
                                }
                                Button(L("Add Scene"), systemImage: "plus") { state.storyScenes.append(StoryScene(text: "")) }
                                    .buttonStyle(.glass)
                                    .disabled(state.storyScenes.count >= 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if writesFirst {
                                    Text(L("Leave them empty and Generate writes %ld scenes from your story first.", state.storyFrames))
                                        .helperTextStyle()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        PanelSection(title: L("Visual style"), step: 3, isDone: hasStory) {
                            let pictures = OptionImages.pictures(family: "storyboard", values: Self.templates.map(\.id))
                            OptionGrid(minimum: pictures == nil ? 110 : PanelLayout.pictureCardMinimum) {
                                ForEach(Self.templates, id: \.id) { item in
                                    OptionTile(title: item.name, subtitle: item.summary, systemImage: item.symbol, picture: pictures?[item.id],
                                               isSelected: state.storyTemplate == item.id) {
                                        state.storyTemplate = item.id
                                    }
                                }
                            }
                        }
                    }
                    ExtrasHeader()
                    VStack(alignment: .leading, spacing: 16) {
                        OptionalSection(L("Main character and style"), systemImage: "person.crop.square",
                                        summary: Self.summary([character?.name, state.presetID.flatMap(StylePresets.preset)?.name].compactMap(\.self)
                                            .joined(separator: " · ")),
                                        isFilled: character != nil || state.presetID != nil, storageKey: "storyboard.cast") {
                            VStack(alignment: .leading, spacing: 6) {
                                FlowLayout(spacing: 8) {
                                    CharacterMenu(selection: $state.characterID, placeholder: L("Choose a saved character…"))
                                    Button {
                                        showStyles = true
                                    } label: {
                                        Label(state.presetID.flatMap(StylePresets.preset)?.name ?? L("Style"), systemImage: "paintpalette")
                                            .lineLimit(1)
                                    }
                                    .buttonStyle(.glass)
                                    .popover(isPresented: $showStyles) {
                                        StylePicker(selection: $state.presetID) { showStyles = false }
                                    }
                                }
                                Text(L("Keeps the same face and look in every scene."))
                                    .helperTextStyle()
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        OptionalSection(L("References"), systemImage: "photo.stack",
                                        summary: state.references.isEmpty ? L("Optional")
                                            : state.references.count == 1 ? L("1 image") : L("%ld images", state.references.count),
                                        isFilled: !state.references.isEmpty, storageKey: "storyboard.references") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(L("Up to 4 images of places, objects or the look you want."))
                                    .helperTextStyle()
                                    .fixedSize(horizontal: false, vertical: true)
                                ReferenceStrip(images: $state.references, limit: 4)
                            }
                        }
                        OptionalSection(L("More options"), systemImage: "slider.horizontal.3",
                                        summary: [state.aspectRatio.label,
                                                  state.modelID == nil ? L("Auto") : model.map { app.catalog.choice(for: $0).displayName } ?? ""]
                                            .filter { !$0.isEmpty }.joined(separator: " · "),
                                        storageKey: "storyboard.moreOptions") {
                            FlowLayout(spacing: 8) {
                                if let model, !model.aspectRatios.isEmpty {
                                    AspectRatioMenu(selection: $state.aspectRatio, available: model.aspectRatios)
                                }
                                ModelPicker(selectionID: $state.modelID, current: model, requirement: requirement)
                            }
                        }
                    }
                }
                .padding(20)
            }
            Divider()
            VStack(spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    GenerateButton(title: title, isEnabled: reason == nil && !isWriting, disabledReason: reason,
                                   estimatedCost: cost, isWorking: isWriting, size: .extraLarge, action: create)
                    GenerateButton(title: title, isEnabled: reason == nil && !isWriting, disabledReason: reason,
                                   estimatedCost: cost, isWorking: isWriting, action: create)
                }
                .frame(maxWidth: .infinity)
                DisabledReasonLabel(reason: reason)
            }
            .animation(reduceMotion ? nil : Motion.standard, value: reason)
            .padding(16)
        }
    }

    private static func summary(_ text: String) -> String { text.isEmpty ? L("Optional") : text }

    private var trimmedStory: String { state.story.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func disabledReason(model: ImageModel?, filled: Int) -> String? {
        if !app.hasAnyKey { return L("Add an API key") }
        if filled == 0 && trimmedStory.isEmpty { return L("Write the story or at least one scene") }
        if model == nil { return app.catalog.isLoading ? L("Loading models…") : L("No model available") }
        return nil
    }

    private func writeScenes(thenCreateWith model: ImageModel? = nil) {
        isWriting = true
        writeError = nil
        Task {
            defer { isWriting = false }
            do {
                let lines = try await app.writeStoryScenes(state)
                withAnimation(reduceMotion ? nil : Motion.standard) { state.storyScenes = lines.map { StoryScene(text: $0) } }
                if let model { app.runStoryboard(state, scenes: lines, model: model) }
            } catch {
                writeError = error.localizedDescription
            }
        }
    }
}

struct StoryboardResults: View {
    @Binding var selectedAssetID: UUID?
    @Environment(AppModel.self) private var app

    var body: some View {
        let feed = FeedModel(app: app, tool: .storyboard)
        if feed.isEmpty {
            VStack(spacing: 18) {
                ContentUnavailableView {
                    Label(L("Your storyboard will appear here"), systemImage: "film.stack")
                } description: {
                    Text(L("Write the story on the right. Pick a character to keep the same face in every scene."))
                }
                if let example = Examples.tool(.storyboard) {
                    ToolExampleCard(example: example)
                        .frame(maxWidth: 560, maxHeight: 220)
                }
            }
            .padding(24)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    videoBar(feed)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 18) {
                        ForEach(feed.batches.reversed()) { batch in
                            if let slot = batch.slots.first {
                                VStack(alignment: .leading, spacing: 6) {
                                    FeedSlotView(slot: slot, batch: batch) { asset in
                                        AssetCard(asset: asset, isSelected: selectedAssetID == asset.id, maxPixel: 700)
                                            .onTapGesture { selectedAssetID = asset.id }
                                            .onTapGesture(count: 2) { app.quickLook(asset) }
                                    }
                                    Text(batch.title).fineTextStyle().lineLimit(2)
                                }
                            }
                        }
                    }
                    .animation(Motion.emphasized, value: feed.slotKeys)
                }
                .padding(20)
            }
        }
    }

    @ViewBuilder private func videoBar(_ feed: FeedModel) -> some View {
        let runs = StoryboardRuns.recent(in: app.library.assets)
        if let run = runs.first(where: { $0.frames.contains { $0.asset.id == selectedAssetID } }) ?? runs.first {
            let isFinished = run.isComplete || run.id != runs.first?.id || !feed.batches.contains { $0.pending > 0 }
            HStack(spacing: 10) {
                Label(run.title, systemImage: "rectangle.split.3x1")
                    .fineTextStyle()
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(L("Make a Video"), systemImage: "video.badge.plus") {
                    app.makeStoryboardVideo(run.frames.map { (asset: $0.asset, action: $0.text) })
                }
                .buttonStyle(.glass)
                .fixedSize()
                .disabled(!isFinished)
                .help(isFinished ? L("Sends this storyboard's frames, in order, to Photos to Video")
                                 : L("Wait until every frame is ready"))
            }
        }
    }
}

extension StoryboardRun {
    var isComplete: Bool {
        guard let prompt = frames.first?.asset.finalPrompt,
              let match = prompt.firstMatch(of: /shot \d+ of (\d+) of a continuous story/),
              let total = Int(match.1) else { return false }
        return frames.count >= total
    }
}
