import Foundation

public struct OpenRouterClient: Sendable {
    public let apiKey: String
    private let base = URL(string: "https://openrouter.ai/api/v1/")!

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    func request(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: path, relativeTo: base)!)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://freefield.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Freefield", forHTTPHeaderField: "X-OpenRouter-Title")
        request.setValue("image-gen", forHTTPHeaderField: "X-OpenRouter-Categories")
        request.httpBody = body
        if method == "POST" { request.timeoutInterval = 600 }
        return request
    }

    @concurrent
    public func accountStatus() async throws -> AccountStatus {
        let data = try await HTTP.send(request("key"), provider: .openRouter)
        let decoded = try JSONDecoder().decode(KeyResponse.self, from: data)
        var status = AccountStatus(label: decoded.data.label, totalUsage: decoded.data.usage)
        if let remaining = decoded.data.limitRemaining {
            status.remainingCredits = remaining
        } else if let credits = try? await credits() {
            status.remainingCredits = credits.total - credits.used
        }
        return status
    }

    private func credits() async throws -> (total: Double, used: Double) {
        let data = try await HTTP.send(request("credits"), provider: .openRouter)
        let decoded = try JSONDecoder().decode(CreditsResponse.self, from: data)
        return (decoded.data.totalCredits, decoded.data.totalUsage)
    }

    @concurrent
    public func imageModels() async throws -> [ImageModel] {
        async let capabilitiesData = HTTP.send(request("images/models"), provider: .openRouter)
        async let catalogData = HTTP.send(request("models?output_modalities=image"), provider: .openRouter)
        let capabilities = try JSONDecoder().decode(ImageModelsResponse.self, from: try await capabilitiesData).data
        let catalog = (try? JSONDecoder().decode(ModelsResponse.self, from: try await catalogData).data) ?? []
        let catalogByID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return capabilities
            .filter { !$0.id.hasPrefix("openrouter/") }
            .map { Self.makeModel($0, catalog: catalogByID[$0.id]) }
    }

    @concurrent
    public func visionTextModels() async throws -> [TextModel] {
        let data = try await HTTP.send(request("models?input_modalities=image&output_modalities=text"), provider: .openRouter)
        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decoded.data
            .filter { !$0.architecture.outputModalities.contains("image") && !$0.id.hasPrefix("openrouter/") }
            .map { TextModel(provider: .openRouter, modelID: $0.id, name: Self.split($0.name).name) }
    }

    static func split(_ fullName: String) -> (vendor: String, name: String) {
        guard let colon = fullName.firstIndex(of: ":") else { return ("", fullName) }
        let vendor = fullName[..<colon].trimmingCharacters(in: .whitespaces)
        let name = fullName[fullName.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return (vendor, name)
    }

    static func makeModel(_ raw: RawImageModel, catalog: RawModel?) -> ImageModel {
        let (vendor, cleanName) = split(catalog?.name ?? raw.name)
        let parameters = raw.supportedParameters ?? [:]
        let ratios = parameters["aspect_ratio"]?.values?.compactMap(AspectRatio.init(rawValue:)) ?? []
        let resolutions = parameters["resolution"]?.values?.compactMap(Resolution.init(rawValue:)) ?? []
        let references = parameters["input_references"]
        let quality = catalog?.benchmarks?.designArena?
            .filter { $0.category == "image" }
            .map(\.elo)
            .max()
        return ImageModel(
            provider: .openRouter,
            modelID: raw.id,
            name: cleanName,
            vendor: vendor.isEmpty ? Self.vendor(fromID: raw.id) : vendor,
            summary: raw.description ?? catalog?.description ?? "",
            endpoint: .openRouterImages,
            aspectRatios: ratios,
            resolutions: resolutions,
            maxImagesPerRequest: parameters["n"]?.max ?? 1,
            minReferences: references?.min ?? 0,
            maxReferences: references?.max ?? 0,
            supportsSeed: parameters["seed"] != nil,
            qualities: parameters["quality"]?.values ?? [],
            supportsTransparency: parameters["background"]?.values?.contains("transparent") ?? false,
            outputsVector: parameters["output_format"]?.values == ["svg"],
            estimatedCostPerImage: catalog.flatMap(estimateCost),
            qualityScore: quality,
            createdAt: (raw.created ?? catalog?.created).map { Date(timeIntervalSince1970: $0) }
        )
    }

    static func vendor(fromID id: String) -> String {
        let slug = id.split(separator: "/").first.map(String.init) ?? id
        return slug.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }

    static func estimateCost(_ raw: RawModel) -> Double? {
        guard let pricing = raw.pricing else { return nil }
        let perToken = Double(pricing.imageOutput ?? pricing.imageToken ?? "") ?? 0
        guard perToken > 0 else { return nil }
        switch raw.architecture.tokenizer {
        case "Gemini": return perToken * 1120
        case "GPT": return perToken * 1500
        default: return perToken * 4096
        }
    }

    @concurrent
    public func generate(_ imageRequest: ImageRequest) async throws -> ImageResponse {
        let model = imageRequest.model
        var body: [String: Any] = [
            "model": model.modelID,
            "prompt": imageRequest.prompt,
        ]
        if let ratio = model.bestAspectRatio(for: imageRequest.aspectRatio) {
            body["aspect_ratio"] = ratio.rawValue
        }
        if let resolution = model.bestResolution(for: imageRequest.resolution) {
            body["resolution"] = resolution.rawValue
        }
        if model.maxImagesPerRequest > 1 {
            body["n"] = min(model.maxImagesPerRequest, max(1, imageRequest.count))
        }
        if let seed = imageRequest.seed, model.supportsSeed { body["seed"] = seed }
        if let quality = imageRequest.quality, model.qualities.contains(quality) { body["quality"] = quality }
        if imageRequest.transparentBackground, model.supportsTransparency {
            body["background"] = "transparent"
            body["output_format"] = "png"
        }
        let references = imageRequest.images.prefix(max(model.maxReferences, 0))
        if !references.isEmpty {
            body["input_references"] = references.map { ["type": "image_url", "image_url": ["url": $0.dataURL]] }
        }

        let data: Data
        do {
            data = try await HTTP.send(request("images", method: "POST", body: try HTTP.jsonBody(body)), provider: .openRouter)
        } catch FreefieldError.http(400, let message) where Self.isUnsupportedSize(message) {
            guard let current = body["resolution"] as? String,
                  let larger = model.resolutions.first(where: { $0.pixels > (Resolution(rawValue: current)?.pixels ?? .max) }) else {
                throw FreefieldError.http(status: 400, message: message)
            }
            body["resolution"] = larger.rawValue
            data = try await HTTP.send(request("images", method: "POST", body: try HTTP.jsonBody(body)), provider: .openRouter)
        }
        let decoded: ImagesResponse
        do {
            decoded = try JSONDecoder().decode(ImagesResponse.self, from: data)
        } catch {
            if let message = HTTP.errorMessage(in: data) { throw FreefieldError.http(status: 200, message: message) }
            throw FreefieldError.decoding(String(describing: error).prefix(200).description)
        }
        var images: [GeneratedImage] = []
        for item in decoded.data ?? [] {
            if let base64 = item.b64JSON, let bytes = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) {
                images.append(GeneratedImage(data: bytes, mimeType: item.mediaType ?? Self.sniffMimeType(bytes)))
            } else if let url = item.url {
                images.append(try await HTTP.imageData(fromURLString: url))
            }
        }
        guard !images.isEmpty else { throw FreefieldError.noImageReturned(modelText: nil) }
        return ImageResponse(images: images, text: nil, cost: decoded.usage?.cost)
    }

    static func isUnsupportedSize(_ message: String) -> Bool {
        let mentionsSize = message.localizedCaseInsensitiveContains("size") || message.localizedCaseInsensitiveContains("resolution")
        let rejected = message.localizedCaseInsensitiveContains("not supported") || message.localizedCaseInsensitiveContains("not valid")
            || message.localizedCaseInsensitiveContains("output pixels") || message.localizedCaseInsensitiveContains("larger resolution")
        return mentionsSize && rejected
    }

        static func sniffMimeType(_ data: Data) -> String {
        let prefix = [UInt8](data.prefix(12))
        if prefix.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if prefix.starts(with: [0xFF, 0xD8]) { return "image/jpeg" }
        if prefix.count >= 12, prefix[8...11] == [0x57, 0x45, 0x42, 0x50] { return "image/webp" }
        if let text = String(data: data.prefix(256), encoding: .utf8), text.contains("<svg") { return "image/svg+xml" }
        return "image/png"
    }

    @concurrent
    public func complete(model: String, system: String, user: String, images: [InputImage] = []) async throws -> TextResponse {
        var content: [[String: Any]] = [["type": "text", "text": user]]
        for image in images {
            content.append(["type": "image_url", "image_url": ["url": image.dataURL]])
        }
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": content],
            ],
            "temperature": 0.7,
        ]
        let data = try await HTTP.send(
            request("chat/completions", method: "POST", body: try HTTP.jsonBody(body)),
            provider: .openRouter
        )
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let text = decoded.choices?.first?.message?.content, !text.isEmpty else {
            throw FreefieldError.decoding(L("empty text response"))
        }
        return TextResponse(text: text.trimmingCharacters(in: .whitespacesAndNewlines), cost: decoded.usage?.cost)
    }
}

public struct TextModel: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(provider.rawValue):\(modelID)" }
    public let provider: Provider
    public let modelID: String
    public let name: String

    public init(provider: Provider, modelID: String, name: String) {
        self.provider = provider
        self.modelID = modelID
        self.name = name
    }
}

struct KeyResponse: Decodable {
    struct Payload: Decodable {
        let label: String?
        let usage: Double?
        let limitRemaining: Double?
        enum CodingKeys: String, CodingKey {
            case label, usage
            case limitRemaining = "limit_remaining"
        }
    }
    let data: Payload
}

struct CreditsResponse: Decodable {
    struct Payload: Decodable {
        let totalCredits: Double
        let totalUsage: Double
        enum CodingKeys: String, CodingKey {
            case totalCredits = "total_credits"
            case totalUsage = "total_usage"
        }
    }
    let data: Payload
}

struct ImageModelsResponse: Decodable {
    let data: [RawImageModel]
}

struct RawImageModel: Decodable {
    struct Parameter: Decodable {
        let type: String?
        let values: [String]?
        let min: Int?
        let max: Int?
    }
    let id: String
    let name: String
    let description: String?
    let created: Double?
    let supportedParameters: [String: Parameter]?

    enum CodingKeys: String, CodingKey {
        case id, name, description, created
        case supportedParameters = "supported_parameters"
    }
}

struct ModelsResponse: Decodable {
    let data: [RawModel]
}

struct RawModel: Decodable {
    struct Architecture: Decodable {
        let inputModalities: [String]
        let outputModalities: [String]
        let tokenizer: String?
        enum CodingKeys: String, CodingKey {
            case inputModalities = "input_modalities"
            case outputModalities = "output_modalities"
            case tokenizer
        }
    }
    struct Pricing: Decodable {
        let imageOutput: String?
        let imageToken: String?
        enum CodingKeys: String, CodingKey {
            case imageOutput = "image_output"
            case imageToken = "image_token"
        }
    }
    struct Benchmarks: Decodable {
        struct Arena: Decodable {
            let category: String?
            let elo: Int
        }
        let designArena: [Arena]?
        enum CodingKeys: String, CodingKey { case designArena = "design_arena" }
    }

    let id: String
    let name: String
    let description: String?
    let created: Double?
    let architecture: Architecture
    let pricing: Pricing?
    let benchmarks: Benchmarks?
}

struct ImagesResponse: Decodable {
    struct Item: Decodable {
        let b64JSON: String?
        let url: String?
        let mediaType: String?
        enum CodingKeys: String, CodingKey {
            case b64JSON = "b64_json"
            case url
            case mediaType = "media_type"
        }
    }
    struct Usage: Decodable { let cost: Double? }
    let data: [Item]?
    let usage: Usage?
}

struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message?
    }
    struct Usage: Decodable { let cost: Double? }
    let choices: [Choice]?
    let usage: Usage?
}
