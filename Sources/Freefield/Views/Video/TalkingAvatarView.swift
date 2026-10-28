import FreefieldCore
import SwiftUI

struct TalkingAvatarView: View {
    let tool: VideoTool

    @Environment(AppModel.self) private var app
    @State private var faces: FaceCount?
    @State private var isCheckingFaces = false
    @State private var showsAllScenes = false

    private static let firstScenes = 6

    private var draft: TalkingAvatarDraft { .shared }

    var body: some View {
        let state = app.videoState(for: tool)
        let inputs = app.videoInputs(tool, state: state, forRun: false)
        let model = app.resolvedVideoModel(tool, state: state, inputs: inputs)
        let recipe = model.flatMap { VideoRecipes.request(for: tool, state: inputs, model: $0) }
        let isScene = state.choice("mode", in: tool) == "Talking scene"
        VideoToolScreen(tool: tool, state: state, model: model) {
            HStack(alignment: .top, spacing: 16) {
                photo(state)
                    .frame(width: 300)
                voice(state, isScene: isScene, inputs: inputs, model: model, recipe: recipe)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if isScene {
                gestures(state)
                scenes(state, isReady: isReady(state, isScene: isScene, inputs: inputs))
            } else {
                photoOptions(state, isReady: isReady(state, isScene: isScene, inputs: inputs))
            }
            VideoRunNotes(state: state, recipe: recipe)
        } bar: {
            VideoRunBar(tool: tool, state: state, inputs: inputs, model: model,
                        blockedReason: blockedReason(state, isScene: isScene, inputs: inputs, model: model))
        }
        .task(id: state.firstFrame?.count) {
            faces = nil
            isCheckingFaces = false
            guard let data = state.firstFrame, app.canLookWithAI else { return }
            isCheckingFaces = true
            let found = await app.countFaces(in: data)
            guard !Task.isCancelled else { return }
            faces = found
            isCheckingFaces = false
        }
        .onAppear {
            if isScene { draft.useScript(state) } else { draft.useRecording(state) }
        }
    }

    private func voiceTabs(_ state: VideoState, isScene: Bool, model: VideoModel?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(L("What do they say?"), selection: Binding(get: { isScene }, set: { setMode($0 ? "Talking scene" : "Talking photo", state: state) })) {
                Text(L("Type it")).tag(true)
                Text(L("Upload my recording")).tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Text(isScene ? L("The person is filmed saying your words in a setting you pick.")
                 : L("The photo's face lip-syncs your own recording."))
                .helperTextStyle()
                .help(isScene ? L("Made with: %@", model.map { VideoLineup.displayName(for: $0.id, fallback: $0.name) } ?? "Veo 3.1 Lite")
                      : L("Made with HeyGen Avatar IV"))
        }
    }

    private func setMode(_ value: String, state: VideoState) {
        guard state.choices["mode"] != value else { return }
        state.choices["mode"] = value
        state.modelID = nil
        state.duration = tool.defaults.duration
        if value == "Talking scene" { draft.useScript(state) } else { draft.useRecording(state) }
    }

    @ViewBuilder private func photo(_ state: VideoState) -> some View {
        @Bindable var state = state
        if let slot = tool.slot(.firstFrame) {
            PanelSection(title: slot.title, systemImage: "person.crop.square", step: 1, isDone: state.firstFrame != nil) {
                VStack(alignment: .leading, spacing: 8) {
                    ImageWell(title: slot.title, subtitle: slot.hint, systemImage: "person.crop.square", data: $state.firstFrame, minHeight: 200,
                              sources: .person)
                        .frame(height: 220)
                    if let faces {
                        if faces.faces == 0 {
                            Label(L("No face found. Use a front-facing photo with the mouth visible."), systemImage: "exclamationmark.triangle")
                                .font(.callout).foregroundStyle(.orange)
                        } else if faces.faces > 1 {
                            Label(L("More than one face: only one person speaks. Crop the photo to that person."),
                                  systemImage: "person.2")
                                .font(.callout).foregroundStyle(.orange)
                        } else if !faces.mouthVisible {
                            Label(L("The mouth isn't clearly visible. Use a photo where it can be seen."), systemImage: "exclamationmark.triangle")
                                .font(.callout).foregroundStyle(.orange)
                        } else {
                            Label(L("One face found."), systemImage: "checkmark.circle").helperTextStyle()
                        }
                    } else if isCheckingFaces {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(L("Checking the face…")).helperTextStyle()
                        }
                    } else if state.firstFrame == nil, app.canLookWithAI {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("When you add it, the AI checks the face and the mouth."))
                                .helperTextStyle()
                                .fixedSize(horizontal: false, vertical: true)
                            PricePill(text: VideoCostLabel.price(AIChecks.estimate))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func voice(_ state: VideoState, isScene: Bool, inputs: VideoToolInputs, model: VideoModel?,
                                    recipe: VideoRecipe?) -> some View {
        @Bindable var state = state
        let usesRecording = !isScene
        PanelSection(title: L("What do they say?"), systemImage: isScene ? "text.quote" : "waveform", step: 2,
                     isDone: voiceIsDone(state, isScene: isScene, inputs: inputs)) {
            VStack(alignment: .leading, spacing: 10) {
                voiceTabs(state, isScene: isScene, model: model)
                if usesRecording {
                    AudioWell(file: $state.audioFile, duration: $state.audioDuration, link: $state.audioLink,
                              title: L("Your voice"), hint: L("An m4a, mp3 or wav of up to 60 seconds, 15 MB at most"))
                    Text(app.sharesClipsFromMac
                         ? L("The lips follow your recording. It's shared from this Mac through a temporary link only while the video job reads it, then closed.")
                         : L("The lips follow your recording. Sharing from this Mac is off, so paste a link (https) to the file."))
                        .font(.callout).foregroundStyle(app.sharesClipsFromMac ? Color.secondary : .orange)
                        .fixedSize(horizontal: false, vertical: true)
                    if let seconds = state.audioDuration {
                        Label(L("≈%ld s", Int(seconds.rounded())), systemImage: "timer").font(.callout.monospacedDigit())
                            .foregroundStyle(seconds > 60.5 ? Color.orange : .primary)
                        if seconds > 60.5 {
                            Text(L("Use a recording of 60 seconds or less.")).font(.callout).foregroundStyle(.orange)
                        }
                    }
                } else if let field = tool.textField("script") {
                    let binding = Binding(get: { state.texts[field.id] ?? "" }, set: { state.texts[field.id] = $0 })
                    TextField(field.placeholder, text: binding, axis: .vertical)
                        .lineLimit(4...10)
                        .inputBox()
                        .characterLimit(binding, VideoTextBudget.limit(tool, inputs: inputs, model: model, field: field),
                                        clampsWhenLimitDrops: false)
                    Text(L("Spoken exactly as you type it.")).helperTextStyle()
                    scriptTiming(state, isScene: isScene, model: model, recipe: recipe)
                    if isScene { SpokenLanguageMenu(tool: tool, state: state, inputs: inputs) }
                }
            }
        }
    }

    @ViewBuilder private func scriptTiming(_ state: VideoState, isScene: Bool, model: VideoModel?, recipe: VideoRecipe?) -> some View {
        let words = VideoRecipes.wordCount(state.text("script"))
        let spoken = Int((Double(words) / Self.wordsPerSecond).rounded(.up))
        if words > 0 {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label(L("≈%ld s", max(words > 0 ? 1 : 0, spoken)), systemImage: "timer")
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text(words == 1 ? L("1 word") : L("%ld words", words)).font(.callout).foregroundStyle(.secondary)
            }
            if isScene {
                if let recipe, let seconds = OpenRouterClient.videoDuration(for: recipe.request), words > 0 {
                    let budget = VideoRecipes.dialogueWordBudget(seconds: seconds)
                    if words > budget {
                        HStack(spacing: 8) {
                            Text(L("About %ld words fit in %ld seconds, so it would be rushed.", budget, seconds))
                                .font(.callout).foregroundStyle(.orange)
                            if let model, let longer = VideoRecipes.suggestedDuration(forWords: words, model: model), longer > seconds {
                                Button(L("Use %ld s", longer)) { state.duration = longer }
                            }
                        }
                    } else {
                        Text(L("Fits in %ld seconds (about %ld words).", seconds, budget)).helperTextStyle()
                    }
                }
            } else {
                Text(L("People speak about 2.5 words per second, so 20 words take about 8 seconds."))
                    .font(.callout).foregroundStyle(spoken > 60 ? Color.orange : .secondary)
            }
        }
        }
    }

    private static let wordsPerSecond = 2.5

    @ViewBuilder private func photoOptions(_ state: VideoState, isReady: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                tiles("expressiveness", state: state, step: 3, isReady: isReady)
                tiles("background", state: state, step: 4, isReady: isReady)
                captions(state, isReady: isReady)
            }
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    tiles("expressiveness", state: state, step: 3, isReady: isReady)
                    tiles("background", state: state, step: 4, isReady: isReady)
                }
                captions(state, isReady: isReady)
            }
            VStack(alignment: .leading, spacing: 16) {
                tiles("expressiveness", state: state, step: 3, isReady: isReady)
                tiles("background", state: state, step: 4, isReady: isReady)
                captions(state, isReady: isReady)
            }
        }
    }

    private func voiceIsDone(_ state: VideoState, isScene: Bool, inputs: VideoToolInputs) -> Bool {
        isScene ? !state.text("script").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : inputs.hasAudio
    }

    private func isReady(_ state: VideoState, isScene: Bool, inputs: VideoToolInputs) -> Bool {
        state.firstFrame != nil && voiceIsDone(state, isScene: isScene, inputs: inputs)
    }

    @ViewBuilder private func captions(_ state: VideoState, isReady: Bool) -> some View {
        if let captions = tool.group("captions") {
            PanelSection(title: captions.title, systemImage: "captions.bubble", step: 5, isDone: isReady) {
                Toggle(L("Burn captions into the video"),
                       isOn: Binding(get: { state.choice(captions.id, in: tool) == "On" },
                                     set: { state.choices[captions.id] = $0 ? "On" : "Off" }))
                    .toggleStyle(.switch)
            }
            .frame(minWidth: 300, maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder private func tiles(_ id: String, state: VideoState, step: Int, isReady: Bool) -> some View {
        if let group = tool.group(id) {
            let pictures = OptionImages.pictures(videoTool: tool.id, group: group)
            PanelSection(title: group.title, systemImage: "square.grid.2x2", step: step, isDone: isReady) {
                OptionGrid(columns: group.values.count, minimum: pictures == nil ? 96 : 120) {
                    ForEach(group.values, id: \.self) { value in
                        let detail = group.details[value]
                        OptionTile(title: group.label(value), subtitle: detail?.subtitle, systemImage: detail?.symbol,
                                   picture: pictures?[value], isSelected: state.choice(id, in: tool) == value,
                                   compact: pictures != nil) {
                            state.choices[id] = value
                        }
                    }
                }
            }
            .frame(minWidth: pictures == nil ? 300 : CGFloat(group.values.count) * 130, maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder private func scenes(_ state: VideoState, isReady: Bool) -> some View {
        if let group = tool.group("scene") {
            let pictures = OptionImages.pictures(videoTool: tool.id, group: group)
            let selection = state.choice(group.id, in: tool)
            let selectedIndex = group.values.firstIndex(of: selection) ?? 0
            let showsAll = showsAllScenes || selectedIndex >= Self.firstScenes
            PanelSection(title: group.title, systemImage: "film", step: 3, isDone: isReady) {
                VStack(alignment: .leading, spacing: 8) {
                    OptionGrid(minimum: pictures == nil ? 120 : 150) {
                        ForEach(showsAll ? group.values : Array(group.values.prefix(Self.firstScenes)), id: \.self) { value in
                            OptionTile(title: group.label(value), subtitle: pictures == nil ? nil : Self.sceneDetails[value],
                                       systemImage: group.details[value]?.symbol,
                                       picture: pictures?[value], isSelected: selection == value) {
                                state.pick(value, for: group.id)
                            }
                        }
                    }
                    if selectedIndex < Self.firstScenes {
                        Button {
                            withAnimation(Motion.standard) { showsAllScenes.toggle() }
                        } label: {
                            Label(showsAllScenes ? L("Show fewer") : L("See all (%ld)", group.values.count),
                                  systemImage: showsAllScenes ? "chevron.up" : "chevron.down")
                                .font(.callout)
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
        }
    }

    @ViewBuilder private func gestures(_ state: VideoState) -> some View {
        if let field = tool.textField("gestures") {
            let binding = Binding(get: { state.texts[field.id] ?? "" }, set: { state.texts[field.id] = $0 })
            ExtraInstructionField(text: binding, placeholder: field.placeholder, title: field.title,
                                  caption: L("Leave it empty to use the scene's own gestures."), limit: field.limit)
        }
    }

    private static let sceneDetails: [String: String] = [
        "Selfie": L("Front camera at arm's length"),
        "Podcast": L("At a desk with a studio mic"),
        "Car talking": L("Phone on the dashboard, in the driver's seat"),
        "Selling": L("Facing the camera, presenting a product"),
        "Mirror selfie": L("Filmed in a mirror, phone in view"),
        "Stream": L("Webcam at a desk, like a live stream"),
        "Static": L("Camera still on a tripod"),
        "Steadicam": L("A smooth camera that walks with them"),
        "Handheld": L("Close, with a slight shake"),
        "Angry": L("Tense and angry, close up"),
        "Happy": L("Smiling, in warm light"),
        "Crying": L("Teary, in soft light"),
        "Singing": L("They sing the words with feeling"),
        "Rapping": L("They rap to the beat, filmed from below"),
        "CCTV": L("Black-and-white security camera"),
    ]

    private func blockedReason(_ state: VideoState, isScene: Bool, inputs: VideoToolInputs, model: VideoModel?) -> String? {
        if isScene, state.text("script").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L("Write what the person says.")
        }
        if !isScene, draft.voice == .script { return L("A talking photo lip-syncs your own recording. To use a written script, choose “Type it”.") }
        if !isScene, !inputs.hasAudio { return L("Add your recording.") }
        if let field = tool.textField("script"), state.text(field.id).utf16.count > VideoTextBudget.limit(tool, inputs: inputs, model: model, field: field) {
            return L("Shorten the text to fit the selected model")
        }
        return nil
    }
}

@Observable
final class TalkingAvatarDraft {
    static let shared = TalkingAvatarDraft()

    enum Voice: Hashable {
        case script
        case recording
    }

    private(set) var voice = Voice.script
    private var setAsideScript = ""
    private var setAsideAudio: (file: URL?, duration: Double?, link: String)?

    func useRecording(_ state: VideoState) {
        guard voice != .recording else { return }
        setAsideScript = state.texts["script"] ?? ""
        state.texts["script"] = ""
        if let audio = setAsideAudio {
            state.audioFile = audio.file
            state.audioDuration = audio.duration
            state.audioLink = audio.link
            setAsideAudio = nil
        }
        voice = .recording
    }

    func useScript(_ state: VideoState) {
        guard voice != .script else { return }
        if state.audioFile != nil || !state.audioLink.isEmpty {
            setAsideAudio = (state.audioFile, state.audioDuration, state.audioLink)
        }
        state.audioFile = nil
        state.audioDuration = nil
        state.audioLink = ""
        if (state.texts["script"] ?? "").isEmpty { state.texts["script"] = setAsideScript }
        voice = .script
    }
}
