import CoreGraphics
import Foundation
import FreefieldCore

struct VideoJobSpec {
    var toolID: String
    var title: String
    var record: String?
    var userTexts: [String] = []
    var literalTexts: [String] = []
    var request: VideoRequest
    var characterID: UUID?
    var productID: UUID?
    var presetID: String?
    var parentAssetID: UUID?
    var sourceDuration: Double?
    var sourceSize: CGSize?
    var estimate: Double?
    var batchID: UUID?

    var tool: Tool { .video }

    var estimatedCost: Double? {
        estimate ?? VideoPricing.estimate(request, sourceSeconds: sourceDuration, sourceSize: sourceSize)
    }

    var guardedCost: Double {
        estimatedCost ?? VideoPricing.ceiling(for: request.model)
    }
}

struct PendingVideoJob: Codable {
    var remoteID: String
    var submittedAt: Date
    var estimate: Double?
    var spec: StoredVideoSpec
    var inputFileNames: [String]
    var isQuiet: Bool?
    var discardsResult: Bool?
    var usageEntryID: UUID?
    var outputCount: Int?
    var filedOutputs: Int?
}

struct PendingVideoEntry: Codable {
    var record: PendingVideoJob?
    var unreadable: JSONValue?

    init(record: PendingVideoJob) {
        self.record = record
    }

    init(unreadable: JSONValue) {
        self.unreadable = unreadable
    }

    init(from decoder: any Decoder) throws {
        if let record = try? PendingVideoJob(from: decoder) {
            self.record = record
        } else {
            unreadable = try JSONValue(from: decoder)
        }
    }

    func encode(to encoder: any Encoder) throws {
        if let record {
            try record.encode(to: encoder)
        } else {
            try (unreadable ?? .null).encode(to: encoder)
        }
    }
}

struct StoredVideoSpec: Codable {
    struct Input: Codable {
        enum Kind: String, Codable { case image, video, audio }
        var kind: Kind
        var value: String
        var mimeType: String?
        var role: String?
    }

    var toolID: String
    var title: String
    var record: String?
    var userTexts: [String]
    var literalTexts: [String]
    var characterID: UUID?
    var productID: UUID?
    var presetID: String?
    var parentAssetID: UUID?
    var sourceDuration: Double?
    var sourceWidth: Double?
    var sourceHeight: Double?
    var estimate: Double?
    var batchID: UUID?

    var model: VideoModel
    var prompt: String
    var duration: Int?
    var resolution: String?
    var aspectRatio: String?
    var firstFrame: Input?
    var lastFrame: Input?
    var references: [Input]
    var generateAudio: Bool?
    var seed: Int?
    var previousJobID: String?
    var upscaleFactor: Double?
    var creativity: Int?
    var providerParameters: [String: JSONValue]

    init(_ spec: VideoJobSpec, store: (InputImage) -> String) {
        let request = spec.request
        func stored(_ image: InputImage) -> Input {
            Input(kind: .image, value: store(image), mimeType: image.mimeType, role: image.role)
        }
        toolID = spec.toolID
        title = spec.title
        record = spec.record
        userTexts = spec.userTexts
        literalTexts = spec.literalTexts
        characterID = spec.characterID
        productID = spec.productID
        presetID = spec.presetID
        parentAssetID = spec.parentAssetID
        sourceDuration = spec.sourceDuration
        sourceWidth = spec.sourceSize.map { Double($0.width) }
        sourceHeight = spec.sourceSize.map { Double($0.height) }
        estimate = spec.estimate
        batchID = spec.batchID
        model = request.model
        prompt = request.prompt
        duration = request.duration
        resolution = request.resolution
        aspectRatio = request.aspectRatio
        firstFrame = request.firstFrame.map(stored)
        lastFrame = request.lastFrame.map(stored)
        references = request.references.map { input in
            switch input {
            case .image(let image): stored(image)
            case .videoURL(let url): Input(kind: .video, value: url)
            case .audioURL(let url): Input(kind: .audio, value: url)
            }
        }
        generateAudio = request.generateAudio
        seed = request.seed
        previousJobID = request.previousJobID
        upscaleFactor = request.upscaleFactor
        creativity = request.creativity
        providerParameters = request.providerParameters
    }

    var inputFileNames: [String] {
        ([firstFrame, lastFrame].compactMap(\.self) + references.filter { $0.kind == .image }).map(\.value)
    }

    mutating func update(from spec: VideoJobSpec) {
        title = spec.title
        record = spec.record
        userTexts = spec.userTexts
        prompt = spec.request.prompt
    }

    func restored(load: (String) -> Data?) -> VideoJobSpec {
        func image(_ input: Input) -> InputImage? {
            guard input.kind == .image, let data = load(input.value) else { return nil }
            let mimeType = input.mimeType ?? ImageCoding.mimeType(forFileExtension: (input.value as NSString).pathExtension)
            return InputImage(data: data, mimeType: mimeType, role: input.role)
        }
        let inputs: [VideoInput] = references.compactMap { input in
            switch input.kind {
            case .image: image(input).map(VideoInput.image)
            case .video: .videoURL(input.value)
            case .audio: .audioURL(input.value)
            }
        }
        let request = VideoRequest(
            model: model, prompt: prompt, duration: duration, resolution: resolution, aspectRatio: aspectRatio,
            firstFrame: firstFrame.flatMap(image), lastFrame: lastFrame.flatMap(image), references: inputs,
            generateAudio: generateAudio, seed: seed, previousJobID: previousJobID, upscaleFactor: upscaleFactor,
            creativity: creativity, providerParameters: providerParameters
        )
        var spec = VideoJobSpec(toolID: toolID, title: title, record: record, userTexts: userTexts, literalTexts: literalTexts,
                                request: request, characterID: characterID, productID: productID, presetID: presetID,
                                parentAssetID: parentAssetID, sourceDuration: sourceDuration, estimate: estimate, batchID: batchID)
        if let sourceWidth, let sourceHeight { spec.sourceSize = CGSize(width: sourceWidth, height: sourceHeight) }
        return spec
    }
}

enum VideoPolling {
    static let patience: TimeInterval = 45 * 60
    static let recheckPatience: TimeInterval = 10 * 60

    static func delay(elapsed: TimeInterval, checks: Int, failures: Int) -> TimeInterval {
        if failures > 0 { return min(120, 15 * pow(2, Double(failures - 1))) }
        if checks == 0 { return max(1, 10 - elapsed) }
        return elapsed < 180 ? 12 : 30
    }
}

enum VideoFailure {
    static func message(for status: VideoJobStatus, request: VideoRequest) -> String {
        switch status.state {
        case .cancelled: return L("The provider cancelled this video.")
        case .expired:
            return request.model.host == .google ? L("This video expired at Google before it could be downloaded.")
                : L("This video expired at OpenRouter before it could be downloaded.")
        default: break
        }
        if let hint = hint(for: status.error, request: request) { return hint }
        if let text = status.error?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return L("The provider couldn't make this video: %@", String(text.prefix(220)))
        }
        return L("The provider couldn't make this video. Try again or pick another model.")
    }

    static func message(for error: any Error, request: VideoRequest) -> String {
        switch error {
        case FreefieldError.http(_, let text), FreefieldError.unsupported(let text):
            if let hint = hint(for: text, request: request) { return hint }
        case FreefieldError.rateLimited:
            return L("%@ is overloaded or out of quota at its provider right now. Try again in a few minutes or pick another model.",
                     VideoLineup.displayName(for: request.model.id, fallback: request.model.name))
        default:
            break
        }
        return error.localizedDescription
    }

    static func hint(for text: String?, request: VideoRequest) -> String? {
        guard let text = text?.lowercased(), !text.isEmpty else { return nil }
        let model = request.model
        if OpenRouterClient.isUnreachableInput(text) { return OpenRouterClient.unreachableInputMessage }
        let name = VideoLineup.displayName(for: model.id, fallback: model.name)
        let sentImage = request.firstFrame != nil || request.lastFrame != nil || request.references.contains { $0.image != nil }
        let mentionsFace = sentImage && text.range(of: #"\b(faces?|real (person|people|human)s?|likeness|celebrit(y|ies)|public figures?)\b"#,
                                                   options: .regularExpression) != nil
        if mentionsFace {
            let alternative = model.id.hasPrefix("kwaivgi/") ? "Veo 3.1 Lite" : "Kling 3.0"
            return L("%@ doesn't accept this photo of a real person. Try %@, which works with photos of people.", name, alternative)
        }
        if text.contains("copyright") {
            return L("The provider blocked the generated sound as possibly copyrighted music. Try again with sound off, or keep to sound effects.")
        }
        let moderated = ["moderation", "content policy", "safety", "nsfw", "inappropriate", "sensitive", "violat", "prohibited", "flagged"]
            .contains { text.contains($0) }
        if moderated {
            return L("The provider's content filter stopped this video. Change the prompt or the images and try again.")
        }
        return nil
    }
}
