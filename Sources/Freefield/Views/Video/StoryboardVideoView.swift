import FreefieldCore
import SwiftUI

struct StoryboardVideoView: View {
    let tool: VideoTool

    @Environment(AppModel.self) private var app
    @State private var choosingImages = false

    var body: some View {
        let state = app.videoState(for: tool)
        let inputs = app.videoInputs(tool, state: state, forRun: false)
        let model = app.resolvedVideoModel(tool, state: state, inputs: inputs)
        let recipes = model.map { VideoRecipes.requests(for: tool, state: inputs, model: $0) } ?? []
        let perFrame = state.choice("mode", in: tool) == "Clip per frame"
        VideoToolScreen(tool: tool, state: state, model: model) {
            VStack(alignment: .leading, spacing: Spacing.l) {
                frames(state)
                if let field = tool.textField(VideoCatalog.extraFieldID) {
                    ExtraInstructionField(text: Binding(get: { state.texts[field.id] ?? "" }, set: { state.texts[field.id] = $0 }),
                                          placeholder: field.placeholder, caption: L("Applies to every shot."),
                                          limit: VideoTextBudget.limit(tool, inputs: inputs, model: model, field: field))
                }
            }
            modes(state, perFrame: perFrame)
            direction(state, recipe: recipes.first)
            VStack(alignment: .leading, spacing: Spacing.l) {
                ExtrasHeader(topPadding: 0)
                joins(state, perFrame: perFrame)
                sound(state, inputs: inputs, model: model)
            }
            VideoRunNotes(state: state, recipe: recipes.first, extra: Self.unique(recipes.dropFirst().flatMap(\.notes)))
            if perFrame { joinShots(state) }
        } bar: {
            VideoRunBar(tool: tool, state: state, inputs: inputs, model: model,
                        blockedReason: textIsTooLong(state, inputs: inputs, model: model) ? L("Shorten the text to fit the selected model") : nil,
                        note: runNote(state, perFrame: perFrame, clips: recipes.count))
        }
        .sheet(isPresented: $choosingImages) {
            LibraryPicker(multiple: true) { add($0.map { (image: $0, action: "") }, to: state) }
                .environment(app)
        }
    }

    @ViewBuilder private func frames(_ state: VideoState) -> some View {
        @Bindable var state = state
        if let slot = tool.slot(.shots) {
            let runs = StoryboardRuns.recent(in: app.library.assets)
            let session = PhotoSessionRuns.all(in: app.library.assets).first
            PanelSection(title: slot.title, systemImage: slot.symbol, step: 1, isDone: framesAreDone(state)) {
                VStack(alignment: .leading, spacing: 10) {
                    latestButton(runs.first, session: session, state: state)
                    HStack(alignment: .top, spacing: 8) {
                        FlowLayout(spacing: 8) {
                            Menu(L("From a Photo Story"), systemImage: "rectangle.split.3x1") {
                                if runs.isEmpty {
                                    Text(L("Make a photo story first in People & Faces ▸ Photo Story."))
                                }
                                ForEach(runs) { run in
                                    Button(run.title) { use(run, state: state) }
                                }
                            }
                            .menuStyle(.button)
                            .fixedSize()
                            Button(L("From Library…"), systemImage: "photo.on.rectangle") { choosingImages = true }
                                .fixedSize()
                            Button(L("Choose Files…"), systemImage: "folder") {
                                add(ImageIntake.pick(multiple: true).map { (image: $0, action: "") }, to: state)
                            }
                            .fixedSize()
                        }
                        if state.shots.contains(where: { $0.image != nil || !$0.action.isEmpty }) {
                            Button(L("Clear"), role: .destructive) {
                                withAnimation(Motion.standard) { state.shots = (0..<max(1, slot.minCount)).map { _ in VideoShotDraft() } }
                            }
                            .fixedSize()
                        }
                    }
                    .buttonStyle(.glass)
                    Text(slot.hint).helperTextStyle()
                    VideoShotsEditor(shots: $state.shots, minimum: slot.minCount, maximum: slot.maxCount, takesImages: true)
                    Text(L("Describe only what moves in each image; the image itself sets the look."))
                        .helperTextStyle()
                }
            }
        }
    }

    @ViewBuilder private func latestButton(_ storyboard: StoryboardRun?, session: PhotoSessionRun?, state: VideoState) -> some View {
        let sessionDate = session?.shots.last?.asset.createdAt
        if let storyboard, sessionDate.map({ (storyboard.frames.last?.asset.createdAt ?? storyboard.date) >= $0 }) ?? true {
            Button(L("Use my latest storyboard"), systemImage: "rectangle.split.3x1.fill") { use(storyboard, state: state) }
                .buttonStyle(.glass)
                .help(storyboard.title)
        } else if let session {
            Button(L("Use my latest photo session"), systemImage: "person.crop.square.on.square.angled") {
                let frames = session.shots.compactMap { shot in app.library.imageData(for: shot.asset).map { VideoShotDraft(image: $0) } }
                let maximum = tool.slot(.shots)?.maxCount ?? 8
                withAnimation(Motion.standard) { state.shots = Array(frames.prefix(maximum)) }
            }
            .buttonStyle(.glass)
            .help(session.title)
        }
    }

    private func add(_ items: [(image: Data, action: String)], to state: VideoState) {
        guard !items.isEmpty else { return }
        let maximum = tool.slot(.shots)?.maxCount ?? 8
        var shots = state.shots
        var pending = items[...]
        for index in shots.indices where shots[index].image == nil {
            guard let next = pending.popFirst() else { break }
            shots[index].image = next.image
            if shots[index].action.isEmpty { shots[index].action = next.action }
        }
        while shots.count < maximum, let next = pending.popFirst() {
            shots.append(VideoShotDraft(action: next.action, image: next.image))
        }
        withAnimation(Motion.standard) { state.shots = shots }
    }

    private func use(_ run: StoryboardRun, state: VideoState) {
        let frames = run.frames.compactMap { frame in app.library.imageData(for: frame.asset).map { (image: $0, action: frame.text) } }
        let maximum = tool.slot(.shots)?.maxCount ?? 8
        withAnimation(Motion.standard) {
            state.shots = frames.prefix(maximum).map { VideoShotDraft(action: $0.action, image: $0.image) }
        }
    }

    private func framesAreDone(_ state: VideoState) -> Bool {
        state.shots.filter { $0.image != nil }.count >= max(1, tool.slot(.shots)?.minCount ?? 1)
    }

    @ViewBuilder private func modes(_ state: VideoState, perFrame: Bool) -> some View {
        let shown = tool.optionGroups.filter { tool.isShown($0.shownWhen, choices: state.choices) }
        ForEach(shown.filter { $0.id == "mode" }) { group in modeGroup(group, state: state, perFrame: perFrame) }
    }

    @ViewBuilder private func joins(_ state: VideoState, perFrame: Bool) -> some View {
        let joins = tool.optionGroups.filter { tool.isShown($0.shownWhen, choices: state.choices) && $0.id != "mode" }
        if !joins.isEmpty {
            let changed = joins.contains { state.choice($0.id, in: tool) != $0.initial }
            OptionalSection(L("How the shots join"), systemImage: "film.stack",
                            summary: joins.map { $0.label(state.choice($0.id, in: tool)) }.joined(separator: " · "),
                            isFilled: changed, storageKey: "video.storyboardVideo.join") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(joins) { group in modeGroup(group, state: state, perFrame: perFrame) }
                }
            }
        }
    }

    private func modeGroup(_ group: VideoOptionGroup, state: VideoState, perFrame: Bool) -> some View {
        PanelSection(title: group.title, systemImage: "square.grid.2x2", step: group.id == "mode" ? 2 : nil,
                     isDone: group.id == "mode" && framesAreDone(state)) {
            VStack(alignment: .leading, spacing: 6) {
                VideoColumns(minimum: 160, spacing: 8, fillsRowHeight: true) {
                    ForEach(group.values.filter { $0 != "AI transition" }, id: \.self) { value in
                        let detail = group.details[value]
                        OptionTile(title: group.label(value), subtitle: detail?.subtitle, systemImage: detail?.symbol,
                                   isSelected: state.choice(group.id, in: tool) == value) {
                            state.choices[group.id] = value
                            if group.id == "mode" { state.modelID = nil }
                        }
                        .help(value == "One multi-shot clip" ? L("Works with stylized faces only (illustration, anime, 3D), not real people.") : "")
                    }
                }
                if group.id == "mode", !perFrame {
                    Label(L("Works with stylized faces only (illustration, anime, 3D), not real people."), systemImage: "info.circle")
                        .helperTextStyle()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private func direction(_ state: VideoState, recipe: VideoRecipe?) -> some View {
        @Bindable var state = state
        let seconds = recipe.flatMap { OpenRouterClient.videoDuration(for: $0.request) }
        PanelSection(title: L("Camera"), systemImage: "video", step: 3, isDone: !state.cameraMoves.isEmpty, isOptional: true) {
            VStack(alignment: .leading, spacing: 6) {
                CameraMoveChip(selection: $state.cameraMoves, strength: $state.strength, limit: CameraMoves.maxMoves(forDuration: seconds))
                Text(L("Used for images without a camera move of their own.")).helperTextStyle()
            }
        }
    }

    @ViewBuilder private func sound(_ state: VideoState, inputs: VideoToolInputs, model: VideoModel?) -> some View {
        @Bindable var state = state
        HStack(alignment: .top, spacing: 16) {
            if let field = tool.textField("sound") {
                let binding = Binding(get: { state.texts[field.id] ?? "" }, set: { state.texts[field.id] = $0 })
                PanelSection(title: VideoSlotTitle.plain(field.title), systemImage: "speaker.wave.2") {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField(field.placeholder, text: binding)
                            .textFieldStyle(.roundedBorder)
                            .characterLimit(binding, VideoTextBudget.limit(tool, inputs: inputs, model: model, field: field),
                                            clampsWhenLimitDrops: false)
                        Text(L("Each clip's own ambience, on models that make sound.")).helperTextStyle()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let slot = tool.slot(.audio) {
                PanelSection(title: VideoSlotTitle.plain(slot.title), systemImage: slot.symbol) {
                    VStack(alignment: .leading, spacing: 4) {
                        LocalSoundPicker(file: $state.audioFile, duration: $state.audioDuration, title: L("Choose a song or track"), hint: slot.hint)
                        Text(L("Replaces the clips' sound once they're joined; it never leaves this Mac.")).helperTextStyle()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func textIsTooLong(_ state: VideoState, inputs: VideoToolInputs, model: VideoModel?) -> Bool {
        tool.textFields.contains { state.text($0.id).utf16.count > VideoTextBudget.limit(tool, inputs: inputs, model: model, field: $0) }
    }

    private func runNote(_ state: VideoState, perFrame: Bool, clips: Int) -> String? {
        guard perFrame, clips > 1 else { return nil }
        return state.count == 1 ? L("%ld clips, one per image, joined in order on this Mac when they're all in (free).", clips)
            : L("%ld clips per image: join the takes you like in Join & Trim.", state.count)
    }

    @ViewBuilder private func joinShots(_ state: VideoState) -> some View {
        let shots = Self.latestShots(in: app.library.assets, toolID: tool.id)
        if shots.count >= 2 {
            let isJoining = state.localWork.contains(where: \.isRunning)
            let isMaking = app.engine.jobs.contains { $0.isRunning && $0.videoSpec?.toolID == tool.id }
            let wasJoined = app.library.assets.contains { $0.isVideo && $0.appID == tool.id && $0.parentAssetID == shots.first?.id }
            PanelSection(title: L("Latest shots"), systemImage: "film.stack") {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(shots) { asset in
                                VideoTile(url: app.library.url(for: asset), posterURL: app.library.posterURL(for: asset),
                                          duration: asset.duration, hasAudio: asset.hasAudio, maxPixel: 300)
                                    .frame(width: 128, height: 80)
                                    .onTapGesture(count: 2) { app.quickLook(asset) }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                    HStack(spacing: 8) {
                        Button(wasJoined ? L("Join Again") : L("Join These Shots"), systemImage: "link") {
                            let flows = state.choice("flow", in: tool) == "Flow into next frame"
                            let crossfade = state.choice("between", in: tool) == "Crossfade" ? 0.5 : 0
                            app.joinOnMac(shots.map { VideoJoinPart(asset: $0) }, crossfade: crossfade, trimSeams: flows,
                                          music: state.audioFile, title: L("Joining the storyboard clips…"),
                                          record: english(tool.name) + " · " + E("%ld shots joined", shots.count), tool: tool, state: state)
                        }
                        .disabled(isJoining || isMaking)
                        .help(isMaking ? L("Wait until every shot is in.") : "")
                        Button(L("Open in Join & Trim"), systemImage: "scissors") {
                            if let joinTool = VideoCatalog.tool("joinClips") {
                                app.videoState(for: joinTool).clipIDs = Array(shots.map(\.id).prefix(JoinTrimView.maximum))
                                app.openVideo(joinTool.id)
                            }
                        }
                    }
                    .buttonStyle(.glass)
                    Text(L("Free, on this Mac. Join & Trim lets you trim each shot and reorder them first."))
                        .helperTextStyle()
                }
            }
        }
    }

    static func latestShots(in assets: [Asset], toolID: String) -> [Asset] {
        let shots = assets.filter { $0.isVideo && $0.appID == toolID && $0.parentAssetID == nil }
        guard let newest = shots.max(by: { $0.createdAt < $1.createdAt }) else { return [] }
        return shots.filter { $0.batchID == newest.batchID }
            .sorted { (frameIndex($0) ?? 0, $0.createdAt) < (frameIndex($1) ?? 0, $1.createdAt) }
    }

    private static func frameIndex(_ asset: Asset) -> Int? {
        guard let match = asset.prompt.firstMatch(of: /·\s*(\d+)\/\d+/) else { return nil }
        return Int(match.1)
    }

    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

struct StoryboardRun: Identifiable {
    struct Frame {
        let asset: Asset
        let scene: Int
        let text: String
    }

    let id: UUID
    let date: Date
    var frames: [Frame]

    var title: String {
        let first = frames.first?.text ?? ""
        let snippet = first.count > 40 ? String(first.prefix(40)) + "…" : first
        let count = frames.count == 1 ? L("1 image") : L("%ld images", frames.count)
        return [count, date.formatted(date: .abbreviated, time: .shortened), snippet].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

enum StoryboardRuns {
    private static var cache: (key: String, runs: [StoryboardRun])?

    static func recent(in assets: [Asset], limit: Int = 8) -> [StoryboardRun] {
        let key = "\(assets.count)|\(assets.first?.id.uuidString ?? "")|\(assets.last?.id.uuidString ?? "")|\(limit)"
        if let cache, cache.key == key { return cache.runs }
        let runs = scan(assets, limit: limit)
        cache = (key, runs)
        return runs
    }

    private static func scan(_ assets: [Asset], limit: Int) -> [StoryboardRun] {
        let frames = assets.filter { $0.tool == .storyboard && !$0.isVideo }
            .compactMap { asset -> StoryboardRun.Frame? in
                guard let match = asset.prompt.firstMatch(of: /^Scene (\d+): (.*)$/.dotMatchesNewlines()),
                      let scene = Int(match.1) else { return nil }
                return StoryboardRun.Frame(asset: asset, scene: scene, text: String(match.2))
            }
            .sorted { $0.asset.createdAt < $1.asset.createdAt }
        var runs: [StoryboardRun] = []
        for frame in frames {
            if var current = runs.last, let last = current.frames.last, frame.scene > last.scene,
               frame.asset.createdAt.timeIntervalSince(last.asset.createdAt) < 30 * 60 {
                current.frames.append(frame)
                runs[runs.count - 1] = current
            } else {
                runs.append(StoryboardRun(id: frame.asset.id, date: frame.asset.createdAt, frames: [frame]))
            }
        }
        return Array(runs.filter { $0.frames.count >= 2 }.reversed().prefix(limit))
    }
}
