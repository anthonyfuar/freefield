import Foundation

public struct GeminiClient: Sendable {
    public let apiKey: String
    let base = URL(string: "https://generativelanguage.googleapis.com/v1beta/")!

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    func request(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: path, relativeTo: base)!)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        if method == "POST" { request.timeoutInterval = 600 }
        return request
    }

    @concurrent
    public func accountStatus() async throws -> AccountStatus {
        _ = try await HTTP.send(request("models?pageSize=1"), provider: .google)
        return AccountStatus(label: "Google AI Studio")
    }

    @concurrent
    public func allModels() async throws -> [RawGeminiModel] {
        var models: [RawGeminiModel] = []
        var pageToken: String?
        repeat {
            var path = "models?pageSize=1000"
            if let pageToken { path += "&pageToken=\(pageToken)" }
            let data = try await HTTP.send(request(path), provider: .google)
            let page = try JSONDecoder().decode(GeminiModelList.self, from: data)
            models += page.models ?? []
            pageToken = page.nextPageToken
        } while pageToken?.isEmpty == false
        return models
    }

    @concurrent
    public func imageModels() async throws -> [ImageModel] {
        try await allModels().compactMap(Self.makeModel)
            .sorted { ($0.qualityScore ?? 0, $0.modelID) > ($1.qualityScore ?? 0, $1.modelID) }
    }

    @concurrent
    public func textModels() async throws -> [TextModel] {
        try await allModels()
            .filter {
                let id = $0.id
                return id.hasPrefix("gemini") && !id.contains("image") && !id.contains("tts")
                    && !id.contains("embedding") && !id.contains("live") && !id.contains("audio")
                    && ($0.supportedGenerationMethods ?? []).contains("generateContent")
            }
            .map { TextModel(provider: .google, modelID: $0.id, name: $0.displayName ?? $0.id) }
    }

    static func makeModel(_ raw: RawGeminiModel) -> ImageModel? {
        let id = raw.id
        let methods = raw.supportedGenerationMethods ?? []
        guard id.hasPrefix("gemini"), id.contains("-image") || id.contains("nano-banana"),
              methods.contains("generateContent") else { return nil }

        let wide: [AspectRatio] = [.auto, .square, .portrait2x3, .landscape3x2, .portrait3x4, .landscape4x3,
                                   .portrait4x5, .landscape5x4, .portrait9x16, .landscape16x9, .ultrawide21x9]
        let all: [Resolution] = [.oneK, .twoK, .fourK]
        let (name, resolutions, references, cost, rank): (String, [Resolution], Int, Double, Int) =
            if id.contains("nano-banana-2.1") {
                ("Nano Banana 2.1", all, 14, 0.067, 40)
            } else if id.contains("3-pro-image") {
                ("Nano Banana Pro", all, 14, 0.134, 50)
            } else if id.contains("flash-lite-image") {
                ("Nano Banana 2 Lite", [.oneK], 14, 0.034, 20)
            } else if id.contains("3.1-flash-image") {
                ("Nano Banana 2", all, 14, 0.067, 30)
            } else if id.contains("2.5-flash-image") {
                ("Nano Banana", [], 3, 0.039, 10)
            } else {
                (raw.displayName ?? id, [], 3, 0.04, 5)
            }
        return ImageModel(
            provider: .google, modelID: id, name: name, vendor: "Google",
            summary: raw.description ?? L("Gemini native image model: generates and edits with references."),
            endpoint: .geminiGenerateContent, aspectRatios: wide, resolutions: resolutions,
            maxImagesPerRequest: 1, minReferences: 0, maxReferences: references,
            supportsSeed: true, estimatedCostPerImage: cost,
            qualityScore: rank - (id.contains("preview") ? 1 : 0)
        )
    }

    @concurrent
    public func generate(_ imageRequest: ImageRequest) async throws -> ImageResponse {
        try await generateContent(imageRequest)
    }

    private func generateContent(_ imageRequest: ImageRequest) async throws -> ImageResponse {
        var parts: [[String: Any]] = [["text": imageRequest.prompt]]
        for image in imageRequest.images {
            parts.append(["inlineData": ["mimeType": image.mimeType, "data": image.data.base64EncodedString()]])
        }
        var generationConfig: [String: Any] = ["responseModalities": ["TEXT", "IMAGE"]]
        var imageConfig: [String: Any] = [:]
        if let ratio = imageRequest.model.bestAspectRatio(for: imageRequest.aspectRatio) {
            imageConfig["aspectRatio"] = ratio.rawValue
        }
        if let resolution = imageRequest.model.bestResolution(for: imageRequest.resolution) {
            imageConfig["imageSize"] = resolution.rawValue
        }
        if !imageConfig.isEmpty { generationConfig["imageConfig"] = imageConfig }
        if let seed = imageRequest.seed { generationConfig["seed"] = seed }

        let body: [String: Any] = [
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": generationConfig,
        ]
        let data = try await HTTP.send(
            request("models/\(imageRequest.model.modelID):generateContent", method: "POST", body: try HTTP.jsonBody(body)),
            provider: .google
        )
        let decoded: GenerateContentResponse
        do {
            decoded = try JSONDecoder().decode(GenerateContentResponse.self, from: data)
        } catch {
            throw FreefieldError.decoding(String(describing: error).prefix(200).description)
        }
        if let reason = decoded.promptFeedback?.blockReason {
            throw FreefieldError.unsupported(L("Google blocked the description (%@). Rephrase it and try again.", reason))
        }
        var images: [GeneratedImage] = []
        var texts: [String] = []
        for part in decoded.candidates?.first?.content?.parts ?? [] where part.thought != true {
            if let inline = part.inlineData ?? part.inline_data, let bytes = Data(base64Encoded: inline.data, options: .ignoreUnknownCharacters) {
                images.append(GeneratedImage(data: bytes, mimeType: inline.mimeType ?? "image/png"))
            } else if let text = part.text {
                texts.append(text)
            }
        }
        let text = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !images.isEmpty else {
            if let finish = decoded.candidates?.first?.finishReason, finish != "STOP" {
                throw FreefieldError.unsupported(L("Google stopped the generation (%@). Try another description.", finish))
            }
            throw FreefieldError.noImageReturned(modelText: text)
        }
        return ImageResponse(images: images, text: text.isEmpty ? nil : text, cost: nil)
    }

    @concurrent
    public func complete(model: String, system: String, user: String, images: [InputImage] = []) async throws -> TextResponse {
        var parts: [[String: Any]] = [["text": user]]
        for image in images {
            parts.append(["inlineData": ["mimeType": image.mimeType, "data": image.data.base64EncodedString()]])
        }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": ["temperature": 0.7],
        ]
        let data = try await HTTP.send(
            request("models/\(model):generateContent", method: "POST", body: try HTTP.jsonBody(body)),
            provider: .google
        )
        let decoded = try JSONDecoder().decode(GenerateContentResponse.self, from: data)
        let text = (decoded.candidates?.first?.content?.parts ?? [])
            .filter { $0.thought != true }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw FreefieldError.decoding(L("empty text response")) }
        return TextResponse(text: text, cost: nil)
    }
}

public struct RawGeminiModel: Decodable, Sendable {
    public let name: String
    public let displayName: String?
    public let description: String?
    public let supportedGenerationMethods: [String]?

    public var id: String { name.hasPrefix("models/") ? String(name.dropFirst(7)) : name }
}

struct GeminiModelList: Decodable {
    let models: [RawGeminiModel]?
    let nextPageToken: String?
}

struct GenerateContentResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                struct InlineData: Decodable {
                    let mimeType: String?
                    let data: String
                }
                let text: String?
                let inlineData: InlineData?
                let inline_data: InlineData?
                let thought: Bool?
            }
            let parts: [Part]?
        }
        let content: Content?
        let finishReason: String?
    }
    struct PromptFeedback: Decodable { let blockReason: String? }
    let candidates: [Candidate]?
    let promptFeedback: PromptFeedback?
}
