import Foundation

public struct APIKeys: Sendable, Equatable {
    public var openRouter: String?
    public var google: String?

    public init(openRouter: String? = nil, google: String? = nil) {
        self.openRouter = openRouter?.nilIfBlank
        self.google = google?.nilIfBlank
    }

    public func key(for provider: Provider) -> String? {
        switch provider {
        case .openRouter: openRouter
        case .google: google
        }
    }

    public mutating func set(_ value: String?, for provider: Provider) {
        switch provider {
        case .openRouter: openRouter = value?.nilIfBlank
        case .google: google = value?.nilIfBlank
        }
    }

    public var configuredProviders: [Provider] {
        Provider.allCases.filter { key(for: $0) != nil }
    }
}

public struct ImageService: Sendable {
    public let keys: APIKeys

    public init(keys: APIKeys) {
        self.keys = keys
    }

    private func apiKey(_ provider: Provider) throws -> String {
        guard let key = keys.key(for: provider) else { throw FreefieldError.missingKey(provider) }
        return key
    }

    public func accountStatus(for provider: Provider) async throws -> AccountStatus {
        switch provider {
        case .openRouter: try await OpenRouterClient(apiKey: apiKey(.openRouter)).accountStatus()
        case .google: try await GeminiClient(apiKey: apiKey(.google)).accountStatus()
        }
    }

    public func imageModels(for provider: Provider) async throws -> [ImageModel] {
        switch provider {
        case .openRouter: try await OpenRouterClient(apiKey: apiKey(.openRouter)).imageModels()
        case .google: try await GeminiClient(apiKey: apiKey(.google)).imageModels()
        }
    }

    public func textModels(for provider: Provider) async throws -> [TextModel] {
        switch provider {
        case .openRouter: try await OpenRouterClient(apiKey: apiKey(.openRouter)).visionTextModels()
        case .google: try await GeminiClient(apiKey: apiKey(.google)).textModels()
        }
    }

    public func generate(
        _ request: ImageRequest,
        count: Int,
        onResult: @escaping @Sendable (Result<ImageResponse, Error>) async -> Void
    ) async {
        let perCall = max(1, request.model.maxImagesPerRequest)
        let calls: [Int] = stride(from: 0, to: count, by: perCall).map { min(perCall, count - $0) }
        await withTaskGroup(of: Void.self) { group in
            for (index, imagesInCall) in calls.enumerated() {
                var call = request
                call.count = imagesInCall
                if let seed = request.seed { call.seed = seed + index }
                let finalCall = call
                group.addTask {
                    do {
                        let response = try await self.generateOnce(finalCall)
                        await onResult(.success(response))
                    } catch {
                        await onResult(.failure(error))
                    }
                }
            }
        }
    }

    public func generateOnce(_ request: ImageRequest) async throws -> ImageResponse {
        do {
            return try await callProvider(request)
        } catch let error as FreefieldError where error.isTransient {
            try await Task.sleep(for: .seconds(2.5))
            return try await callProvider(request)
        }
    }

    private func callProvider(_ request: ImageRequest) async throws -> ImageResponse {
        try Task.checkCancellation()
        switch request.model.provider {
        case .openRouter: return try await OpenRouterClient(apiKey: apiKey(.openRouter)).generate(request)
        case .google: return try await GeminiClient(apiKey: apiKey(.google)).generate(request)
        }
    }

    public func complete(model: TextModel, system: String, user: String, images: [InputImage] = []) async throws -> TextResponse {
        switch model.provider {
        case .openRouter:
            try await OpenRouterClient(apiKey: apiKey(.openRouter)).complete(model: model.modelID, system: system, user: user, images: images)
        case .google:
            try await GeminiClient(apiKey: apiKey(.google)).complete(model: model.modelID, system: system, user: user, images: images)
        }
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
