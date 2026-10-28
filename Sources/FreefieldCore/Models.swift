import Foundation

public enum Provider: String, Codable, CaseIterable, Sendable, Identifiable {
    case openRouter
    case google

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openRouter: "OpenRouter"
        case .google: "Google Gemini"
        }
    }

    public var keyPlaceholder: String {
        switch self {
        case .openRouter: "sk-or-v1-…"
        case .google: "AIza…"
        }
    }

    public var keyURL: URL {
        switch self {
        case .openRouter: URL(string: "https://openrouter.ai/settings/keys")!
        case .google: URL(string: "https://aistudio.google.com/apikey")!
        }
    }
}

public enum AspectRatio: String, Codable, CaseIterable, Sendable, Identifiable {
    case auto
    case square = "1:1"
    case portrait2x3 = "2:3"
    case landscape3x2 = "3:2"
    case portrait3x4 = "3:4"
    case landscape4x3 = "4:3"
    case portrait4x5 = "4:5"
    case landscape5x4 = "5:4"
    case portrait9x16 = "9:16"
    case landscape16x9 = "16:9"
    case ultrawide21x9 = "21:9"

    public var id: String { rawValue }

    public var label: String { self == .auto ? "Auto" : rawValue }

    public var ratio: Double {
        guard self != .auto else { return 1 }
        let parts = rawValue.split(separator: ":").compactMap { Double($0) }
        return parts.count == 2 ? parts[0] / parts[1] : 1
    }

    public var usage: String {
        switch self {
        case .auto: L("The model decides (or follows the input image)")
        case .square: L("Instagram feed, avatar")
        case .portrait2x3: L("Classic portrait, poster")
        case .landscape3x2: L("35 mm photography")
        case .portrait3x4: L("Portrait, Pinterest")
        case .landscape4x3: L("Presentation, digital camera")
        case .portrait4x5: L("Vertical Instagram post")
        case .landscape5x4: L("Print, gallery")
        case .portrait9x16: L("Stories, Reels, TikTok")
        case .landscape16x9: L("YouTube, screen, cinema")
        case .ultrawide21x9: L("Cinematic widescreen")
        }
    }

    public static let standard: [AspectRatio] = allCases
}

public enum Resolution: String, Codable, CaseIterable, Sendable, Identifiable {
    case oneK = "1K"
    case twoK = "2K"
    case fourK = "4K"

    public var id: String { rawValue }

    var pixels: Int {
        switch self {
        case .oneK: 1024
        case .twoK: 2048
        case .fourK: 4096
        }
    }

    public var detail: String {
        switch self {
        case .oneK: L("≈1024 px · fast")
        case .twoK: L("≈2048 px · detail")
        case .fourK: L("≈4096 px · maximum quality")
        }
    }
}

public enum ModelEndpoint: String, Codable, Sendable {
    case openRouterImages
    case geminiGenerateContent
}

public struct ImageModel: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(provider.rawValue):\(modelID)" }

    public let provider: Provider
    public let modelID: String
    public let name: String
    public let vendor: String
    public let summary: String
    public let endpoint: ModelEndpoint
    public let aspectRatios: [AspectRatio]
    public let resolutions: [Resolution]
    public let maxImagesPerRequest: Int
    public let minReferences: Int
    public let maxReferences: Int
    public let supportsSeed: Bool
    public let qualities: [String]
    public let supportsTransparency: Bool
    public let outputsVector: Bool
    public let estimatedCostPerImage: Double?
    public let qualityScore: Int?
    public let createdAt: Date?

    public init(
        provider: Provider, modelID: String, name: String, vendor: String, summary: String,
        endpoint: ModelEndpoint, aspectRatios: [AspectRatio], resolutions: [Resolution],
        maxImagesPerRequest: Int = 1, minReferences: Int = 0, maxReferences: Int = 0,
        supportsSeed: Bool = false, qualities: [String] = [], supportsTransparency: Bool = false,
        outputsVector: Bool = false, estimatedCostPerImage: Double? = nil, qualityScore: Int? = nil,
        createdAt: Date? = nil
    ) {
        self.provider = provider
        self.modelID = modelID
        self.name = name
        self.vendor = vendor
        self.summary = summary
        self.endpoint = endpoint
        self.aspectRatios = aspectRatios
        self.resolutions = resolutions
        self.maxImagesPerRequest = max(1, maxImagesPerRequest)
        self.minReferences = minReferences
        self.maxReferences = maxReferences
        self.supportsSeed = supportsSeed
        self.qualities = qualities
        self.supportsTransparency = supportsTransparency
        self.outputsVector = outputsVector
        self.estimatedCostPerImage = estimatedCostPerImage
        self.qualityScore = qualityScore
        self.createdAt = createdAt
    }

    public var acceptsImageInput: Bool { maxReferences > 0 }
    public var requiresImageInput: Bool { minReferences > 0 }

    public func bestAspectRatio(for desired: AspectRatio) -> AspectRatio? {
        if aspectRatios.contains(desired) { return desired == .auto ? nil : desired }
        if desired == .auto { return nil }
        let candidates = aspectRatios.filter { $0 != .auto }
        return candidates.min { abs(log($0.ratio / desired.ratio)) < abs(log($1.ratio / desired.ratio)) }
    }

    public func bestResolution(for desired: Resolution) -> Resolution? {
        guard !resolutions.isEmpty else { return nil }
        if resolutions.contains(desired) { return desired }
        return resolutions.min { abs($0.pixels - desired.pixels) < abs($1.pixels - desired.pixels) }
    }
}

public struct InputImage: Sendable, Hashable {
    public var data: Data
    public var mimeType: String
    public var role: String?
    public var uploadMaxPixel: Int?

    public init(data: Data, mimeType: String, role: String? = nil) {
        self.data = data
        self.mimeType = mimeType
        self.role = role
    }

    public var dataURL: String { "data:\(mimeType);base64,\(data.base64EncodedString())" }
}

public struct ImageRequest: Sendable {
    public var model: ImageModel
    public var prompt: String
    public var images: [InputImage]
    public var aspectRatio: AspectRatio
    public var resolution: Resolution
    public var seed: Int?
    public var count: Int
    public var quality: String?
    public var transparentBackground: Bool

    public init(
        model: ImageModel, prompt: String, images: [InputImage] = [],
        aspectRatio: AspectRatio = .auto, resolution: Resolution = .oneK, seed: Int? = nil,
        count: Int = 1, quality: String? = nil, transparentBackground: Bool = false
    ) {
        self.model = model
        self.prompt = prompt
        self.images = images
        self.aspectRatio = aspectRatio
        self.resolution = resolution
        self.seed = seed
        self.count = count
        self.quality = quality
        self.transparentBackground = transparentBackground
    }
}

public struct GeneratedImage: Sendable {
    public var data: Data
    public var mimeType: String

    public init(data: Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}

public struct ImageResponse: Sendable {
    public var images: [GeneratedImage]
    public var text: String?
    public var cost: Double?
}

public struct TextResponse: Sendable {
    public var text: String
    public var cost: Double?

    public init(text: String, cost: Double?) {
        self.text = text
        self.cost = cost
    }
}

public struct AccountStatus: Sendable, Equatable {
    public var label: String?
    public var remainingCredits: Double?
    public var totalUsage: Double?

    public init(label: String? = nil, remainingCredits: Double? = nil, totalUsage: Double? = nil) {
        self.label = label
        self.remainingCredits = remainingCredits
        self.totalUsage = totalUsage
    }
}

public enum FreefieldError: LocalizedError, Sendable, Equatable {
    public var isTransient: Bool {
        switch self {
        case .rateLimited: true
        case .http(let status, _): [408, 502, 503, 504, 524, 529].contains(status)
        default: false
        }
    }

    case missingKey(Provider)
    case invalidKey(Provider)
    case http(status: Int, message: String)
    case noImageReturned(modelText: String?)
    case decoding(String)
    case unsupported(String)
    case insufficientCredits(String)
    case rateLimited(String)
    case limitReached(String)

    public var errorDescription: String? {
        switch self {
        case .missingKey(let provider):
            L("The %@ API key is missing. Add it in Settings.", provider.displayName)
        case .invalidKey(let provider):
            L("The %@ API key is not valid.", provider.displayName)
        case .http(let status, let message):
            "Error \(status): \(message)"
        case .noImageReturned(let text):
            if let text, !text.isEmpty {
                L("The model did not return an image. It replied: “%@”", String(text.prefix(300)))
            } else {
                L("The model did not return any image. Try another description or model.")
            }
        case .decoding(let detail):
            L("Unexpected response from the provider (%@).", detail)
        case .unsupported(let detail):
            detail
        case .insufficientCredits(let message):
            L("Not enough credits: %@", message)
        case .limitReached(let message):
            message
        case .rateLimited(let message):
            L("This model is overloaded or out of quota at its provider right now. Try another one (for example Nano Banana 2 or Seedream 4.5). Detail: %@", String(message.prefix(140)))
        }
    }
}
