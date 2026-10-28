import CoreGraphics
import Foundation
import FreefieldCore

nonisolated enum VideoFamily: String, Sendable, CaseIterable {
    case seedance, wan, veo, omni, kling, hailuo, grok, runway, flux, heygen, happyhorse, other

    init(slug: String) {
        let slug = slug.lowercased()
        let name = slug.split(separator: "/").last.map(String.init) ?? slug
        if name.contains("seedance") {
            self = .seedance
        } else if name.hasPrefix("wan") {
            self = .wan
        } else if name.contains("veo") {
            self = .veo
        } else if name.hasPrefix("gemini-omni") {
            self = .omni
        } else if name.contains("kling") {
            self = .kling
        } else if name.contains("hailuo") || slug.hasPrefix("minimax/") {
            self = .hailuo
        } else if name.contains("grok") {
            self = .grok
        } else if slug.hasPrefix("runway/") {
            self = .runway
        } else if name.contains("happyhorse") {
            self = .happyhorse
        } else if slug.hasPrefix("black-forest-labs/") || name.contains("flux") {
            self = .flux
        } else if slug.hasPrefix("heygen/") {
            self = .heygen
        } else {
            self = .other
        }
    }
}

nonisolated struct VideoModelTraits: Sendable {
    let slug: String
    let family: VideoFamily
    let kind: VideoModelKind
    let maxImageReferences: Int
    let acceptsVideo: Bool
    let acceptsAudio: Bool
    let controlsSound: Bool

    init(_ model: VideoModel) {
        slug = model.id.lowercased()
        family = VideoFamily(slug: model.id)
        kind = model.kind
        maxImageReferences = model.maxImageReferences
        acceptsVideo = model.acceptsVideoInput
        acceptsAudio = model.acceptsAudioInput
        controlsSound = model.makesAudio
    }

    var isSeedance25: Bool { slug.contains("seedance-2.5") }
    var isWan26: Bool { slug.contains("wan-2.6") }
    var isAvatar: Bool { kind == .avatar }

    var alwaysMakesSound: Bool {
        !controlsSound && (slug.hasPrefix("x-ai/grok-imagine-video") || slug.hasPrefix("alibaba/happyhorse")
            || slug.hasPrefix("heygen/heygen-video") || slug.hasPrefix("google/gemini-omni"))
    }

    var makesSound: Bool { controlsSound || alwaysMakesSound || isAvatar }

    var boundReferences: Int {
        guard kind == .generate, maxImageReferences > 0 else { return 0 }
        switch family {
        case .seedance, .wan, .hailuo, .veo, .omni, .heygen: return maxImageReferences
        case .grok: return slug.contains("1.5") ? 0 : maxImageReferences
        default: return 0
        }
    }

    static let klingLanguages: Set<String> = ["English", "Chinese", "Japanese", "Korean", "Spanish"]

    var promptLimit: Int {
        switch family {
        case .kling: 2_500
        case .wan: isWan26 ? 1_500 : 5_000
        case .hailuo: slug.contains("hailuo-3") ? 7_000 : 2_000
        case .heygen: isAvatar ? 5_000 : 2_000
        default: 4_000
        }
    }

    var usesTokens: Bool { [.seedance, .wan, .hailuo, .heygen, .omni].contains(family) }

    func imageToken(_ n: Int) -> String {
        switch family {
        case .seedance: "@Image \(n)"
        case .wan, .hailuo: "Image \(n)"
        case .heygen: "Picture \(n)"
        case .omni: "<IMAGE_REF_\(n - 1)>"
        default: "the \(Self.ordinal(n)) reference image"
        }
    }

    func videoToken(_ n: Int) -> String {
        switch family {
        case .seedance: "@Video \(n)"
        case .wan, .hailuo, .heygen: "Video \(n)"
        default: n == 1 ? "the reference video" : "the \(Self.ordinal(n)) reference video"
        }
    }

    func audioToken(_ n: Int) -> String {
        switch family {
        case .seedance: "@Audio \(n)"
        case .wan, .hailuo, .heygen: "Audio \(n)"
        default: n == 1 ? "the reference audio" : "the \(Self.ordinal(n)) reference audio"
        }
    }

    static func ordinal(_ n: Int) -> String {
        let words = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"]
        return n >= 1 && n <= words.count ? words[n - 1] : "#\(n)"
    }
}

nonisolated struct VideoSubject: Sendable, Hashable {
    var name = ""
    var details = ""
    var photos: [InputImage] = []
    var isPhotoreal = false
}

nonisolated struct VideoDialogueLine: Sendable, Hashable {
    var speaker = ""
    var text: String
    var tone: String?

    static func parse(_ text: String) -> [VideoDialogueLine] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            if let colon = line.firstIndex(of: ":") {
                let name = line[..<colon].trimmingCharacters(in: .whitespaces)
                let words = unquoted(String(line[line.index(after: colon)...]))
                if !name.isEmpty, name.count <= 30, name.split(separator: " ").count <= 3,
                   !name.contains(where: \.isNumber), !words.isEmpty {
                    return VideoDialogueLine(speaker: name, text: words)
                }
            }
            return VideoDialogueLine(text: unquoted(line))
        }
    }

    static func unquoted(_ text: String) -> String {
        var text = text.trimmingCharacters(in: .whitespaces)
        let quotes: Set<Swift.Character> = ["\"", "\u{201C}", "\u{201D}", "«", "»"]
        while let first = text.first, quotes.contains(first) { text.removeFirst() }
        while let last = text.last, quotes.contains(last) { text.removeLast() }
        return text.trimmingCharacters(in: .whitespaces)
    }
}

nonisolated struct VideoShot: Sendable, Hashable {
    var action = ""
    var camera: String?
    var emotion: String?
    var image: InputImage?
}

nonisolated struct VideoToolInputs: Sendable {
    var prompt = ""
    var motionHint: String?
    var choices: [String: String] = [:]
    var texts: [String: String] = [:]
    var firstFrame: InputImage?
    var firstFrameIsKeyframe = false
    var lastFrame: InputImage?
    var drawing: InputImage?
    var references: [InputImage] = []
    var character: VideoSubject?
    var product: VideoSubject?

    var sourceVideoFile: URL?
    var sourceVideoURL: String?
    var sourceDuration: Double?
    var sourceSize: CGSize?
    var sourceModelID: String?
    var sourceJobID: String?
    var drivingVideoFile: URL?
    var drivingVideoURL: String?
    var drivingDuration: Double?
    var drivingSize: CGSize?
    var audioFile: URL?
    var audioURL: String?
    var audioDuration: Double?

    var style: String?
    var cameraMoves: [String] = []
    var strength: CameraStrength = .normal
    var dialogue: [VideoDialogueLine] = []
    var language: String?
    var shots: [VideoShot] = []
    var effectID: String?

    var duration: Int?
    var resolution: String?
    var aspect: String?
    var audio: Bool?
    var seed: Int?
    var negativePrompt: String?
    var consent = false

    func text(_ id: String) -> String {
        (texts[id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasSourceVideo: Bool { sourceVideoFile != nil || !(sourceVideoURL ?? "").isEmpty }
    var hasDrivingVideo: Bool { drivingVideoFile != nil || !(drivingVideoURL ?? "").isEmpty }
    var hasAudio: Bool { audioFile != nil || !(audioURL ?? "").isEmpty }
}

extension VideoToolInputs {
    @MainActor init(tool: VideoTool) {
        self.init()
        choices = tool.initialChoices
        duration = tool.defaults.duration
        resolution = tool.defaults.resolution
        aspect = tool.defaults.aspect
        audio = tool.defaults.audio
    }

    @MainActor mutating func apply(_ effect: VideoEffect) {
        effectID = effect.id
        duration = effect.duration
        resolution = effect.resolution
        aspect = effect.aspect
        audio = effect.audio
        firstFrameIsKeyframe = false
    }
}

nonisolated struct VideoKeyframePlan: Sendable, Hashable {
    enum Kind: Sendable, Hashable {
        case subject
        case quickStyle(String)
        case adShot(String)
    }

    var kind: Kind
    var scene = ""
    var userTexts: [String] = []
    var reason = ""
    var showsPerson = true
}

nonisolated struct VideoRecipe: Sendable {
    var request: VideoRequest
    var userTexts: [String]
    var literalTexts: [String]
    var title: String
    var record: String
    var keyframe: VideoKeyframePlan?
    var cropFirstFrameTo: String?
    var needsLinks = false
    var sourceSeconds: Double?
    var sourceSize: CGSize?
    var notes: [String] = []

    var needsKeyframe: Bool { keyframe != nil }
}

nonisolated struct VideoCostEstimate: Sendable, Hashable {
    var video: Double?
    var keyframe: Double?
    var keyframeUnpriced = false
    var isFree = false
    var usesHelper = false
    var clips = 1
    var seconds: Double?

    var total: Double? {
        if isFree { return 0 }
        guard let video else { return nil }
        return video + (keyframe ?? 0)
    }
}

enum VideoRecipes {
    static let pendingLinkPlaceholder = "https://pending.invalid/clip.mp4"

    static let nativeContinuationModels: Set<String> = ["black-forest-labs/flux-3-video"]

    static let hookCheckEstimate = 0.01

    static func request(for tool: VideoTool, state: VideoToolInputs, model: VideoModel) -> VideoRecipe? {
        requests(for: tool, state: state, model: model).first
    }

    static func requests(for tool: VideoTool, state: VideoToolInputs, model: VideoModel) -> [VideoRecipe] {
        guard tool.engine == .model, !tool.runsOnDevice(for: state.choices) else { return [] }
        if tool.id == "storyboardVideo" { return storyboard(tool, state, model) }
        let draft: Draft = switch tool.id {
        case "animateImage": animate(tool, state, model)
        case "videoEffects": effect(tool, state, model)
        case "transitions": transition(tool, state, model)
        case "cinemaStudio": cinema(tool, state, model)
        case "talkingAvatar": talkingAvatar(tool, state, model)
        case "extendVideo": extend(tool, state, model)
        case "editVideo": edit(tool, state, model)
        case "motionTransfer": motionTransfer(tool, state, model)
        case "swapVideo": swap(tool, state, model)
        case "upscaleVideo": upscale(tool, state, model)
        case "reframeVideo": reframe(tool, state, model)
        case "videoAd": videoAd(tool, state, model)
        case "drawToVideo": drawToVideo(tool, state, model)
        default: create(tool, state, model)
        }
        return [finish(draft, tool: tool, state: state, model: model)]
    }

    static func preferredModelIDs(for tool: VideoTool, state: VideoToolInputs) -> [String] {
        var first: [String] = []
        switch tool.id {
        case "videoEffects":
            if let effect = state.effectID.flatMap(VideoEffects.effect) { first = [effect.model] }
        case "editVideo" where !state.references.isEmpty:
            first = ["runway/aleph-2"]
        case "extendVideo":
            if let source = state.sourceModelID { first = [source] }
        default:
            break
        }
        var seen = Set<String>()
        return (first + tool.modelIDs(for: state.choices)).filter { seen.insert($0).inserted }
    }

    static func modelFilter(for tool: VideoTool, state s: VideoToolInputs) -> VideoModelFilter {
        var filter = tool.modelFilter(for: s.choices)
        switch tool.id {
        case "createVideo":
            if s.firstFrame != nil {
                filter.firstFrame = true
                if s.lastFrame != nil { filter.lastFrame = true }
            } else {
                if s.hasSourceVideo { filter.videoInput = true }
                if s.hasAudio { filter.audioInput = true }
            }
        case "talkingAvatar":
            if s.hasAudio, filter.kinds.contains(.avatar) { filter.audioInput = true }
        case "editVideo":
            if !s.references.isEmpty { filter.imageReferences = 1 }
        case "extendVideo":
            if isNativeExtend(tool, s, modelID: s.sourceModelID) { filter.firstFrame = false }
        case "storyboardVideo":
            if tool.choice("flow", in: s.choices) == "Flow into next frame",
               tool.choice("mode", in: s.choices) == "Clip per frame" { filter.lastFrame = true }
        default:
            break
        }
        return filter
    }

    static func keyframePlan(for tool: VideoTool, state s: VideoToolInputs, model: VideoModel) -> VideoKeyframePlan? {
        guard !s.firstFrameIsKeyframe else { return nil }
        switch tool.id {
        case "videoEffects":
            guard let effect = s.effectID.flatMap(VideoEffects.effect), let style = effect.quickStyleID,
                  s.firstFrame != nil else { return nil }
            return VideoKeyframePlan(kind: .quickStyle(style),
                                     reason: L("This effect first makes its image with Photo Effects, then animates it."))
        case "videoAd":
            guard s.firstFrame == nil else { return nil }
            let mode = tool.choice("mode", in: s.choices)
            if mode == "Before and after" {
                let before = s.text("before")
                var scene = "The first frame of a before-and-after ad, showing the before state: "
                scene += before.isEmpty ? "the everyday problem the product fixes." : terminated(before)
                scene += " The product is visible nearby but not in use yet."
                return VideoKeyframePlan(kind: .subject, scene: scene, userTexts: before.isEmpty ? [] : [before],
                                         reason: L("Freefield first makes the “before” scene as a still, then animates the change."))
            }
            if let shot = VideoPhrases.adScenes[mode] {
                return VideoKeyframePlan(kind: .subject, scene: shot.scene,
                                         reason: L("Freefield first makes the ad's start image, then animates it."), showsPerson: shot.showsPerson)
            }
            return VideoKeyframePlan(kind: .adShot(VideoPhrases.adKeyframeTools[mode] ?? "product-shoot"),
                                     reason: L("Freefield first makes the ad's start image, then animates it."))
        case "createVideo", "cinemaStudio":
            guard s.firstFrame == nil, model.supportsFirstFrame else { return nil }
            let traits = VideoModelTraits(model)
            let character = s.character.flatMap { $0.photos.isEmpty ? nil : $0 }
            let product = s.product.flatMap { $0.photos.isEmpty ? nil : $0 }
            let characterNeedsStill = character.map { traits.boundReferences == 0 || (traits.family == .seedance && $0.isPhotoreal) } ?? false
            let productNeedsStill = product != nil && traits.boundReferences == 0
            guard characterNeedsStill || productNeedsStill else { return nil }
            var userTexts: [String] = []
            var scene = "The opening frame of a film shot."
            let prompt = s.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !prompt.isEmpty {
                userTexts.append(prompt)
                scene += " " + terminated(prompt)
            }
            if let action = s.shots.first?.action.trimmingCharacters(in: .whitespacesAndNewlines), !action.isEmpty {
                userTexts.append(action)
                scene += " " + terminated(action)
            }
            if tool.id == "cinemaStudio" {
                let film = cinemaLook(tool, s)
                if let setting = film.setting { scene += " " + terminated(setting) }
                if !film.camera.isEmpty { scene += " " + terminated(capitalizedFirst(film.camera.joined(separator: ", "))) }
            }
            let reason = traits.family == .seedance && character?.isPhotoreal == true
                ? L("Seedance doesn't accept photos of real people as references, so Freefield makes a still with the person first, then animates it.")
                : L("This model can't use the photos as references, so Freefield makes a still with them first, then animates it.")
            return VideoKeyframePlan(kind: .subject, scene: scene, userTexts: userTexts, reason: reason)
        default:
            return nil
        }
    }

    static func problems(for tool: VideoTool, state s: VideoToolInputs, model: VideoModel?) -> [String] {
        var list: [String] = []
        func add(_ message: String) { if !list.contains(message) { list.append(message) } }
        let mode = tool.choice("mode", in: s.choices)
        for slot in tool.inputs where slot.isRequired {
            switch slot.kind {
            case .prompt:
                if s.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { add(L("Describe the scene.")) }
            case .firstFrame:
                let hasPhoto = s.firstFrame != nil || (tool.id == "talkingAvatar" && !(s.character?.photos.isEmpty ?? true))
                if !hasPhoto, !(tool.id == "transitions" && s.hasSourceVideo) {
                    add(tool.id == "talkingAvatar" ? L("Add a photo of the person.") : L("Add an image."))
                }
            case .lastFrame:
                if s.lastFrame == nil, s.firstFrame != nil { add(L("Add an end image.")) }
            case .character:
                if s.character?.photos.isEmpty ?? true { add(L("Add a photo of the person, or pick a saved character.")) }
            case .product:
                if s.product?.photos.isEmpty ?? true { add(L("Add a product.")) }
            case .sourceVideo:
                if !s.hasSourceVideo { add(L("Add a clip.")) }
            case .drivingVideo:
                if !s.hasDrivingVideo { add(L("Add the motion video.")) }
            case .script:
                if s.text("script").isEmpty, !s.hasAudio { add(L("Write the script, or add your own voice.")) }
            case .shots:
                let filled = tool.id == "storyboardVideo" ? s.shots.filter { $0.image != nil }.count : s.shots.count
                if filled < slot.minCount { add(L("Add at least %ld images.", slot.minCount)) }
            case .clips:
                break
            case .drawing:
                if s.drawing == nil, s.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    add(L("Draw arrows or notes on the image first."))
                }
            default:
                break
            }
        }
        switch tool.id {
        case "createVideo":
            if s.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, s.firstFrame == nil {
                add(L("Describe your video or add a start image."))
            }
        case "videoEffects":
            if s.effectID.flatMap(VideoEffects.effect) == nil { add(L("Pick an effect.")) }
        case "editVideo":
            if mode == "Describe a change", s.text("change").isEmpty, s.references.isEmpty { add(L("Describe the change.")) }
            if mode == "Restyle", tool.choice("restyle", in: s.choices) == "My moodboard",
               (s.style ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                add(L("Pick a moodboard for this restyle."))
            }
        case "swapVideo":
            if !s.consent { add(L("Confirm you have the right to use this person's likeness.")) }
        case "extendVideo":
            if s.hasSourceVideo, s.sourceVideoFile == nil {
                add(L("Extend Video needs a clip on this Mac, not a link."))
            } else if !isNativeExtend(tool, s, modelID: model?.id), s.firstFrame == nil, s.hasSourceVideo, model != nil {
                add(L("The clip's last frame couldn't be read. Try the clip again."))
            }
        case "talkingAvatar":
            if mode != "Talking scene", s.hasAudio, let seconds = s.audioDuration, seconds > 60.5 {
                add(L("Use a recording of 60 seconds or less."))
            }
        default:
            break
        }
        guard let model, tool.engine == .model, !tool.runsOnDevice(for: s.choices) else { return list }
        let name = VideoLineup.displayName(for: model.id, fallback: model.name)
        if !modelFilter(for: tool, state: s).allows(model) {
            add(L("%@ can't do this. Pick another model.", name))
        }
        let traits = VideoModelTraits(model)
        if traits.family == .seedance, s.character?.isPhotoreal == true, ["swapVideo", "motionTransfer"].contains(tool.id) {
            add(L("Seedance doesn't accept photos of real people. Pick Runway Aleph 2 or Wan 3.0."))
        }
        if tool.id == "storyboardVideo", mode == "One multi-shot clip", traits.boundReferences < 2 {
            add(L("%@ can't make one multi-shot clip from several images. Pick Seedance or Wan.", name))
        }
        return list
    }

    static func dialogueWordBudget(seconds: Int) -> Int { Int((2.5 * Double(max(1, seconds))).rounded(.down)) }

    static func wordCount(_ text: String) -> Int {
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        let ideographs = text.unicodeScalars.filter {
            (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value)
        }.count
        return ideographs > words ? (ideographs + 1) / 2 : words
    }

    static func suggestedDuration(forWords words: Int, model: VideoModel) -> Int? {
        guard !model.durations.isEmpty else { return nil }
        let needed = Int((Double(words) / 2.5).rounded(.up)) + 2
        return model.durations.first { $0 >= needed } ?? model.durations.last
    }

    static let drawHelperInstructions = """
    Image 1 is a frame; Image 2 is the same frame with the director's arrows and notes. Write one short English paragraph describing only the motion: for each arrow, which object moves, its path in frame terms (left, right, up, toward the camera), its speed and the order of events; turn the notes into actions. Do not describe the static scene; never mention arrows or drawings.
    """

    static func estimatedCost(tool: VideoTool, inputs: VideoToolInputs, model: VideoModel, duration: Int?, resolution: String?,
                              aspect: String?, audio: Bool, count: Int, keyframeCost: Double? = nil) -> VideoCostEstimate {
        var s = inputs
        s.duration = duration
        s.resolution = resolution
        s.aspect = aspect
        s.audio = audio
        let batch = max(1, count)
        if tool.engine == .onDevice || tool.runsOnDevice(for: s.choices) {
            return VideoCostEstimate(video: 0, isFree: true, clips: 0)
        }
        if tool.engine == .promptHelper {
            return VideoCostEstimate(video: hookCheckEstimate * Double(batch), usesHelper: true, clips: 0)
        }
        let recipes = requests(for: tool, state: s, model: model)
        var total = 0.0
        var priced = !recipes.isEmpty
        var seconds: Double?
        for recipe in recipes {
            if let cost = VideoPricing.estimate(recipe.request, sourceSeconds: recipe.sourceSeconds, sourceSize: recipe.sourceSize) {
                total += cost
            } else {
                priced = false
            }
            seconds = seconds ?? OpenRouterClient.videoDuration(for: recipe.request).map(Double.init) ?? recipe.sourceSeconds
        }
        let plan = recipes.first?.keyframe
        return VideoCostEstimate(
            video: priced ? total * Double(batch) : nil,
            keyframe: plan == nil ? nil : keyframeCost,
            keyframeUnpriced: plan != nil && keyframeCost == nil,
            clips: recipes.count * batch,
            seconds: seconds
        )
    }

    private struct Draft {
        let traits: VideoModelTraits
        var request: VideoRequest
        var sentences: [String] = []
        var userTexts: [String] = []
        var literalTexts: [String] = []
        var notes: [String] = []
        var spokenWords = 0
        var verbatimPrompt: String?
        var title: String?
        var record: String?
        var sourceSeconds: Double?
        var sourceSize: CGSize?
        var cropFirstFrame = true

        init(_ model: VideoModel, request: VideoRequest) {
            traits = VideoModelTraits(model)
            self.request = request
        }

        var family: VideoFamily { traits.family }

        mutating func add(_ sentence: String?) {
            guard let sentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty else { return }
            sentences.append(VideoRecipes.terminated(sentence))
        }

        mutating func user(_ text: String?) -> String? {
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            if !userTexts.contains(text) { userTexts.append(text) }
            return text
        }

        mutating func literal(_ text: String?) -> String? {
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            if !literalTexts.contains(text) { literalTexts.append(text) }
            return text
        }

        mutating func note(_ text: String) {
            if !notes.contains(text) { notes.append(text) }
        }

        var prompt: String { verbatimPrompt ?? sentences.joined(separator: " ") }
    }

    private static func terminated(_ text: String) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = text.last else { return text }
        let closers: Set<Swift.Character> = [".", "!", "?", "…", "\"", "\u{201D}", "】", ">", "）", ":", ";"]
        return closers.contains(last) ? text : text + "."
    }

    private static func joined(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        default: items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }

    private static func possessive(_ name: String) -> String {
        name.hasSuffix("s") ? name + "'" : name + "'s"
    }

    private static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    private static func baseRequest(_ s: VideoToolInputs, _ tool: VideoTool, _ model: VideoModel) -> VideoRequest {
        VideoRequest(model: model, prompt: "", duration: s.duration ?? tool.defaults.duration,
                     resolution: s.resolution ?? tool.defaults.resolution, aspectRatio: s.aspect,
                     generateAudio: s.audio ?? tool.defaults.audio, seed: s.seed)
    }

    private static func clipLength(_ request: VideoRequest) -> Int? {
        OpenRouterClient.videoDuration(for: request) ?? request.model.clampedDuration(request.duration)
    }

    private static func soundOn(_ d: Draft) -> Bool {
        d.request.generateAudio == true && d.traits.makesSound
    }

    private static func link(_ url: String?, file: URL?) -> String? {
        if let url = url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty { return url }
        return file == nil ? nil : pendingLinkPlaceholder
    }

    private static func sentClip(duration: Double?, size: CGSize?, url: String?, file: URL?, fullSize: Bool = false,
                                 _ d: inout Draft) -> (duration: Double?, size: CGSize?) {
        let given = url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard file != nil, given.isEmpty || given == pendingLinkPlaceholder || ClipSharing.isTunnelLink(given) else {
            return (duration, size)
        }
        var seconds = duration
        if let duration, duration > VideoMedia.shareMaxSeconds + 0.05 {
            seconds = VideoMedia.shareMaxSeconds
            d.note(L("Only the first %ld seconds of the clip are sent.", Int(VideoMedia.shareMaxSeconds)))
        }
        return (seconds, size.map { VideoMedia.sharedSize(of: $0, fullSize: fullSize) })
    }

    private static func nearestRatio(to size: CGSize?, model: VideoModel) -> String? {
        guard let size, size.width > 0, size.height > 0, !model.aspectRatios.isEmpty else { return nil }
        return model.bestAspectRatio("\(Int(size.width.rounded())):\(Int(size.height.rounded()))")
    }

    private static func spokenLanguage(_ s: VideoToolInputs, _ tool: VideoTool, group: String = "language") -> String {
        if let language = s.language?.trimmingCharacters(in: .whitespaces), !language.isEmpty { return language }
        let chosen = tool.choice(group, in: s.choices)
        return chosen.isEmpty ? "English" : chosen
    }

    private static func extraInstructions(_ tool: VideoTool, _ s: VideoToolInputs) -> String? {
        guard let field = tool.textField(VideoCatalog.extraFieldID), tool.isShown(field.shownWhen, choices: s.choices) else { return nil }
        return s.text(field.id).nonBlank
    }

    private static func dialogue(_ s: VideoToolInputs) -> [VideoDialogueLine] {
        s.dialogue.isEmpty ? VideoDialogueLine.parse(s.texts["dialogue"] ?? "") : s.dialogue
    }

    private static func cameraLine(_ ids: [String], strength: CameraStrength?, seconds: Int?, allowsThird: Bool = false,
                           _ d: inout Draft) -> String? {
        var seen = Set<String>()
        let moves = ids.filter { seen.insert($0).inserted }.compactMap(CameraMoves.move)
        guard !moves.isEmpty else { return nil }
        let limit = CameraMoves.maxMoves(forDuration: seconds, allowsThird: allowsThird)
        if moves.count > limit {
            d.note(L("Only %ld camera moves fit a %ld-second clip; the others were left out.", limit, seconds ?? 5))
        }
        if moves.prefix(limit).contains(where: \.isBig), ![.kling, .veo].contains(d.family) {
            d.note(L("Big camera moves like orbits, FPV flights and crash zooms work best on Kling or Veo."))
        }
        return CameraMoves.combined(moves.map(\.id), strength: strength, family: d.family, limit: limit).map {
            $0.hasPrefix("The camera") ? $0 : "Camera: " + $0
        }
    }

    private static func toneWords(_ tone: String?, adjective: Bool) -> String? {
        guard let tone = tone?.trimmingCharacters(in: .whitespaces), !tone.isEmpty, tone != "Natural", tone != "Auto" else { return nil }
        let adverbs = ["Warm": "warmly", "Excited": "excitedly", "Calm": "calmly", "Serious": "seriously", "Playful": "playfully",
                       "Whispering": "in a whisper", "Angry": "angrily", "Sad": "sadly"]
        if adjective { return tone.lowercased() }
        return adverbs[tone] ?? tone.lowercased()
    }

    private static func addDialogue(_ lines: [VideoDialogueLine], language: String, tone: String?, phrase: String? = nil,
                            speaker fallback: String, verb: String = "says", _ d: inout Draft) {
        var spoke = false
        for line in lines {
            guard let text = d.literal(line.text) else { continue }
            spoke = true
            d.spokenWords += wordCount(text)
            let speaker = line.speaker.trimmingCharacters(in: .whitespaces).isEmpty ? fallback : line.speaker
            let manner = phrase ?? toneWords(line.tone ?? tone, adjective: d.family == .kling)
            switch d.family {
            case .kling:
                let delivery = [verb == "says" ? nil : participle(verb), manner.map(adjectivePhrase)].compactMap { $0 }
                d.add("\(speaker) (\(delivery.map { "\($0), " }.joined())\(language)): \"\(text)\"")
            case .seedance where language == "English" || language == "Chinese":
                d.add(manner.map { "\(speaker) \(verb), \($0): \"\(text)\"" } ?? "\(speaker) \(verb): \"\(text)\"")
            default:
                d.add("\(speaker) \(verb) in \(language)\(manner.map { ", \($0)" } ?? ""): \"\(text)\"")
            }
        }
        guard spoke else { return }
        if d.family == .kling, !VideoModelTraits.klingLanguages.contains(language) {
            d.note(L("Kling voices speak English, Chinese, Japanese, Korean and Spanish; %@ will come out in English.", L(language)))
        }
        if !d.traits.makesSound {
            d.note(L("This model makes no sound, so the dialogue won't be heard."))
        } else if d.traits.controlsSound, d.request.generateAudio != true {
            d.note(L("Sound is off, so the dialogue won't be heard."))
        }
    }

    private static func participle(_ verb: String) -> String {
        switch verb {
        case "sings": "singing"
        case "raps": "rapping"
        case "says": "speaking"
        default: verb.hasSuffix("s") ? String(verb.dropLast()) + "ing" : verb
        }
    }

    private static func adjectivePhrase(_ phrase: String) -> String {
        let adjectives = ["warmly": "warm", "confidently": "confident", "casually": "casual", "enthusiastically": "enthusiastic",
                          "energetically": "energetic", "clearly": "clear", "naturally": "natural", "angrily": "angry",
                          "happily": "happy", "tearfully": "tearful", "rhythmically": "rhythmic", "quietly": "quiet",
                          "excitedly": "excited", "calmly": "calm", "seriously": "serious", "playfully": "playful", "sadly": "sad"]
        return phrase.split(separator: " ").map { adjectives[String($0)] ?? String($0) }.joined(separator: " ")
    }

    private static func soundCue(_ sound: String, _ d: Draft) -> String {
        switch d.family {
        case .seedance: "< \(sound) >"
        case .veo: "Ambient noise: \(sound)"
        default: "Sound: \(sound)"
        }
    }

    private static func musicCue(_ music: String, _ d: Draft) -> String {
        d.family == .seedance ? "（\(music)）" : "Music: \(music)"
    }

    private static func addSound(_ sound: String?, hasDialogue: Bool, _ d: inout Draft) {
        guard soundOn(d) else {
            if d.traits.alwaysMakesSound { d.add("Quiet natural ambience only, with no music or speech") }
            return
        }
        if let sound = d.user(sound) { d.add(soundCue(sound, d)) }
        if d.family == .wan, !hasDialogue { d.add("No dialogue") }
    }

    private static func addTextRule(onScreen: String?, _ d: inout Draft) {
        if let text = d.literal(onScreen) {
            d.add(d.family == .seedance ? "On-screen text: 【\(text)】" : "The on-screen text reads \"\(text)\", spelled exactly, shown once")
            return
        }
        let prompt = d.prompt.lowercased()
        if !prompt.contains("on-screen text"), !prompt.contains("subtitles") { d.add("No on-screen text or subtitles") }
    }

    private static func providerParameters(_ d: Draft, override: String?, extraNegative: [String] = [], wantsText: Bool = false) -> [String: JSONValue] {
        let keys = Set(d.request.model.passthrough)
        var parameters: [String: JSONValue] = [:]
        let sendsImage = d.request.firstFrame != nil || d.request.references.contains { $0.image != nil }
        if keys.contains("personGeneration"), sendsImage { parameters["personGeneration"] = "allow_adult" }
        let custom = override?.trimmingCharacters(in: .whitespacesAndNewlines).nonBlank
        if keys.contains("negative_prompt") {
            let terms = ["low resolution", "deformed", "extra fingers", "bad proportions", "flicker", "watermark"] + extraNegative
                + (wantsText ? [] : ["subtitles"])
            parameters["negative_prompt"] = .string(String((custom ?? terms.joined(separator: ", ")).prefix(500)))
        }
        if keys.contains("negativePrompt") {
            let terms = ["watermark", "distorted hands", "extra limbs", "flicker"] + (wantsText ? [] : ["subtitles", "on-screen text"])
            parameters["negativePrompt"] = .string(String((custom ?? terms.joined(separator: ", ")).prefix(500)))
        }
        if !d.literalTexts.isEmpty {
            for key in ["prompt_extend", "enable_prompt_expansion", "prompt_optimizer", "prompt_enhancement"] where keys.contains(key) {
                parameters[key] = false
            }
        }
        return parameters
    }

    private struct Binding {
        var references: [VideoInput] = []
        var before: [String] = []
        var after: [String] = []
        var lead: String?
    }

    private static func bind(character: VideoSubject?, product: VideoSubject?, extra: [InputImage], video: String?, audio: String?,
                     _ d: inout Draft) -> Binding {
        var binding = Binding()
        let traits = d.traits
        let capacity = traits.boundReferences
        var images = 0
        var roles: [String] = []
        var dropped = false

        func take(_ photos: [InputImage], max limit: Int) -> [String] {
            let count = min(photos.count, limit, capacity - images)
            guard count > 0 else {
                if !photos.isEmpty { dropped = true }
                return []
            }
            if count < min(photos.count, limit) { dropped = true }
            let tokens = (images + 1...images + count).map(traits.imageToken)
            binding.references += photos.prefix(count).map(VideoInput.image)
            images += count
            return tokens
        }

        if let character, !character.photos.isEmpty {
            let tokens = take(character.photos, max: 3)
            if !tokens.isEmpty {
                let name = character.name.trimmingCharacters(in: .whitespaces)
                let who = name.isEmpty ? "the main person" : name
                let details = d.user(character.details).map { " (\($0))" } ?? ""
                let list = joined(tokens)
                switch traits.family {
                case .seedance:
                    binding.before.append(name.isEmpty ? "The person in \(list)\(details) is the main character"
                                          : "Use the person in \(list) as \(name)\(details)")
                case .hailuo:
                    binding.before.append("\(list): \(who), the main character\(details)")
                case .veo:
                    roles.append("\(who)\(details)")
                default:
                    binding.before.append("\(capitalizedFirst(list)) \(tokens.count == 1 ? "shows" : "show") \(who)\(details)")
                }
                let anchor = traits.family == .veo ? "the provided image" : tokens[0]
                let face = "\(capitalizedFirst(possessive(name.isEmpty ? "the person" : name))) face stays consistent with \(anchor) throughout"
                binding.after.append(traits.family == .seedance ? face + "; no identical duplicate characters" : face)
            }
        }
        if let product, !product.photos.isEmpty {
            let tokens = take(product.photos, max: 3)
            if !tokens.isEmpty {
                let name = product.name.trimmingCharacters(in: .whitespaces)
                let details = d.user(product.details).map { " (\($0))" } ?? ""
                let what = name.isEmpty ? "the product\(details)" : "\(name)\(details)"
                let list = joined(tokens)
                switch traits.family {
                case .seedance: binding.before.append("Use the product in \(list) exactly as shown: \(what)")
                case .hailuo: binding.before.append("\(list): the product, \(what)")
                case .veo: roles.append("the product, \(what)")
                default: binding.before.append("\(capitalizedFirst(list)) \(tokens.count == 1 ? "shows" : "show") the product: \(what)")
                }
                let anchor = traits.family == .veo ? "the provided images" : tokens[0]
                binding.after.append("The product's shape, label, logo and colors stay exactly as in \(anchor), with no redesign or relabeling")
            }
        }
        if !extra.isEmpty {
            let tokens = take(extra, max: extra.count)
            if !tokens.isEmpty {
                let list = joined(tokens)
                if traits.family == .veo {
                    roles.append("the scene details")
                } else {
                    binding.before.append("\(capitalizedFirst(list)) \(tokens.count == 1 ? "is an extra reference" : "are extra references"): use \(tokens.count == 1 ? "it" : "them") only for what the description names")
                }
            }
        }
        if dropped {
            d.note(capacity == 0
                   ? L("%@ can't use reference images; they were left out.", d.request.model.name)
                   : L("%@ takes up to %ld reference images; the rest were left out.", d.request.model.name, capacity))
        }
        if let video {
            if traits.acceptsVideo {
                binding.references.append(.videoURL(video))
                binding.before.append("\(capitalizedFirst(traits.videoToken(1))) sets the motion and pacing to follow")
            } else {
                d.note(L("%@ can't use a reference video; it was left out.", d.request.model.name))
            }
        }
        if let audio {
            if traits.acceptsAudio {
                binding.references.append(.audioURL(audio))
                binding.before.append("\(capitalizedFirst(traits.audioToken(1))) is the soundtrack: match its voice, music and timing")
            } else {
                d.note(L("%@ can't use a reference audio track; it was left out.", d.request.model.name))
            }
        }
        if !roles.isEmpty {
            binding.lead = "Using the provided images for \(joined(roles)), create this scene:"
        }
        return binding
    }

    private static func frameIdentity(character: VideoSubject?, product: VideoSubject?, _ d: inout Draft) {
        if character != nil { d.add("The person keeps the same face, hair and clothing throughout") }
        if let product {
            let name = product.name.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { d.add("The product is \(name)") }
            d.add("The product's shape, label, logo and colors stay exactly as in the first frame")
        }
    }

    private static func canBindCharacter(_ character: VideoSubject?, _ traits: VideoModelTraits) -> Bool {
        guard let character else { return false }
        return traits.boundReferences > 0 && !(traits.family == .seedance && character.isPhotoreal)
    }

    private static func create(_ tool: VideoTool, _ s: VideoToolInputs, _ model: VideoModel) -> Draft {
        var d = Draft(model, request: baseRequest(s, tool, model))
        let frame = model.supportsFirstFrame ? s.firstFrame : nil
        var binding = Binding()
        if let frame {
            d.request.firstFrame = frame
            if let last = s.lastFrame {
                if model.supportsLastFrame { d.request.lastFrame = last } else { d.note(L("%@ can't use an end image; it was left out.", model.name)) }
            }
            let hasReferences = s.character != nil || s.product != nil || !s.references.isEmpty
            if hasReferences, !s.firstFrameIsKeyframe {
                d.note(L("The start image sets the scene, so the character, product and reference images aren't sent."))
            }
            if s.hasSourceVideo || s.hasAudio { d.note(L("With a start image, the reference video and audio aren't sent.")) }
        } else {
            if s.firstFrame != nil { d.note(L("%@ can't start from an image; the start image was left out.", model.name)) }
            if s.lastFrame != nil { d.note(L("An end image needs a start image; it was left out.")) }
            binding = bind(character: canBindCharacter(s.character, d.traits) ? s.character : nil,
                           product: d.traits.boundReferences > 0 ? s.product : nil,
                           extra: s.references, video: link(s.sourceVideoURL, file: s.sourceVideoFile),
                           audio: link(s.audioURL, file: s.audioFile), &d)
            d.request.references = binding.references
            if binding.references.contains(where: { if case .videoURL = $0 { true } else { false } }) {
                d.sourceSeconds = sentClip(duration: s.sourceDuration, size: s.sourceSize, url: s.sourceVideoURL,
                                           file: s.sourceVideoFile, &d).duration
            }
            if s.hasSourceVideo || s.hasAudio, keyframePlan(for: tool, state: s, model: model) != nil {
                d.note(L("With a start image, the reference video and audio aren't sent."))
            }
        }
        let seconds = clipLength(d.request)

        if d.family == .hailuo, let seconds {
            d.add([String(seconds) + "s", d.request.aspectRatio].compactMap { $0 }.joined(separator: ", "))
        }
        binding.before.forEach { d.add($0) }
        let camera = cameraLine(s.cameraMoves, strength: s.strength, seconds: seconds, &d)
        if d.family == .veo { d.add(camera) }
        let hint = s.motionHint?.nonBlank
        let body = d.user(s.prompt) ?? (frame != nil && hint == nil ? "Natural, subtle motion of the subject" : nil)
        let opening = [binding.lead, body].compactMap { $0 }.joined(separator: " ")
        d.add(opening)
        if let hint { d.add("Motion to follow: \(hint)") }
        if d.family != .veo { d.add(camera) }
        if frame == nil, let style = d.user(s.style) {
            d.add("Style: \(style)")
        } else if frame != nil, !(s.style ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            d.note(L("The start image sets the look, so the style isn't added."))
        }
        let lines = dialogue(s)
        addDialogue(lines, language: spokenLanguage(s, tool), tone: tool.choice("tone", in: s.choices),
                    speaker: s.character?.name.nonBlank ?? "The person", &d)
        addSound(s.text("sound"), hasDialogue: !lines.isEmpty, &d)
        if frame != nil {
            if s.firstFrameIsKeyframe { frameIdentity(character: s.character, product: s.product, &d) }
            d.add(d.request.lastFrame != nil ? "The clip ends exactly on the last frame" : "Everything else stays exactly as in the first frame")
        } else {
            binding.after.forEach { d.add($0) }
        }
        addTextRule(onScreen: s.text("onScreenText"), &d)
        d.request.providerParameters = providerParameters(d, override: s.negativePrompt, wantsText: !s.text("onScreenText").isEmpty)
        return d
    }

    private static func animate(_ tool: VideoTool, _ s: VideoToolInputs, _ model: VideoModel) -> Draft {
        var d = Draft(model, request: baseRequest(s, tool, model))
        d.request.firstFrame = s.firstFrame
        let seconds = clipLength(d.request)
        let motion = d.user(s.prompt)
        d.add(motion)
        let moves = s.cameraMoves.isEmpty ? ["general"] : s.cameraMoves
        let camera = cameraLine(moves, strength: s.strength, seconds: seconds, allowsThird: true, &d)
        d.add(camera)
        d.add("One continuous shot with no cuts")
        d.add("The subject, clothing, setting and light stay exactly as in the first frame; only \(motion == nil ? "the subject's natural small movements" : "the described action") and the camera move")
        addSound(s.text("sound"), hasDialogue: false, &d)
        addTextRule(onScreen: nil, &d)
        d.request.providerParameters = providerParameters(d, override: s.negativePrompt, extraNegative: ["morphing", "warping", "extra limbs"])
        return d
    }

    private static func effect(_ tool: VideoTool, _ s: VideoToolInputs, _ model: VideoModel) -> Draft {
        guard let effect = s.effectID.flatMap(VideoEffects.effect) else { return animate(tool, s, model) }
        var d = Draft(model, request: baseRequest(s, tool, model))
        d.request.firstFrame = s.firstFrame
        d.title = tool.name + " · " + effect.name
        d.record = english(tool.name) + " · " + english(effect.name)
        var text = effect.template
        if effect.takesText {
            let value = d.user(s.text(VideoEffects.textFieldID)) ?? "a completely different outfit"
            text = text.replacingOccurrences(of: "{text}", with: value)
        }
        text = adaptSoundCues(text, d)
        d.add(text)
        let lowered = text.lowercased()
        if let identity = effect.identityLine ?? effect.input.identityLine, !identity.isEmpty, !mentionsIdentity(lowered) {
            d.add(identity)
        }
        if let extra = d.user(extraInstructions(tool, s)) { d.add(extra) }
        if !lowered.contains("continuous"), !lowered.contains("no cuts") { d.add("One continuous shot") }
        if !soundOn(d), d.traits.alwaysMakesSound { d.add("Quiet natural ambience only, with no music or speech") }
        if !lowered.contains("on-screen text"), !lowered.contains("subtitles") { d.add("No on-screen text, captions or watermarks") }
        d.request.providerParameters = providerParameters(d, override: s.negativePrompt)
        return d
    }

    private static func mentionsIdentity(_ lowered: String) -> Bool {
        ["keeps the same face", "keep the same face", "stay exact", "stays exact", "same face", "stays recognizable",
         "stays the same", "stay exactly the same", "stays unchanged", "stay unchanged"].contains { lowered.contains($0) }
    }

    private static func adaptSoundCues(_ text: String, _ d: Draft) -> String {
        let sound = soundOn(d)
        var result = text
        let cue = try? NSRegularExpression(pattern: "<\\s*([^<>]+?)\\s*>")
        let music = try? NSRegularExpression(pattern: "（([^（）]+)）")
        func replace(_ regex: NSRegularExpression?, _ make: (String) -> String) {
            guard let regex else { return }
            let range = NSRange(result.startIndex..., in: result)
            var output = ""
            var cursor = result.startIndex
            for match in regex.matches(in: result, range: range) {
                guard let whole = Range(match.range, in: result), let inner = Range(match.range(at: 1), in: result) else { continue }
                output += result[cursor..<whole.lowerBound]
                output += make(String(result[inner]))
                cursor = whole.upperBound
            }
            result = output + result[cursor...]
        }
        if !sound {
            replace(cue) { _ in "" }
            replace(music) { _ in "" }
            let kept = sentences(of: result).filter { sentence in
                !["SFX:", "Ambient noise:", "Music:", "No music"].contains { sentence.hasPrefix($0) }
            }
            return kept.joined(separator: " ").replacingOccurrences(of: "  ", with: " ")
        }
        if d.family != .seedance {
            replace(cue) { "SFX: \($0)." }
            replace(music) { "Music: \($0)." }
        } else if ["SFX:", "Ambient noise:", "Music:"].contains(where: { result.contains($0) }) {
            result = sentences(of: result).map { sentence in
                for prefix in ["SFX:", "Ambient noise:"] where sentence.hasPrefix(prefix) {
                    return "< " + CameraMoves.clause(String(sentence.dropFirst(prefix.count))).trimmingCharacters(in: .whitespaces) + " >"
                }
                if sentence.hasPrefix("Music:") {
                    return "（" + CameraMoves.clause(String(sentence.dropFirst(6))).trimmingCharacters(in: .whitespaces) + "）"
                }
                return sentence
            }.joined(separator: " ")
        }
        return result.replacingOccurrences(of: "  ", with: " ")
    }

    private static func sentences(of text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if [".", "!", "?"].contains(character) {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { parts.append(trimmed) }
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { parts.append(rest) }
        return parts
    }

    private static func transition(_ tool: VideoTool, _ s: VideoToolInputs, _ model: VideoModel) -> Draft {
        var d = Draft(model, request: baseRequest(s, tool, model))
        d.request.firstFrame = s.firstFrame
        if let last = s.lastFrame {
            if model.supportsLastFrame { d.request.lastFrame = last } else { d.note(L("%@ can't use an end image; it was left out.", model.name)) }
        }
        let style = tool.choice("style", in: s.choices)
        let phrase = VideoPhrases.transitions[style] ?? VideoPhrases.transitions["Seamless morph"]!
        d.add("Seamless transition from the first frame to the last frame: \(phrase.motion)")
        let camera = cameraLine(s.cameraMoves, strength: nil, seconds: clipLength(d.request), &d)
        d.add(camera ?? "Camera: \(phrase.camera)")
        let extra = d.user(s.prompt)
        d.add(extra)
        d.add("One continuous shot with no hard cut, consistent light direction, ending exactly on the last frame")
        addSound(s.text("sound"), hasDialogue: false, &d)
        addTextRule(onScreen: nil, &d)
        d.request.providerParameters = providerParameters(d, override: s.negativePrompt, extraNegative: ["hard cut"])
        return d
    }

    private static func cinema(_ tool: VideoTool, _ s: VideoToolInputs, _ model: VideoModel) -> Draft {
        var d = Draft(model, request: baseRequest(s, tool, model))
        let choice = { (id: String) in tool.choice(id, in: s.choices) }
        let frame = model.supportsFirstFrame ? s.firstFrame : nil
        var binding = Binding()
        if let frame {
            d.request.firstFrame = frame
            if !s.firstFrameIsKeyframe, s.character != nil || !s.references.isEmpty {
                d.note(L("The start image sets the scene, so the character and reference images aren't sent."))
            }
        } else {
            binding = bind(character: canBindCharacter(s.character, d.traits) ? s.character : nil, product: nil,
                           extra: s.references, video: nil, audio: nil, &d)
            d.request.references = binding.references
        }
        let seconds = clipLength(d.request)
        binding.before.forEach { d.add($0) }
        let summary = d.user(s.prompt)
        d.add([binding.lead, summary].compactMap { $0 }.joined(separator: " "))

        let film = cinemaLook(tool, s)
        if frame == nil {
            d.add(film.setting)
        } else if !s.firstFrameIsKeyframe, film.setting != nil || !film.camera.isEmpty {
            d.note(L("The start image sets the look, so the genre, era, camera, lens and light aren't added."))
        }

        let emotion = choice("emotion")
        let intense = choice("intensity") == "High"
        func behavior(_ value: String?) -> String? {
            guard let value, value != "Auto", let base = VideoPhrases.emotions[value] else { return nil }
            return intense ? base + ", the emotion strong and visible" : base
        }
        let shots = Array(s.shots.filter { !$0.action.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(3))
        if shots.isEmpty {
            let camera = cameraLine(s.cameraMoves, strength: s.strength, seconds: seconds, &d)
            d.add(camera)
            if let feeling = behavior(emotion) { d.add("The character's emotion shows as \(feeling)") }
        } else {
            let total = max(shots.count, seconds ?? 5)
            let bounds = (0...shots.count).map { Int((Double($0) * Double(total) / Double(shots.count)).rounded()) }
            for (index, shot) in shots.enumerated() {
                let start = bounds[index], end = bounds[index + 1]
                let action = d.user(shot.action) ?? ""
                let feeling = behavior(shot.emotion ?? emotion).map { ", \($0)" } ?? ""
                let move = shot.camera.flatMap(CameraMoves.move).map { lowercasedClause($0.text(for: d.family)) }
                if let id = shot.camera, CameraMoves.move(id)?.isBig == true, ![.kling, .veo].contains(d.family) {
                    d.note(L("Big camera moves like orbits, FPV flights and crash zooms work best on Kling or Veo."))
                }
                let camera = move.map { " (\($0))" } ?? ""
                switch d.family {
                case .seedance where d.traits.isSeedance25:
                    d.add("[\(start)-\(end)s]\(camera) \(action)\(feeling)")
                case .veo:
                    d.add(String(format: "[00:%02d-00:%02d]", start, end) + "\(camera) \(action)\(feeling)")
                case .wan:
                    d.add("Shot \(index + 1) [\(start)-\(end)s]\(camera): \(action)\(feeling)")
                default:
                    d.add("Shot \(index + 1)\(camera): \(action)\(feeling)")
                }
            }
        }
        if d.traits.isSeedance25, intense, emotion != "Auto" || shots.contains(where: { $0.emotion != nil }) {
            d.add("Normal, non-glowing eyes")
        }

        var look = frame == nil ? film.camera : []
        if let pacing = VideoPhrases.pacing[choice("pacing")] { look.append(pacing) }
        if let speed = VideoPhrases.speeds[choice("speed")] { look.append(speed) }
        if !look.isEmpty { d.add(capitalizedFirst(look.joined(separator: ", "))) }
        if frame == nil, let style = d.user(s.style) { d.add("Style: \(style)") }

        let lines = dialogue(s)
        addDialogue(lines, language: spokenLanguage(s, tool), tone: choice("tone"), speaker: s.character?.name.nonBlank ?? "The person", &d)
        addSound(s.text("sound"), hasDialogue: !lines.isEmpty, &d)
        if frame != nil {
            if s.firstFrameIsKeyframe { frameIdentity(character: s.character, product: nil, &d) }
        } else {
            binding.after.forEach { d.add($0) }
        }
        addTextRule(onScreen: nil, &d)
        d.request.providerParameters = providerParameters(d, override: s.negativePrompt)
        return d
    }

    private static func cinemaLook(_ tool: VideoTool, _ s: VideoToolInputs) -> (setting: String?, camera: [String]) {
        let choice = { (id: String) in tool.choice(id, in: s.choices) }
        let genre = choice("genre"), era = choice("era")
        let setting: String? = switch (genre == "Auto", era == "Auto") {
        case (false, false): "Genre: \(genre.lowercased()), set in the \(era)"
        case (false, true): "Genre: \(genre.lowercased())"
        case (true, false): "Set in the \(era)"
        case (true, true): nil
        }
        var camera: [String] = []
        if let body = VideoPhrases.cameraBodies[choice("body")] { camera.append("shot on \(body)") }
        if let lens = VideoPhrases.lenses[choice("lens")] { camera.append("with \(lens)") }
        if let aperture = VideoPhrases.apertures[choice("aperture")] { camera.append("at \(aperture)") }
        if let light = VideoPhrases.lights[choice("light")] { camera.append(light) }
        return (setting, camera)
    }

    private static func lowercasedClause(_ sentence: String) -> String {
        CameraMoves.lowercasingFirst(CameraMoves.clause(sentence))
    }

    private static func storyboard(_ tool: VideoTool, _ s: VideoToolInputs, _ model: VideoModel) -> [VideoRecipe] {
        let frames = s.shots.filter { $0.image != nil }
        guard !frames.isEmpty else { return [] }
        if tool.choice("mode", in: s.choices) == "One multi-shot clip" {
            var d = Draft(model, request: baseRequest(s, tool, model))
            let traits = d.traits
            let usable = Array(frames.prefix(max(1, traits.boundReferences)))
            if usable.count < frames.count { d.note(L("%@ takes up to %ld reference images; the rest were left out.", model.name, traits.boundReferences)) }
            d.request.references = usable.compactMap(\.image).map(VideoInput.image)
            let perShot = s.duration ?? tool.defaults.duration ?? 5
            d.request.duration = model.clampedDuration(min(15, perShot * usable.count))
            let range = traits.usesTokens ? "\(traits.imageToken(1)) to \(traits.imageToken(usable.count))" : "the provided images"
            d.add("Use \(range) in order as keyframes")
            for (index, shot) in usable.enumerated() {
                let action = d.user(shot.action) ?? "the scene continues"
                let camera = shot.camera.flatMap(CameraMoves.move).map { " (\(lowercasedClause($0.text(for: d.family))))" } ?? ""
                d.add("Shot \(index + 1)\(camera): \(action)")
            }
            d.add("Same characters and art style throughout; no identical duplicate characters")
            if let extra = d.user(extraInstructions(tool, s)) { d.add(extra) }
            addSound(s.text("sound"), hasDialogue: false, &d)
            addTextRule(onScreen: nil, &d)
            d.request.providerParameters = providerParameters(d, override: s.negativePrompt)
            return [finish(d, tool: tool, state: s, model: model)]
        }
        let flows = tool.choice("flow", in: s.choices) == "Flow into next frame"
        let seed = s.seed ?? Int.random(in: 1...2_000_000_000)
        return frames.enumerated().map { index, shot in
            var d = Draft(model, request: baseRequest(s, tool, model))
            d.request.seed = seed
            d.request.firstFrame = shot.image
            if flows, index + 1 < frames.count {
                if model.supportsLastFrame { d.request.lastFrame = frames[index + 1].image } else {
                    d.note(L("%@ can't use an end image; it was left out.", model.name))
                }
            }
            d.title = "\(tool.name) · \(index + 1)/\(frames.count)"
            d.record = "\(english(tool.name)) · \(index + 1)/\(frames.count)"
            let action = d.user(shot.action) ?? "Natural, subtle motion that continues the story"
            d.add(action)
            let moves = shot.camera.map { [$0] } ?? s.cameraMoves
            let camera = cameraLine(moves, strength: s.strength, seconds: clipLength(d.request), &d)
            d.add(camera)
            d.add("Keep the characters, art style and light exactly as in the first frame")
            if let extra = d.user(extraInstructions(tool, s)) { d.add(extra) }
            if d.request.lastFrame != nil { d.add("End exactly on the last frame") }
            addSound(s.text("sound"), hasDialogue: false, &d)
            addTextRule(onScreen: nil, &d)
            d.request.providerParameters = providerParameters(d, override: s.negativePrompt)
            return finish(d, tool: tool, state: s, model: model)
        }
    }

    private static func talkingAvatar(_ tool: VideoTool, _ s: VideoToolInputs, _ model: VideoModel) -> Draft {
        var d = Draft(model, request: baseRequest(s, tool, model))
        let photo = s.firstFrame ?? s.character?.photos.first
        let script = s.text("script")
        let words = wordCount(script)
        let language = spokenLanguage(s, tool)
        if d.traits.isAvatar {
            d.request.duration = nil
            d.request.generateAudio = nil
            d.request.references = [photo].compactMap { $0 }.map(VideoInput.image)
            if let voice = link(s.audioURL, file: s.audioFile) { d.request.references.append(.audioURL(voice)) }
            if let script = d.literal(script) {
                d.verbatimPrompt = script
            } else {
                d.verbatimPrompt = "Lip-sync to the provided voice track."
                d.note(L("With your own voice and no script, the lip sync follows the audio."))
            }
            let expressiveness = tool.choice("expressiveness", in: s.choices).lowercased()
            var parameters: [String: JSONValue] = [
                "motion_prompt": "natural head nods and small hand gestures, eyes on the lens",
                "expressiveness": .string(expressiveness.isEmpty ? "medium" : expressiveness),
            ]
            if tool.choice("background", in: s.choices) == "Remove" { parameters["remove_background"] = true }
            if tool.choice("captions", in: s.choices) == "On" { parameters["caption"] = true }
            d.request.providerParameters = parameters
            d.sourceSeconds = s.audioDuration ?? max(3, Double(words) / 2.5)
            if (d.sourceSeconds ?? 0) > 60 { d.note(L("This video can last 60 seconds at most; shorten the recording or the script.")) }
            d.cropFirstFrame = false
            return d
        }
        let sceneName = tool.choice("scene", in: s.choices)
        let scene = VideoPhrases.scenes[sceneName] ?? VideoPhrases.scenes["Static"]!
        d.request.firstFrame = photo
        if s.duration == nil, let suggested = suggestedDuration(forWords: words, model: model) { d.request.duration = suggested }
        d.add("\(scene.camera): the person looks into the camera")
        let line = VideoDialogueLine(text: script)
        addDialogue(script.isEmpty ? [] : [line], language: language, tone: nil, phrase: scene.tone, speaker: "The person",
                    verb: scene.verb, &d)
        if let gesture = d.user(s.text("gestures")) {
            d.add("Gestures: \(gesture)")
        } else {
            d.add(scene.gesture)
        }
        if soundOn(d) { d.add(soundCue(scene.ambience, d)) }
        d.add(sceneName == "Singing" || sceneName == "Rapping" ? "No subtitles" : "No music, no subtitles")
        d.add("The person keeps the same face, hair and clothing throughout")
        d.request.providerParameters = providerParameters(d, override: s.negativePrompt)
        if !d.traits.makesSound { d.note(L("This model makes no sound. Pick Veo 3.1 Lite or Kling 3.0 so the words are heard.")) }
        return d
    }

    private static func isNativeExtend(_ tool: VideoTool, _ s: VideoToolInputs, modelID: String?) -> Bool {
        guard s.sourceJobID != nil, tool.choice("method", in: s.choices) != "Last frame" else { return false }
        return modelID != nil && modelID == s.sourceModelID && nativeContinuationModels.contains(modelID ?? "")
    }

    private static func extend(_ tool: VideoTool, _ s: VideoToolInputs, _ model: VideoModel) -> Draft {
        var d = Draft(model, request: baseRequest(s, tool, model))
        let next = d.user(s.prompt) ?? "the action continues naturally"
        if isNativeExtend(tool, s, modelID: model.id), let job = s.sourceJobID {
            d.request.previousJobID = job
            d.request.resolution = nil
            d.request.aspectRatio = nil
            d.add("Extend the video: \(next)")
            d.add("Same camera style, lighting, characters and pacing")
        } else {
            if tool.choice("method", in: s.choices) == "Native continuation" {
                d.note(s.sourceJobID == nil
                       ? L("Native continuation needs a clip made in Freefield; it continues from the last frame instead.")
                       : L("%@ can't continue this clip natively; it continues from the last frame instead.", model.name))
            }
            d.request.firstFrame = s.firstFrame
            if d.request.aspectRatio == nil { d.request.aspectRatio = nearestRatio(to: s.sourceSize, model: model) }
            if d.request.resolution == nil, let size = s.sourceSize, min(size.width, size.height) > 0 {
                d.request.resolution = "\(Int(min(size.width, size.height).rounded()))p"
            }
            d.add("Continue this shot seamlessly from the first frame: \(next)")
            d.add("Same camera move direction and speed, same light and characters, no cut at the start")
            d.cropFirstFrame = false
        }
        let lines = dialogue(s)
        addDialogue(lines, language: spokenLanguage(s, tool), tone: nil, speaker: s.character?.name.nonBlank ?? "The person", &d)
        addSound(s.text("sound"), hasDialogue: !lines.isEmpty, &d)
        addTextRule(onScreen: nil, &d)
        d.request.providerParameters = providerParameters(d, override: s.negativePrompt)
        return d
    }

    private static func edit(_ tool: VideoTool, _ s: VideoToolInputs, _ model: VideoModel) -> Draft {
        var d = Draft(model, request: VideoRequest(model: model, prompt: "", seed: s.seed))
        let traits = d.traits
        let mode = tool.choice("mode", in: s.choices)
        if let video = link(s.sourceVideoURL, file: s.sourceVideoFile) { d.request.references.append(.videoURL(video)) }
        var hasImage = false
        if let image = s.references.first {
            if model.maxImageReferences > 0 {
                d.request.references.append(.image(image))
                hasImage = true
            } else {
                d.note(L("%@ can't use the image; Runway Aleph 2 can.", model.name))
            }
        }
        sourceShape(s, &d)
        let clip = traits.usesTokens ? traits.videoToken(1) : "the video"
        let image = traits.usesTokens ? traits.imageToken(1) : "the reference image"
        let lead = traits.usesTokens ? "Edit \(clip): " : ""
        switch mode {
        case "Restyle":
            let choice = tool.choice("restyle", in: s.choices)
            let look = choice == "My moodboard" ? d.user(s.style) ?? "the moodboard's look" : VideoPhrases.restyles[choice] ?? choice.lowercased()
            d.add(lead + (hasImage ? "Make it look like the style of \(image), \(look)" : "Make it look like \(look)")
                  + ", keeping the same motion, composition and timing")
        case "Relight":
            let light = VideoPhrases.relights[tool.choice("relight", in: s.choices)] ?? "soft natural light"
            d.add(lead + "Relight the scene as \(light); shadows and reflections follow the new light; keep everything else unchanged")
        case "Weather & time":
            let weather = VideoPhrases.weather[tool.choice("weather", in: s.choices)] ?? "a different weather"
            d.add(lead + "Change the weather and time of day to \(weather); keep the people, motion, camera and timing unchanged")
        case "Translate dialogue":
            let target = spokenLanguage(s, tool, group: "targetLanguage")
            d.add(lead + "Change the spoken dialogue to \(target) with matching lip sync; same voice character and timing")
        default:
            let change = d.user(s.text("change")) ?? (hasImage ? "Add what \(image) shows to the scene" : "Improve the clip")
            d.add(lead + change + (hasImage ? ", using \(image) for it" : ""))
            d.add("Keep everything else identical: people, faces, motion, camera and timing")
        }
        if let extra = d.user(extraInstructions(tool, s)) { d.add(extra) }
        if traits.family == .wan { d.add("Generate single shot") }
        return d
    }

    private static func sourceShape(_ s: VideoToolInputs, _ d: inout Draft) {
        let model = d.request.model
        let sent = sentClip(duration: s.sourceDuration, size: s.sourceSize, url: s.sourceVideoURL, file: s.sourceVideoFile, &d)
        d.sourceSeconds = sent.duration
        d.sourceSize = sent.size
        d.request.aspectRatio = s.aspect ?? nearestRatio(to: sent.size, model: model)
        if !model.durations.isEmpty {
            d.request.duration = model.clampedDuration(Int((sent.duration ?? 5).rounded()))
            d.request.resolution = s.resolution ?? "720p"
            d.request.generateAudio = s.audio ?? true
        }
    }

    private static func motionTransfer(_ tool: VideoTool, _ s: VideoToolInputs, _ model: VideoModel) -> Draft {
        var d = Draft(model, request: baseRequest(s, tool, model))
        let traits = d.traits
        if let photo = s.character?.photos.first {
            if model.maxImageReferences > 0 { d.request.references.append(.image(photo)) } else {
                d.note(L("%@ can't use reference images; they were left out.", model.name))
            }
        }
        if let driving = link(s.drivingVideoURL, file: s.drivingVideoFile) { d.request.references.append(.videoURL(driving)) }
        let sent = sentClip(duration: s.drivingDuration, size: s.drivingSize, url: s.drivingVideoURL, file: s.drivingVideoFile, &d)
        d.request.duration = model.clampedDuration(Int((sent.duration ?? 5).rounded())) ?? d.request.duration
        d.request.aspectRatio = s.aspect ?? nearestRatio(to: sent.size, model: model)
        d.request.generateAudio = false
        d.sourceSeconds = sent.duration
        let image = traits.imageToken(1), video = traits.videoToken(1)
        let details = d.user(s.character?.details).map { " (\($0))" } ?? ""
        let setting = tool.choice("scene", in: s.choices) == "Video" ? video : image
        d.add("\(capitalizedFirst(image)) is the character\(details). \(capitalizedFirst(video)) is the motion source")
        d.add("The character from \(image) performs exactly the same body movements, timing and camera framing as the person in \(video), in the setting of \(setting)")
        d.add("Keep \(possessive(image)) face, hair, outfit and body proportions throughout; natural hands; one person only")
        if let extra = d.user(extraInstructions(tool, s)) { d.add(extra) }
        if traits.family == .wan { d.add("Generate single shot") }
        addTextRule(onScreen: nil, &d)
        d.request.providerParameters = providerParameters(d, override: s.negativePrompt)
        return d
    }

    private static func swap(_ tool: VideoTool, _ s: VideoToolInputs, _ model: VideoModel) -> Draft {
        var d = Draft(model, request: VideoRequest(model: model, prompt: "", seed: s.seed))
        let traits = d.traits
        if let video = link(s.sourceVideoURL, file: s.sourceVideoFile) { d.request.references.append(.videoURL(video)) }
        if let photo = s.character?.photos.first {
            if model.maxImageReferences > 0 { d.request.references.append(.image(photo)) } else {
                d.note(L("%@ can't use reference images; they were left out.", model.name))
            }
        }
        sourceShape(s, &d)
        d.request.generateAudio = d.request.model.durations.isEmpty ? nil : false
        let clip = traits.usesTokens ? traits.videoToken(1) : "the video"
        let photo = traits.usesTokens ? traits.imageToken(1) : "the reference image"
        let details = d.user(s.character?.details).map { " (\($0))" } ?? ""
        if traits.usesTokens { d.add("\(capitalizedFirst(clip)) is the clip. \(capitalizedFirst(photo)) is the person\(details)") }
        switch tool.choice("swap", in: s.choices) {
        case "Whole character":
            d.add("Replace the person in \(clip) with the person in \(photo), including face, hair, body and clothing, performing exactly the same motion")
            d.add("Keep the background, camera and timing unchanged")
        case "Outfit only":
            d.add("Change only the clothing of the person in \(clip) to match the outfit in \(photo); keep the face, motion and background")
        default:
            d.add("Replace the face of the person in \(clip) with the face from \(photo): same facial structure, skin tone, eyes and hairline")
            d.add("Keep the original expressions, head motion, lighting, camera and timing")
        }
        if !traits.usesTokens, !details.isEmpty { d.add("The person in the reference image is\(details)") }
        if let extra = d.user(extraInstructions(tool, s)) { d.add(extra) }
        if traits.family == .wan { d.add("Generate single shot") }
        return d
    }

    private static func upscale(_ tool: VideoTool, _ s: VideoToolInputs, _ model: VideoModel) -> Draft {
        var d = Draft(model, request: VideoRequest(model: model, prompt: ""))
        if let video = link(s.sourceVideoURL, file: s.sourceVideoFile) { d.request.references = [.videoURL(video)] }
        let sent = sentClip(duration: s.sourceDuration, size: s.sourceSize, url: s.sourceVideoURL, file: s.sourceVideoFile,
                            fullSize: true, &d)
        var factor = VideoPhrases.upscaleFactor(tool.choice("factor", in: s.choices))
        if let size = sent.size, max(size.width, size.height) > 0 {
            let cap = 3840 / Double(max(size.width, size.height))
            if factor > cap {
                factor = max(1.5, cap)
                d.note(cap < 1.5 ? L("This clip is already close to 4K, so it can only grow 1.5×.")
                       : L("The size was lowered to keep the clip within 4K."))
            }
        }
        let creative = tool.choice("mode", in: s.choices) == "Creative"
        d.request.upscaleFactor = (factor * 100).rounded() / 100
        d.request.creativity = creative ? 1 : 0
        d.add(VideoRequest.defaultUpscalePrompt(creative: creative))
        if let detail = d.user(s.prompt) { d.add("Bring out \(detail)") }
        d.sourceSeconds = sent.duration
        d.sourceSize = sent.size
        return d
    }

    private static func reframe(_ tool: VideoTool, _ s: VideoToolInputs, _ model: VideoModel) -> Draft {
        var d = Draft(model, request: VideoRequest(model: model, prompt: "", seed: s.seed))
        if let video = link(s.sourceVideoURL, file: s.sourceVideoFile) { d.request.references = [.videoURL(video)] }
        let target = tool.choice("target", in: s.choices)
        d.request.aspectRatio = model.bestAspectRatio(target) ?? target
        if let sent = d.request.aspectRatio, sent != target {
            d.note(L("%@ makes %@ instead of %@; crop the result on this Mac if needed.", model.name, sent, target))
        }
        d.add("Expand the shot to a \(target) frame, naturally continuing the scene beyond the original edges with matching light, perspective and motion; keep the original content, people, motion and timing unchanged")
        if let extra = d.user(extraInstructions(tool, s)) { d.add("In the new space: \(extra)") }
        d.add("No borders, no blur fill, no text")
        let sent = sentClip(duration: s.sourceDuration, size: s.sourceSize, url: s.sourceVideoURL, file: s.sourceVideoFile,
                            fullSize: true, &d)
        d.sourceSeconds = sent.duration
        d.sourceSize = sent.size
        return d
    }

    private static func videoAd(_ tool: VideoTool, _ s: VideoToolInputs, _ model: VideoModel) -> Draft {
        var d = Draft(model, request: baseRequest(s, tool, model))
        d.request.firstFrame = model.supportsFirstFrame ? s.firstFrame : nil
        let mode = tool.choice("mode", in: s.choices)
        d.title = tool.name + " · " + (tool.group("mode")?.label(mode) ?? L(mode))
        d.record = english(tool.name) + " · " + mode
        let vertical = (d.request.aspectRatio ?? "9:16") == "9:16"
        switch mode {
        case "UGC talking":
            d.add("\(vertical ? "Vertical phone video" : "Phone video"), front camera at arm's length. The person holds the product next to their face, label toward the lens")
            let script = s.text("script")
            addDialogue(script.isEmpty ? [] : [VideoDialogueLine(text: script)], language: spokenLanguage(s, tool), tone: nil,
                        phrase: "casual and excited", speaker: "The person", &d)
            d.add("Small natural hand gestures, slight handheld shake")
            if soundOn(d) { d.add(soundCue("real room ambience", d)) }
            d.add("No music, no subtitles")
        case "Unboxing":
            d.add("Unboxing video seen from above: two hands open the box, lift out the product and turn it toward the camera, label facing the lens")
            d.add("Close, steady camera with a slow push-in")
            if soundOn(d) { d.add(d.family == .veo ? "SFX: paper rustling, the box opening" : soundCue("paper rustle, box opening", d)) }
            if soundOn(d) { d.add("Natural sound effects only, no music") }
        case "Hook to video":
            let motion = d.user(s.text("motion")) ?? "the scene comes alive with quick, eye-catching motion"
            d.add("The scroll-stopping first frame comes to life: \(motion); a quick push-in in the first second grabs attention, then the product takes center stage")
            d.add("Any text already in the first frame stays sharp and unchanged; no new text appears")
            if soundOn(d) { d.add("Natural sound effects and ambience only, no music") }
        case "Product review":
            d.add("\(vertical ? "Vertical phone video" : "Phone video") on a tripod at eye level. The person sits facing the camera, holds up the product, turns it so the label faces the lens and gives an honest review")
            let script = s.text("script")
            addDialogue(script.isEmpty ? [] : [VideoDialogueLine(text: script)], language: spokenLanguage(s, tool), tone: nil,
                        phrase: "honest and relaxed", speaker: "The person", &d)
            d.add("Natural hand gestures; the product stays in view")
            if soundOn(d) { d.add(soundCue("quiet room ambience", d)) }
            d.add("No music, no subtitles")
        case "TV spot":
            let story = d.user(s.text("motion")) ?? "a real person enjoys the product in an everyday moment"
            d.add("A polished TV commercial in three quick shots: first, \(story); then a close detail shot of the product in use; finally the product centered and still, label facing the camera")
            d.add("Smooth cinematic camera, clean cuts between the shots")
            if soundOn(d) { d.add("Natural sound effects and light ambience only, no music, no speech") }
        case "Tutorial":
            let steps = d.user(s.text("steps")) ?? "open it, use it the way it is meant to be used, then show the result"
            d.add("How-to video, seen close and slightly from above: two hands show how to use the product, step by step: \(steps). Each step is clear and unhurried")
            d.add("Steady close camera; only the hands and forearms are visible, with natural five-fingered hands")
            if soundOn(d) { d.add("Natural sound effects only, no music") }
        case "Virtual try-on":
            let action = d.user(s.text("motion")) ?? "a slow turn toward the camera, a glance down at it and a confident final pose"
            d.add("Try-on video: the person wears the product and shows it off: \(action). The fabric or material moves naturally with the body")
            d.add("Smooth handheld follow camera at medium-full framing, street-style feel")
            d.add("The product keeps its exact cut, color, pattern and logos as it moves")
            if soundOn(d) { d.add(soundCue("light street ambience", d) + ", no music") }
        case "Hyper motion":
            let burst = d.user(s.text("props")) ?? "liquid splashes and glowing particles"
            d.add("Hyper-real 3D product film with the product as the hero: it spins in mid-air as \(burst) burst around it, fast macro close-ups glide over the label and materials, then it lands centered in a final hero pose")
            d.add("Dynamic, impossible camera moves with speed ramps from fast to slow motion; glossy studio light and bold color")
            if soundOn(d) { d.add(soundCue("whooshes and splashes", d) + ", no music") }
        case "App demo":
            let steps = d.user(s.text("steps")) ?? "scrolls through the app and taps a button"
            d.add("App demo: a hand holds the smartphone steady while the thumb \(steps). The screen stays sharp and readable and keeps showing the same app as in the first frame")
            d.add("Slow push-in toward the screen")
            d.add("The app's screen does not morph, blur or turn into gibberish; no new captions or subtitles")
            if soundOn(d) { d.add(soundCue("soft screen taps and quiet room tone", d) + ", no music") }
            d.note(L("Add a screenshot of your app as the product photo."))
        case "Wild card":
            d.add("A surprising, scroll-stopping ad: bring one unexpected but believable visual twist to life for this product, such as an unusual setting, a playful change of scale or a clever visual metaphor, with the product clearly the hero and on screen at the end")
            if let idea = d.user(s.text("motion")) { d.add("Idea to build on: \(idea)") }
            d.add("Bold, confident camera work")
            if soundOn(d) { d.add("Natural sound effects only, no music") }
            d.note(L("The AI picks the idea; make a few and keep your favorite."))
        case "Before and after":
            let before = d.user(s.text("before")) ?? "the everyday problem, before the product"
            let after = d.user(s.text("after")) ?? "the result after using the product"
            d.add("Before and after in one shot: the scene starts with \(before); a smooth wipe from left to right reveals \(after), with the product in use")
            d.add("Locked-off camera")
            if soundOn(d) { d.add("Natural sound effects only, no music") }
        default:
            let props = d.user(s.text("props")).map { ", \($0) drift past" } ?? ""
            let move = d.family == .wan ? "a slow arc of about 45 degrees around the product" : "a slow orbit around the product"
            d.add("Premium product film: \(move), a soft light sweep glides across the label\(props), ending on a centered hero shot")
            if soundOn(d) { d.add(soundCue("a soft whoosh as the light sweeps", d) + ", no music") }
        }
        if let extra = d.user(extraInstructions(tool, s)) { d.add(extra) }
        if !soundOn(d), d.traits.alwaysMakesSound { d.add("Quiet natural ambience only, with no music or speech") }
        if mode == "Before and after" {
            if s.character != nil { d.add("The person keeps the same face throughout") }
            frameIdentity(character: nil, product: s.product, &d)
        } else {
            let showsPerson = VideoPhrases.adScenes[mode]?.showsPerson
                ?? (AdCatalog.tool(VideoPhrases.adKeyframeTools[mode] ?? "product-shoot")?.usesPerson == true)
            frameIdentity(character: showsPerson ? s.character : nil, product: s.product, &d)
        }
        if mode != "Hook to video", mode != "App demo" { addTextRule(onScreen: nil, &d) }
        d.request.providerParameters = providerParameters(d, override: s.negativePrompt)
        return d
    }

    private static func drawToVideo(_ tool: VideoTool, _ s: VideoToolInputs, _ model: VideoModel) -> Draft {
        var d = Draft(model, request: baseRequest(s, tool, model))
        d.request.firstFrame = s.firstFrame
        let motion = d.user(s.prompt) ?? "Natural, subtle motion of the subject"
        d.add(motion)
        if let extra = d.user(extraInstructions(tool, s)) { d.add(extra) }
        let camera = cameraLine(s.cameraMoves.isEmpty ? ["static"] : s.cameraMoves, strength: s.cameraMoves.isEmpty ? nil : s.strength,
                                seconds: clipLength(d.request), &d)
        d.add(camera)
        d.add("Everything else stays exactly as in the first frame")
        addSound(s.text("sound"), hasDialogue: false, &d)
        addTextRule(onScreen: nil, &d)
        d.request.providerParameters = providerParameters(d, override: s.negativePrompt, extraNegative: ["arrows", "drawn lines"])
        return d
    }

    private static func finish(_ draft: Draft, tool: VideoTool, state s: VideoToolInputs, model: VideoModel) -> VideoRecipe {
        var d = draft
        d.request.prompt = d.prompt
        if d.request.firstFrame != nil, d.request.model.kind == .generate { d.request.references = [] }
        let seconds = OpenRouterClient.videoDuration(for: d.request)
        if d.spokenWords > 0, let seconds {
            let budget = dialogueWordBudget(seconds: seconds)
            if d.spokenWords > budget {
                d.note(L("The dialogue has %ld words; about %ld fit in %ld seconds. Shorten it so it isn't rushed.", d.spokenWords, budget, seconds))
            }
        }
        let limit = d.traits.promptLimit
        if d.request.prompt.count > limit {
            d.note(L("The instructions are %ld characters; %@ takes up to %ld. Shorten your description.", d.request.prompt.count, model.name, limit))
        }
        let links = d.request.references.contains {
            switch $0 {
            case .videoURL(let url), .audioURL(let url): url == pendingLinkPlaceholder
            case .image: false
            }
        }
        var crop: String?
        if d.cropFirstFrame, let frame = d.request.firstFrame {
            if d.request.aspectRatio != nil {
                crop = model.bestAspectRatio(d.request.aspectRatio)
            } else if let nearest = nearestSupportedRatio(for: frame, model: model) {
                crop = nearest
                d.request.aspectRatio = nearest
            }
        }
        return VideoRecipe(
            request: d.request,
            userTexts: d.userTexts,
            literalTexts: d.literalTexts,
            title: d.title ?? tool.name,
            record: d.record ?? english(tool.name),
            keyframe: keyframePlan(for: tool, state: s, model: model),
            cropFirstFrameTo: crop,
            needsLinks: links,
            sourceSeconds: d.sourceSeconds ?? seconds.map(Double.init),
            sourceSize: d.sourceSize,
            notes: d.notes
        )
    }

    private static func nearestSupportedRatio(for frame: InputImage, model: VideoModel) -> String? {
        guard !model.aspectRatios.isEmpty, let size = ImageCoding.pixelSize(of: frame.data), size.width > 0, size.height > 0,
              let nearest = model.bestAspectRatio("\(Int(size.width)):\(Int(size.height))"),
              let value = VideoModel.ratioValue(nearest) else { return nil }
        let shape = Double(size.width / size.height)
        return abs(value - shape) / shape > 0.01 ? nearest : nil
    }
}

extension String {
    fileprivate var nonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension AppModel {
    func videoToolCost(_ tool: VideoTool, inputs: VideoToolInputs, model: VideoModel, count: Int) -> VideoCostEstimate {
        let plan = VideoRecipes.keyframePlan(for: tool, state: inputs, model: model)
        return VideoRecipes.estimatedCost(
            tool: tool, inputs: inputs, model: model, duration: inputs.duration ?? tool.defaults.duration,
            resolution: inputs.resolution ?? tool.defaults.resolution, aspect: inputs.aspect,
            audio: inputs.audio ?? tool.defaults.audio, count: count, keyframeCost: plan.flatMap(keyframeImageCost)
        )
    }

    func keyframeImageCost(for plan: VideoKeyframePlan) -> Double? {
        estimatedCost(model: keyframeImageModel(for: plan), count: 1, resolution: .oneK)
    }

    func keyframeImageModel(for plan: VideoKeyframePlan) -> ImageModel? {
        let preferred: [String] = switch plan.kind {
        case .subject: Lineup.defaultModelIDs(for: .create)
        case .quickStyle(let id): (AppCatalog.item(id)?.model).map { [$0] } ?? Lineup.defaultModelIDs(for: .create)
        case .adShot(let id): AdCatalog.tool(id).map { [$0.model] } ?? Lineup.defaultModelIDs(for: .create)
        }
        let featured = choices(for: ModelRequirement(images: 1)).featured
        for id in preferred {
            if let match = featured.first(where: { $0.lineup?.id == id && !catalog.strained.contains($0.model.id) }) { return match.model }
        }
        return featured.first?.model
    }
}

#if DEBUG
extension VideoRecipes {
    static func selfCheck(models: [VideoModel] = []) -> [String] {
        var problems = catalogProblems()
        for (label, tool, state, modelID) in sampleRuns() {
            guard let model = model(modelID, in: models) else {
                problems.append("\(label): no model \(modelID)")
                continue
            }
            problems += check(label, tool: tool, state: state, model: model)
        }
        return problems
    }

    static func sampleDump(models: [VideoModel] = []) -> String {
        sampleRuns().map { label, tool, state, modelID -> String in
            guard let model = model(modelID, in: models) else { return "## \(label)\nno model \(modelID)" }
            return requests(for: tool, state: state, model: model).enumerated().map { index, recipe in
                let json = (try? recipe.request.model.host == .google ? GeminiClient.videoRequestJSON(recipe.request)
                    : OpenRouterClient.videoRequestJSON(recipe.request)) ?? "invalid request"
                let notes = recipe.notes.isEmpty ? "" : "\nnotes: " + recipe.notes.joined(separator: " | ")
                let keyframe = recipe.keyframe.map { "\nkeyframe: \($0.kind) \($0.scene)" } ?? ""
                return "## \(label)\(index > 0 ? " #\(index + 1)" : "") · \(model.id) · \(recipe.request.prompt.count) chars\(keyframe)\(notes)\n\(json)"
            }.joined(separator: "\n\n")
        }.joined(separator: "\n\n")
    }

    static func model(_ id: String, in models: [VideoModel]) -> VideoModel? {
        models.first { $0.id == id } ?? sampleModels.first { $0.id == id }
    }

    static func catalogProblems() -> [String] {
        var problems: [String] = []
        if VideoCatalog.all.count != 18 { problems.append("catalog: \(VideoCatalog.all.count) tools, expected 18") }
        if CameraMoves.all.count != 72 { problems.append("camera: \(CameraMoves.all.count) moves, expected 72") }
        if VideoEffects.all.count != 133 { problems.append("effects: \(VideoEffects.all.count) effects, expected 133") }
        for (name, ids) in [("tool", VideoCatalog.all.map(\.id)), ("effect", VideoEffects.all.map(\.id)), ("camera", CameraMoves.all.map(\.id))] {
            let repeated = Dictionary(grouping: ids, by: { $0 }).filter { $0.value.count > 1 }.keys
            if !repeated.isEmpty { problems.append("\(name) ids repeat: \(repeated.sorted())") }
        }
        for tool in VideoCatalog.all {
            if tool.steps.isEmpty { problems.append("\(tool.id): no How it works steps") }
            if tool.engine == .model, tool.defaultModel == nil { problems.append("\(tool.id): no default model") }
            for group in tool.optionGroups {
                if group.values.isEmpty { problems.append("\(tool.id).\(group.id): no values") }
                if let value = group.defaultValue, !group.values.contains(value) { problems.append("\(tool.id).\(group.id): default \(value) missing") }
                if let condition = group.shownWhen { problems += conditionProblems(condition, tool: tool, owner: group.id) }
            }
            for field in tool.textFields {
                if let condition = field.shownWhen { problems += conditionProblems(condition, tool: tool, owner: field.id) }
            }
            for mode in tool.modeModels where !(tool.group(mode.group)?.values.contains(mode.value) ?? false) {
                problems.append("\(tool.id): mode model for unknown \(mode.group)=\(mode.value)")
            }
            if let condition = tool.onDeviceWhen { problems += conditionProblems(condition, tool: tool, owner: "onDevice") }
            if Set(tool.optionGroups.map(\.id)).count != tool.optionGroups.count { problems.append("\(tool.id): repeated group ids") }
        }
        let phraseTables: [(String, String, [String: Any])] = [
            ("editVideo", "restyle", VideoPhrases.restyles), ("editVideo", "relight", VideoPhrases.relights),
            ("editVideo", "weather", VideoPhrases.weather), ("transitions", "style", VideoPhrases.transitions),
            ("cinemaStudio", "body", VideoPhrases.cameraBodies), ("cinemaStudio", "lens", VideoPhrases.lenses),
            ("cinemaStudio", "aperture", VideoPhrases.apertures), ("cinemaStudio", "light", VideoPhrases.lights),
            ("cinemaStudio", "pacing", VideoPhrases.pacing), ("cinemaStudio", "speed", VideoPhrases.speeds),
            ("cinemaStudio", "emotion", VideoPhrases.emotions), ("talkingAvatar", "scene", VideoPhrases.scenes),
            ("videoAd", "mode", VideoPhrases.adKeyframeTools.merging(VideoPhrases.adScenes.mapValues(\.scene)) { first, _ in first }),
        ]
        let unphrased: Set<String> = ["Auto", "Linear", "My moodboard", "Before and after"]
        for (toolID, groupID, table) in phraseTables {
            for value in VideoCatalog.tool(toolID)?.group(groupID)?.values ?? [] where table[value] == nil && !unphrased.contains(value) {
                problems.append("\(toolID).\(groupID): no prompt text for \(value)")
            }
        }
        for effect in VideoEffects.all {
            if let style = effect.quickStyleID, AppCatalog.item(style) == nil { problems.append("effect \(effect.id): no Quick Style \(style)") }
            if effect.takesText, effect.textTitle == nil { problems.append("effect \(effect.id): takes text but has no field") }
        }
        for ad in VideoPhrases.adKeyframeTools.values where AdCatalog.tool(ad) == nil {
            problems.append("videoAd: no Ad Studio tool \(ad)")
        }
        for move in CameraMoves.all where move.prompt.isEmpty || move.name.isEmpty {
            problems.append("camera \(move.id): empty")
        }
        return problems
    }

    static func conditionProblems(_ condition: VideoOptionCondition, tool: VideoTool, owner: String) -> [String] {
        guard let group = tool.group(condition.group) else { return ["\(tool.id).\(owner): condition on unknown group \(condition.group)"] }
        return condition.values.filter { !group.values.contains($0) }.map { "\(tool.id).\(owner): condition value \($0) not in \(group.id)" }
    }

    static func check(_ label: String, tool: VideoTool, state: VideoToolInputs, model: VideoModel) -> [String] {
        var problems: [String] = []
        let recipes = requests(for: tool, state: state, model: model)
        if recipes.isEmpty { return ["\(label): no request"] }
        for recipe in recipes {
            let request = recipe.request
            let prompt = request.prompt
            let traits = VideoModelTraits(model)
            do {
                if model.host == .google {
                    let body = try GeminiClient.videoRequestBody(request)
                    let task = ((body["generation_config"] as? [String: Any])?["video_config"] as? [String: Any])?["task"] as? String
                    if traits.family == .omni, task == "reference_to_video", !prompt.contains("<IMAGE_REF_0>") {
                        problems.append("\(label): Omni references without <IMAGE_REF_n> tags")
                    }
                    if traits.family == .omni, ((body["input"] as? [[String: Any]]) ?? []).count(where: { $0["type"] as? String == "image" }) > 3 {
                        problems.append("\(label): more than 3 images sent to Omni")
                    }
                } else {
                    let body = try OpenRouterClient.videoRequestBody(request)
                    if body["frame_images"] != nil, body["input_references"] != nil { problems.append("\(label): frames and references together") }
                    if (body["aspect_ratio"] as? String)?.lowercased() == "auto" { problems.append("\(label): aspect_ratio auto") }
                    if state.aspect == nil, request.firstFrame != nil, body["aspect_ratio"] != nil, tool.id != "extendVideo",
                       recipe.cropFirstFrameTo != (body["aspect_ratio"] as? String) {
                        problems.append("\(label): ratio sent for Auto without cropping the start frame to it")
                    }
                    if traits.family == .seedance, (body["input_references"] as? [Any])?.isEmpty == false,
                       request.references.contains(where: { $0.image != nil }), !prompt.contains("@Image 1") {
                        problems.append("\(label): Seedance references without @Image tokens")
                    }
                }
            } catch {
                problems.append("\(label): \(error.localizedDescription)")
            }
            if prompt.count > traits.promptLimit { problems.append("\(label): prompt \(prompt.count) > \(traits.promptLimit)") }
            for text in recipe.userTexts where !prompt.contains(text) { problems.append("\(label): user text missing: \(text.prefix(40))") }
            for text in recipe.literalTexts where !prompt.contains(text) { problems.append("\(label): literal missing: \(text.prefix(40))") }
            if prompt.contains("{") || prompt.contains("}") { problems.append("\(label): placeholder left: \(prompt.prefix(80))") }
            if prompt.contains("..") { problems.append("\(label): double period") }
        }
        return problems
    }

    static let sampleImage = InputImage(
        data: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAASCAIAAAC1qksFAAAAH0lEQVR42mM4UWFDU8QwasGoBaMWjFowasGoBfSwAACbvVcu5R6rMgAAAABJRU5ErkJggg==") ?? Data(),
        mimeType: "image/png", role: "sample"
    )

    static func sampleRuns() -> [(String, VideoTool, VideoToolInputs, String)] {
        var runs: [(String, VideoTool, VideoToolInputs, String)] = []
        let image = sampleImage
        let clip = "https://example.com/clip.mp4"
        let leo = VideoSubject(name: "Leo", details: "un hombre alto con barba", photos: [image, image])
        let can = VideoSubject(name: "Acme Cola", details: "red aluminum can", photos: [image])
        func add(_ label: String, _ toolID: String, _ modelID: String? = nil, _ edit: (inout VideoToolInputs) -> Void) {
            guard let tool = VideoCatalog.tool(toolID) else { return }
            var state = VideoToolInputs(tool: tool)
            edit(&state)
            runs.append((label, tool, state, modelID ?? preferredModelIDs(for: tool, state: state).first ?? ""))
        }

        let families = ["bytedance/seedance-2.0-fast", "bytedance/seedance-2.5", "kwaivgi/kling-v3.0-std", "google/veo-3.1-lite",
                        "google/veo-3.1-fast", "alibaba/wan-3.0", "minimax/hailuo-3", "x-ai/grok-imagine-video-1.5-lite",
                        "heygen/heygen-video-1", GeminiClient.omniSlug]
        for slug in families {
            add("create T2V \(slug)", "createVideo", slug) {
                $0.prompt = "Un chef cocina pasta en una cocina pequeña"
                $0.cameraMoves = ["dolly-in", "arc-left"]
                $0.texts = ["dialogue": "Leo: ¡Ya casi está!\nAna: Huele increíble.", "sound": "sizzling pan"]
                $0.choices["language"] = "Spanish"
                $0.choices["tone"] = "Warm"
                $0.style = "warm film look"
            }
            add("create refs \(slug)", "createVideo", slug) {
                $0.prompt = "Leo drinks the soda on a sunny rooftop"
                $0.character = leo
                $0.product = can
                $0.references = [image]
            }
        }
        add("create frames", "createVideo") {
            $0.prompt = "the waves roll in"
            $0.firstFrame = image
            $0.lastFrame = image
            $0.aspect = nil
            $0.texts = ["onScreenText": "SALE"]
        }
        add("create photoreal keyframe", "createVideo") {
            $0.prompt = "Leo walks into the café"
            $0.character = VideoSubject(name: "Leo", photos: [image], isPhotoreal: true)
        }
        add("create keyframe made", "createVideo") {
            $0.prompt = "Leo walks into the café"
            $0.character = VideoSubject(name: "Leo", photos: [image], isPhotoreal: true)
            $0.firstFrame = image
            $0.firstFrameIsKeyframe = true
            $0.aspect = nil
        }
        add("animate", "animateImage") {
            $0.firstFrame = image
            $0.prompt = "her hair blows in the wind"
            $0.cameraMoves = ["dolly-in", "crane-up", "360-orbit"]
            $0.strength = .strong
            $0.duration = 10
        }
        add("animate wan", "animateImage", "alibaba/wan-3.0") {
            $0.firstFrame = image
            $0.cameraMoves = ["360-orbit"]
        }
        for style in VideoCatalog.tool("transitions")?.group("style")?.values ?? [] {
            add("transition \(style)", "transitions") {
                $0.firstFrame = image
                $0.lastFrame = image
                $0.choices["style"] = style
            }
        }
        add("transition veo lite", "transitions", "google/veo-3.1-lite") {
            $0.firstFrame = image
            $0.lastFrame = image
        }
        for modelID in ["bytedance/seedance-2.0-fast", "bytedance/seedance-2.5", "google/veo-3.1-fast", "alibaba/wan-3.0", "kwaivgi/kling-v3.0-pro"] {
            add("cinema \(modelID)", "cinemaStudio", modelID) {
                $0.prompt = "A detective searches a rain-soaked alley at night"
                $0.character = VideoSubject(name: "Mara", details: "detective in a trench coat", photos: [image])
                $0.shots = [VideoShot(action: "Mara kneels by a puddle", camera: "dolly-in", emotion: "Fear"),
                            VideoShot(action: "She looks up at a window", camera: "tilt-up"),
                            VideoShot(action: "A shadow moves behind the glass", camera: "crash-zoom-in", emotion: "Surprise")]
                $0.choices = ["genre": "Noir", "era": "1980s", "body": "35 mm film", "lens": "Anamorphic", "aperture": "f/1.4 wide open",
                              "light": "Practicals", "pacing": "Calm", "speed": "Slow motion", "intensity": "High", "language": "English"]
                $0.texts = ["dialogue": "Mara: Who's there?"]
                $0.duration = 9
            }
        }
        add("storyboard per frame", "storyboardVideo") {
            $0.shots = [VideoShot(action: "a fox wakes up", camera: "zoom-in", image: image),
                        VideoShot(action: "it runs across the snow", image: image),
                        VideoShot(action: "it jumps into a burrow", camera: "tilt-down", image: image)]
            $0.choices["flow"] = "Flow into next frame"
        }
        add("storyboard multi-shot", "storyboardVideo") {
            $0.shots = [VideoShot(action: "a fox wakes up", image: image), VideoShot(action: "it runs across the snow", image: image)]
            $0.choices["mode"] = "One multi-shot clip"
        }
        add("avatar photo", "talkingAvatar") {
            $0.firstFrame = image
            $0.texts = ["script": "Hola, soy Ana y hoy te enseño tres trucos."]
            $0.choices["background"] = "Remove"
        }
        add("avatar voice", "talkingAvatar") {
            $0.firstFrame = image
            $0.audioURL = "https://example.com/voice.m4a"
        }
        for modelID in ["google/veo-3.1-lite", "kwaivgi/kling-v3.0-std"] {
            add("avatar scene \(modelID)", "talkingAvatar", modelID) {
                $0.firstFrame = image
                $0.aspect = nil
                $0.choices = ["mode": "Talking scene", "scene": "Podcast", "language": "Spanish"]
                $0.texts = ["script": "Hoy hablamos de café.", "gestures": "se inclina hacia el micrófono"]
                $0.duration = nil
            }
        }
        add("extend last frame", "extendVideo") {
            $0.sourceVideoURL = clip
            $0.firstFrame = image
            $0.prompt = "the dog catches the ball"
            $0.sourceSize = CGSize(width: 720, height: 1280)
        }
        add("extend native", "extendVideo", "black-forest-labs/flux-3-video") {
            $0.sourceVideoURL = clip
            $0.sourceJobID = "gen-vid-123"
            $0.sourceModelID = "black-forest-labs/flux-3-video"
        }
        for mode in VideoCatalog.tool("editVideo")?.group("mode")?.values ?? [] {
            add("edit \(mode)", "editVideo") {
                $0.sourceVideoFile = URL(fileURLWithPath: "/tmp/clip.mp4")
                $0.sourceDuration = 6
                $0.choices["mode"] = mode
                $0.choices["restyle"] = "Claymation"
                $0.texts = ["change": "haz la chaqueta roja"]
            }
        }
        add("edit with image", "editVideo") {
            $0.sourceVideoURL = clip
            $0.references = [image]
            $0.texts = ["change": "replace the hat with the one in the image"]
            $0.sourceSize = CGSize(width: 1080, height: 1920)
        }
        add("edit seedance", "editVideo", "bytedance/seedance-2.0-fast") {
            $0.sourceVideoURL = clip
            $0.sourceDuration = 5
            $0.texts = ["change": "make it snow"]
        }
        for modelID in ["alibaba/wan-3.0", "bytedance/seedance-2.0-fast"] {
            add("motion \(modelID)", "motionTransfer", modelID) {
                $0.character = VideoSubject(name: "Kai", details: "cartoon robot", photos: [image])
                $0.drivingVideoURL = clip
                $0.drivingDuration = 7.4
                $0.drivingSize = CGSize(width: 1080, height: 1920)
            }
        }
        for swap in ["Face only", "Whole character", "Outfit only"] {
            for modelID in ["runway/aleph-2", "alibaba/wan-3.0"] {
                add("swap \(swap) \(modelID)", "swapVideo", modelID) {
                    $0.sourceVideoURL = clip
                    $0.sourceDuration = 4
                    $0.character = VideoSubject(name: "Sam", photos: [image], isPhotoreal: true)
                    $0.choices["swap"] = swap
                    $0.consent = true
                }
            }
        }
        for mode in ["Precise", "Creative"] {
            add("upscale \(mode)", "upscaleVideo") {
                $0.sourceVideoURL = clip
                $0.sourceSize = CGSize(width: 1920, height: 1080)
                $0.sourceDuration = 5
                $0.choices = ["mode": mode, "factor": "3×"]
                $0.prompt = "the fabric texture"
            }
        }
        add("reframe expand", "reframeVideo") {
            $0.sourceVideoURL = clip
            $0.choices = ["target": "4:5", "mode": "AI expand"]
        }
        for mode in VideoCatalog.tool("videoAd")?.group("mode")?.values ?? [] {
            add("ad \(mode)", "videoAd") {
                $0.product = can
                $0.firstFrame = image
                $0.firstFrameIsKeyframe = true
                $0.choices = ["mode": mode, "language": "Spanish"]
                $0.texts = ["script": "¡No puedo creer lo rápido que funciona!", "props": "rodajas de naranja", "before": "cabello sin brillo",
                            "after": "cabello brillante", "motion": "the can spins and lands in a hand", "steps": "abre la lata y sirve"]
            }
        }
        add("ad keyframe pending", "videoAd") { $0.product = can }
        add("draw", "drawToVideo") {
            $0.firstFrame = image
            $0.prompt = "The red car drives from the left edge to the center and stops."
        }
        for effect in VideoEffects.all {
            add("effect \(effect.id)", "videoEffects") {
                $0.apply(effect)
                $0.firstFrame = image
                $0.firstFrameIsKeyframe = effect.quickStyleID != nil
                if effect.takesText { $0.texts[VideoEffects.textFieldID] = "un vestido rojo de seda" }
            }
        }
        add("effect silent veo", "videoEffects") {
            if let effect = VideoEffects.effect("building-explosion") { $0.apply(effect) }
            $0.firstFrame = image
            $0.audio = false
        }
        add("effect seedance cues on kling", "videoEffects", "kwaivgi/kling-v3.0-std") {
            if let effect = VideoEffects.effect("splash") { $0.apply(effect) }
            $0.firstFrame = image
            $0.audio = true
            $0.aspect = "1:1"
        }
        return runs
    }

    static let sampleModels: [VideoModel] = {
        let seedanceRatios = ["1:1", "3:4", "9:16", "4:3", "16:9", "21:9", "9:21"]
        let frames = ["first_frame", "last_frame"]
        let veo = ["personGeneration", "aspectRatio", "negativePrompt", "conditioningScale", "enhancePrompt"]
        return [
            GeminiClient.makeOmniModel(id: GeminiClient.omniModelID),
            VideoModel(id: "bytedance/seedance-2.0-fast", name: "Seedance 2.0 Fast", durations: Array(4...15), resolutions: ["480p", "720p"],
                       aspectRatios: seedanceRatios, frameTypes: frames, audio: true, supportsSeed: true, passthrough: ["watermark", "req_key"]),
            VideoModel(id: "bytedance/seedance-2.0-mini", name: "Seedance 2.0 Mini", durations: Array(4...15), resolutions: ["480p", "720p"],
                       aspectRatios: seedanceRatios, frameTypes: frames, audio: true, supportsSeed: true,
                       passthrough: ["watermark", "req_key", "return_last_frame"]),
            VideoModel(id: "bytedance/seedance-2.0", name: "Seedance 2.0", durations: Array(4...15), resolutions: ["480p", "720p", "1080p", "4K"],
                       aspectRatios: seedanceRatios, frameTypes: frames, audio: true, supportsSeed: true, passthrough: ["watermark", "req_key"]),
            VideoModel(id: "bytedance/seedance-2.5", name: "Seedance 2.5", durations: Array(4...30), resolutions: ["480p", "720p"],
                       aspectRatios: ["16:9", "4:3", "1:1", "3:4", "9:16", "21:9"], frameTypes: frames, audio: true, supportsSeed: true,
                       passthrough: ["watermark", "req_key", "output_format"]),
            VideoModel(id: "kwaivgi/kling-v3.0-std", name: "Kling 3.0", durations: Array(3...15), resolutions: ["720p"],
                       aspectRatios: ["16:9", "9:16", "1:1"], frameTypes: frames, audio: true, passthrough: ["negative_prompt", "cfg_scale"]),
            VideoModel(id: "kwaivgi/kling-v3.0-pro", name: "Kling 3.0 Pro", durations: Array(3...15), resolutions: ["720p"],
                       aspectRatios: ["16:9", "9:16", "1:1"], frameTypes: frames, audio: true, passthrough: ["negative_prompt", "cfg_scale"]),
            VideoModel(id: "google/veo-3.1-lite", name: "Veo 3.1 Lite", durations: [4, 6, 8], resolutions: ["720p", "1080p"],
                       aspectRatios: ["16:9", "9:16"], frameTypes: frames, audio: true, supportsSeed: true, passthrough: veo),
            VideoModel(id: "google/veo-3.1-fast", name: "Veo 3.1 Fast", durations: [4, 6, 8], resolutions: ["720p", "1080p", "4K"],
                       aspectRatios: ["16:9", "9:16"], frameTypes: frames, audio: true, supportsSeed: true, passthrough: veo),
            VideoModel(id: "alibaba/wan-3.0", name: "Wan 3.0", durations: Array(2...30), resolutions: ["480p", "720p", "1080p"],
                       aspectRatios: ["16:9", "4:3", "1:1", "3:4", "9:16"], frameTypes: frames, audio: true, supportsSeed: true),
            VideoModel(id: "alibaba/wan-3.0-prime", name: "Wan 3.0 Prime", durations: Array(2...30), resolutions: ["480p", "720p", "1080p"],
                       aspectRatios: ["16:9", "4:3", "1:1", "3:4", "9:16"], frameTypes: frames, audio: true, supportsSeed: true),
            VideoModel(id: "minimax/hailuo-3", name: "MiniMax H3", durations: Array(5...15), resolutions: ["2K"],
                       aspectRatios: ["21:9", "16:9", "4:3", "1:1", "3:4", "9:16"], frameTypes: frames, audio: true, passthrough: ["aigc_watermark"]),
            VideoModel(id: "x-ai/grok-imagine-video-1.5-lite", name: "Grok Imagine 1.5 Lite", durations: Array(1...15),
                       resolutions: ["480p", "720p", "1080p"], aspectRatios: ["16:9", "9:16", "1:1", "4:3", "3:4", "3:2", "2:3"],
                       frameTypes: ["first_frame"]),
            VideoModel(id: "heygen/heygen-video-1", name: "HeyGen Video 1", durations: Array(5...15), resolutions: ["480p", "768p", "2K"],
                       aspectRatios: ["21:9", "16:9", "4:3", "1:1", "3:4", "9:16"], frameTypes: ["first_frame"], audio: false,
                       supportsSeed: true, passthrough: ["prompt_enhancement"]),
            VideoModel(id: "black-forest-labs/flux-3-video", name: "FLUX.3 Video", durations: Array(5...20), resolutions: ["720p", "1080p", "2K", "4K"],
                       aspectRatios: ["16:9", "9:16", "1:1", "4:3", "3:4", "21:9"], frameTypes: frames, audio: true,
                       passthrough: ["safety_tolerance", "version"]),
            VideoModel(id: "black-forest-labs/flux-video-edit", name: "FLUX Video Edit", audio: false, passthrough: ["safety_tolerance"]),
            VideoModel(id: "black-forest-labs/flux-video-upscale", name: "FLUX Video Upscale", audio: false, passthrough: ["safety_tolerance"],
                       creativity: [0, 1], upscaleRange: 1.5...3),
            VideoModel(id: "runway/aleph-2", name: "Runway Aleph 2", aspectRatios: ["16:9", "4:3", "3:2", "1:1", "2:3", "3:4", "9:16", "21:9"],
                       audio: false, supportsSeed: true, passthrough: ["contentModeration", "keyframes"]),
            VideoModel(id: "heygen/avatar-iv", name: "HeyGen Avatar IV", resolutions: ["720p", "1080p"], aspectRatios: ["16:9", "9:16", "1:1"],
                       audio: false, passthrough: ["voice_id", "voice_settings", "motion_prompt", "expressiveness", "fit",
                                                   "remove_background", "background", "caption", "title"]),
        ]
    }()
}
#endif
