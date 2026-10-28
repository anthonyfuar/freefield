import Foundation

public enum VideoModelKind: String, Codable, Sendable {
    case generate
    case edit
    case upscale
    case avatar

    public static func infer(_ id: String) -> VideoModelKind {
        if let rule = VideoCapabilities.rule(for: id) { return rule.kind }
        let slug = id.lowercased()
        if slug.contains("upscale") { return .upscale }
        if slug.contains("avatar") { return .avatar }
        if slug.contains("video-edit") || slug.hasSuffix("-edit") { return .edit }
        return .generate
    }
}

public struct VideoModel: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var name: String
    public var vendor: String
    public var summary: String
    public var durations: [Int]
    public var resolutions: [String]
    public var aspectRatios: [String]
    public var frameTypes: [String]
    public var audio: Bool?
    public var supportsSeed: Bool
    public var passthrough: [String]
    public var pricing: [String: String]
    public var sizes: [String]?
    public var creativity: [Int]?
    public var kind: VideoModelKind
    public var acceptsVideoInput: Bool
    public var acceptsAudioInput: Bool
    public var maxImageReferences: Int

    public var upscaleRange: ClosedRange<Double>?
    public var providerTag: String?
    public var discount: Double?
    public var isBusy: Bool?
    public var createdAt: Date?
    public var expiresAt: Date?
    public var provider: Provider?
    public var providerModelID: String?

    public init(
        id: String, name: String, vendor: String = "", summary: String = "",
        durations: [Int] = [], resolutions: [String] = [], aspectRatios: [String] = [], frameTypes: [String] = [],
        audio: Bool? = nil, supportsSeed: Bool = false, passthrough: [String] = [], pricing: [String: String] = [:],
        sizes: [String]? = nil, creativity: [Int]? = nil,
        kind: VideoModelKind? = nil, acceptsVideoInput: Bool? = nil, acceptsAudioInput: Bool? = nil,
        maxImageReferences: Int? = nil, upscaleRange: ClosedRange<Double>? = nil, providerTag: String? = nil,
        discount: Double? = nil, isBusy: Bool? = nil, createdAt: Date? = nil, expiresAt: Date? = nil,
        provider: Provider? = nil, providerModelID: String? = nil
    ) {
        let rule = VideoCapabilities.rule(for: id)
        self.id = id
        self.name = name
        self.vendor = vendor
        self.summary = summary
        self.durations = Array(Set(durations)).sorted()
        self.resolutions = resolutions.sorted { VideoModel.rank(of: $0) < VideoModel.rank(of: $1) }
        self.aspectRatios = aspectRatios
        self.frameTypes = frameTypes
        self.audio = audio
        self.supportsSeed = supportsSeed
        self.passthrough = passthrough
        self.pricing = pricing
        self.sizes = sizes
        self.creativity = creativity
        self.kind = kind ?? VideoModelKind.infer(id)
        self.acceptsVideoInput = acceptsVideoInput ?? rule?.video ?? false
        self.acceptsAudioInput = acceptsAudioInput ?? rule?.audio ?? false
        self.maxImageReferences = maxImageReferences ?? rule?.images ?? 0
        self.upscaleRange = upscaleRange
        self.providerTag = providerTag ?? VideoCapabilities.providerTag(for: id)
        self.discount = discount
        self.isBusy = isBusy
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.provider = provider == .openRouter ? nil : provider
        self.providerModelID = providerModelID
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            (try? container.decodeIfPresent(type, forKey: key)) ?? nil
        }
        let id = try container.decode(String.self, forKey: .id)
        self.init(
            id: id, name: value(String.self, .name) ?? id, vendor: value(String.self, .vendor) ?? "",
            summary: value(String.self, .summary) ?? "", durations: value([Int].self, .durations) ?? [],
            resolutions: value([String].self, .resolutions) ?? [], aspectRatios: value([String].self, .aspectRatios) ?? [],
            frameTypes: value([String].self, .frameTypes) ?? [], audio: value(Bool.self, .audio),
            supportsSeed: value(Bool.self, .supportsSeed) ?? false, passthrough: value([String].self, .passthrough) ?? [],
            pricing: value([String: String].self, .pricing) ?? [:], sizes: value([String].self, .sizes),
            creativity: value([Int].self, .creativity),
            kind: value(String.self, .kind).flatMap(VideoModelKind.init(rawValue:)),
            acceptsVideoInput: value(Bool.self, .acceptsVideoInput), acceptsAudioInput: value(Bool.self, .acceptsAudioInput),
            maxImageReferences: value(Int.self, .maxImageReferences), upscaleRange: value(ClosedRange<Double>.self, .upscaleRange),
            providerTag: value(String.self, .providerTag), discount: value(Double.self, .discount),
            isBusy: value(Bool.self, .isBusy), createdAt: value(Date.self, .createdAt), expiresAt: value(Date.self, .expiresAt),
            provider: value(Provider.self, .provider), providerModelID: value(String.self, .providerModelID)
        )
    }

    public var host: Provider { provider ?? .openRouter }
    public var apiModelID: String { providerModelID ?? id }

    public var makesAudio: Bool { audio == true }
    public var supportsFirstFrame: Bool { frameTypes.contains("first_frame") }
    public var supportsLastFrame: Bool { frameTypes.contains("last_frame") }
    public var acceptsReferences: Bool { maxImageReferences > 0 || acceptsVideoInput || acceptsAudioInput }
    public var followsSourceDuration: Bool { durations.isEmpty }

    public func clampedDuration(_ seconds: Int?) -> Int? {
        guard let seconds, !durations.isEmpty else { return nil }
        return durations.min { a, b in
            let da = abs(a - seconds), db = abs(b - seconds)
            return da == db ? a > b : da < db
        }
    }

    public func makes(_ label: String) -> Bool {
        resolutions.isEmpty || resolutions.contains { $0.caseInsensitiveCompare(label) == .orderedSame }
    }

    public func clampedResolution(_ label: String?) -> String? {
        guard let label, !resolutions.isEmpty else { return nil }
        if let exact = resolutions.first(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) { return exact }
        let wanted = Self.rank(of: label)
        return resolutions.last { Self.rank(of: $0) < wanted } ?? resolutions.first
    }

    public func bestAspectRatio(_ ratio: String?) -> String? {
        guard let ratio, !aspectRatios.isEmpty else { return nil }
        if aspectRatios.contains(ratio) { return ratio }
        guard let wanted = Self.ratioValue(ratio) else { return nil }
        return aspectRatios.min { a, b in
            abs(log((Self.ratioValue(a) ?? 1) / wanted)) < abs(log((Self.ratioValue(b) ?? 1) / wanted))
        }
    }

    public static func rank(of label: String) -> Int {
        let lower = label.lowercased()
        switch lower {
        case "1k": return 1080
        case "2k": return 1440
        case "4k": return 2160
        case "8k": return 4320
        default: return Int(lower.trimmingCharacters(in: CharacterSet(charactersIn: "p"))) ?? 0
        }
    }

    public static func ratioValue(_ ratio: String) -> Double? {
        let parts = ratio.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        return parts[0] / parts[1]
    }
}

enum VideoCapabilities {
    struct Rule {
        let prefix: String
        let kind: VideoModelKind
        let video: Bool
        let audio: Bool
        let images: Int
    }

    static let rules: [Rule] = [
        Rule(prefix: "black-forest-labs/flux-video-edit", kind: .edit, video: true, audio: false, images: 0),
        Rule(prefix: "black-forest-labs/flux-video-upscale", kind: .upscale, video: true, audio: false, images: 0),
        Rule(prefix: "black-forest-labs/flux-3-video", kind: .generate, video: false, audio: false, images: 4),
        Rule(prefix: "runway/aleph", kind: .edit, video: true, audio: false, images: 1),
        Rule(prefix: "heygen/avatar", kind: .avatar, video: false, audio: true, images: 1),
        Rule(prefix: "heygen/heygen-video", kind: .generate, video: true, audio: true, images: 4),
        Rule(prefix: "bytedance/seedance-2", kind: .generate, video: true, audio: true, images: 9),
        Rule(prefix: "alibaba/wan-3", kind: .generate, video: true, audio: true, images: 5),
        Rule(prefix: "minimax/hailuo-3", kind: .generate, video: true, audio: true, images: 5),
        Rule(prefix: "google/gemini-omni", kind: .generate, video: false, audio: false, images: 3),
        Rule(prefix: "google/veo-3.1-lite", kind: .generate, video: false, audio: false, images: 0),
        Rule(prefix: "google/veo", kind: .generate, video: false, audio: false, images: 3),
        Rule(prefix: "kwaivgi/kling-video-o1", kind: .generate, video: false, audio: false, images: 7),
        Rule(prefix: "kwaivgi/kling", kind: .generate, video: false, audio: false, images: 4),
        Rule(prefix: "x-ai/grok-imagine-video", kind: .generate, video: false, audio: false, images: 1),
    ]

    static let providerTags: [(prefix: String, tag: String)] = [
        ("google/veo", "google-vertex"),
        ("bytedance/", "seed"),
        ("kwaivgi/", "atlas-cloud"),
        ("alibaba/wan-2", "atlas-cloud"),
        ("alibaba/", "alibaba"),
        ("black-forest-labs/", "black-forest-labs"),
        ("heygen/", "heygen"),
        ("minimax/", "minimax"),
        ("runway/", "runway"),
        ("x-ai/", "xai"),
    ]

    static let freeReferenceImages: [(prefix: String, count: Int)] = [
        ("minimax/hailuo-3", 5),
        ("heygen/", 2),
    ]

    static func rule(for id: String) -> Rule? {
        let slug = id.lowercased()
        return rules.first { slug.hasPrefix($0.prefix) }
    }

    static func providerTag(for id: String) -> String? {
        let slug = id.lowercased()
        return providerTags.first { slug.hasPrefix($0.prefix) }?.tag
    }

    static func requiredDuration(for id: String, resolution: String?, frames: Int, imageReferences: Int) -> Int? {
        let slug = id.lowercased()
        let resolution = resolution?.lowercased() ?? ""
        if slug.hasPrefix("google/veo"),
           resolution == "1080p" || resolution == "4k" || imageReferences > 0 || (slug.contains("lite") && frames >= 2) {
            return 8
        }
        if slug.hasPrefix("minimax/hailuo-2.3"), resolution == "1080p" { return 6 }
        return nil
    }

    static func freeReferenceImages(for id: String) -> Int {
        let slug = id.lowercased()
        return freeReferenceImages.first { slug.hasPrefix($0.prefix) }?.count ?? 0
    }
}

public enum VideoInput: Sendable, Hashable {
    case image(InputImage)
    case videoURL(String)
    case audioURL(String)
}

public struct VideoRequest: Sendable {
    public var model: VideoModel
    public var prompt: String
    public var duration: Int?
    public var resolution: String?
    public var aspectRatio: String?
    public var firstFrame: InputImage?
    public var lastFrame: InputImage?
    public var references: [VideoInput]
    public var generateAudio: Bool?
    public var seed: Int?
    public var previousJobID: String?
    public var upscaleFactor: Double?
    public var creativity: Int?
    public var providerParameters: [String: JSONValue]

    public init(
        model: VideoModel, prompt: String, duration: Int? = nil, resolution: String? = nil, aspectRatio: String? = nil,
        firstFrame: InputImage? = nil, lastFrame: InputImage? = nil, references: [VideoInput] = [],
        generateAudio: Bool? = nil, seed: Int? = nil, previousJobID: String? = nil,
        upscaleFactor: Double? = nil, creativity: Int? = nil, providerParameters: [String: JSONValue] = [:]
    ) {
        self.model = model
        self.prompt = prompt
        self.duration = duration
        self.resolution = resolution
        self.aspectRatio = aspectRatio
        self.firstFrame = firstFrame
        self.lastFrame = lastFrame
        self.references = references
        self.generateAudio = generateAudio
        self.seed = seed
        self.previousJobID = previousJobID
        self.upscaleFactor = upscaleFactor
        self.creativity = creativity
        self.providerParameters = providerParameters
    }
}

extension VideoRequest {
    public static func defaultUpscalePrompt(creative: Bool) -> String {
        creative
            ? "Upscale and enrich fine detail (skin pores, fabric weave, foliage) consistent with the source; keep identities and motion unchanged."
            : "Upscale faithfully: keep every face, texture, edge and on-screen text exactly as in the source; no new details, no smoothing."
    }
}

public struct VideoJobStatus: Sendable {
    public enum State: String, Sendable {
        case pending
        case inProgress = "in_progress"
        case completed
        case failed
        case cancelled
        case expired

        public var isTerminal: Bool { self != .pending && self != .inProgress }
    }

    public var id: String
    public var state: State
    public var error: String?
    public var cost: Double?
    public var contentURLs: [String]
    public var signedURLs: [String]
    public var expiresAt: Date?

    public init(
        id: String, state: State, error: String? = nil, cost: Double? = nil, contentURLs: [String] = [],
        signedURLs: [String] = [], expiresAt: Date? = nil
    ) {
        self.id = id
        self.state = state
        self.error = error
        self.cost = cost
        self.contentURLs = contentURLs
        self.signedURLs = signedURLs
        self.expiresAt = expiresAt
    }
}

public struct VideoJobGone: LocalizedError, Sendable, Equatable {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public enum JSONValue: Hashable, Sendable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var foundationValue: Any {
        switch self {
        case .string(let value): value
        case .number(let value): value.rounded() == value && abs(value) < 1e15 ? Int(value) as Any : value as Any
        case .bool(let value): value
        case .array(let value): value.map(\.foundationValue)
        case .object(let value): value.mapValues(\.foundationValue)
        case .null: NSNull()
        }
    }

    public var stringValue: String? {
        switch self {
        case .string(let value): value
        case .number(let value): value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
        case .bool(let value): String(value)
        default: nil
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
    public init(nilLiteral: ()) { self = .null }
}
