import Foundation

extension GeminiClient {
    public static let omniModelID = "gemini-omni-1.1-flash"
    public static let omniSlug = "google/gemini-omni-1.1-flash"
    static let interactionPrefix = "interactions/"

    @concurrent
    public func videoModels() async throws -> [VideoModel] {
        Self.videoModels(from: try await allModels())
    }

    public static func videoModels(from raw: [RawGeminiModel]) -> [VideoModel] {
        var bySlug: [String: VideoModel] = [:]
        for model in raw.compactMap(makeVideoModel) {
            let isPreview = model.apiModelID.contains("preview")
            if let existing = bySlug[model.id], !existing.apiModelID.contains("preview") || isPreview { continue }
            bySlug[model.id] = model
        }
        let listed = raw.filter { isOmniID($0.id) && !$0.id.lowercased().contains("preview") }
        let omni = listed.isEmpty ? [makeOmniModel(id: omniModelID)] : listed.map { makeOmniModel(id: $0.id, raw: $0) }
        for model in omni where bySlug[model.id] == nil { bySlug[model.id] = model }
        let order = [omniSlug, "google/veo-3.1", "google/veo-3.1-fast", "google/veo-3.1-lite"]
        return bySlug.values.sorted {
            ((order.firstIndex(of: $0.id) ?? 9), $0.id) < ((order.firstIndex(of: $1.id) ?? 9), $1.id)
        }
    }

    public static func isOmniID(_ id: String) -> Bool {
        id.lowercased().hasPrefix("gemini-omni-")
    }

    public static func usesInteractions(_ model: VideoModel) -> Bool {
        model.host == .google && (isOmniID(model.apiModelID) || model.id.lowercased().hasPrefix("google/gemini-omni-"))
    }

    public static func makeOmniModel(id: String, raw: RawGeminiModel? = nil) -> VideoModel {
        let slug = "google/\(id.lowercased())"
        return VideoModel(
            id: slug, name: id == omniModelID ? "Gemini Omni Flash" : (raw?.displayName ?? id), vendor: "Google",
            summary: L("Google's video model for AI Studio keys: text or images to video with native sound."),
            durations: Array(3...10), resolutions: ["720p", "1080p", "4K"], aspectRatios: ["16:9", "9:16"],
            frameTypes: ["first_frame", "last_frame"], audio: false, supportsSeed: false, passthrough: [],
            pricing: VideoPricing.geminiSKUs(for: slug), kind: .generate,
            acceptsVideoInput: false, acceptsAudioInput: false, maxImageReferences: 3,
            provider: .google, providerModelID: id
        )
    }

    public static func videoSlug(forGeminiID id: String) -> String? {
        let id = id.lowercased()
        guard id.hasPrefix("veo-3.1") else { return nil }
        if id.contains("lite") { return "google/veo-3.1-lite" }
        if id.contains("fast") { return "google/veo-3.1-fast" }
        return "google/veo-3.1"
    }

    static func makeVideoModel(_ raw: RawGeminiModel) -> VideoModel? {
        guard let slug = videoSlug(forGeminiID: raw.id),
              (raw.supportedGenerationMethods ?? []).contains("predictLongRunning") else { return nil }
        let isLite = slug.hasSuffix("-lite")
        let name = switch slug {
        case "google/veo-3.1-lite": "Veo 3.1 Lite"
        case "google/veo-3.1-fast": "Veo 3.1 Fast"
        default: "Veo 3.1"
        }
        return VideoModel(
            id: slug, name: name, vendor: "Google", summary: raw.description ?? "",
            durations: [4, 6, 8], resolutions: isLite ? ["720p", "1080p"] : ["720p", "1080p", "4K"],
            aspectRatios: ["16:9", "9:16"], frameTypes: ["first_frame", "last_frame"],
            audio: true, supportsSeed: false, passthrough: ["personGeneration", "negativePrompt"],
            pricing: VideoPricing.geminiSKUs(for: slug), kind: .generate,
            acceptsVideoInput: false, acceptsAudioInput: false, maxImageReferences: isLite ? 0 : 3,
            provider: .google, providerModelID: raw.id
        )
    }

    @concurrent
    public func submitVideo(_ videoRequest: VideoRequest) async throws -> String {
        if Self.usesInteractions(videoRequest.model) { return try await submitInteraction(videoRequest) }
        let body = try HTTP.jsonBody(try Self.videoRequestBody(videoRequest))
        let path = "models/\(videoRequest.model.apiModelID):predictLongRunning"
        let data: Data
        do {
            data = try await HTTP.send(request(path, method: "POST", body: body), provider: .google)
        } catch {
            throw Self.videoError(error, during: .submit)
        }
        guard let decoded = try? JSONDecoder().decode(GeminiOperation.self, from: data), let name = decoded.name, !name.isEmpty else {
            if let message = HTTP.errorMessage(in: data) { throw FreefieldError.http(status: 200, message: message) }
            throw FreefieldError.decoding(L("no video job id"))
        }
        return name
    }

    func submitInteraction(_ videoRequest: VideoRequest) async throws -> String {
        var body = try Self.omniRequestBody(videoRequest)
        let data: Data
        do {
            data = try await HTTP.send(request("interactions", method: "POST", body: try HTTP.jsonBody(body)), provider: .google)
        } catch FreefieldError.http(400, let message) where message.localizedCaseInsensitiveContains("background") {
            body["background"] = nil
            do {
                data = try await HTTP.send(request("interactions", method: "POST", body: try HTTP.jsonBody(body)), provider: .google)
            } catch {
                throw Self.videoError(error, during: .submit)
            }
        } catch {
            throw Self.videoError(error, during: .submit)
        }
        return try Self.interactionJobID(from: data)
    }

    public static func interactionJobID(from data: Data) throws -> String {
        guard let decoded = try? JSONDecoder().decode(GeminiInteraction.self, from: data),
              let id = decoded.id, isResourceID(id) else {
            if let message = HTTP.errorMessage(in: data) { throw FreefieldError.http(status: 200, message: message) }
            throw FreefieldError.decoding(L("no video job id"))
        }
        return interactionPrefix + id
    }

    @concurrent
    public func videoStatus(_ operation: String) async throws -> VideoJobStatus {
        if operation.hasPrefix(Self.interactionPrefix) { return try await interactionStatus(operation) }
        guard Self.isOperationName(operation) else {
            throw VideoJobGone(message: L("Google no longer has this video job. It may have expired."))
        }
        let data: Data
        do {
            data = try await HTTP.send(request(operation), provider: .google)
        } catch {
            throw Self.videoError(error, during: .status)
        }
        return try Self.videoJobStatus(from: data, id: operation)
    }

    func interactionStatus(_ jobID: String) async throws -> VideoJobStatus {
        let id = String(jobID.dropFirst(Self.interactionPrefix.count))
        guard Self.isResourceID(id) else {
            throw VideoJobGone(message: L("Google no longer has this video job. It may have expired."))
        }
        var call = request("interactions/\(id)")
        call.timeoutInterval = 300
        let data: Data
        do {
            data = try await HTTP.send(call, provider: .google)
        } catch {
            throw Self.videoError(error, during: .status)
        }
        let result = try Self.interactionResult(from: data, id: jobID)
        guard result.status.state == .completed else { return result.status }
        if let video = result.videoData {
            let file = Self.inlineVideoURL(for: id)
            try video.write(to: file, options: .atomic)
            return VideoJobStatus(id: jobID, state: .completed, contentURLs: [file.absoluteString])
        }
        guard let fileID = result.fileID else { return result.status }
        let fileData: Data
        do {
            fileData = try await HTTP.send(request("files/\(fileID)"), provider: .google)
        } catch {
            throw Self.videoError(error, during: .download)
        }
        return try Self.fileJobStatus(from: fileData, fileID: fileID, id: jobID)
    }

    public static func interactionResult(from data: Data, id: String) throws -> InteractionVideo {
        let interaction: GeminiInteraction
        do {
            interaction = try JSONDecoder().decode(GeminiInteraction.self, from: data)
        } catch {
            if let message = HTTP.errorMessage(in: data) { throw FreefieldError.http(status: 200, message: message) }
            throw FreefieldError.decoding(String(describing: error).prefix(200).description)
        }
        let outputs = (interaction.steps ?? []).filter { $0.type == "model_output" }.flatMap { $0.content ?? [] }
        let video = outputs.first { $0.type == "video" && ($0.data?.isEmpty == false || $0.uri?.isEmpty == false) }
        let problem = (interaction.errors ?? []).compactMap { $0.message?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        func ended(_ state: VideoJobStatus.State, _ message: String?) -> InteractionVideo {
            InteractionVideo(status: VideoJobStatus(id: id, state: state, error: message))
        }
        switch interaction.status ?? (video == nil ? "in_progress" : "completed") {
        case "in_progress":
            return ended(.inProgress, nil)
        case "requires_action":
            return ended(.failed, L("Google paused this video to ask for a step Freefield can't take. Try again, or simplify the description."))
        case "cancelled":
            return ended(.cancelled, problem ?? L("Google cancelled this video."))
        case "failed", "budget_exceeded":
            return ended(.failed, problem ?? L("Google couldn't make this video."))
        default:
            break
        }
        if let video {
            if let encoded = video.data, !encoded.isEmpty {
                guard let bytes = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters), !bytes.isEmpty else {
                    return ended(.failed, L("Google sent a video Freefield couldn't read. Try again."))
                }
                return InteractionVideo(status: VideoJobStatus(id: id, state: .completed), videoData: bytes)
            }
            let uri = video.uri ?? ""
            if let fileID = fileID(fromVideoURI: uri) {
                return InteractionVideo(status: VideoJobStatus(id: id, state: .completed, contentURLs: [downloadLink(fileID)]), fileID: fileID)
            }
            if uri.lowercased().hasPrefix("https://") {
                return InteractionVideo(status: VideoJobStatus(id: id, state: .completed, contentURLs: [uri]))
            }
        }
        if interaction.status == "incomplete" {
            return ended(.failed, problem ?? L("Google stopped before the video was finished. Try again."))
        }
        let said = outputs.filter { $0.type == "text" }.compactMap(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !said.isEmpty {
            return ended(.failed, L("Google finished without a video: %@", String(said.prefix(220))))
        }
        return ended(.failed, problem ?? L("Google finished the job without a video."))
    }

    public static func fileJobStatus(from data: Data, fileID: String, id: String) throws -> VideoJobStatus {
        guard let file = try? JSONDecoder().decode(GeminiFile.self, from: data) else {
            if let message = HTTP.errorMessage(in: data) { throw FreefieldError.http(status: 200, message: message) }
            throw FreefieldError.decoding(L("no HTTP response"))
        }
        switch (file.state ?? file.file?.state ?? "").uppercased() {
        case "PROCESSING":
            return VideoJobStatus(id: id, state: .inProgress)
        case "FAILED":
            let message = (file.error ?? file.file?.error)?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
            return VideoJobStatus(id: id, state: .failed,
                                  error: message?.isEmpty == false ? message : L("Google couldn't prepare the finished video for download."))
        default:
            return VideoJobStatus(id: id, state: .completed, contentURLs: [downloadLink(fileID)])
        }
    }

    public static func fileID(fromVideoURI uri: String) -> String? {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        let tail: Substring
        if let range = trimmed.range(of: "/files/") {
            tail = trimmed[range.upperBound...]
        } else if trimmed.hasPrefix("files/") {
            tail = trimmed.dropFirst(6)
        } else {
            return nil
        }
        let id = String(tail.prefix { !":?/#".contains($0) })
        return isResourceID(id) ? id : nil
    }

    static func downloadLink(_ fileID: String) -> String {
        "https://generativelanguage.googleapis.com/v1beta/files/\(fileID):download?alt=media"
    }

    static func isResourceID(_ id: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return !id.isEmpty && id.count <= 256 && !id.contains("..") && id.unicodeScalars.allSatisfy(allowed.contains)
    }

    static func inlineVideoURL(for id: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Freefield-omni-\(id).mp4")
    }

    static func moveInlineVideo(_ file: URL, to destination: URL) throws {
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        let resolved = file.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.deletingLastPathComponent().path == folder, resolved.lastPathComponent.hasPrefix("Freefield-omni-") else {
            throw FreefieldError.decoding(L("invalid video link"))
        }
        let fileManager = FileManager.default
        let size = ((try? fileManager.attributesOfItem(atPath: resolved.path))?[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0 else { throw FreefieldError.decoding(L("the video Google sent is no longer on this Mac")) }
        try? fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.moveItem(at: resolved, to: destination)
    }

    public static func videoJobStatus(from data: Data, id: String) throws -> VideoJobStatus {
        let operation: GeminiOperation
        do {
            operation = try JSONDecoder().decode(GeminiOperation.self, from: data)
        } catch {
            if let message = HTTP.errorMessage(in: data) { throw FreefieldError.http(status: 200, message: message) }
            throw FreefieldError.decoding(String(describing: error).prefix(200).description)
        }
        guard operation.done == true else {
            return VideoJobStatus(id: operation.name ?? id, state: .inProgress)
        }
        if let error = operation.error {
            let message = error.message?.trimmingCharacters(in: .whitespacesAndNewlines)
            return VideoJobStatus(id: operation.name ?? id, state: .failed, error: message?.isEmpty == false ? message : L("Google couldn't make this video."))
        }
        let result = operation.response?.generateVideoResponse
        let links = (result?.generatedSamples ?? []).compactMap { $0.video?.uri }.filter { !$0.isEmpty }
        guard !links.isEmpty else {
            let reasons = (result?.raiMediaFilteredReasons ?? []).joined(separator: " ")
            let filtered = (result?.raiMediaFilteredCount ?? 0) > 0 || !reasons.isEmpty
            return VideoJobStatus(
                id: operation.name ?? id, state: .failed,
                error: filtered ? "Google's safety filter blocked this video. \(reasons)".trimmingCharacters(in: .whitespaces)
                    : L("Google finished the job without a video.")
            )
        }
        return VideoJobStatus(id: operation.name ?? id, state: .completed, contentURLs: links)
    }

    @concurrent
    public func downloadVideo(from link: String, to destination: URL) async throws {
        if let file = URL(string: link), file.isFileURL {
            try Self.moveInlineVideo(file, to: destination)
            return
        }
        guard let url = URL(string: link), url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else {
            throw FreefieldError.decoding(L("invalid video link"))
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 300
        if host == "googleapis.com" || host.hasSuffix(".googleapis.com") {
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        }
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
            throw Self.videoError(HTTP.error(status: status, body: body.prefix(64_000), provider: .google), during: .download)
        }
        let size = ((try? fileManager.attributesOfItem(atPath: temporary.path))?[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0 else { throw FreefieldError.decoding(L("the downloaded video is empty")) }
        try? fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.moveItem(at: temporary, to: destination)
    }

    static func isOperationName(_ name: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./"))
        return name.contains("operations/") && !name.contains("..") && !name.hasPrefix("/")
            && name.unicodeScalars.allSatisfy(allowed.contains)
    }

    public static func videoRequestBody(_ request: VideoRequest) throws -> [String: Any] {
        if usesInteractions(request.model) { return try omniRequestBody(request) }
        let model = request.model
        var instance: [String: Any] = [:]
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty {
            let quiet = "Quiet natural ambience only, with no music or speech."
            instance["prompt"] = request.generateAudio == false && !prompt.contains("Quiet natural ambience only")
                ? prompt + (prompt.hasSuffix(".") ? " " : ". ") + quiet : prompt
        }
        var parameters: [String: Any] = [:]
        if let duration = OpenRouterClient.videoDuration(for: request) { parameters["durationSeconds"] = duration }
        if let resolution = model.clampedResolution(request.resolution) { parameters["resolution"] = resolution.lowercased() }
        if let ratio = model.bestAspectRatio(request.aspectRatio) {
            parameters["aspectRatio"] = ratio
        } else if let image = request.firstFrame ?? request.references.lazy.compactMap(\.image).first,
                  let size = ImageCoding.pixelSize(of: image.data), size.width > 0, size.height > 0 {
            parameters["aspectRatio"] = size.height > size.width ? "9:16" : "16:9"
        }

        let sendsFirstFrame = request.firstFrame != nil && model.supportsFirstFrame
        if let first = request.firstFrame, sendsFirstFrame { instance["image"] = inline(first) }
        if let last = request.lastFrame, model.supportsLastFrame {
            guard sendsFirstFrame else {
                throw FreefieldError.unsupported(L("Add a start image: %@ can't use only an end image.", model.name))
            }
            instance["lastFrame"] = inline(last)
        }
        var sendsImages = sendsFirstFrame
        if !sendsFirstFrame, !request.references.isEmpty {
            var references: [[String: Any]] = []
            for input in request.references {
                switch input {
                case .image(let image):
                    guard model.maxImageReferences > 0 else {
                        throw FreefieldError.unsupported(L("%@ doesn't take reference images. Use the image as the first frame or pick another model.", model.name))
                    }
                    guard references.count < model.maxImageReferences else { continue }
                    references.append(["image": inline(image), "referenceType": "asset"])
                case .videoURL, .audioURL:
                    throw FreefieldError.unsupported(googleLinkInputMessage(model.name))
                }
            }
            if !references.isEmpty {
                instance["referenceImages"] = references
                sendsImages = true
            }
        }
        if prompt.isEmpty, !sendsFirstFrame {
            throw FreefieldError.unsupported(L("Describe your video: %@ needs a description.", model.name))
        }
        if let previous = request.previousJobID, !previous.isEmpty {
            throw FreefieldError.unsupported(OpenRouterClient.noContinuationMessage)
        }
        if sendsImages {
            parameters["personGeneration"] = "allow_adult"
        }
        if model.passthrough.contains("negativePrompt"),
           let negative = request.providerParameters["negativePrompt"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !negative.isEmpty {
            parameters["negativePrompt"] = negative
        }
        var body: [String: Any] = ["instances": [instance]]
        if !parameters.isEmpty { body["parameters"] = parameters }
        return body
    }

    public static func omniRequestBody(_ request: VideoRequest) throws -> [String: Any] {
        let model = request.model
        if let previous = request.previousJobID, !previous.isEmpty {
            throw FreefieldError.unsupported(OpenRouterClient.noContinuationMessage)
        }
        if request.references.contains(where: { $0.image == nil }) {
            throw FreefieldError.unsupported(googleLinkInputMessage(model.name))
        }
        let sendsFirstFrame = request.firstFrame != nil && model.supportsFirstFrame
        if request.lastFrame != nil, model.supportsLastFrame, !sendsFirstFrame {
            throw FreefieldError.unsupported(L("Add a start image: %@ can't use only an end image.", model.name))
        }
        var images: [InputImage] = []
        var task: String?
        if let first = request.firstFrame, sendsFirstFrame {
            images.append(first)
            if let last = request.lastFrame, model.supportsLastFrame { images.append(last) }
            task = "image_to_video"
        } else if !request.references.isEmpty {
            guard model.maxImageReferences > 0 else {
                throw FreefieldError.unsupported(L("%@ doesn't take reference images. Use the image as the first frame or pick another model.", model.name))
            }
            images = Array(request.references.compactMap(\.image).prefix(model.maxImageReferences))
            task = "reference_to_video"
        }
        var prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if prompt.isEmpty, !sendsFirstFrame {
            throw FreefieldError.unsupported(L("Describe your video: %@ needs a description.", model.name))
        }
        func adding(_ sentence: String) {
            guard let last = prompt.last else {
                prompt = sentence
                return
            }
            prompt += (".!?".contains(last) ? " " : ". ") + sentence
        }
        if request.generateAudio == false, !prompt.contains("Quiet natural ambience only") {
            adding("Quiet natural ambience only, with no music or speech.")
        }
        if let negative = request.providerParameters["negativePrompt"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !negative.isEmpty {
            adding("Do not include " + negative + (".!?".contains(negative.last ?? ".") ? "" : "."))
        }
        prompt = omniRoles(prompt, task: task, imageCount: images.count)
        var input: [[String: Any]] = images.map { ["type": "image", "data": $0.data.base64EncodedString(), "mime_type": $0.mimeType] }
        if !prompt.isEmpty { input.append(["type": "text", "text": prompt]) }

        var format: [String: Any] = ["type": "video", "delivery": "uri"]
        if let ratio = model.bestAspectRatio(request.aspectRatio) {
            format["aspect_ratio"] = ratio
        } else if let image = images.first, let size = ImageCoding.pixelSize(of: image.data), size.width > 0, size.height > 0 {
            format["aspect_ratio"] = size.height > size.width ? "9:16" : "16:9"
        }
        if let resolution = model.clampedResolution(request.resolution) { format["resolution"] = resolution.lowercased() }
        if let seconds = OpenRouterClient.videoDuration(for: request) ?? model.clampedDuration(5) { format["duration"] = "\(seconds)s" }

        var body: [String: Any] = ["model": model.apiModelID, "input": input, "response_format": format, "background": true]
        if let task { body["generation_config"] = ["video_config": ["task": task]] }
        return body
    }

    static func omniRoles(_ prompt: String, task: String?, imageCount: Int) -> String {
        let body = prompt.isEmpty ? "" : " " + prompt + ((".!?".contains(prompt.last ?? ".")) ? "" : ".")
        switch task {
        case "image_to_video" where imageCount >= 2:
            return "[# Sources <FIRST_FRAME>@Image1 <LAST_FRAME>@Image2]" + body
                + " Use Image1 as the starting frame: the video begins exactly on it and continues from its framing in one unbroken shot, with no fade, dissolve or cut. Use Image2 as the final frame."
        case "image_to_video":
            return "[# Sources <FIRST_FRAME>@Image1]" + body
                + " Use Image1 as the starting frame: the video begins exactly on it and continues from its framing in one unbroken shot, with no fade, dissolve or cut."
        case "reference_to_video" where imageCount > 0:
            let tags = (0..<imageCount).map { "<IMAGE_REF_\($0)>@Image\($0 + 1)" }.joined(separator: " ")
            return "[# References \(tags)]" + body
                + " Use the given image(s) as references for video generation. The images should not be used as literal initial frames."
        default:
            return prompt
        }
    }

    public static func videoRequestJSON(_ request: VideoRequest) throws -> String {
        let printable = elideImages(try videoRequestBody(request))
        let data = try JSONSerialization.data(withJSONObject: printable, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    static func inline(_ image: InputImage) -> [String: Any] {
        ["inlineData": ["mimeType": image.mimeType, "data": image.data.base64EncodedString()]]
    }

    static func elideImages(_ value: Any) -> Any {
        switch value {
        case var dictionary as [String: Any]:
            if let data = dictionary["data"] as? String, dictionary["mimeType"] != nil || dictionary["mime_type"] != nil {
                dictionary["data"] = "… (\(ByteCountFormatter.string(fromByteCount: Int64(data.count * 3 / 4), countStyle: .file)))"
                return dictionary
            }
            return dictionary.mapValues(elideImages)
        case let array as [Any]:
            return array.map(elideImages)
        default:
            return value
        }
    }

    public static func googleLinkInputMessage(_ modelName: String) -> String {
        L("%@ through Google takes images only. Clips and sounds are read from a link, which only OpenRouter's video models do.", modelName)
    }

    enum VideoCallStage {
        case submit, status, download
    }

    static func videoError(_ error: any Error, during stage: VideoCallStage) -> any Error {
        guard let error = error as? FreefieldError else { return error }
        switch error {
        case .rateLimited(let message) where stage == .submit && isFreeTierRefusal(message):
            return FreefieldError.unsupported(paidTierMessage(message))
        case .http(let status, let message):
            let detail = String(message.prefix(200))
            switch status {
            case 403 where stage == .submit:
                return FreefieldError.unsupported(paidTierMessage(message))
            case 400 where stage == .submit && isFreeTierRefusal(message):
                return FreefieldError.unsupported(paidTierMessage(message))
            case 404 where stage == .status, 410 where stage == .status:
                return VideoJobGone(message: L("Google no longer has this video job. It may have expired."))
            case 403 where stage == .download, 404 where stage == .download, 410 where stage == .download:
                return VideoJobGone(message: L("This video can no longer be downloaded from Google. Google keeps finished videos for 2 days."))
            case 404:
                return FreefieldError.unsupported(L("Google doesn't offer this video model to your key right now. Refresh the models or pick another one. (%@)", detail))
            default:
                return error
            }
        default:
            return error
        }
    }

    static func isFreeTierRefusal(_ message: String) -> Bool {
        let text = message.lowercased()
        return ["free_tier", "free tier", "limit: 0", "billing", "paid tier", "paid_tier"].contains { text.contains($0) }
    }

    static func paidTierMessage(_ message: String) -> String {
        L("Google refused the video: video generation needs a Google AI Studio key with billing turned on (the free tier doesn't include video). (%@)", String(message.prefix(160)))
    }
}

struct GeminiOperation: Decodable {
    struct Status: Decodable {
        let code: Int?
        let message: String?
    }

    struct Response: Decodable {
        let generateVideoResponse: VideoResult?
    }

    struct VideoResult: Decodable {
        struct Sample: Decodable {
            struct Video: Decodable {
                let uri: String?
            }
            let video: Video?
        }
        let generatedSamples: [Sample]?
        let raiMediaFilteredCount: Int?
        let raiMediaFilteredReasons: [String]?
    }

    let name: String?
    let done: Bool?
    let error: Status?
    let response: Response?
}

public struct InteractionVideo: Sendable {
    public var status: VideoJobStatus
    public var videoData: Data?
    public var fileID: String?

    public init(status: VideoJobStatus, videoData: Data? = nil, fileID: String? = nil) {
        self.status = status
        self.videoData = videoData
        self.fileID = fileID
    }
}

struct GeminiInteraction: Decodable {
    struct Content: Decodable {
        let type: String?
        let text: String?
        let data: String?
        let uri: String?

        enum CodingKeys: String, CodingKey {
            case type, text, data, uri
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? nil
            text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? nil
            data = (try? container.decodeIfPresent(String.self, forKey: .data)) ?? nil
            uri = (try? container.decodeIfPresent(String.self, forKey: .uri)) ?? nil
        }
    }

    struct Step: Decodable {
        let type: String?
        let content: [Content]?

        enum CodingKeys: String, CodingKey {
            case type, content
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? nil
            content = (try? container.decodeIfPresent([Content].self, forKey: .content)) ?? nil
        }
    }

    struct Problem: Decodable {
        let message: String?
    }

    let id: String?
    let status: String?
    let steps: [Step]?
    let errors: [Problem]?
}

struct GeminiFile: Decodable {
    struct Inner: Decodable {
        let state: String?
        let error: GeminiOperation.Status?
    }

    let state: String?
    let error: GeminiOperation.Status?
    let file: Inner?
}
