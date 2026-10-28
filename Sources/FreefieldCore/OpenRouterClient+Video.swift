import Foundation

extension OpenRouterClient {
    func videoURLRequest(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = self.request(path, method: method, body: body)
        request.setValue("video-gen,image-gen", forHTTPHeaderField: "X-OpenRouter-Categories")
        return request
    }

    @concurrent
    public func videoModels() async throws -> [VideoModel] {
        async let listData = HTTP.send(videoURLRequest("videos/models"), provider: .openRouter)
        async let catalogData = HTTP.send(videoURLRequest("models?output_modalities=video"), provider: .openRouter)
        let raw: [RawVideoModel]
        do {
            raw = try JSONDecoder().decode(VideoModelsResponse.self, from: try await listData).data.compactMap(\.value)
        } catch let error as FreefieldError {
            throw Self.videoError(error, during: .models)
        } catch {
            throw FreefieldError.decoding(String(describing: error).prefix(200).description)
        }
        let catalog = (try? JSONDecoder().decode(VideoCatalogResponse.self, from: try await catalogData).data.compactMap(\.value)) ?? []
        let catalogByID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let listed = raw.filter { !$0.id.hasPrefix("openrouter/") }
        let endpoints = await videoEndpoints(for: listed.map(\.id))
        let now = Date()
        return listed
            .map { Self.makeVideoModel($0, catalog: catalogByID[$0.id], endpoint: endpoints[$0.id]) }
            .filter { ($0.expiresAt ?? .distantFuture) > now }
    }

    func videoEndpoints(for ids: [String]) async -> [String: VideoEndpointInfo] {
        await withTaskGroup(of: (String, VideoEndpointInfo?).self) { group in
            for id in ids {
                group.addTask {
                    var request = self.videoURLRequest("models/\(id)/endpoints")
                    request.timeoutInterval = 20
                    guard let data = try? await HTTP.send(request, provider: .openRouter),
                          let decoded = try? JSONDecoder().decode(VideoEndpointsResponse.self, from: data) else {
                        return (id, nil)
                    }
                    return (id, decoded.info)
                }
            }
            var result: [String: VideoEndpointInfo] = [:]
            for await (id, info) in group {
                if let info { result[id] = info }
            }
            return result
        }
    }

    static func makeVideoModel(_ raw: RawVideoModel, catalog: RawVideoCatalogEntry?, endpoint: VideoEndpointInfo?) -> VideoModel {
        let (vendor, cleanName) = split(raw.name ?? catalog?.name ?? raw.id)
        let rule = VideoCapabilities.rule(for: raw.id)
        let modalities = catalog?.inputModalities
        func accepts(_ modality: String, _ known: Bool?) -> Bool {
            guard let modalities else { return known ?? false }
            return (known ?? true) && modalities.contains(modality)
        }
        return VideoModel(
            id: raw.id,
            name: cleanName,
            vendor: vendor.isEmpty ? Self.vendor(fromID: raw.id) : vendor,
            summary: raw.description ?? catalog?.description ?? "",
            durations: raw.durations ?? [],
            resolutions: raw.resolutions ?? [],
            aspectRatios: raw.aspectRatios ?? [],
            frameTypes: raw.frameImages ?? [],
            audio: raw.generateAudio,
            supportsSeed: raw.seed ?? false,
            passthrough: raw.passthrough ?? [],
            pricing: raw.pricing ?? [:],
            sizes: raw.sizes,
            creativity: raw.creativity,
            acceptsVideoInput: accepts("video", rule?.video),
            acceptsAudioInput: accepts("audio", rule?.audio),
            upscaleRange: raw.upscaleRange,
            providerTag: endpoint?.tag,
            discount: endpoint?.discount,
            isBusy: endpoint?.isBusy,
            createdAt: raw.created.map { Date(timeIntervalSince1970: $0) },
            expiresAt: catalog?.expirationDate
        )
    }

    @concurrent
    public func submitVideo(_ videoRequest: VideoRequest) async throws -> String {
        let body = try HTTP.jsonBody(try Self.videoRequestBody(videoRequest))
        let data: Data
        do {
            data = try await HTTP.send(videoURLRequest("videos", method: "POST", body: body), provider: .openRouter)
        } catch {
            throw Self.videoError(error, during: .submit)
        }
        guard let decoded = try? JSONDecoder().decode(VideoJobResponse.self, from: data), let id = decoded.id, !id.isEmpty else {
            if let message = HTTP.errorMessage(in: data) { throw FreefieldError.http(status: 200, message: message) }
            throw FreefieldError.decoding(L("no video job id"))
        }
        return id
    }

    @concurrent
    public func videoStatus(_ id: String) async throws -> VideoJobStatus {
        let data: Data
        do {
            data = try await HTTP.send(videoURLRequest("videos/\(Self.pathComponent(id))"), provider: .openRouter)
        } catch {
            throw Self.videoError(error, during: .status)
        }
        return try Self.videoJobStatus(from: data, id: id)
    }

    public static func videoJobStatus(from data: Data, id: String) throws -> VideoJobStatus {
        let decoded: VideoJobResponse
        do {
            decoded = try JSONDecoder().decode(VideoJobResponse.self, from: data)
        } catch {
            if let message = HTTP.errorMessage(in: data) { throw FreefieldError.http(status: 200, message: message) }
            throw FreefieldError.decoding(String(describing: error).prefix(200).description)
        }
        return VideoJobStatus(
            id: decoded.id ?? id,
            state: decoded.status.flatMap(VideoJobStatus.State.init(rawValue:)) ?? .pending,
            error: decoded.error,
            cost: decoded.usage?.cost,
            contentURLs: decoded.unsignedURLs ?? [],
            signedURLs: decoded.urls ?? [],
            expiresAt: decoded.expiresAt.map { Date(timeIntervalSince1970: $0) }
        )
    }

    @concurrent
    public func downloadVideo(_ id: String, index: Int, to destination: URL) async throws {
        var request = videoURLRequest("videos/\(Self.pathComponent(id))/content?index=\(max(0, index))")
        request.timeoutInterval = 300
        let (temporary, response) = try await HTTP.session.download(for: request)
        let fileManager = FileManager.default
        defer { try? fileManager.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse else {
            throw FreefieldError.decoding(L("no HTTP response"))
        }
        let isJSON = http.value(forHTTPHeaderField: "Content-Type")?.localizedCaseInsensitiveContains("json") ?? false
        guard http.statusCode == 200, !isJSON else {
            let body = (try? Data(contentsOf: temporary)) ?? Data()
            let status = http.statusCode == 200 ? 502 : http.statusCode
            throw Self.videoError(HTTP.error(status: status, body: body.prefix(64_000), provider: .openRouter), during: .download)
        }
        let size = ((try? fileManager.attributesOfItem(atPath: temporary.path))?[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0 else { throw FreefieldError.decoding(L("the downloaded video is empty")) }
        try? fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.moveItem(at: temporary, to: destination)
    }

    static func pathComponent(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_."))) ?? id
    }

    public static func videoRequestBody(_ request: VideoRequest) throws -> [String: Any] {
        let model = request.model
        var body: [String: Any] = ["model": model.id]
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty { body["prompt"] = prompt }
        if let duration = videoDuration(for: request) { body["duration"] = duration }
        if let resolution = model.clampedResolution(request.resolution) { body["resolution"] = resolution }
        if let ratio = model.bestAspectRatio(request.aspectRatio) { body["aspect_ratio"] = ratio }

        var frames: [[String: Any]] = []
        let sendsFirstFrame = request.firstFrame != nil && model.supportsFirstFrame
        if let first = request.firstFrame, sendsFirstFrame {
            frames.append(["type": "image_url", "image_url": ["url": first.dataURL], "frame_type": "first_frame"])
        }
        if let last = request.lastFrame, model.supportsLastFrame {
            guard sendsFirstFrame else {
                throw FreefieldError.unsupported(L("Add a start image: %@ can't use only an end image.", model.name))
            }
            frames.append(["type": "image_url", "image_url": ["url": last.dataURL], "frame_type": "last_frame"])
        }
        if !frames.isEmpty {
            body["frame_images"] = frames
        } else if !request.references.isEmpty {
            let references = try videoReferences(request.references, for: model)
            if !references.isEmpty { body["input_references"] = references }
        }
        if prompt.isEmpty, model.kind != .generate || frames.isEmpty {
            throw FreefieldError.unsupported(L("Describe your video: %@ needs a description.", model.name))
        }

        if let audio = request.generateAudio, model.audio == true { body["generate_audio"] = audio }
        if let seed = request.seed, model.supportsSeed { body["seed"] = seed }
        if let previous = request.previousJobID, !previous.isEmpty { body["previous_job_id"] = previous }
        if let factor = request.upscaleFactor, model.kind == .upscale || model.upscaleRange != nil {
            let range = model.upscaleRange ?? 1.5...3
            body["upscale_factor"] = min(max(factor, range.lowerBound), range.upperBound)
        }
        if let creativity = request.creativity, let levels = model.creativity, !levels.isEmpty {
            body["creativity"] = levels.contains(creativity) ? creativity : levels.min { abs($0 - creativity) < abs($1 - creativity) }
        }
        let parameters = request.providerParameters.filter { model.passthrough.contains($0.key) }
        if !parameters.isEmpty, let tag = model.providerTag ?? VideoCapabilities.providerTag(for: model.id) {
            body["provider"] = ["options": [tag: ["parameters": parameters.mapValues(\.foundationValue)]]]
        }
        return body
    }

    public static func videoDuration(for request: VideoRequest) -> Int? {
        let model = request.model
        guard let chosen = model.clampedDuration(request.duration) else { return nil }
        let frames = sentFrameCount(request)
        let imageReferences = frames > 0 ? 0 : min(request.references.filter { $0.image != nil }.count, model.maxImageReferences)
        let required = VideoCapabilities.requiredDuration(
            for: model.id, resolution: model.clampedResolution(request.resolution), frames: frames, imageReferences: imageReferences
        )
        return required.flatMap { model.durations.contains($0) ? $0 : nil } ?? chosen
    }

    static func sentFrameCount(_ request: VideoRequest) -> Int {
        guard request.firstFrame != nil, request.model.supportsFirstFrame else { return 0 }
        return request.lastFrame != nil && request.model.supportsLastFrame ? 2 : 1
    }

    static func videoReferences(_ inputs: [VideoInput], for model: VideoModel) throws -> [[String: Any]] {
        var references: [[String: Any]] = []
        var images = 0
        for input in inputs {
            switch input {
            case .image(let image):
                guard model.maxImageReferences > 0 else {
                    throw FreefieldError.unsupported(L("%@ doesn't take reference images. Use the image as the first frame or pick another model.", model.name))
                }
                guard images < model.maxImageReferences else { continue }
                images += 1
                references.append(["type": "image_url", "image_url": ["url": image.dataURL]])
            case .videoURL(let url):
                guard model.acceptsVideoInput else {
                    throw FreefieldError.unsupported(L("%@ doesn't take a video as input. Pick a model that edits or references videos.", model.name))
                }
                references.append(["type": "video_url", "video_url": ["url": try httpsURL(url)]])
            case .audioURL(let url):
                guard model.acceptsAudioInput else {
                    throw FreefieldError.unsupported(L("%@ doesn't take an audio track as input. Pick a model that accepts audio.", model.name))
                }
                references.append(["type": "audio_url", "audio_url": ["url": try httpsURL(url)]])
            }
        }
        return references
    }

    static func httpsURL(_ string: String) throws -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), !host.isEmpty else {
            throw FreefieldError.unsupported(httpsOnlyMessage)
        }
        if host == "openrouter.ai" || host.hasSuffix(".openrouter.ai") || url.path.contains("/api/v1/videos/") {
            throw FreefieldError.unsupported(privateLinkMessage)
        }
        return trimmed
    }

    static var httpsOnlyMessage: String {
        L("Video and audio inputs must be HTTPS links. OpenRouter doesn't accept files or data URLs for them.")
    }

    public static var privateLinkMessage: String {
        L("Providers can't open OpenRouter's own video links (they need your key). Leave the link empty so Freefield shares the clip from this Mac, or paste a public link (https).")
    }

    public static var unreachableInputMessage: String {
        L("The provider couldn't download the clip; the temporary link may have closed. Try again to share it from this Mac once more, or paste a public link (https).")
    }

    public static var noContinuationMessage: String {
        L("This model can't continue a clip directly. Continue it from its last frame instead (Extend Video does this).")
    }

    public static func isUnreachableInput(_ text: String) -> Bool {
        let text = text.lowercased()
        if text.contains("resource download failed") { return true }
        let aboutInput = text.contains("video_url") || text.contains("audio_url")
        return aboutInput && (text.contains("download") || text.contains("fetch"))
    }

    public static func videoRequestJSON(_ request: VideoRequest, elidingMedia: Bool = true) throws -> String {
        let body = try videoRequestBody(request)
        let printable = elidingMedia ? (elideMedia(body) as? [String: Any] ?? body) : body
        let data = try JSONSerialization.data(withJSONObject: printable, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    static func elideMedia(_ value: Any) -> Any {
        switch value {
        case let string as String where string.hasPrefix("data:"):
            let header = string.prefix { $0 != "," }
            let bytes = Int64(max(0, string.count - header.count - 1)) * 3 / 4
            return "\(header),… (\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))"
        case let dictionary as [String: Any]:
            return dictionary.mapValues(elideMedia)
        case let array as [Any]:
            return array.map(elideMedia)
        default:
            return value
        }
    }

    enum VideoCallStage {
        case models, submit, status, download
    }

    static func videoError(_ error: any Error, during stage: VideoCallStage) -> any Error {
        guard let error = error as? FreefieldError, case .http(let status, let message) = error else { return error }
        let detail = String(message.prefix(200))
        let lowered = message.lowercased()
        switch status {
        case 400 where lowered.contains("only https") || lowered.contains("invalid reference url"):
            return FreefieldError.unsupported(httpsOnlyMessage)
        case 400 where isUnreachableInput(lowered):
            return FreefieldError.unsupported(unreachableInputMessage)
        case 400 where lowered.contains("does not support previous_job_id"):
            return FreefieldError.unsupported(noContinuationMessage)
        case 403:
            return FreefieldError.limitReached(L("OpenRouter refused the request: the key's spending limit was reached or the key is disabled. Check the key at openrouter.ai/settings/keys. (%@)", detail))
        case 404 where stage == .status, 410 where stage == .status:
            return VideoJobGone(message: L("OpenRouter no longer has this video job. It may have expired."))
        case 404 where stage == .download, 410 where stage == .download:
            return VideoJobGone(message: L("This video can no longer be downloaded from OpenRouter. It may have expired."))
        case 404:
            return FreefieldError.unsupported(L("OpenRouter doesn't offer this video model right now. Refresh the models or pick another one. (%@)", detail))
        case 409 where stage == .download:
            return FreefieldError.http(status: 409, message: L("The video isn't ready to download yet. Try again in a moment."))
        default:
            return error
        }
    }
}

struct LossyVideoElement<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

struct VideoModelsResponse: Decodable {
    let data: [LossyVideoElement<RawVideoModel>]
}

struct RawVideoModel: Decodable {
    let id: String
    let name: String?
    let description: String?
    let created: Double?
    let durations: [Int]?
    let resolutions: [String]?
    let aspectRatios: [String]?
    let sizes: [String]?
    let frameImages: [String]?
    let generateAudio: Bool?
    let seed: Bool?
    let passthrough: [String]?
    let pricing: [String: String]?
    let creativity: [Int]?
    let upscaleRange: ClosedRange<Double>?

    enum CodingKeys: String, CodingKey {
        case id, name, description, created, seed, creativity
        case durations = "supported_durations"
        case resolutions = "supported_resolutions"
        case aspectRatios = "supported_aspect_ratios"
        case sizes = "supported_sizes"
        case frameImages = "supported_frame_images"
        case generateAudio = "generate_audio"
        case passthrough = "allowed_passthrough_parameters"
        case pricing = "pricing_skus"
        case upscaleFactor = "upscale_factor"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func optional<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            (try? container.decodeIfPresent(type, forKey: key)) ?? nil
        }
        id = try container.decode(String.self, forKey: .id)
        name = optional(String.self, .name)
        description = optional(String.self, .description)
        created = optional(Double.self, .created)
        durations = optional([Int].self, .durations) ?? optional([Double].self, .durations)?.map { Int($0.rounded()) }
        resolutions = optional([String].self, .resolutions)
        aspectRatios = optional([String].self, .aspectRatios)
        sizes = optional([String].self, .sizes)
        frameImages = optional([String].self, .frameImages)
        generateAudio = optional(Bool.self, .generateAudio)
        seed = optional(Bool.self, .seed)
        passthrough = optional([String].self, .passthrough)
        pricing = optional([String: JSONValue].self, .pricing)?.compactMapValues(\.stringValue)
        creativity = optional([Int].self, .creativity)
        upscaleRange = switch optional(JSONValue.self, .upscaleFactor) {
        case .object(let bounds):
            if let low = bounds["min"]?.stringValue.flatMap(Double.init), let high = bounds["max"]?.stringValue.flatMap(Double.init), low <= high {
                low...high
            } else {
                nil
            }
        case .number(let value): value...value
        default: nil
        }
    }
}

struct VideoCatalogResponse: Decodable {
    let data: [LossyVideoElement<RawVideoCatalogEntry>]
}

struct RawVideoCatalogEntry: Decodable {
    let id: String
    let name: String?
    let description: String?
    let inputModalities: [String]?
    let expirationDate: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, description, architecture
        case expirationDate = "expiration_date"
    }

    enum ArchitectureKeys: String, CodingKey {
        case inputModalities = "input_modalities"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil
        description = (try? container.decodeIfPresent(String.self, forKey: .description)) ?? nil
        let architecture = try? container.nestedContainer(keyedBy: ArchitectureKeys.self, forKey: .architecture)
        inputModalities = (try? architecture?.decodeIfPresent([String].self, forKey: .inputModalities)) ?? nil
        let expiration = (try? container.decodeIfPresent(String.self, forKey: .expirationDate)) ?? nil
        expirationDate = expiration.flatMap(Self.date)
    }

    static func date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: string)
    }
}

struct VideoEndpointInfo: Sendable {
    let tag: String?
    let discount: Double?
    let isBusy: Bool
}

struct VideoEndpointsResponse: Decodable {
    struct Payload: Decodable {
        let endpoints: [LossyVideoElement<Endpoint>]?
    }

    struct Endpoint: Decodable {
        struct Pricing: Decodable {
            let discount: JSONValue?
        }
        let tag: String?
        let status: Int?
        let pricing: Pricing?
    }

    let data: Payload

    var info: VideoEndpointInfo? {
        let endpoints = (data.endpoints ?? []).compactMap(\.value)
        guard !endpoints.isEmpty else { return nil }
        let healthy = endpoints.filter { ($0.status ?? 0) >= 0 }
        let chosen = healthy.first ?? endpoints[0]
        let discount = chosen.pricing?.discount?.stringValue.flatMap(Double.init)
        return VideoEndpointInfo(tag: chosen.tag, discount: discount.flatMap { $0 > 0 ? $0 : nil }, isBusy: healthy.isEmpty)
    }
}

struct VideoJobResponse: Decodable {
    struct Usage: Decodable {
        let cost: Double?
    }

    let id: String?
    let status: String?
    let error: String?
    let unsignedURLs: [String]?
    let urls: [String]?
    let usage: Usage?
    let expiresAt: Double?

    enum CodingKeys: String, CodingKey {
        case id, status, error, urls, usage
        case unsignedURLs = "unsigned_urls"
        case expiresAt = "expires_at"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? nil
        status = (try? container.decodeIfPresent(String.self, forKey: .status)) ?? nil
        error = switch (try? container.decodeIfPresent(JSONValue.self, forKey: .error)) ?? nil {
        case .string(let message): message
        case .object(let object): object["message"]?.stringValue ?? object["raw"]?.stringValue
        default: nil
        }
        unsignedURLs = (try? container.decodeIfPresent([String].self, forKey: .unsignedURLs)) ?? nil
        urls = (try? container.decodeIfPresent([String].self, forKey: .urls)) ?? nil
        usage = (try? container.decodeIfPresent(Usage.self, forKey: .usage)) ?? nil
        expiresAt = (try? container.decodeIfPresent(Double.self, forKey: .expiresAt)) ?? nil
    }
}
