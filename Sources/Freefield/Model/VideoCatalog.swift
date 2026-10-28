import FreefieldCore
import SwiftUI

enum VideoToolSection: String {
    case create
    case edit
    case ad
}

enum VideoToolEngine: String {
    case model
    case onDevice
    case promptHelper
}

struct VideoSlot: Hashable {
    enum Kind: String {
        case prompt
        case firstFrame
        case lastFrame
        case imageReferences
        case character
        case product
        case sourceVideo
        case drivingVideo
        case audio
        case script
        case shots
        case clips
        case drawing
    }

    let kind: Kind
    var isRequired = false
    var minCount = 0
    var maxCount = 1
    let title: String
    let hint: String
    let symbol: String
}

extension VideoSlot {
    static func prompt(required: Bool, title: String = L("Describe your video"),
                       hint: String = L("Describe the scene, the action and the sound, in any language")) -> VideoSlot {
        VideoSlot(kind: .prompt, isRequired: required, title: title, hint: hint, symbol: "text.alignleft")
    }

    static func firstFrame(required: Bool, title: String = L("Start image"),
                           hint: String = L("The clip starts exactly on this image")) -> VideoSlot {
        VideoSlot(kind: .firstFrame, isRequired: required, title: title, hint: hint, symbol: "photo")
    }

    static func lastFrame(required: Bool, title: String = L("End image"),
                          hint: String = L("The clip ends exactly on this image")) -> VideoSlot {
        VideoSlot(kind: .lastFrame, isRequired: required, title: title, hint: hint, symbol: "photo.badge.checkmark")
    }

    static func imageReferences(max: Int, required: Bool = false, title: String = L("References"),
                                hint: String = L("Photos of places, clothes or objects for the video")) -> VideoSlot {
        VideoSlot(kind: .imageReferences, isRequired: required, minCount: required ? 1 : 0, maxCount: max, title: title,
                  hint: hint, symbol: "photo.stack")
    }

    static func character(required: Bool, title: String = L("Character"),
                          hint: String = L("A saved character or a photo, kept consistent")) -> VideoSlot {
        VideoSlot(kind: .character, isRequired: required, title: title, hint: hint, symbol: "person.crop.circle")
    }

    static func product(required: Bool, title: String = L("Product"),
                        hint: String = L("A saved product or product photos")) -> VideoSlot {
        VideoSlot(kind: .product, isRequired: required, title: title, hint: hint, symbol: "shippingbox")
    }

    static func sourceVideo(required: Bool, title: String = L("Clip"),
                            hint: String = L("A clip from your library or a file")) -> VideoSlot {
        VideoSlot(kind: .sourceVideo, isRequired: required, title: title, hint: hint, symbol: "film")
    }

    static func drivingVideo(required: Bool, title: String = L("Motion video"),
                             hint: String = L("3–15 s of one person moving, with no cuts")) -> VideoSlot {
        VideoSlot(kind: .drivingVideo, isRequired: required, title: title, hint: hint, symbol: "figure.walk.motion")
    }

    static func audio(required: Bool, title: String = L("Audio"),
                      hint: String = L("An m4a, mp3 or wav file")) -> VideoSlot {
        VideoSlot(kind: .audio, isRequired: required, title: title, hint: hint, symbol: "waveform")
    }

    static func script(required: Bool, title: String = L("Script"),
                       hint: String = L("Spoken exactly as you type it, in any language")) -> VideoSlot {
        VideoSlot(kind: .script, isRequired: required, title: title, hint: hint, symbol: "text.quote")
    }

    static func shots(min: Int = 1, max: Int, title: String = L("Shots"),
                      hint: String = L("Each shot is one action and one camera move")) -> VideoSlot {
        VideoSlot(kind: .shots, isRequired: min > 0, minCount: min, maxCount: max, title: title, hint: hint,
                  symbol: "rectangle.split.3x1")
    }

    static func clips(min: Int, max: Int, required: Bool, title: String = L("Clips"),
                      hint: String = L("Clips from your library, in order")) -> VideoSlot {
        VideoSlot(kind: .clips, isRequired: required, minCount: min, maxCount: max, title: title, hint: hint,
                  symbol: "film.stack")
    }

    static func drawing(title: String = L("Your drawing"),
                        hint: String = L("Arrows and short notes drawn on the image")) -> VideoSlot {
        VideoSlot(kind: .drawing, isRequired: true, title: title, hint: hint, symbol: "pencil.and.scribble")
    }
}

struct VideoOptionCondition: Hashable {
    let group: String
    let values: [String]
}

struct VideoOptionDetail: Hashable {
    var symbol: String?
    var subtitle: String?
    var title: String?

    init(_ symbol: String?, _ subtitle: String? = nil, title: String? = nil) {
        self.symbol = symbol
        self.subtitle = subtitle
        self.title = title
    }
}

struct VideoOptionGroup: Hashable, Identifiable {
    let id: String
    let title: String
    let values: [String]
    var defaultValue: String?
    var shownWhen: VideoOptionCondition?
    var details: [String: VideoOptionDetail] = [:]

    var initial: String { defaultValue ?? values.first ?? "" }

    func label(_ value: String) -> String { details[value]?.title ?? L(value) }
}

struct VideoTextField: Hashable, Identifiable {
    let id: String
    let title: String
    let placeholder: String
    var isLiteral = false
    var limit = 300
    var isMultiline = false
    var shownWhen: VideoOptionCondition?
}

struct VideoModelFilter: Hashable {
    var kinds: Set<VideoModelKind> = [.generate]
    var firstFrame = false
    var lastFrame = false
    var videoInput = false
    var audioInput = false
    var imageReferences = 0
    var sound = false

    func allows(_ model: VideoModel) -> Bool {
        guard kinds.contains(model.kind) else { return false }
        if firstFrame, !model.supportsFirstFrame { return false }
        if lastFrame, !model.supportsLastFrame { return false }
        if videoInput, !model.acceptsVideoInput { return false }
        if audioInput, !model.acceptsAudioInput { return false }
        if imageReferences > 0, model.maxImageReferences < imageReferences { return false }
        if sound, !VideoModelTraits(model).makesSound { return false }
        return true
    }
}

struct VideoToolDefaults: Hashable {
    var duration: Int? = 5
    var resolution: String? = "720p"
    var aspect: String?
    var audio = false
}

struct VideoModeModel: Hashable {
    let group: String
    let value: String
    let model: String
    var filter: VideoModelFilter?
}

struct VideoTool: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let symbol: String
    let section: VideoToolSection
    var engine: VideoToolEngine = .model
    let inputs: [VideoSlot]
    var optionGroups: [VideoOptionGroup] = []
    var textFields: [VideoTextField] = []
    var defaultModel: String?
    var fallbackModels: [String] = []
    var modeModels: [VideoModeModel] = []
    var filter = VideoModelFilter()
    var defaults = VideoToolDefaults()
    var aspects: [String]?
    var durations: ClosedRange<Int>?
    var onDeviceWhen: VideoOptionCondition?
    var needsConsent = false
    let steps: [String]
}

extension VideoTool {
    func group(_ id: String) -> VideoOptionGroup? { optionGroups.first { $0.id == id } }

    func textField(_ id: String) -> VideoTextField? { textFields.first { $0.id == id } }

    func slot(_ kind: VideoSlot.Kind) -> VideoSlot? { inputs.first { $0.kind == kind } }

    func takes(_ kind: VideoSlot.Kind) -> Bool { slot(kind) != nil }

    func choice(_ id: String, in choices: [String: String]) -> String {
        guard let group = group(id) else { return "" }
        if let chosen = choices[id], group.values.contains(chosen) { return chosen }
        return group.initial
    }

    func isShown(_ condition: VideoOptionCondition?, choices: [String: String]) -> Bool {
        guard let condition else { return true }
        return condition.values.contains(choice(condition.group, in: choices))
    }

    func modeModel(for choices: [String: String]) -> VideoModeModel? {
        modeModels.first { choice($0.group, in: choices) == $0.value }
    }

    func modelIDs(for choices: [String: String]) -> [String] {
        var seen = Set<String>()
        let first = modeModel(for: choices)?.model ?? defaultModel
        return ([first].compactMap { $0 } + fallbackModels + [defaultModel].compactMap { $0 }).filter { seen.insert($0).inserted }
    }

    func modelFilter(for choices: [String: String]) -> VideoModelFilter {
        modeModel(for: choices)?.filter ?? filter
    }

    func runsOnDevice(for choices: [String: String]) -> Bool {
        engine == .onDevice || (onDeviceWhen.map { isShown($0, choices: choices) } ?? false)
    }

    var initialChoices: [String: String] {
        Dictionary(optionGroups.map { ($0.id, $0.initial) }, uniquingKeysWith: { first, _ in first })
    }
}

enum VideoCatalog {
    static func tool(_ id: String) -> VideoTool? { all.first { $0.id == id } }

    static func tools(in section: VideoToolSection) -> [VideoTool] { all.filter { $0.section == section } }

    static let languageGroup = VideoOptionGroup(id: "language", title: L("Spoken language"), values: [
        "English", "Spanish", "Portuguese", "French", "German", "Italian", "Japanese", "Korean", "Chinese", "Hindi",
        "Arabic", "Russian", "Turkish", "Dutch", "Polish", "Indonesian",
    ], defaultValue: interfaceLanguage)

    static var interfaceLanguage: String {
        Bundle.main.preferredLocalizations.first?.lowercased().hasPrefix("es") == true ? "Spanish" : "English"
    }

    static func languages(id: String = "language", title: String = L("Spoken language"),
                          shownWhen: VideoOptionCondition? = nil, defaultValue: String? = nil) -> VideoOptionGroup {
        VideoOptionGroup(id: id, title: title, values: languageGroup.values, defaultValue: defaultValue, shownWhen: shownWhen)
    }

    static func extraField(_ placeholder: String, limit: Int = 200, shownWhen: VideoOptionCondition? = nil) -> VideoTextField {
        VideoTextField(id: extraFieldID, title: L("Your instructions (optional)"), placeholder: placeholder, limit: limit,
                       isMultiline: true, shownWhen: shownWhen)
    }

    static let extraFieldID = "extra"

    static let toneGroup = VideoOptionGroup(id: "tone", title: L("Delivery"), values: [
        "Natural", "Warm", "Excited", "Calm", "Serious", "Playful", "Whispering", "Angry", "Sad",
    ])

    private static let dialogueField = VideoTextField(
        id: "dialogue", title: L("Dialogue (optional)"),
        placeholder: L("One line each, e.g.\nLeo: We made it!\nAna: Just in time."),
        isLiteral: true, limit: 300, isMultiline: true
    )
    private static let soundField = VideoTextField(
        id: "sound", title: L("Ambient sound (optional)"), placeholder: L("e.g. rain on the window, distant thunder"), limit: 150
    )

    private static let seedanceFast = "bytedance/seedance-2.0-fast"
    private static let klingStd = "kwaivgi/kling-v3.0-std"
    private static let klingPro = "kwaivgi/kling-v3.0-pro"
    private static let veoLite = "google/veo-3.1-lite"
    private static let wan3 = "alibaba/wan-3.0"
    private static let aleph = "runway/aleph-2"

    static let all: [VideoTool] = [
        VideoTool(
            id: "createVideo", name: L("Create Video"), subtitle: L("Text or images to a clip, with sound."),
            symbol: "video.badge.plus", section: .create,
            inputs: [
                .prompt(required: false, title: L("Describe your video")),
                .firstFrame(required: false, title: L("Start image")),
                .lastFrame(required: false, title: L("End image")),
                .character(required: false),
                .product(required: false),
                .imageReferences(max: 9),
                .sourceVideo(required: false, title: L("Reference video"),
                             hint: L("Motion or style to follow, on models that take videos")),
                .audio(required: false, title: L("Reference audio"), hint: L("A voice or a track to follow, on models that take audio")),
            ],
            optionGroups: [languageGroup, toneGroup],
            textFields: [
                dialogueField,
                VideoTextField(id: "onScreenText", title: L("On-screen text (optional)"),
                               placeholder: L("Words that appear in the video, exactly as typed"), isLiteral: true, limit: 60),
                soundField,
            ],
            defaultModel: seedanceFast,
            fallbackModels: ["bytedance/seedance-2.0", klingStd, veoLite],
            defaults: VideoToolDefaults(duration: 5, resolution: "720p", aspect: "16:9", audio: true),
            steps: [
                L("Describe the scene, or add a start image to animate."),
                L("Add a character, a product or reference images to keep them consistent."),
                L("Pick a camera move and a style, and write any dialogue in your language."),
                L("Freefield writes the instructions each model understands, in English, and makes the clip."),
            ]
        ),
        VideoTool(
            id: "animateImage", name: L("Animate Image"), subtitle: L("Bring a photo to life with camera moves."),
            symbol: "livephoto.play", section: .create,
            inputs: [
                .firstFrame(required: true, title: L("Image"), hint: L("A photo or any image from your library")),
                .prompt(required: false, title: L("What moves (optional)"), hint: L("e.g. her hair blows in the wind and she smiles")),
            ],
            defaultModel: klingStd,
            fallbackModels: [klingPro, veoLite],
            filter: VideoModelFilter(firstFrame: true),
            defaults: VideoToolDefaults(duration: 5, resolution: "720p", aspect: nil, audio: false),
            steps: [
                L("Add a photo, or pick one from the library."),
                L("Choose up to three camera moves; they play in order."),
                L("Optionally say what moves, and how strongly."),
                L("Only the motion is described, so the photo's look stays as it is."),
            ]
        ),
        VideoTool(
            id: "cinemaStudio", name: L("Cinema Studio"), subtitle: L("Film-style shots from a director's panel."),
            symbol: "movieclapper", section: .create,
            inputs: [
                .prompt(required: true, title: L("Scene"), hint: L("What happens and where, in one or two sentences")),
                .character(required: false),
                .shots(min: 0, max: 3),
                .firstFrame(required: false, title: L("Start image (optional)"),
                            hint: L("Or let Freefield make a start image with your character first")),
                .imageReferences(max: 4, title: L("Location and props"), hint: L("Images of the place or objects in the scene")),
            ],
            optionGroups: [
                VideoOptionGroup(id: "genre", title: L("Genre"), values: ["Auto", "Epic", "Drama", "Noir", "Comedy", "Horror", "Action"]),
                VideoOptionGroup(id: "era", title: L("Era"), values: ["Auto", "1960s", "1980s", "1990s", "2000s", "2020s"]),
                VideoOptionGroup(id: "body", title: L("Camera"), values: ["Auto", "Modern digital", "35 mm film", "8 mm film", "DV camcorder"]),
                VideoOptionGroup(id: "lens", title: L("Lens"), values: ["Auto", "Sharp", "Anamorphic", "Vintage anamorphic", "Warm vintage", "Vintage halation"]),
                VideoOptionGroup(id: "aperture", title: L("Aperture"), values: ["Auto", "f/1.4 wide open", "f/4 moderate", "f/11 deep focus"]),
                VideoOptionGroup(id: "light", title: L("Light"), values: ["Auto", "Silhouette", "Practicals", "Window light", "Overhead fall", "Contre-jour", "Soft cross"]),
                VideoOptionGroup(id: "pacing", title: L("Pacing"), values: ["Auto", "Chaotic", "Dynamic", "Calm", "Single shot"]),
                VideoOptionGroup(id: "speed", title: L("Speed"), values: ["Linear", "Slow motion", "Speed-up", "Impact", "Bullet time", "Ramp up", "Flash in", "Flash out", "Hero moment"]),
                VideoOptionGroup(id: "emotion", title: L("Emotion"), values: ["Auto", "Joy", "Anger", "Fear", "Sadness", "Surprise", "Calm"]),
                VideoOptionGroup(id: "intensity", title: L("Intensity"), values: ["Low", "High"], defaultValue: "Low"),
                languageGroup,
                toneGroup,
            ],
            textFields: [dialogueField, soundField],
            defaultModel: seedanceFast,
            fallbackModels: [VideoLineup.cinemaMaxModelID, "bytedance/seedance-2.0", klingPro],
            defaults: VideoToolDefaults(duration: 5, resolution: "720p", aspect: "21:9", audio: true),
            aspects: ["21:9", "16:9", "9:16", "4:3", "1:1"],
            steps: [
                L("Describe the scene and add up to three shots, each with an action and a camera move."),
                L("Set the genre, era, camera, lens and light like a director."),
                L("Add a character: with a real face, a start image is made first so the face stays right."),
                L("Freefield turns the panel into clear instructions in English."),
            ]
        ),
        VideoTool(
            id: "storyboardVideo", name: L("Photos to Video"), subtitle: L("Turn photos, in order, into a short film."),
            symbol: "film.stack", section: .create,
            inputs: [
                .shots(min: 2, max: 8, title: L("Images"), hint: L("2–8 images in order, each with its action and camera move")),
                .audio(required: false, title: L("Music (optional)"), hint: L("Mixed in on this Mac after the clips are joined")),
            ],
            optionGroups: [
                VideoOptionGroup(id: "mode", title: L("Mode"), values: ["Clip per frame", "One multi-shot clip"], details: [
                    "Clip per frame": VideoOptionDetail("square.split.2x1", L("Joined on this Mac"), title: L("One clip per image")),
                    "One multi-shot clip": VideoOptionDetail("film", L("All images in one clip of up to 15 s")),
                ]),
                VideoOptionGroup(id: "flow", title: L("Continuity"), values: ["Separate shots", "Flow into next frame"],
                                 shownWhen: VideoOptionCondition(group: "mode", values: ["Clip per frame"]), details: [
                                     "Separate shots": VideoOptionDetail("rectangle.split.2x1", L("Each clip starts on its image")),
                                     "Flow into next frame": VideoOptionDetail("arrow.right.to.line", L("Each clip also ends on the next image"),
                                                                               title: L("Flow into the next image")),
                                 ]),
                VideoOptionGroup(id: "between", title: L("Between shots"), values: ["Cut", "Crossfade", "AI transition"],
                                 shownWhen: VideoOptionCondition(group: "mode", values: ["Clip per frame"]), details: [
                                     "Cut": VideoOptionDetail("scissors", L("A straight cut")),
                                     "Crossfade": VideoOptionDetail("circle.lefthalf.filled", L("A short dissolve")),
                                 ]),
            ],
            textFields: [soundField, extraField(L("e.g. warm film look and soft light in every shot"))],
            defaultModel: seedanceFast,
            fallbackModels: [VideoLineup.draftModelID, klingStd],
            modeModels: [
                VideoModeModel(group: "mode", value: "One multi-shot clip", model: seedanceFast,
                               filter: VideoModelFilter(imageReferences: 2)),
            ],
            filter: VideoModelFilter(firstFrame: true),
            defaults: VideoToolDefaults(duration: 5, resolution: "720p", aspect: nil, audio: true),
            durations: 4...10,
            steps: [
                L("Bring the images of a photo story, or add 2 to 8 images in order."),
                L("Give each image its action and camera move."),
                L("Each image becomes its own clip in the same style; the clips are joined on this Mac."),
                L("Or make one multi-shot clip from all the images at once."),
            ]
        ),
        VideoTool(
            id: "talkingAvatar", name: L("Talking Avatar"), subtitle: L("A photo that speaks your script."),
            symbol: "person.wave.2", section: .create,
            inputs: [
                .firstFrame(required: true, title: L("Photo"), hint: L("A front-facing face with the mouth visible")),
                .script(required: true),
                .audio(required: false, title: L("Your voice (optional)"), hint: L("An m4a, mp3 or wav to lip-sync instead of a computer voice")),
            ],
            optionGroups: [
                VideoOptionGroup(id: "mode", title: L("Mode"), values: ["Talking scene", "Talking photo"]),
                VideoOptionGroup(id: "scene", title: L("Setting"), values: [
                    "Selfie", "Podcast", "Car talking", "Selling", "Mirror selfie", "Stream", "Static", "Steadicam",
                    "Handheld", "Angry", "Happy", "Crying", "Singing", "Rapping", "CCTV",
                ], shownWhen: VideoOptionCondition(group: "mode", values: ["Talking scene"]), details: [
                    "Selfie": VideoOptionDetail("person.crop.square"), "Podcast": VideoOptionDetail("mic"),
                    "Car talking": VideoOptionDetail("car"), "Selling": VideoOptionDetail("bag"),
                    "Mirror selfie": VideoOptionDetail("iphone"), "Stream": VideoOptionDetail("dot.radiowaves.left.and.right"),
                    "Static": VideoOptionDetail("camera"), "Steadicam": VideoOptionDetail("figure.walk"),
                    "Handheld": VideoOptionDetail("hand.raised"), "Angry": VideoOptionDetail("flame"),
                    "Happy": VideoOptionDetail("face.smiling"), "Crying": VideoOptionDetail("drop"),
                    "Singing": VideoOptionDetail("music.mic"), "Rapping": VideoOptionDetail("music.note"),
                    "CCTV": VideoOptionDetail("video"),
                ]),
                languageGroup,
                VideoOptionGroup(id: "expressiveness", title: L("Expressiveness"), values: ["Low", "Medium", "High"], defaultValue: "Medium",
                                 shownWhen: VideoOptionCondition(group: "mode", values: ["Talking photo"]), details: [
                                     "Low": VideoOptionDetail("face.dashed", L("Calm, small movements")),
                                     "Medium": VideoOptionDetail("face.smiling", L("Natural")),
                                     "High": VideoOptionDetail("face.smiling.inverse", L("Big, lively expressions")),
                                 ]),
                VideoOptionGroup(id: "background", title: L("Background"), values: ["Keep", "Remove"],
                                 shownWhen: VideoOptionCondition(group: "mode", values: ["Talking photo"]), details: [
                                     "Keep": VideoOptionDetail("photo", L("The photo's own background")),
                                     "Remove": VideoOptionDetail("person.crop.rectangle", L("Just the person")),
                                 ]),
                VideoOptionGroup(id: "captions", title: L("Captions"), values: ["Off", "On"],
                                 shownWhen: VideoOptionCondition(group: "mode", values: ["Talking photo"])),
            ],
            textFields: [
                VideoTextField(id: "script", title: L("Script"), placeholder: L("What the person says, in any language"),
                               isLiteral: true, limit: 900, isMultiline: true),
                VideoTextField(id: "gestures", title: L("Gestures (optional)"), placeholder: L("e.g. she leans in and smiles"),
                               limit: 150, shownWhen: VideoOptionCondition(group: "mode", values: ["Talking scene"])),
            ],
            defaultModel: "heygen/avatar-iv",
            fallbackModels: [VideoLineup.talkingSceneModelID],
            modeModels: [
                VideoModeModel(group: "mode", value: "Talking scene", model: VideoLineup.talkingSceneModelID,
                               filter: VideoModelFilter(firstFrame: true, sound: true)),
            ],
            filter: VideoModelFilter(kinds: [.avatar], imageReferences: 1),
            defaults: VideoToolDefaults(duration: 8, resolution: "720p", aspect: "9:16", audio: true),
            aspects: ["9:16", "16:9", "1:1"],
            steps: [
                L("Add a front-facing photo with the mouth visible."),
                L("Type what they say, in any language, or upload your own recording."),
                L("Typed words: the person is filmed saying them in the setting you pick. Your recording: the photo's lips follow your voice."),
                L("The words are spoken exactly as you typed them."),
            ]
        ),
        VideoTool(
            id: "videoEffects", name: L("Video Effects"), subtitle: L("One-click effects for photos and products."),
            symbol: "rectangle.stack.badge.play", section: .create,
            inputs: [
                .firstFrame(required: true, title: L("Photo"), hint: L("Each effect says what works best")),
            ],
            textFields: [extraField(L("e.g. keep her glasses on; slow it down at the end"), limit: 200)],
            defaultModel: seedanceFast,
            fallbackModels: [klingStd, veoLite, "x-ai/grok-imagine-video-1.5-lite"],
            filter: VideoModelFilter(firstFrame: true),
            defaults: VideoToolDefaults(duration: 5, resolution: "720p", aspect: "9:16", audio: false),
            steps: [
                L("Pick an effect from the gallery."),
                L("Add the photo it asks for."),
                L("Effects paired with a photo effect first make that image, then animate it."),
                L("Each effect starts on the model it was tuned for; you can pick another."),
            ]
        ),
        VideoTool(
            id: "transitions", name: L("Transitions"), subtitle: L("Morph one image or clip into another."),
            symbol: "rectangle.2.swap", section: .create,
            inputs: [
                .firstFrame(required: true, title: L("Start image")),
                .lastFrame(required: true, title: L("End image")),
                .clips(min: 2, max: 2, required: false, title: L("Or two clips"),
                       hint: L("Freefield uses the last frame of the first clip and the first frame of the second")),
                .prompt(required: false, title: L("Extra direction (optional)"), hint: L("e.g. petals swirl during the change")),
            ],
            optionGroups: [
                VideoOptionGroup(id: "style", title: L("Transition"), values: [
                    "Seamless morph", "Zoom through", "Whip pan", "Spin", "Liquid", "Light leak", "Particle dissolve",
                    "Match cut", "Fly through object", "Day to night",
                ], details: [
                    "Seamless morph": VideoOptionDetail("circle.dashed", L("One image flows into the other")),
                    "Zoom through": VideoOptionDetail("plus.magnifyingglass", L("Dives into the first image")),
                    "Whip pan": VideoOptionDetail("wind", L("A fast sideways swish")),
                    "Spin": VideoOptionDetail("arrow.triangle.2.circlepath", L("The frame spins into the next")),
                    "Liquid": VideoOptionDetail("drop", L("It melts and re-forms")),
                    "Light leak": VideoOptionDetail("sun.max", L("A warm flash of light")),
                    "Particle dissolve": VideoOptionDetail("aqi.medium", L("Breaks into glowing particles")),
                    "Match cut": VideoOptionDetail("square.on.square", L("Matching shapes line up")),
                    "Fly through object": VideoOptionDetail("airplane", L("The camera flies through a gap")),
                    "Day to night": VideoOptionDetail("moon.stars", L("The light turns from day to night")),
                ]),
                VideoOptionGroup(id: "join", title: L("With clips"), values: ["Transition only", "Join with clips"], details: [
                    "Transition only": VideoOptionDetail("rectangle.2.swap", L("Just the transition clip")),
                    "Join with clips": VideoOptionDetail("film.stack", L("The transition joined between your two clips")),
                ]),
            ],
            defaultModel: klingStd,
            fallbackModels: [klingPro, seedanceFast],
            filter: VideoModelFilter(firstFrame: true, lastFrame: true),
            defaults: VideoToolDefaults(duration: 5, resolution: "720p", aspect: nil, audio: false),
            durations: 3...8,
            steps: [
                L("Add a start image and an end image, or two clips."),
                L("Pick how one turns into the other."),
                L("Similar framing in both images gives the cleanest morph."),
                L("With clips, the transition is joined between them on this Mac."),
            ]
        ),
        VideoTool(
            id: "drawToVideo", name: L("Draw the Movement"), subtitle: L("Sketch arrows to direct the motion."),
            symbol: "scribble.variable", section: .create,
            inputs: [
                .firstFrame(required: true, title: L("Image")),
                .drawing(),
            ],
            textFields: [extraField(L("e.g. only the dog moves; the background stays still"))],
            defaultModel: klingStd,
            fallbackModels: [klingPro, veoLite],
            filter: VideoModelFilter(firstFrame: true),
            defaults: VideoToolDefaults(duration: 5, resolution: "720p", aspect: nil, audio: false),
            durations: 4...10,
            steps: [
                L("Add an image and draw arrows and short notes on it."),
                L("Freefield turns the drawing into motion directions."),
                L("The clean image becomes the first frame, so the drawing never shows in the video."),
            ]
        ),

        VideoTool(
            id: "editVideo", name: L("Edit Video"), subtitle: L("Change a clip by describing it."),
            symbol: "bubble.and.pencil", section: .edit,
            inputs: [
                .sourceVideo(required: true, hint: L("Up to 15 seconds")),
                .imageReferences(max: 1, title: L("Style or subject image (optional)"),
                                 hint: L("With an image, the edit uses a premium model that costs more.")),
            ],
            optionGroups: [
                VideoOptionGroup(id: "mode", title: L("Mode"), values: ["Describe a change", "Restyle", "Relight", "Weather & time", "Translate dialogue"],
                                 details: [
                                     "Describe a change": VideoOptionDetail("text.cursor", L("In your own words")),
                                     "Restyle": VideoOptionDetail("paintbrush", L("Another art style")),
                                     "Relight": VideoOptionDetail("lightbulb", L("A new light")),
                                     "Weather & time": VideoOptionDetail("cloud.sun.rain", L("Rain, snow, night…")),
                                     "Translate dialogue": VideoOptionDetail("character.bubble", L("Another language")),
                                 ]),
                VideoOptionGroup(id: "restyle", title: L("Style"), values: [
                    "Watercolor", "Anime", "Claymation", "3D animated film", "Oil painting", "Comic ink", "Pixel art",
                    "Paper cut-out", "Felt stop-motion", "Toy bricks", "Low-poly", "Charcoal sketch", "Ukiyo-e print",
                    "Noir black-and-white", "Vintage 16mm", "VHS", "Cyberpunk neon", "Vaporwave", "Pastel dream",
                    "Cel shading", "Stained glass", "Marble statue", "Liquid chrome", "Origami", "Graffiti",
                    "Neon outline", "Thermal camera", "Infrared", "Sepia silent film", "My moodboard",
                ], shownWhen: VideoOptionCondition(group: "mode", values: ["Restyle"])),
                VideoOptionGroup(id: "relight", title: L("Light"), values: ["Golden hour", "Blue hour", "Neon night", "Studio softbox", "Candlelight", "Moonlight"],
                                 shownWhen: VideoOptionCondition(group: "mode", values: ["Relight"]), details: [
                                     "Golden hour": VideoOptionDetail("sun.horizon"), "Blue hour": VideoOptionDetail("cloud.moon"),
                                     "Neon night": VideoOptionDetail("lightspectrum.horizontal"), "Studio softbox": VideoOptionDetail("lamp.desk"),
                                     "Candlelight": VideoOptionDetail("flame"), "Moonlight": VideoOptionDetail("moon"),
                                 ]),
                VideoOptionGroup(id: "weather", title: L("Weather & time"), values: ["Rain", "Snow", "Fog", "Night", "Sunset"],
                                 shownWhen: VideoOptionCondition(group: "mode", values: ["Weather & time"]), details: [
                                     "Rain": VideoOptionDetail("cloud.rain"), "Snow": VideoOptionDetail("snowflake"),
                                     "Fog": VideoOptionDetail("cloud.fog"), "Night": VideoOptionDetail("moon.stars"),
                                     "Sunset": VideoOptionDetail("sunset"),
                                 ]),
                languages(id: "targetLanguage", title: L("New language"),
                          shownWhen: VideoOptionCondition(group: "mode", values: ["Translate dialogue"])),
            ],
            textFields: [
                VideoTextField(id: "change", title: L("What to change"), placeholder: L("e.g. make the jacket red"), limit: 300,
                               shownWhen: VideoOptionCondition(group: "mode", values: ["Describe a change"])),
                extraField(L("e.g. don't change the logo on the shirt"),
                           shownWhen: VideoOptionCondition(group: "mode", values: ["Restyle", "Relight", "Weather & time", "Translate dialogue"])),
            ],
            defaultModel: "black-forest-labs/flux-video-edit",
            fallbackModels: [aleph],
            filter: VideoModelFilter(kinds: [.edit, .generate], videoInput: true),
            defaults: VideoToolDefaults(duration: nil, resolution: nil, aspect: nil, audio: true),
            steps: [
                L("Pick a clip of up to 15 seconds."),
                L("Describe one change, or pick a restyle, a new light, the weather or a new language."),
                L("The clip keeps its timing, framing and sound."),
                L("If the usual model is busy, a premium one makes the edit instead; it costs more."),
            ]
        ),
        VideoTool(
            id: "extendVideo", name: L("Extend Video"), subtitle: L("Add seconds to a clip."),
            symbol: "goforward.plus", section: .edit,
            inputs: [
                .sourceVideo(required: true),
                .prompt(required: false, title: L("What happens next"), hint: L("Leave it empty to continue naturally")),
            ],
            optionGroups: [
                VideoOptionGroup(id: "method", title: L("Method"), values: ["Auto", "Native continuation", "Last frame"], details: [
                    "Auto": VideoOptionDetail("arrow.triangle.branch", L("Freefield picks the best way for this clip")),
                    "Native continuation": VideoOptionDetail("forward", L("The same model carries on; only for clips made here")),
                    "Last frame": VideoOptionDetail("photo", L("A new clip starts from its last image")),
                ]),
                languageGroup,
            ],
            textFields: [
                VideoTextField(id: "dialogue", title: L("Continue the dialogue (optional)"), placeholder: L("e.g. Ana: Let's go!"),
                               isLiteral: true, limit: 200, isMultiline: true),
            ],
            defaultModel: seedanceFast,
            fallbackModels: ["bytedance/seedance-2.0", klingStd],
            filter: VideoModelFilter(firstFrame: true),
            defaults: VideoToolDefaults(duration: 5, resolution: nil, aspect: nil, audio: true),
            durations: 4...15,
            steps: [
                L("Pick a clip from your library, or import one."),
                L("Say what happens next, or leave it empty."),
                L("Freefield continues from the clip's last frame on the same model, then joins both parts seamlessly."),
                L("Quality drops after several extensions in a row."),
            ]
        ),
        VideoTool(
            id: "motionTransfer", name: L("Copy a Movement"), subtitle: L("Your character performs the moves from a video."),
            symbol: "figure.dance", section: .edit,
            inputs: [
                .character(required: true, title: L("Character image"), hint: L("A full-body photo with the hands visible")),
                .drivingVideo(required: true),
            ],
            optionGroups: [
                VideoOptionGroup(id: "scene", title: L("Background"), values: ["Image", "Video"], details: [
                    "Image": VideoOptionDetail("photo", L("The character stays where the photo is"), title: L("From your photo")),
                    "Video": VideoOptionDetail("film", L("The character moves into the video's place"), title: L("From the video")),
                ]),
                VideoOptionGroup(id: "sound", title: L("Sound"), values: ["Keep original sound", "No sound"], details: [
                    "Keep original sound": VideoOptionDetail("speaker.wave.2", L("Added back on this Mac, free")),
                    "No sound": VideoOptionDetail("speaker.slash", L("A silent clip")),
                ]),
            ],
            textFields: [extraField(L("e.g. no other people; keep the photo's light"))],
            defaultModel: wan3,
            fallbackModels: ["alibaba/wan-3.0-prime", "minimax/hailuo-3"],
            filter: VideoModelFilter(videoInput: true, imageReferences: 1),
            defaults: VideoToolDefaults(duration: nil, resolution: "720p", aspect: nil, audio: false),
            steps: [
                L("Add your character: a full-body photo works best."),
                L("Add 3–15 seconds of one person moving, with no cuts."),
                L("The character performs the same moves, timing and framing."),
                L("The original sound can be added back on this Mac, free."),
            ]
        ),
        VideoTool(
            id: "swapVideo", name: L("Swap a Person in Video"), subtitle: L("Put your character into a clip."),
            symbol: "person.line.dotted.person", section: .edit,
            inputs: [
                .sourceVideo(required: true, hint: L("Up to 10 seconds keeps the cost down")),
                .character(required: true, title: L("Person"), hint: L("A clear photo of the face")),
            ],
            optionGroups: [
                VideoOptionGroup(id: "swap", title: L("What to swap"), values: ["Face only", "Whole character", "Outfit only"], details: [
                    "Face only": VideoOptionDetail("face.smiling", L("Just the face; hair and clothes stay")),
                    "Whole character": VideoOptionDetail("person.fill", L("Face, hair, body and clothes")),
                    "Outfit only": VideoOptionDetail("tshirt", L("Just the clothes; the face stays")),
                ]),
            ],
            textFields: [extraField(L("e.g. keep the original hairstyle"))],
            defaultModel: aleph,
            fallbackModels: [VideoLineup.budgetSwapModelID],
            filter: VideoModelFilter(kinds: [.edit, .generate], videoInput: true, imageReferences: 1),
            defaults: VideoToolDefaults(duration: nil, resolution: "720p", aspect: nil, audio: false),
            needsConsent: true,
            steps: [
                L("Pick a clip; up to 10 seconds keeps the cost down."),
                L("Add the person: a clear photo or a saved character."),
                L("Choose what to swap: the face, the whole person or the outfit."),
                L("Motion, camera and timing stay the same, and the original sound is added back."),
            ]
        ),
        VideoTool(
            id: "upscaleVideo", name: L("Improve Video Quality"), subtitle: L("Sharper, larger clips."),
            symbol: "arrow.up.left.and.arrow.down.right", section: .edit,
            inputs: [
                .sourceVideo(required: true),
                .prompt(required: false, title: L("Detail to bring out (optional)"), hint: L("e.g. the fabric texture and the text on the sign")),
            ],
            optionGroups: [
                VideoOptionGroup(id: "factor", title: L("Size"), values: ["1.5×", "2×", "3×"], defaultValue: "2×", details: [
                    "1.5×": VideoOptionDetail("arrow.up.left.and.arrow.down.right", L("A little larger")),
                    "2×": VideoOptionDetail("arrow.up.left.and.arrow.down.right", L("Twice the size")),
                    "3×": VideoOptionDetail("arrow.up.left.and.arrow.down.right", L("Three times, up to 4K")),
                ]),
                VideoOptionGroup(id: "mode", title: L("Mode"), values: ["Precise", "Creative"], details: [
                    "Precise": VideoOptionDetail("scope", L("Keeps every detail as it is")),
                    "Creative": VideoOptionDetail("paintbrush.pointed", L("Adds fine texture and detail")),
                ]),
            ],
            defaultModel: "black-forest-labs/flux-video-upscale",
            filter: VideoModelFilter(kinds: [.upscale], videoInput: true),
            defaults: VideoToolDefaults(duration: nil, resolution: nil, aspect: nil, audio: false),
            steps: [
                L("Pick a clip."),
                L("Choose 1.5×, 2× or 3×; the long side stays within 4K."),
                L("Precise keeps every detail as it is; Creative adds fine texture."),
                L("Larger and longer clips cost more; the estimate is shown first."),
            ]
        ),
        VideoTool(
            id: "reframeVideo", name: L("Change Video Shape"), subtitle: L("Change a clip's shape for each platform."),
            symbol: "aspectratio", section: .edit,
            inputs: [.sourceVideo(required: true)],
            optionGroups: [
                VideoOptionGroup(id: "target", title: L("New shape"), values: ["9:16", "1:1", "4:5", "16:9", "21:9"]),
                VideoOptionGroup(id: "mode", title: L("Mode"), values: ["Smart crop", "AI expand"]),
            ],
            textFields: [extraField(L("e.g. more beach and sky at the sides"), limit: 150,
                                    shownWhen: VideoOptionCondition(group: "mode", values: ["AI expand"]))],
            defaultModel: aleph,
            filter: VideoModelFilter(kinds: [.edit], videoInput: true),
            defaults: VideoToolDefaults(duration: nil, resolution: nil, aspect: nil, audio: false),
            onDeviceWhen: VideoOptionCondition(group: "mode", values: ["Smart crop"]),
            steps: [
                L("Pick a clip and its new shape."),
                L("Smart crop follows the subject with AI, for a fraction of a cent."),
                L("AI expand paints the missing sides; it costs more."),
            ]
        ),
        VideoTool(
            id: "joinClips", name: L("Join & Trim"), subtitle: L("Trim, order and join clips on this Mac."),
            symbol: "timeline.selection", section: .edit, engine: .onDevice,
            inputs: [
                .clips(min: 2, max: 8, required: true),
                .audio(required: false, title: L("Music (optional)"), hint: L("Mixed under the clips")),
            ],
            optionGroups: [
                VideoOptionGroup(id: "transition", title: L("Between clips"), values: ["Cut", "Crossfade", "Seam fix"]),
                VideoOptionGroup(id: "beat", title: L("Beat cuts"), values: ["Off", "Cut on the beat"]),
                VideoOptionGroup(id: "codec", title: L("Format"), values: ["HEVC", "H.264"]),
                VideoOptionGroup(id: "fps", title: L("Frame rate"), values: ["30 fps", "24 fps"]),
            ],
            defaults: VideoToolDefaults(duration: nil, resolution: nil, aspect: nil, audio: true),
            steps: [
                L("Add 2 to 8 clips and put them in order."),
                L("Trim each one, and pick a cut or a crossfade between them."),
                L("Add music if you like; it replaces the clips' sound."),
                L("Everything runs on this Mac, free."),
            ]
        ),
        VideoTool(
            id: "colorGradeVideo", name: L("Color Grade Video"), subtitle: L("Film looks and color palettes for a clip, free on your Mac."),
            symbol: "camera.filters", section: .edit, engine: .onDevice,
            inputs: [.sourceVideo(required: true, hint: L("A clip from your library or a file"))],
            optionGroups: [
                VideoOptionGroup(id: "look", title: L("Look"), values: VideoGradeLooks.all.map(\.id), defaultValue: VideoGradeLooks.defaultLook,
                                 details: Dictionary(uniqueKeysWithValues: VideoGradeLooks.all.map {
                                     ($0.id, VideoOptionDetail("camera.filters", $0.detail, title: $0.name))
                                 })),
                VideoOptionGroup(id: "strength", title: L("Intensity"), values: ["Subtle", "Balanced", "Strong"], defaultValue: "Strong"),
            ],
            defaults: VideoToolDefaults(duration: nil, resolution: nil, aspect: nil, audio: true),
            steps: [
                L("Pick a clip from your library or a file."),
                L("Choose a look; the tiles show it on your own clip."),
                L("Set how strong it is, then apply it."),
                L("Everything runs on this Mac, free; the sound and size stay the same."),
            ]
        ),
        VideoTool(
            id: "hookCheck", name: L("Does My Video Hook?"), subtitle: L("An AI review of your clip's first seconds."),
            symbol: "gauge.with.needle", section: .ad, engine: .promptHelper,
            inputs: [.sourceVideo(required: true, hint: L("A finished clip of up to a minute"))],
            optionGroups: [
                VideoOptionGroup(id: "platform", title: L("Platform"), values: ["TikTok", "Reels", "Shorts", "YouTube"], details: [
                    "TikTok": VideoOptionDetail("music.note"), "Reels": VideoOptionDetail("camera"),
                    "Shorts": VideoOptionDetail("play.rectangle"), "YouTube": VideoOptionDetail("play.tv"),
                ]),
                VideoOptionGroup(id: "goal", title: L("Goal"), values: ["Awareness", "Sales", "Followers"], details: [
                    "Awareness": VideoOptionDetail("megaphone", L("More people get to know you")),
                    "Sales": VideoOptionDetail("cart", L("People buy")),
                    "Followers": VideoOptionDetail("person.2", L("People follow you")),
                ]),
            ],
            textFields: [VideoTextField(id: "context", title: L("About the clip (optional)"),
                                        placeholder: L("e.g. a 20-second ad for a coffee shop, aimed at students"), limit: 200,
                                        isMultiline: true)],
            defaults: VideoToolDefaults(duration: nil, resolution: nil, aspect: nil, audio: false),
            steps: [
                L("Pick a finished clip of up to a minute."),
                L("Choose the platform and the goal."),
                L("Freefield's AI scores the hook, clarity, pacing and call to action from key frames (it can't hear the sound) and suggests three fixes."),
                L("It's an opinion, not a prediction from real viewer data."),
            ]
        ),

        VideoTool(
            id: "videoAd", name: L("Video Ad"), subtitle: L("Ad videos from your product."),
            symbol: "play.rectangle.on.rectangle", section: .ad,
            inputs: [
                .product(required: true),
                .character(required: false, title: L("Person (optional)"), hint: L("A saved character or a photo")),
                .firstFrame(required: false, title: L("Start image (optional)"),
                            hint: L("Leave it empty and Freefield makes it first")),
            ],
            optionGroups: [
                VideoOptionGroup(id: "mode", title: L("Ad type"), values: ["Product showcase", "UGC talking", "Unboxing", "Hook to video", "Before and after", "TV spot", "Tutorial", "Product review", "Virtual try-on", "Hyper motion", "App demo", "Wild card"],
                                 details: [
                                     "Product showcase": VideoOptionDetail("rotate.3d", L("The product turns in soft, premium light")),
                                     "UGC talking": VideoOptionDetail("person.wave.2", L("A person holds it and talks to the camera"),
                                                                      title: L("Person recommending it")),
                                     "Unboxing": VideoOptionDetail("gift", L("Hands open the box and show it")),
                                     "Hook to video": VideoOptionDetail("bolt", L("An eye-catching first second, then the product"),
                                                                        title: L("Attention-grabbing start")),
                                     "Before and after": VideoOptionDetail("arrow.left.and.right", L("The problem, then the result with it")),
                                     "TV spot": VideoOptionDetail("tv", L("Three quick shots that end on the product"),
                                                                  title: L("TV commercial")),
                                     "Tutorial": VideoOptionDetail("list.number", L("Hands show how to use it, step by step"),
                                                                   title: L("How to use it")),
                                     "Product review": VideoOptionDetail("star.bubble", L("A person gives an honest review to the camera")),
                                     "Virtual try-on": VideoOptionDetail("tshirt", L("A person wears it and shows it off"),
                                                                         title: L("Try it on")),
                                     "Hyper motion": VideoOptionDetail("sparkles", L("Splashes, spins and close-ups, like a 3D film"),
                                                                       title: L("Hyper motion (3D look)")),
                                     "App demo": VideoOptionDetail("iphone", L("A phone shows your app's screen; add a screenshot as the product")),
                                     "Wild card": VideoOptionDetail("dice", L("The AI comes up with a surprising idea"),
                                                                    title: L("Surprise me")),
                                 ]),
                languages(shownWhen: VideoOptionCondition(group: "mode", values: ["UGC talking", "Product review"]), defaultValue: interfaceLanguage),
            ],
            textFields: [
                VideoTextField(id: "script", title: L("Script"), placeholder: L("e.g. I can't believe how fast this works!"),
                               isLiteral: true, limit: 200, isMultiline: true,
                               shownWhen: VideoOptionCondition(group: "mode", values: ["UGC talking", "Product review"])),
                VideoTextField(id: "props", title: L("Props (optional)"), placeholder: L("e.g. orange slices and mint leaves"), limit: 120,
                               shownWhen: VideoOptionCondition(group: "mode", values: ["Product showcase", "Hyper motion"])),
                VideoTextField(id: "motion", title: L("What happens (optional)"), placeholder: L("e.g. the product spins and lands in a hand"),
                               limit: 150, shownWhen: VideoOptionCondition(group: "mode", values: ["Hook to video", "TV spot", "Virtual try-on", "Wild card"])),
                VideoTextField(id: "steps", title: L("Steps (optional)"), placeholder: L("e.g. open it, apply two drops, rub them in"),
                               limit: 150, shownWhen: VideoOptionCondition(group: "mode", values: ["Tutorial", "App demo"])),
                VideoTextField(id: "before", title: L("Before"), placeholder: L("e.g. a dull, frizzy ponytail"), limit: 120,
                               shownWhen: VideoOptionCondition(group: "mode", values: ["Before and after"])),
                VideoTextField(id: "after", title: L("After"), placeholder: L("e.g. smooth, shiny hair"), limit: 120,
                               shownWhen: VideoOptionCondition(group: "mode", values: ["Before and after"])),
                extraField(L("e.g. a summer feel, the product on a wooden table"), limit: 150),
            ],
            defaultModel: seedanceFast,
            fallbackModels: [veoLite, klingStd],
            modeModels: [
                VideoModeModel(group: "mode", value: "UGC talking", model: VideoLineup.talkingSceneModelID,
                               filter: VideoModelFilter(firstFrame: true, sound: true)),
                VideoModeModel(group: "mode", value: "Product review", model: VideoLineup.talkingSceneModelID,
                               filter: VideoModelFilter(firstFrame: true, sound: true)),
            ],
            filter: VideoModelFilter(firstFrame: true),
            defaults: VideoToolDefaults(duration: 8, resolution: "720p", aspect: "9:16", audio: true),
            aspects: ["9:16", "1:1", "16:9"],
            durations: 4...15,
            steps: [
                L("Pick a saved product, or add product photos."),
                L("Choose the kind of ad and its shape: vertical, square or wide."),
                L("Freefield first makes the ad's start image, then animates it with the ad's script."),
                L("Talking ads speak your script exactly as typed."),
            ]
        ),
    ]
}

enum VideoPhrases {
    static let restyles: [String: String] = [
        "Watercolor": "a hand-painted watercolor animation with soft bleeding edges and visible paper texture",
        "Anime": "a 2D anime film with clean line art and cel shading",
        "Claymation": "a claymation stop-motion film with handmade clay textures and slight fingerprints",
        "3D animated film": "a 3D animated feature film with soft global illumination and stylized characters",
        "Oil painting": "a moving oil painting with thick, visible brushstrokes",
        "Comic ink": "a comic book with bold black ink outlines, halftone dots and flat colors",
        "Pixel art": "16-bit pixel art with a limited color palette",
        "Paper cut-out": "a paper cut-out animation with layered colored paper and soft drop shadows",
        "Felt stop-motion": "a felt stop-motion film with fuzzy wool textures",
        "Toy bricks": "a world built from plastic toy bricks, animated in stop-motion",
        "Low-poly": "low-poly 3D graphics with flat-shaded facets",
        "Charcoal sketch": "a charcoal sketch on textured paper with smudged shading",
        "Ukiyo-e print": "a Japanese ukiyo-e woodblock print with flat colors and fine outlines",
        "Noir black-and-white": "a black-and-white film noir with hard shadows and high contrast",
        "Vintage 16mm": "vintage 16mm film with visible grain, gate weave and faded color",
        "VHS": "a 1990s VHS home video with soft focus, color bleed and tracking noise",
        "Cyberpunk neon": "a cyberpunk night lit by magenta and cyan neon",
        "Vaporwave": "a vaporwave look in pastel pink and teal with a retro digital feel",
        "Pastel dream": "a soft pastel dreamscape in hazy light",
        "Cel shading": "cel-shaded 3D with flat color bands and clean outlines",
        "Stained glass": "a stained-glass window with leaded outlines and glowing colored glass",
        "Marble statue": "white marble sculpture, every person and object carved in polished stone",
        "Liquid chrome": "liquid chrome, every surface mirror-polished metal",
        "Origami": "folded origami paper with crisp creases",
        "Graffiti": "a spray-painted graffiti mural on a brick wall",
        "Neon outline": "glowing neon outlines on a dark background",
        "Thermal camera": "a thermal camera view with a heat-map color palette",
        "Infrared": "infrared photography with white foliage and dark skies",
        "Sepia silent film": "a sepia-toned 1920s silent film with flicker and a soft vignette",
    ]

    static let relights: [String: String] = [
        "Golden hour": "warm, low golden-hour sunlight from the side with long, soft shadows",
        "Blue hour": "cool blue-hour twilight with soft ambient light",
        "Neon night": "a night lit by colorful neon signs in magenta and cyan",
        "Studio softbox": "clean studio softbox light from the front left with soft shadows",
        "Candlelight": "warm, flickering candlelight from below",
        "Moonlight": "cool silver moonlight from above with deep shadows",
    ]

    static let weather: [String: String] = [
        "Rain": "heavy rain falling, with wet, reflective surfaces and droplets",
        "Snow": "snow falling, with a light layer of snow on the ground and surfaces",
        "Fog": "thick fog that softens the background",
        "Night": "night, with the scene lit by streetlights and windows",
        "Sunset": "sunset, with warm orange light and a glowing sky",
    ]

    static let transitions: [String: (motion: String, camera: String)] = [
        "Seamless morph": ("every element morphs physically into its counterpart in the end frame",
                           "a smooth push-in through the center of the frame"),
        "Zoom through": ("the camera zooms into the center of the first image, which opens up into the end frame",
                         "a fast, continuous zoom in"),
        "Whip pan": ("a very fast whip pan with heavy motion blur carries the view from the first scene into the end frame",
                     "a whip pan to the side"),
        "Spin": ("the whole frame spins around its center, blurs and settles on the end frame",
                 "a fast roll around the lens axis"),
        "Liquid": ("the image melts into flowing liquid that ripples and re-forms as the end frame",
                   "a slow push-in"),
        "Light leak": ("a warm burst of light-leak glow washes over the frame and fades to reveal the end frame",
                       "a gentle drift forward"),
        "Particle dissolve": ("the first image breaks into glowing particles that drift and reassemble into the end frame",
                              "a slow arc to the side"),
        "Match cut": ("the main subject's outline flows directly into the matching shape in the end frame",
                      "a steady, locked-off frame"),
        "Fly through object": ("the camera flies through a gap in an object in the first frame and comes out into the end frame",
                               "a continuous fly-through forward"),
        "Day to night": ("the light changes from day to night while the scene transforms into the end frame, lamps and windows lighting up",
                         "a slow push-in"),
    ]

    static let cameraBodies: [String: String] = [
        "Modern digital": "a modern digital cinema camera with clean, high dynamic range",
        "35 mm film": "35mm motion picture film with organic grain and halation",
        "8 mm film": "8mm film with heavy grain, a soft vignette and flickering exposure",
        "DV camcorder": "a 2000s DV camcorder with an interlaced video look",
    ]
    static let lenses: [String: String] = [
        "Sharp": "a clean, sharp spherical lens",
        "Anamorphic": "an anamorphic lens with oval bokeh and horizontal flares",
        "Vintage anamorphic": "a vintage anamorphic lens with soft edges and blue streak flares",
        "Warm vintage": "warm vintage glass with gentle softness and low contrast",
        "Vintage halation": "a vintage lens with a strong halation glow around highlights",
    ]
    static let apertures: [String: String] = [
        "f/1.4 wide open": "f/1.4 with a very shallow depth of field",
        "f/4 moderate": "f/4 with moderate depth of field",
        "f/11 deep focus": "f/11 with everything in deep focus",
    ]
    static let lights: [String: String] = [
        "Silhouette": "silhouette lighting, the subjects dark against a bright background",
        "Practicals": "practical lighting from lamps and screens inside the scene",
        "Window light": "soft window light from one side",
        "Overhead fall": "hard overhead light falling on the subjects",
        "Contre-jour": "contre-jour backlight with glowing rims",
        "Soft cross": "soft cross lighting from two sides",
    ]
    static let pacing: [String: String] = [
        "Chaotic": "chaotic, frantic pacing",
        "Dynamic": "dynamic pacing",
        "Calm": "calm, unhurried pacing",
        "Single shot": "one continuous take with no cuts",
    ]
    static let speeds: [String: String] = [
        "Slow motion": "the action plays in slow motion",
        "Speed-up": "the action speeds up",
        "Impact": "the action is fast, then drops into slow motion at the moment of impact",
        "Bullet time": "the action ramps into bullet time at the key moment",
        "Ramp up": "the action starts in slow motion and ramps up to full speed",
        "Flash in": "the action bursts in at high speed, then settles into normal speed",
        "Flash out": "the action plays at normal speed, then whips away in a fast speed ramp at the end",
        "Hero moment": "the action slows into a dramatic slow-motion hero moment at its peak, then returns to normal speed",
    ]
    static let emotions: [String: String] = [
        "Joy": "smiling broadly, eyes bright, shoulders loose",
        "Anger": "fists clenched, jaw tense, chest heaving",
        "Fear": "eyes wide, breathing fast, body pulling back",
        "Sadness": "eyes lowered and wet, shoulders dropped",
        "Surprise": "eyebrows raised, mouth open, a small step back",
        "Calm": "a relaxed face and slow, steady breathing",
    ]

    struct Scene {
        let camera: String
        let gesture: String
        let ambience: String
        let tone: String
        var verb = "says"
    }

    static let scenes: [String: Scene] = [
        "Selfie": Scene(camera: "Front-camera selfie video at arm's length", gesture: "Small natural head movements and a relaxed smile",
                        ambience: "quiet room tone", tone: "casually"),
        "Podcast": Scene(camera: "Medium shot at a podcast desk with a studio microphone in front of the person",
                         gesture: "They lean toward the microphone and gesture with one hand", ambience: "soft studio room tone",
                         tone: "warmly and confidently"),
        "Car talking": Scene(camera: "A phone mounted on the dashboard films the person in the driver's seat of a parked car",
                             gesture: "They glance out of the window and back at the lens", ambience: "muffled street sounds",
                             tone: "casually"),
        "Selling": Scene(camera: "Medium shot facing the camera, like a product presenter",
                         gesture: "They gesture toward the camera with open hands", ambience: "bright, clean room tone",
                         tone: "enthusiastically"),
        "Mirror selfie": Scene(camera: "A phone mirror selfie with the phone visible in the mirror",
                               gesture: "They shift their pose slightly while talking", ambience: "a light bathroom echo",
                               tone: "casually"),
        "Stream": Scene(camera: "A webcam view of a live streamer at a desk with soft colored light behind",
                        gesture: "They react and talk to their viewers", ambience: "quiet keyboard clicks and room tone",
                        tone: "energetically"),
        "Static": Scene(camera: "A locked-off medium close-up on a tripod", gesture: "Minimal movement and steady eye contact",
                        ambience: "quiet room tone", tone: "clearly"),
        "Steadicam": Scene(camera: "A smooth steadicam shot moving slowly backward as the person walks toward the camera",
                           gesture: "They walk and talk naturally", ambience: "light outdoor ambience", tone: "naturally"),
        "Handheld": Scene(camera: "A handheld camera close to the person, with a natural slight shake",
                          gesture: "They talk with lively hand gestures", ambience: "everyday ambience", tone: "naturally"),
        "Angry": Scene(camera: "A close-up with a slight handheld shake", gesture: "Fists clenched, jaw tense, chest heaving",
                       ambience: "tense room tone", tone: "angrily"),
        "Happy": Scene(camera: "A medium close-up in warm light", gesture: "Smiling broadly, eyes bright",
                       ambience: "light, cheerful room tone", tone: "happily"),
        "Crying": Scene(camera: "A close-up in soft light", gesture: "Eyes wet, voice breaking, wiping away a tear",
                        ambience: "quiet room tone", tone: "tearfully"),
        "Singing": Scene(camera: "A medium shot with a slow push-in", gesture: "They sing with feeling, eyes half closed",
                         ambience: "the room's natural reverb", tone: "with feeling", verb: "sings"),
        "Rapping": Scene(camera: "A low-angle handheld shot", gesture: "Rhythmic hand gestures, nodding to the beat",
                         ambience: "a steady beat", tone: "rhythmically", verb: "raps"),
        "CCTV": Scene(camera: "A grainy black-and-white security camera view from a high ceiling corner",
                      gesture: "They speak toward the camera", ambience: "a faint electrical hum", tone: "quietly"),
    ]

    static let adKeyframeTools: [String: String] = [
        "Product showcase": "product-shoot",
        "UGC talking": "ugc-photo",
        "Unboxing": "unboxing",
        "Hook to video": "hook-frame",
        "Product review": "ugc-photo",
    ]

    static let adScenes: [String: (scene: String, showsPerson: Bool)] = [
        "TV spot": ("The opening frame of a polished TV commercial: the product in a bright, cinematic everyday scene, beautifully lit, with room for motion.", true),
        "Tutorial": ("A close, slightly top-down view of two hands holding the product over a tidy, softly lit table, ready to show how it is used. Only the hands and forearms are visible, no face.", false),
        "Virtual try-on": ("A full-body street-style photo of a person wearing the product from the product photos (the clothing, shoes or accessory), standing on a sunny city sidewalk in a relaxed, confident pose. The product's cut, color, pattern and logos are exact.", true),
        "Hyper motion": ("A dramatic, hyper-real 3D product hero shot: the product floating at the center against a bold, saturated color backdrop, with liquid splashes and small particles frozen around it, glossy studio lighting.", false),
        "App demo": ("A close shot of a hand holding a modern smartphone upright in a bright, softly blurred room. The phone screen shows exactly the app screenshot from the product photos, flat on the display, sharp and readable.", false),
        "Wild card": ("The opening frame of a surprising, playful ad: the product in an unexpected setting or at an unusual scale, eye-catching, well lit and clearly the hero.", false),
    ]

    static func upscaleFactor(_ label: String) -> Double {
        Double(label.replacingOccurrences(of: "×", with: "")) ?? 2
    }
}
