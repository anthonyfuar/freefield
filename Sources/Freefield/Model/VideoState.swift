import FreefieldCore
import NaturalLanguage
import SwiftUI

struct VideoClipPick: Hashable {
    var assetID: UUID?
    var link = ""

    var trimmedLink: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isEmpty: Bool { assetID == nil && trimmedLink.isEmpty }
}

struct VideoShotDraft: Identifiable, Hashable {
    let id = UUID()
    var action = ""
    var camera: String?
    var emotion: String?
    var image: Data?
}

struct VideoRunConfirmation: Identifiable {
    let id = UUID()
    let total: Double?
    let clips: Int
    var modelName: String?
    var isRepeat = false

    var title: String {
        if isRepeat { return L("Generate the same video again?") }
        return total.map { L("Generate for about %@?", AppModel.money($0)) } ?? L("Generate without a price estimate?")
    }

    var message: String {
        if isRepeat {
            return L("You started this exact video a moment ago and it may still be generating. Running it again makes and bills another clip.")
        }
        if total == nil {
            return clips == 1
                ? L("The price of %@ isn't known, so this run can't be estimated. Video providers bill each clip, even if you stop waiting for it.", modelName ?? "")
                : L("The price of %@ isn't known, so these %ld clips can't be estimated. Video providers bill each clip, even if you stop waiting for it.", modelName ?? "", clips)
        }
        return clips == 1
            ? L("Video providers bill each clip, even if you stop waiting for it.")
            : L("This run makes %ld clips. Video providers bill each clip, even if you stop waiting for it.", clips)
    }
}

struct VideoInputProblem: Identifiable {
    let id = UUID()
    let message: String
    let offersFrames: Bool
}

struct VideoRunRecord {
    let toolID: String
    let inputs: VideoToolInputs
    let modelID: String
    var parentAssetID: UUID?
    var batchID: UUID?
}

@Observable
final class VideoLocalWork: Identifiable {
    let id = UUID()
    let title: String
    let startedAt = Date()
    var step: String?
    var failure: String?
    var isRunning: Bool { failure == nil && !isDone }
    var isDone = false
    @ObservationIgnored var task: Task<Void, Never>?

    init(title: String, step: String? = nil) {
        self.title = title
        self.step = step
    }
}

@Observable
final class VideoState {
    let toolID: String

    var prompt = ""
    var choices: [String: String]
    var texts: [String: String] = [:]
    var firstFrame: Data?
    var lastFrame: Data?
    var references: [Data] = []
    var characterID: UUID?
    var characterPhoto: Data?
    var productID: UUID?
    var productPhotos: [Data] = []
    var source = VideoClipPick()
    var driving = VideoClipPick()
    var audioFile: URL?
    var audioDuration: Double?
    var audioLink = ""
    var clipIDs: [UUID] = []
    var shots: [VideoShotDraft] = []
    var presetID: String?
    var moodboardID: UUID?
    var cameraMoves: [String] = []
    var strength = CameraStrength.normal.rawValue
    var effectID: String?
    var drawStrokes: [Stroke] = []
    var drawNotes: [TextNote] = []
    var consent = false
    var firstFrameIsKeyframe = false
    var joinsExtension = true
    var transitionFromClips = false
    var languageIsPicked = false
    var aspectIsPicked = false
    var pickedChoices: Set<String> = []

    var modelID: String?
    var duration: Int?
    var resolution: String?
    var aspect: String?
    var audio: Bool
    var count = 1
    var seed: Int?

    var usesFrames = false

    var sourceLastFrame: Data?
    var clipsStartFrame: Data?
    var clipsEndFrame: Data?
    var subjectIsPhotoreal = false

    var confirmation: VideoRunConfirmation?
    var inputProblem: VideoInputProblem?
    var isPreparing = false
    var preparingStep: String?
    @ObservationIgnored var preparingTask: Task<Void, Never>?
    @ObservationIgnored var preparingID: UUID?
    var runNotes: [String] = []
    var localWork: [VideoLocalWork] = []
    @ObservationIgnored var runs: [UUID: VideoRunRecord] = [:]

    init(tool: VideoTool) {
        toolID = tool.id
        choices = tool.initialChoices
        duration = tool.defaults.duration
        resolution = tool.defaults.resolution
        aspect = tool.defaults.aspect
        audio = tool.defaults.audio
        if let slot = tool.slot(.shots) {
            shots = (0..<max(1, slot.minCount)).map { _ in VideoShotDraft() }
        }
    }

    func choice(_ id: String, in tool: VideoTool) -> String { tool.choice(id, in: choices) }

    func text(_ id: String) -> String { texts[id] ?? "" }

    func pick(_ value: String, for group: String) {
        choices[group] = value
        pickedChoices.insert(group)
    }

    var cameraStrength: CameraStrength { CameraStrength(rawValue: strength) ?? .normal }

    func apply(_ effect: VideoEffect) {
        effectID = effect.id
        duration = effect.duration
        resolution = effect.resolution
        aspect = effect.aspect
        audio = effect.audio
        modelID = nil
    }
}

enum VideoLanguageGuess {
    static func language(of text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard VideoRecipes.wordCount(trimmed) >= 3 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let best = recognizer.languageHypotheses(withMaximum: 1).max(by: { $0.value < $1.value }), best.value >= 0.7 else {
            return nil
        }
        return names[best.key]
    }

    static func spokenText(_ texts: [String: String]) -> String {
        let dialogue = (texts["dialogue"] ?? "").split(whereSeparator: \.isNewline)
            .map { VideoDialogueLine.parse(String($0)).map(\.text).joined(separator: " ") }
            .joined(separator: " ")
        return dialogue.isEmpty ? texts["script"] ?? "" : dialogue
    }

    private static let names: [NLLanguage: String] = [
        .english: "English", .spanish: "Spanish", .portuguese: "Portuguese", .french: "French", .german: "German",
        .italian: "Italian", .japanese: "Japanese", .korean: "Korean", .simplifiedChinese: "Chinese",
        .traditionalChinese: "Chinese", .hindi: "Hindi", .arabic: "Arabic", .russian: "Russian", .turkish: "Turkish",
        .dutch: "Dutch", .polish: "Polish", .indonesian: "Indonesian",
    ]
}
