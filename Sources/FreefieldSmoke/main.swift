import CoreGraphics
import Foundation
import FreefieldCore
import UniformTypeIdentifiers

let environment = ProcessInfo.processInfo.environment
let keys = APIKeys(openRouter: environment["FREEFIELD_OPENROUTER_KEY"], google: environment["FREEFIELD_GOOGLE_KEY"])
let arguments = CommandLine.arguments.dropFirst()
let shouldGenerate = arguments.contains("--generate")
let outputDirectory = URL(fileURLWithPath: arguments.first { !$0.hasPrefix("--") } ?? FileManager.default.temporaryDirectory.path)
let service = ImageService(keys: keys)

if let index = arguments.firstIndex(of: "--import-product"), arguments.index(after: index) < arguments.endIndex {
    let link = arguments[arguments.index(after: index)]
    do {
        let product = try await ProductImporter.fetch(link)
        print("title: \(product.title)\nvendor: \(product.vendor ?? "-")\ndescription: \(product.description.prefix(160))\nphotos: \(product.photos.count) · \(product.photos.compactMap { ImageCoding.pixelSize(of: $0) }.map { "\(Int($0.width))×\(Int($0.height))" })")
    } catch {
        print("ERROR: \(error.localizedDescription)")
    }
    exit(0)
}

if arguments.contains("--test-store") {
    let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Freefield")
    let before = CredentialStore.read(.google)
    CredentialStore.save("AIza-dummy-test-1234567890", for: .google)
    let readBack = CredentialStore.read(.google)
    let vault = (try? Data(contentsOf: folder.appendingPathComponent("credentials.vault"))) ?? Data()
    let plaintextVisible = String(decoding: vault, as: UTF8.self).contains("AIza-dummy")
    func permissions(_ name: String) -> String {
        let value = (try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(name).path)[.posixPermissions] as? Int) ?? 0
        return String(value, radix: 8)
    }
    let legacy = FileManager.default.fileExists(atPath: folder.appendingPathComponent("credentials.json").path)
    CredentialStore.save(before, for: .google)
    print("store: protection \(CredentialStore.protection) · wrote+read \(readBack == "AIza-dummy-test-1234567890" ? "OK" : "FAIL") · key visible in vault: \(plaintextVisible) · vault \(permissions("credentials.vault")) · key file \(permissions("credentials.key")) · legacy plaintext left: \(legacy) · restored \(CredentialStore.read(.google) == before ? "OK" : "FAIL")")
    exit(0)
}

if arguments.contains("--omni-check") {
    exit(await omniCheck() ? 0 : 1)
}

if arguments.contains("--video-dry-run") {
    exit(await videoDryRun(apiKey: keys.openRouter ?? "") ? 0 : 1)
}

func sampleImage(width: Int, height: Int) -> InputImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    context.setFillColor(CGColor(red: 0.9, green: 0.55, blue: 0.25, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return InputImage(data: ImageCoding.encode(context.makeImage()!, as: .jpeg, quality: 0.8)!, mimeType: "image/jpeg")
}

func omniCheck() async -> Bool {
    var passed = true
    func expect(_ ok: Bool, _ label: String) {
        passed = passed && ok
        print("\(ok ? "OK  " : "FAIL") \(label)")
    }
    func raw(_ json: String) -> [RawGeminiModel] {
        (try? JSONDecoder().decode([RawGeminiModel].self, from: Data(json.utf8))) ?? []
    }

    print("== Detection")
    let listed = GeminiClient.videoModels(from: raw(#"[{"name":"models/gemini-3-flash","supportedGenerationMethods":["generateContent"]},{"name":"models/gemini-omni-1.1-flash","displayName":"Gemini Omni 1.1 Flash","supportedGenerationMethods":["createInteraction"]}]"#))
    expect(listed.map(\.id) == [GeminiClient.omniSlug] && listed.first?.apiModelID == GeminiClient.omniModelID, "listed Omni id is offered: \(listed.map(\.id))")
    let unlisted = GeminiClient.videoModels(from: raw(#"[{"name":"models/gemini-3-flash","supportedGenerationMethods":["generateContent"]}]"#))
    expect(unlisted.map(\.id) == [GeminiClient.omniSlug], "Omni is still offered when the list leaves it out")
    let previewOnly = GeminiClient.videoModels(from: raw(#"[{"name":"models/gemini-omni-flash-preview"}]"#))
    expect(previewOnly.map(\.apiModelID) == [GeminiClient.omniModelID], "a shut-down preview id is replaced by the GA id: \(previewOnly.map(\.apiModelID))")
    let withVeo = GeminiClient.videoModels(from: raw(#"[{"name":"models/veo-3.1-lite-generate-preview","supportedGenerationMethods":["predictLongRunning"]},{"name":"models/gemini-omni-1.1-flash"}]"#))
    expect(withVeo.map(\.id) == [GeminiClient.omniSlug, "google/veo-3.1-lite"], "a listed Veo id stays on its old path, after Omni: \(withVeo.map(\.id))")
    expect(withVeo.last.map(GeminiClient.usesInteractions) == false, "Veo does not use the Interactions API")

    guard let omni = listed.first else { return false }
    print("\n== Model")
    print("  \(omni.id) · \(omni.name) · \(omni.kind.rawValue) · \(omni.durations.first!)–\(omni.durations.last!) s · \(omni.resolutions) · \(omni.aspectRatios) · frames \(omni.frameTypes) · refs \(omni.maxImageReferences) · sound flag \(omni.audio.map(String.init) ?? "-") · seed \(omni.supportsSeed) · host \(omni.host.rawValue) · pricing \(omni.pricing)")
    expect(omni.durations == Array(3...10) && omni.resolutions == ["720p", "1080p", "4K"] && omni.aspectRatios == ["16:9", "9:16"]
           && omni.supportsFirstFrame && omni.supportsLastFrame && omni.maxImageReferences == 3 && !omni.supportsSeed
           && omni.kind == .generate && omni.host == .google && !omni.acceptsVideoInput && !omni.acceptsAudioInput
           && GeminiClient.usesInteractions(omni), "capabilities")
    let cached = (try? JSONEncoder().encode(omni)).flatMap { try? JSONDecoder().decode(VideoModel.self, from: $0) }
    expect(cached == omni && cached.map(GeminiClient.usesInteractions) == true, "survives the on-disk model cache")
    for (seconds, resolution) in [(8, "720p"), (3, "720p"), (10, "4K")] {
        let cost = VideoPricing.estimate(VideoRequest(model: omni, prompt: "x", duration: seconds, resolution: resolution))
        let expected = Double(seconds) * 5_792 * 17.5 / 1_000_000
        expect(cost.map { abs($0 - expected) < 0.0005 } == true, "estimate \(seconds) s \(resolution): \(cost.map { String(format: "$%.4f", $0) } ?? "none")")
    }

    print("\n== Request bodies")
    let landscape = sampleImage(width: 1280, height: 720)
    let portrait = sampleImage(width: 720, height: 1280)
    func body(_ request: VideoRequest) -> [String: Any]? { try? GeminiClient.videoRequestBody(request) }
    func images(_ body: [String: Any]?) -> Int {
        ((body?["input"] as? [[String: Any]]) ?? []).count { $0["type"] as? String == "image" }
    }
    func text(_ body: [String: Any]?) -> String? {
        ((body?["input"] as? [[String: Any]]) ?? []).last { $0["type"] as? String == "text" }?["text"] as? String
    }
    func format(_ body: [String: Any]?, _ key: String) -> String? { (body?["response_format"] as? [String: Any])?[key] as? String }
    func task(_ body: [String: Any]?) -> String? {
        ((body?["generation_config"] as? [String: Any])?["video_config"] as? [String: Any])?["task"] as? String
    }
    let cases: [(String, VideoRequest)] = [
        ("text only · 8 s · 720p · 16:9", VideoRequest(model: omni, prompt: "A marble rolls down a wooden chain-reaction track.", duration: 8, resolution: "720p", aspectRatio: "16:9")),
        ("first frame · 6 s · 1080p · ratio from the image", VideoRequest(model: omni, prompt: "The woman turns toward the camera and smiles.", duration: 6, resolution: "1080p", firstFrame: portrait)),
        ("first + last frame · 5 s · 4K · 16:9", VideoRequest(model: omni, prompt: "A smooth transition from day to night.", duration: 5, resolution: "4K", aspectRatio: "16:9", firstFrame: landscape, lastFrame: landscape)),
        ("4 references (3 sent) · 10 s · 9:16", VideoRequest(model: omni, prompt: "<IMAGE_REF_0> holds the can from <IMAGE_REF_1>.", duration: 10, resolution: "720p", aspectRatio: "9:16", references: [.image(portrait), .image(landscape), .image(portrait), .image(landscape)])),
    ]
    for (label, request) in cases {
        print("-- \(label)")
        do {
            print(try GeminiClient.videoRequestJSON(request))
        } catch {
            expect(false, "\(label): \(error.localizedDescription)")
        }
    }
    let t2v = body(cases[0].1), first = body(cases[1].1), pair = body(cases[2].1), refs = body(cases[3].1)
    expect(t2v?["model"] as? String == "gemini-omni-1.1-flash" && t2v?["background"] as? Bool == true && images(t2v) == 0 && task(t2v) == nil
           && format(t2v, "type") == "video" && format(t2v, "delivery") == "uri" && format(t2v, "duration") == "8s"
           && format(t2v, "resolution") == "720p" && format(t2v, "aspect_ratio") == "16:9", "text only")
    expect(images(first) == 1 && task(first) == "image_to_video" && format(first, "aspect_ratio") == "9:16" && format(first, "resolution") == "1080p",
           "first frame: one image, image_to_video, portrait ratio read from the image")
    expect(images(pair) == 2 && task(pair) == "image_to_video" && format(pair, "resolution") == "4k" && format(pair, "duration") == "5s",
           "first + last frame: two images in order, 4k lower-case")
    expect(images(refs) == 3 && task(refs) == "reference_to_video" && text(refs)?.contains("<IMAGE_REF_0>") == true, "references: capped at 3, reference_to_video")
    let order = ((pair?["input"] as? [[String: Any]]) ?? []).compactMap { $0["type"] as? String }
    expect(order == ["image", "image", "text"], "images come before the text: \(order)")
    expect(format(body(VideoRequest(model: omni, prompt: "x", duration: 15)), "duration") == "10s"
           && format(body(VideoRequest(model: omni, prompt: "x", duration: 1)), "duration") == "3s"
           && format(body(VideoRequest(model: omni, prompt: "x")), "duration") == "5s", "durations clamp to 3–10 s and default to the estimate's 5 s")
    expect(format(body(VideoRequest(model: omni, prompt: "x", resolution: "2K")), "resolution") == "1080p", "2K asks the next size down")
    expect(text(body(VideoRequest(model: omni, prompt: "Waves roll in", generateAudio: false))) == "Waves roll in. Quiet natural ambience only, with no music or speech.",
           "sound off becomes a prompt line (Omni always makes sound)")
    expect(text(body(VideoRequest(model: omni, prompt: "Waves roll in.", providerParameters: ["negativePrompt": "people, boats"]))) == "Waves roll in. Do not include people, boats.",
           "a negative prompt becomes a Do not sentence")
    let silentStart = body(VideoRequest(model: omni, prompt: " ", firstFrame: landscape))
    expect(silentStart != nil && images(silentStart) == 1 && text(silentStart)?.hasPrefix("[# Sources <FIRST_FRAME>@Image1]") == true,
           "a start image with no description still says it is the starting frame")
    let started = body(VideoRequest(model: omni, prompt: "She waves", firstFrame: landscape))
    expect(text(started) == "[# Sources <FIRST_FRAME>@Image1] She waves. Use Image1 as the starting frame: the video begins exactly on it and continues from its framing in one unbroken shot, with no fade, dissolve or cut.",
           "a start image is declared as the first frame")
    let framed = body(VideoRequest(model: omni, prompt: "Day turns to night", firstFrame: landscape, lastFrame: landscape))
    expect(text(framed)?.hasPrefix("[# Sources <FIRST_FRAME>@Image1 <LAST_FRAME>@Image2]") == true, "start and end images are declared")
    expect(body(VideoRequest(model: omni, prompt: "x", seed: 4))?.description.contains("seed") == false, "no seed is sent")
    for (label, request) in [
        ("video input", VideoRequest(model: omni, prompt: "x", references: [.videoURL("https://example.com/a.mp4")])),
        ("audio input", VideoRequest(model: omni, prompt: "x", references: [.audioURL("https://example.com/a.mp3")])),
        ("continuation", VideoRequest(model: omni, prompt: "x", previousJobID: "interactions/v1_old")),
        ("end image alone", VideoRequest(model: omni, prompt: "x", lastFrame: landscape)),
        ("no description", VideoRequest(model: omni, prompt: "")),
    ] {
        do {
            _ = try GeminiClient.videoRequestBody(request)
            expect(false, "\(label) rejected before sending")
        } catch {
            expect(true, "\(label) rejected before sending → \(error.localizedDescription)")
        }
    }

    print("\n== Parsing")
    let created = #"{"id":"v1_ChdPbW5pLXRlc3QtMTIz","status":"in_progress","object":"interaction","model":"gemini-omni-1.1-flash"}"#
    let jobID = (try? GeminiClient.interactionJobID(from: Data(created.utf8))) ?? ""
    expect(jobID == "interactions/v1_ChdPbW5pLXRlc3QtMTIz", "creation response gives the job id \(jobID)")
    func status(_ json: String) -> InteractionVideo? { try? GeminiClient.interactionResult(from: Data(json.utf8), id: jobID) }
    expect(status(created)?.status.state == .inProgress, "in_progress keeps polling")
    let bytes = Data("....ftypisom fake mp4 bytes".utf8)
    let inline = #"{"steps":[{"type":"user_input","content":[{"type":"image","data":"/9j/4AAQ","mime_type":"image/jpeg"},{"type":"text","text":"..."}]},{"type":"thought","content":[{"text":"...","type":"thought"}]},{"type":"model_output","content":[{"type":"video","mime_type":"video/mp4","data":""# + bytes.base64EncodedString() + #""}]}],"id":"v1_ChdPbW5pLXRlc3QtMTIz","status":"completed","model":"gemini-omni-1.1-flash","object":"interaction"}"#
    let inlineResult = status(inline)
    expect(inlineResult?.status.state == .completed && inlineResult?.videoData == bytes, "completed with inline base64 video (user_input image ignored)")
    let byURI = #"{"steps":[{"type":"user_input","content":[{"type":"text","text":"..."}]},{"type":"thought","content":[{"text":"...","type":"thought"}]},{"type":"model_output","content":[{"type":"video","mime_type":"video/mp4","uri":"https://generativelanguage.googleapis.com/v1beta/files/abc-123xyz:download?alt=media"}]}],"id":"v1_x","status":"completed","model":"gemini-omni-1.1-flash","object":"interaction"}"#
    let uriResult = status(byURI)
    expect(uriResult?.fileID == "abc-123xyz" && uriResult?.status.contentURLs == ["https://generativelanguage.googleapis.com/v1beta/files/abc-123xyz:download?alt=media"],
           "completed with a URI: file \(uriResult?.fileID ?? "-") · \(uriResult?.status.contentURLs.first ?? "-")")
    expect(GeminiClient.fileID(fromVideoURI: "files/abc-123xyz") == "abc-123xyz" && GeminiClient.fileID(fromVideoURI: "https://example.com/video.mp4") == nil,
           "file ids are read after /files/ and before :download")
    let failed = status(#"{"id":"v1_x","status":"failed","errors":[{"code":"quota","message":"Resource exhausted for this project."}]}"#)
    expect(failed?.status.state == .failed && failed?.status.error == "Resource exhausted for this project.", "failed keeps Google's error text")
    let action = status(#"{"id":"v1_x","status":"requires_action","steps":[]}"#)
    expect(action?.status.state == .failed && action?.status.error?.isEmpty == false, "requires_action → \(action?.status.error ?? "-")")
    expect(status(#"{"id":"v1_x","status":"cancelled"}"#)?.status.state == .cancelled, "cancelled")
    let refused = status(#"{"id":"v1_x","status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":"I can't create that video."}]}]}"#)
    expect(refused?.status.state == .failed && refused?.status.error?.contains("I can't create that video.") == true, "a text-only answer → \(refused?.status.error ?? "-")")
    func file(_ json: String) -> VideoJobStatus? { try? GeminiClient.fileJobStatus(from: Data(json.utf8), fileID: "abc-123xyz", id: jobID) }
    expect(file(#"{"name":"files/abc-123xyz","state":"PROCESSING"}"#)?.state == .inProgress, "file PROCESSING keeps polling")
    expect(file(#"{"name":"files/abc-123xyz","state":"ACTIVE"}"#)?.contentURLs.first?.hasSuffix("files/abc-123xyz:download?alt=media") == true, "file ACTIVE → download link")
    expect(file(#"{"name":"files/abc-123xyz","state":"FAILED","error":{"message":"boom"}}"#)?.error == "boom", "file FAILED keeps Google's error text")

    print("\n== Inline video hand-off (local files only)")
    let folder = FileManager.default.temporaryDirectory
    let cachedVideo = folder.appendingPathComponent("Freefield-omni-selfcheck.mp4")
    let destination = folder.appendingPathComponent("Freefield-omni-selfcheck-out/clip.mp4")
    try? bytes.write(to: cachedVideo)
    let client = GeminiClient(apiKey: "")
    do {
        try await client.downloadVideo(from: cachedVideo.absoluteString, to: destination)
        expect((try? Data(contentsOf: destination)) == bytes, "the saved inline video is moved into place")
    } catch {
        expect(false, "inline video hand-off: \(error.localizedDescription)")
    }
    let stray = folder.appendingPathComponent("not-freefield.mp4")
    try? bytes.write(to: stray)
    do {
        try await client.downloadVideo(from: stray.absoluteString, to: destination)
        expect(false, "a file outside Freefield's inline cache is refused")
    } catch {
        expect(true, "a file outside Freefield's inline cache is refused → \(error.localizedDescription)")
    }
    try? FileManager.default.removeItem(at: stray)
    try? FileManager.default.removeItem(at: destination.deletingLastPathComponent())

    print(passed ? "\nOMNI CHECK OK (no network calls)" : "\nOMNI CHECK FAILED")
    return passed
}

func videoDryRun(apiKey: String) async -> Bool {
    let client = OpenRouterClient(apiKey: apiKey)
    let models: [VideoModel]
    do {
        models = try await client.videoModels()
    } catch {
        print("ERROR: \(error.localizedDescription)")
        return false
    }
    print("== \(models.count) video models")
    for model in models {
        let durations = model.durations.isEmpty ? "follows input" : "\(model.durations.first!)–\(model.durations.last!) s"
        let audio = model.makesAudio ? "yes" : "no"
        print("  - \(model.id) · \(model.vendor) · \(model.name) · \(model.kind.rawValue) · \(durations) · \(model.resolutions) · ratios \(model.aspectRatios.count) · frames \(model.frameTypes) · sound \(audio) · seed \(model.supportsSeed) · video-in \(model.acceptsVideoInput) · audio-in \(model.acceptsAudioInput) · refs \(model.maxImageReferences) · tag \(model.providerTag ?? "-")\(model.discount.map { " · -\(Int($0 * 100))%" } ?? "")\(model.isBusy == true ? " · busy" : "")")
    }
    func model(_ id: String) -> VideoModel? {
        let found = models.first { $0.id == id }
        if found == nil { print("MISSING MODEL: \(id)") }
        return found
    }

    let landscape = sampleImage(width: 1280, height: 720)
    let portrait = sampleImage(width: 600, height: 800)
    let sourceVideo = "https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4"
    let script = "Hi! I'm Ana from Freefield. In ten seconds I'll show you how to turn one photo into a talking video."
    var cases: [(title: String, request: VideoRequest, sourceSeconds: Double?, sourceSize: CGSize?)] = []
    if let seedance = model("bytedance/seedance-2.0-fast") {
        cases.append(("T2V · Seedance 2.0 Fast · 5 s · 720p · 16:9 · audio", VideoRequest(
            model: seedance, prompt: "A barista pours latte art in a sunlit café, slow push-in. No on-screen text or subtitles.",
            duration: 5, resolution: "720p", aspectRatio: "16:9", generateAudio: true, seed: 42,
            providerParameters: ["watermark": false, "not_allowed": 1]
        ), nil, nil))
    }
    if let kling = model("kwaivgi/kling-v3.0-std") {
        cases.append(("I2V · Kling 3.0 Std · 5 s · 720p · first frame", VideoRequest(
            model: kling, prompt: "The woman turns toward the camera and smiles; gentle handheld drift.",
            duration: 5, resolution: "720p", firstFrame: landscape, generateAudio: false, seed: 7,
            providerParameters: ["negative_prompt": "morphing, warping, flicker, text, watermark"]
        ), nil, nil))
    }
    if let veo = model("google/veo-3.1-lite") {
        cases.append(("Veo 3.1 Lite · 8 s · 720p · first + last frame (reference dropped)", VideoRequest(
            model: veo, prompt: "The camera glides from the empty street to the lit shop window as night falls.",
            duration: 8, resolution: "720p", aspectRatio: "16:9", firstFrame: landscape, lastFrame: landscape,
            references: [.image(portrait)], generateAudio: true,
            providerParameters: ["personGeneration": "allow_adult"]
        ), nil, nil))
    }
    if let edit = model("black-forest-labs/flux-video-edit") {
        cases.append(("Edit · FLUX Video Edit · 5 s source", VideoRequest(
            model: edit, prompt: "Make it a snowy winter morning; keep objects, motion, camera and timing identical.",
            duration: 5, resolution: "720p", references: [.videoURL(sourceVideo)]
        ), 5, nil))
        let refused: [(label: String, url: String)] = [
            ("data URL video", "data:video/mp4;base64,AAAA"),
            ("OpenRouter content link", "https://openrouter.ai/api/v1/videos/gen-vid-1792602560-cSpGd550ME1EwmWwPjpP/content?index=0"),
        ]
        for item in refused {
            do {
                _ = try OpenRouterClient.videoRequestBody(VideoRequest(model: edit, prompt: "x", references: [.videoURL(item.url)]))
                print("FAIL: a \(item.label) input was accepted")
                return false
            } catch {
                print("OK: \(item.label) rejected before sending → \(error.localizedDescription)")
            }
        }
    }
    if let upscale = model("black-forest-labs/flux-video-upscale") {
        cases.append(("Upscale · FLUX Video Upscale · 2× precise · 5 s of 1280×720", VideoRequest(
            model: upscale, prompt: VideoRequest.defaultUpscalePrompt(creative: false), references: [.videoURL(sourceVideo)],
            upscaleFactor: 2, creativity: 0
        ), 5, CGSize(width: 1280, height: 720)))
    }
    if let avatar = model("heygen/avatar-iv") {
        let words = Double(script.split(separator: " ").count)
        cases.append(("Avatar · HeyGen Avatar IV · photo + script (≈\(Int((words / 2.5).rounded())) s)", VideoRequest(
            model: avatar, prompt: script, resolution: "720p", aspectRatio: "9:16", references: [.image(portrait)],
            providerParameters: ["motion_prompt": "Friendly, natural head movement", "expressiveness": "high", "voice_id": "en_female_1"]
        ), (words / 2.5).rounded(), nil))
    }
    for item in cases {
        print("\n== \(item.title)")
        do {
            print(try OpenRouterClient.videoRequestJSON(item.request))
        } catch {
            print("ERROR: \(error.localizedDescription)")
            return false
        }
        let estimate = VideoPricing.estimate(item.request, sourceSeconds: item.sourceSeconds, sourceSize: item.sourceSize)
        print("estimate: \(estimate.map { String(format: "$%.4f", $0) } ?? "unknown")")
    }

    print("\n== Estimates per model: 5 s (or a 5 s source) at 720p or nearest, 16:9 · silent / with audio / with 1 image ref")
    for model in models {
        func price(audio: Bool, images: Int) -> String {
            let value = VideoPricing.estimate(
                model, seconds: 5, resolution: "720p", aspectRatio: "16:9", audio: audio,
                hasVideoInput: model.kind == .edit || model.kind == .upscale, imageInputs: images,
                sourceSize: CGSize(width: 1280, height: 720)
            )
            return value.map { String(format: "$%.3f", $0) } ?? "?"
        }
        print("  \(model.id): \(price(audio: false, images: 0)) / \(price(audio: true, images: 0)) / \(price(audio: false, images: 1))")
    }

    var passed = true
    print("\n== Parsing")
    let cached = (try? JSONEncoder().encode(models)).flatMap { try? JSONDecoder().decode([VideoModel].self, from: $0) }
    passed = passed && cached == models
    print("\(cached == models ? "OK  " : "FAIL") models round-trip through Codable (for the on-disk cache)")
    let sample = #"{"id":"gen-vid-1792602596-Vbz4wEPOHFm7JjWhONTd","generation_id":"gen-vid-1792602596-Vbz4wEPOHFm7JjWhONTd","polling_url":"https://openrouter.ai/api/v1/videos/gen-vid-1792602596-Vbz4wEPOHFm7JjWhONTd","status":"completed","unsigned_urls":["https://openrouter.ai/api/v1/videos/gen-vid-1792602596-Vbz4wEPOHFm7JjWhONTd/content?index=0"],"usage":{"cost":0.1358,"is_byok":false},"expires_at":1792689097}"#
    if let status = try? OpenRouterClient.videoJobStatus(from: Data(sample.utf8), id: "x"),
       status.state == .completed, status.cost == 0.1358, status.contentURLs.count == 1, status.expiresAt != nil {
        print("OK   job status: \(status.state.rawValue) · cost \(status.cost!) · \(status.contentURLs.count) content URL")
    } else {
        passed = false
        print("FAIL job status sample did not parse")
    }
    let failed = #"{"id":"gen-vid-1","status":"failed","error":"Content flagged by provider"}"#
    if let status = try? OpenRouterClient.videoJobStatus(from: Data(failed.utf8), id: "x"), status.state == .failed,
       status.error == "Content flagged by provider", status.state.isTerminal {
        print("OK   failed job keeps the provider's error text")
    } else {
        passed = false
        print("FAIL failed job sample did not parse")
    }

    print("\n== Builder rules")
    func rule(_ label: String, _ request: VideoRequest, _ key: String, _ expected: String) {
        let body = (try? OpenRouterClient.videoRequestBody(request)) ?? [:]
        let actual = body[key].map { "\($0)" } ?? "omitted"
        let ok = actual == expected
        passed = passed && ok
        print("\(ok ? "OK  " : "FAIL") \(label): \(key) = \(actual)\(ok ? "" : " (expected \(expected))")")
    }
    if let veo = model("google/veo-3.1-lite"), let seedance = model("bytedance/seedance-2.0-fast"),
       let kling = model("kwaivgi/kling-v3.0-std"), let lite = model("x-ai/grok-imagine-video-1.5-lite"),
       let edit = model("black-forest-labs/flux-video-edit") {
        rule("Veo Lite 1080p asks 4 s", VideoRequest(model: veo, prompt: "x", duration: 4, resolution: "1080p"), "duration", "8")
        rule("Veo Lite 5 s snaps to the longer neighbour", VideoRequest(model: veo, prompt: "x", duration: 5, resolution: "720p"), "duration", "6")
        rule("Seedance asks 1080p (next lower)", VideoRequest(model: seedance, prompt: "x", resolution: "1080p"), "resolution", "720p")
        rule("Kling asks 480p (lowest available)", VideoRequest(model: kling, prompt: "x", resolution: "480p"), "resolution", "720p")
        rule("Kling has no seed", VideoRequest(model: kling, prompt: "x", seed: 3), "seed", "omitted")
        rule("Grok has no audio flag", VideoRequest(model: lite, prompt: "x", generateAudio: true), "generate_audio", "omitted")
        rule("Aspect ratio omitted when nil", VideoRequest(model: seedance, prompt: "x", firstFrame: portrait), "aspect_ratio", "omitted")
        rule("Frames win over references", VideoRequest(model: seedance, prompt: "x", firstFrame: portrait, references: [.image(landscape)]), "input_references", "omitted")
        rule("Grok drops a last frame it can't use", VideoRequest(model: lite, prompt: "x", lastFrame: portrait), "frame_images", "omitted")
        rule("Edit models take no duration", VideoRequest(model: edit, prompt: "x", duration: 5, references: [.videoURL(sourceVideo)]), "duration", "omitted")
        rule("Veo Lite takes no reference images: 4 s stays 4 s", VideoRequest(model: veo, prompt: "x", duration: 4, resolution: "720p"), "duration", "4")
        let liteReference = (try? OpenRouterClient.videoRequestBody(VideoRequest(model: veo, prompt: "x", references: [.image(portrait)]))) == nil
        passed = passed && liteReference && veo.maxImageReferences == 0
        print("\(liteReference && veo.maxImageReferences == 0 ? "OK  " : "FAIL") Veo Lite refuses image references (refs \(veo.maxImageReferences))")
        func refuses(_ label: String, _ request: VideoRequest) {
            do {
                _ = try OpenRouterClient.videoRequestBody(request)
                passed = false
                print("FAIL \(label): accepted")
            } catch {
                print("OK   \(label) → \(error.localizedDescription)")
            }
        }
        refuses("Kling end frame without a start frame", VideoRequest(model: kling, prompt: "x", lastFrame: portrait))
        refuses("Edit without a prompt", VideoRequest(model: edit, prompt: " ", references: [.videoURL(sourceVideo)]))
        refuses("Text-to-video without a prompt", VideoRequest(model: seedance, prompt: ""))
        rule("Image-to-video without a prompt is fine", VideoRequest(model: kling, prompt: "", firstFrame: portrait), "model", kling.id)
        let alone = OpenRouterClient.videoDuration(for: VideoRequest(model: veo, prompt: "x", duration: 4, resolution: "720p", lastFrame: portrait))
        passed = passed && alone == 4
        print("\(alone == 4 ? "OK  " : "FAIL") Veo Lite end frame alone isn't counted as first + last: duration = \(alone.map(String.init) ?? "omitted")")
    } else {
        passed = false
    }
    for silent in models where silent.audio == false {
        rule("\(silent.id) makes no sound", VideoRequest(model: silent, prompt: "x", firstFrame: portrait, generateAudio: true), "generate_audio", "omitted")
    }
    if let kling = model("kwaivgi/kling-v3.0-std") {
        rule("Kling makes sound: the switch is sent", VideoRequest(model: kling, prompt: "x", generateAudio: false), "generate_audio", "false")
    }

    print("\n== Calibration against real bills (±10%)")
    func check(_ label: String, _ estimate: Double?, _ real: Double) {
        guard let estimate else {
            print("FAIL \(label): no estimate")
            passed = false
            return
        }
        let ok = abs(estimate - real) / real <= 0.10
        passed = passed && ok
        print("\(ok ? "OK  " : "FAIL") \(label): estimate \(String(format: "%.4f", estimate)) vs real \(real)")
    }
    if let lite = model("x-ai/grok-imagine-video-1.5-lite") {
        check("Grok Imagine 1.5 Lite · 1 s · 480p · 16:9", VideoPricing.estimate(
            lite, seconds: 1, resolution: "480p", aspectRatio: "16:9", audio: false, hasVideoInput: false, imageInputs: 0
        ), 0.02)
    } else {
        passed = false
    }
    if let mini = model("bytedance/seedance-2.0-mini") {
        check("Seedance 2.0 Mini · 4 s · 480p · portrait first frame (560×752)", VideoPricing.estimate(
            mini, seconds: 4, resolution: "480p", aspectRatio: "3:4", audio: false, hasVideoInput: false, imageInputs: 1, referenceImages: 0
        ), 0.1396185)
        check("  same, from the request (ratio read from the frame)", VideoPricing.estimate(VideoRequest(
            model: mini, prompt: "The man smiles and nods slightly.", duration: 4, resolution: "480p",
            firstFrame: portrait, generateAudio: false
        )), 0.1396185)
        check("Seedance 2.0 Mini · 4 s · 480p · 1:1 · 2 image refs (640×640)", VideoPricing.estimate(
            mini, seconds: 4, resolution: "480p", aspectRatio: "1:1", audio: false, hasVideoInput: false, imageInputs: 2
        ), 0.1358)
        check("  same, from the request", VideoPricing.estimate(VideoRequest(
            model: mini, prompt: "@Image 1 raises the can from @Image 2.", duration: 4, resolution: "480p", aspectRatio: "1:1",
            references: [.image(portrait), .image(landscape)], generateAudio: false
        )), 0.1358)
        check("Seedance 2.0 Mini · 4 s · 480p · 16:9 · 5 s video input (864×496)", VideoPricing.estimate(
            mini, seconds: 4, resolution: "480p", aspectRatio: "16:9", audio: false, hasVideoInput: true, imageInputs: 0,
            videoInputSeconds: 5.011
        ), 0.1907094)
        check("  same, from the request", VideoPricing.estimate(VideoRequest(
            model: mini, prompt: "Recreate @Video 1 as a claymation stop-motion scene.", duration: 4, resolution: "480p",
            aspectRatio: "16:9", references: [.videoURL(sourceVideo)], generateAudio: false
        ), sourceSeconds: 5.011), 0.1907094)
        check("Seedance 2.0 Mini · 4 s · 480p · 3:4 · 4 s video input (560×752)", VideoPricing.estimate(
            mini, seconds: 4, resolution: "480p", aspectRatio: "3:4", audio: false, hasVideoInput: true, imageInputs: 0,
            videoInputSeconds: 4
        ), 0.1666791)
        let ceiling = VideoPricing.ceiling(for: mini)
        let ok = ceiling > 0.1907094
        passed = passed && ok
        print("\(ok ? "OK  " : "FAIL") unknown-length stand-in for the limits: \(String(format: "$%.4f", ceiling))")
    } else {
        passed = false
    }
    if let edit = model("black-forest-labs/flux-video-edit") {
        let unknown = VideoPricing.estimate(VideoRequest(model: edit, prompt: "x", references: [.videoURL(sourceVideo)]))
        let ceiling = VideoPricing.ceiling(for: edit)
        let ok = unknown == nil && ceiling > 0
        passed = passed && ok
        print("\(ok ? "OK  " : "FAIL") FLUX Video Edit without a source length: no estimate, limits count \(String(format: "$%.4f", ceiling))")
    } else {
        passed = false
    }
    print(passed ? "\nDRY RUN OK (no paid calls made)" : "\nDRY RUN FAILED")
    return passed
}

for provider in keys.configuredProviders {
    print("== \(provider.displayName)")
    do {
        let status = try await service.accountStatus(for: provider)
        print("  key OK · label: \(status.label ?? "-") · remaining: \(status.remainingCredits.map { String(format: "$%.2f", $0) } ?? "-")")
        let models = try await service.imageModels(for: provider)
        print("  \(models.count) image models")
        for model in models.prefix(80) {
            let cost = model.estimatedCostPerImage.map { String(format: "$%.3f", $0) } ?? "?"
            print("   - \(model.modelID) · \(model.vendor) · \(model.name) · edit:\(model.acceptsImageInput) res:\(model.resolutions.map(\.rawValue)) n:\(model.maxImagesPerRequest) refs:\(model.minReferences)-\(model.maxReferences) ar:\(model.aspectRatios.count) seed:\(model.supportsSeed) ≈\(cost) q:\(model.qualityScore ?? 0)")
        }
        let text = try await service.textModels(for: provider)
        print("  \(text.count) text models (first: \(text.prefix(5).map(\.modelID)))")

        guard shouldGenerate else { continue }
        let preferred = provider == .openRouter ? "google/gemini-2.5-flash-image" : "gemini-2.5-flash-image"
        guard let model = models.first(where: { $0.modelID == preferred }) ?? models.first(where: \.acceptsImageInput) else { continue }
        let request = ImageRequest(model: model, prompt: "A cute ceramic cat figurine on a wooden desk, soft window light, product photo", aspectRatio: .portrait4x5)
        let response = try await service.generateOnce(request)
        let first = response.images[0]
        let url = outputDirectory.appendingPathComponent("smoke-\(provider.rawValue)-gen.\(ImageCoding.fileExtension(forMimeType: first.mimeType))")
        try first.data.write(to: url)
        print("  generated \(response.images.count) image(s) · \(ImageCoding.pixelSize(of: first.data) ?? .zero) · cost \(response.cost ?? -1) → \(url.path)")

        guard let input = ImageCoding.prepareForUpload(first.data, maxPixel: 1024) else { continue }
        let edit = ImageRequest(model: model, prompt: "Edit the image: make the cat figurine bright blue. Keep everything else identical.", images: [input])
        let edited = try await service.generateOnce(edit)
        let editURL = outputDirectory.appendingPathComponent("smoke-\(provider.rawValue)-edit.png")
        try edited.images[0].data.write(to: editURL)
        print("  edited → \(editURL.path) · cost \(edited.cost ?? -1)")
    } catch {
        print("  ERROR: \(error.localizedDescription)")
    }
}
