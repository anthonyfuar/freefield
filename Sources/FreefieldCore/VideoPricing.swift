import CoreGraphics
import Foundation

public enum VideoPricing {
    public static func estimate(
        _ model: VideoModel, seconds: Double, resolution: String?, aspectRatio: String?,
        audio: Bool, hasVideoInput: Bool, imageInputs: Int,
        referenceImages: Int? = nil, videoInputSeconds: Double? = nil,
        sourceSize: CGSize? = nil, upscaleFactor: Double? = nil, creativity: Int? = nil
    ) -> Double? {
        let references = min(max(0, referenceImages ?? imageInputs), max(0, imageInputs))
        return estimate(model, Inputs(
            seconds: seconds, resolution: resolution, aspectRatio: aspectRatio, audio: audio,
            videoInputs: hasVideoInput ? 1 : 0, videoInputSeconds: videoInputSeconds, audioInputs: 0,
            frameImages: max(0, imageInputs) - references, referenceImages: references,
            sourceSize: sourceSize, upscaleFactor: upscaleFactor, creative: (creativity ?? 0) > 0
        ))
    }

    public static func estimate(_ request: VideoRequest, sourceSeconds: Double? = nil, sourceSize: CGSize? = nil) -> Double? {
        let model = request.model
        var sized = request
        if sized.duration == nil, !model.durations.isEmpty {
            sized.duration = model.durations.contains(5) ? 5 : model.durations.first
        }
        guard let seconds = OpenRouterClient.videoDuration(for: sized).map(Double.init) ?? sourceSeconds else {
            return nil
        }
        let frames = OpenRouterClient.sentFrameCount(request)
        let references = frames > 0 ? [] : request.references
        var images = 0, videos = 0, audios = 0
        for reference in references {
            switch reference {
            case .image: images += 1
            case .videoURL: videos += 1
            case .audioURL: audios += 1
            }
        }
        images = min(images, model.maxImageReferences)
        if request.previousJobID != nil { videos += 1 }
        var ratio = request.aspectRatio
        if ratio == nil, let image = request.firstFrame ?? references.lazy.compactMap(\.image).first,
           let size = ImageCoding.pixelSize(of: image.data), size.height > 0 {
            ratio = nearestRatio(size.width / size.height, among: model.aspectRatios.isEmpty ? standardRatios : model.aspectRatios)
        }
        return estimate(model, Inputs(
            seconds: seconds, resolution: request.resolution, aspectRatio: ratio,
            audio: model.makesAudio && (request.generateAudio ?? true),
            videoInputs: videos, videoInputSeconds: sourceSeconds, audioInputs: audios,
            frameImages: frames, referenceImages: images,
            sourceSize: sourceSize, upscaleFactor: request.upscaleFactor, creative: (request.creativity ?? 0) > 0
        ))
    }

    public static func ceiling(for model: VideoModel, seconds: Double = 15) -> Double {
        let length = max(seconds, model.durations.last.map(Double.init) ?? 0)
        let variants = [false, true].filter { !$0 || model.acceptsVideoInput }.compactMap { withVideo in
            estimate(model, Inputs(
                seconds: length, resolution: model.resolutions.last, aspectRatio: nil, audio: model.makesAudio,
                videoInputs: withVideo ? 1 : 0, videoInputSeconds: length, audioInputs: 0, frameImages: 0, referenceImages: 0,
                sourceSize: nil, upscaleFactor: model.upscaleRange?.upperBound, creative: true
            ))
        }
        return variants.max() ?? 1
    }

    public static let geminiOmniPerSecond = 5_792 * 17.50 / 1_000_000

    public static let geminiRates: [String: [String: Double]] = [
        "google/gemini-omni": ["": geminiOmniPerSecond],
        "google/veo-3.1": ["720p": 0.40, "1080p": 0.40, "4k": 0.60],
        "google/veo-3.1-fast": ["720p": 0.10, "1080p": 0.12, "4k": 0.30],
        "google/veo-3.1-lite": ["720p": 0.05, "1080p": 0.08],
    ]

    public static func geminiSKUs(for slug: String) -> [String: String] {
        let family = slug.hasPrefix("google/gemini-omni-") ? "google/gemini-omni" : slug
        let rates = geminiRates[family] ?? [:]
        return Dictionary(uniqueKeysWithValues: rates.map {
            ($0.key.isEmpty ? "duration_seconds" : "duration_seconds_\($0.key)", String($0.value))
        })
    }

    public static func outputSize(for model: VideoModel, resolution: String?, aspectRatio: String?) -> CGSize {
        let size = renderSize(model, resolution: model.clampedResolution(resolution) ?? resolution, aspectRatio: model.bestAspectRatio(aspectRatio) ?? aspectRatio)
        return CGSize(width: size.width, height: size.height)
    }

    struct Inputs {
        var seconds: Double
        var resolution: String?
        var aspectRatio: String?
        var audio: Bool
        var videoInputs: Int
        var videoInputSeconds: Double?
        var audioInputs: Int
        var frameImages: Int
        var referenceImages: Int
        var sourceSize: CGSize?
        var upscaleFactor: Double?
        var creative: Bool
    }

    struct SKU {
        enum Unit {
            case perSecond, perToken, perMegapixelSecond, perImage, perGeneration, minimum
        }

        let key: String
        let unit: Unit
        let usd: Double
        let resolution: String?
        let audio: Bool?
        let videoInput: Bool
        let referenceMode: Bool
        let imageToVideo: Bool?
        let creative: Bool?
        let referencesOnly: Bool

        static let resolutionTokens: Set<String> = ["360p", "480p", "540p", "720p", "768p", "1080p", "1k", "2k", "4k"]

        init?(key: String, value: String) {
            guard let number = Double(value.trimmingCharacters(in: .whitespaces)), number >= 0 else { return nil }
            let name = key.lowercased()
            self.key = key
            usd = name.contains("cents") ? number / 100 : number
            if name.contains("minimum") {
                unit = .minimum
            } else if name.contains("token") {
                unit = .perToken
            } else if name.contains("megapixel") {
                unit = .perMegapixelSecond
            } else if name.contains("second") {
                unit = .perSecond
            } else if name.contains("image") {
                unit = .perImage
            } else if name.contains("generation") || name.contains("per_video") || name == "generate" {
                unit = .perGeneration
            } else {
                return nil
            }
            resolution = name.split(separator: "_").map(String.init).first(where: Self.resolutionTokens.contains)
            audio = name.contains("without_audio") ? false : (name.contains("with_audio") ? true : nil)
            videoInput = name.contains("video_input") || name.contains("continuation")
            referenceMode = name.hasPrefix("reference_") && unit == .perSecond
            imageToVideo = name.hasPrefix("image_to_video") ? true : (name.hasPrefix("text_to_video") ? false : nil)
            creative = name.contains("creative") ? true : (name.contains("precise") ? false : nil)
            referencesOnly = name.hasPrefix("reference") && unit == .perImage
        }

        var qualifiers: Set<String> {
            var set: Set<String> = []
            if let resolution { set.insert("res:\(resolution)") }
            if let audio { set.insert("audio:\(audio)") }
            if videoInput { set.insert("video-input") }
            if referenceMode { set.insert("reference") }
            if let imageToVideo { set.insert("i2v:\(imageToVideo)") }
            if let creative { set.insert("creative:\(creative)") }
            return set
        }

        func applies(to context: Context, checkingResolution: Bool) -> Bool {
            if checkingResolution, let resolution, resolution != context.resolution { return false }
            if let audio, audio != context.audio { return false }
            if let imageToVideo, imageToVideo != context.hasImages { return false }
            if let creative, creative != context.creative { return false }
            return true
        }
    }

    struct Context {
        let resolution: String?
        let audio: Bool
        let videoInput: Bool
        let referenceMode: Bool
        let hasImages: Bool
        let creative: Bool
    }

    static func estimate(_ model: VideoModel, _ inputs: Inputs) -> Double? {
        let skus = model.pricing.compactMap { SKU(key: $0.key, value: $0.value) }
        guard !skus.isEmpty else { return nil }
        let resolution = model.clampedResolution(inputs.resolution) ?? inputs.resolution
        var seconds = model.clampedDuration(Int(inputs.seconds.rounded())).map(Double.init) ?? inputs.seconds
        if !model.durations.isEmpty,
           let required = VideoCapabilities.requiredDuration(
               for: model.id, resolution: resolution, frames: inputs.frameImages, imageReferences: inputs.referenceImages
           ),
           model.durations.contains(required) {
            seconds = Double(required)
        }
        guard seconds > 0 else { return nil }
        let ratio = model.bestAspectRatio(inputs.aspectRatio) ?? inputs.aspectRatio
        let context = Context(
            resolution: resolution?.lowercased(),
            audio: inputs.audio,
            videoInput: inputs.videoInputs > 0,
            referenceMode: inputs.referenceImages > 0 || inputs.videoInputs > 0 || inputs.audioInputs > 0,
            hasImages: inputs.frameImages + inputs.referenceImages > 0,
            creative: inputs.creative
        )

        var total: Double
        if let sku = pick(skus, .perToken, context) {
            let size = renderSize(model, resolution: resolution, aspectRatio: ratio)
            let pixels = Double(size.width * size.height)
            var tokens = pixels * (24 * seconds + 1) / 1024
            if sku.videoInput {
                tokens += pixels * 24 * (inputs.videoInputSeconds ?? seconds) / 1024
            }
            total = sku.usd * tokens
        } else if let sku = pick(skus, .perMegapixelSecond, context) {
            let source = inputs.sourceSize.map { (width: Double($0.width), height: Double($0.height)) }
                ?? renderSize(model, resolution: resolution ?? "720p", aspectRatio: ratio).doubles
            let range = model.upscaleRange ?? 1.5...3
            let factor = min(max(inputs.upscaleFactor ?? 2, range.lowerBound), range.upperBound)
            let megapixels = source.width * factor * source.height * factor / 1_000_000
            total = sku.usd * megapixels * (inputs.videoInputSeconds ?? seconds)
        } else if let sku = pick(skus, .perSecond, context) {
            total = sku.usd * seconds
        } else if let sku = pick(skus, .perGeneration, context) {
            total = sku.usd
        } else {
            return nil
        }

        let imageFees = skus.filter { $0.unit == .perImage }
        if let fee = imageFees.filter({ !$0.referencesOnly }).max(by: { $0.usd < $1.usd }) {
            total += fee.usd * Double(inputs.frameImages + inputs.referenceImages)
        }
        if let fee = imageFees.filter(\.referencesOnly).max(by: { $0.usd < $1.usd }) {
            let free = VideoCapabilities.freeReferenceImages(for: model.id)
            total += fee.usd * Double(max(0, inputs.referenceImages - free))
        }
        if let minimum = skus.filter({ $0.unit == .minimum }).map(\.usd).max() {
            total = max(total, minimum)
        }
        if let discount = model.discount, discount > 0, discount < 1 {
            total *= 1 - discount
        }
        return total
    }

    static func pick(_ skus: [SKU], _ unit: SKU.Unit, _ context: Context) -> SKU? {
        var candidates = skus.filter { $0.unit == unit }
        guard !candidates.isEmpty else { return nil }
        candidates = prefer(candidates, \.videoInput, when: context.videoInput)
        candidates = prefer(candidates, \.referenceMode, when: context.referenceMode)
        var pool = candidates.filter { $0.applies(to: context, checkingResolution: true) }
        if pool.isEmpty { pool = candidates.filter { $0.applies(to: context, checkingResolution: false) } }
        if pool.isEmpty { pool = candidates }
        let mostSpecific = pool.filter { sku in
            let mine = sku.qualifiers
            return !pool.contains { other in
                let theirs = other.qualifiers
                return theirs.count > mine.count && theirs.isSuperset(of: mine)
            }
        }
        return mostSpecific.max { $0.usd < $1.usd }
    }

    static func prefer(_ skus: [SKU], _ flag: KeyPath<SKU, Bool>, when active: Bool) -> [SKU] {
        let flagged = skus.filter { $0[keyPath: flag] }
        if active, !flagged.isEmpty { return flagged }
        let plain = skus.filter { !$0[keyPath: flag] }
        return plain.isEmpty ? skus : plain
    }

    struct PixelSize {
        let width: Int
        let height: Int
        var doubles: (width: Double, height: Double) { (Double(width), Double(height)) }
    }

    static let standardRatios = ["16:9", "4:3", "1:1", "3:4", "9:16", "21:9", "9:21", "3:2", "2:3"]

    static let standardSizes: [String: [String: (Int, Int)]] = [
        "480p": ["16:9": (864, 496), "4:3": (752, 560), "1:1": (640, 640), "3:4": (560, 752), "9:16": (496, 864),
                 "21:9": (992, 432), "9:21": (432, 992)],
        "720p": ["16:9": (1280, 720), "4:3": (1112, 834), "1:1": (960, 960), "3:4": (834, 1112), "9:16": (720, 1280),
                 "21:9": (1470, 630), "9:21": (630, 1470)],
        "1080p": ["16:9": (1920, 1080), "4:3": (1664, 1248), "1:1": (1440, 1440), "3:4": (1248, 1664), "9:16": (1080, 1920),
                  "21:9": (2206, 946), "9:21": (946, 2206)],
        "4k": ["16:9": (3840, 2160), "4:3": (2880, 2160), "1:1": (2160, 2160), "3:4": (2160, 2880), "9:16": (2160, 3840),
               "21:9": (5040, 2160)],
    ]

    static func renderSize(_ model: VideoModel, resolution: String?, aspectRatio: String?) -> PixelSize {
        let label = (resolution ?? model.clampedResolution("720p") ?? "720p").lowercased()
        let ratio = aspectRatio ?? "16:9"
        let standard = standardSize(label, ratio)
        guard let listed = listedSize(model.sizes ?? [], label, ratio) else { return standard }
        return listed.width * listed.height > standard.width * standard.height ? listed : standard
    }

    static func standardSize(_ label: String, _ ratio: String) -> PixelSize {
        let label = label.lowercased()
        if let size = standardSizes[label]?[ratio] { return PixelSize(width: size.0, height: size.1) }
        let shortSide = Double(max(VideoModel.rank(of: label), 360))
        let area = shortSide * shortSide * 16 / 9
        let value = VideoModel.ratioValue(ratio) ?? 16.0 / 9
        func even(_ x: Double) -> Int { Int((x / 2).rounded()) * 2 }
        return PixelSize(width: even((area * value).squareRoot()), height: even((area / value).squareRoot()))
    }

    static func listedSize(_ sizes: [String], _ label: String, _ ratio: String) -> PixelSize? {
        let shortSide = VideoModel.rank(of: label)
        guard let wanted = VideoModel.ratioValue(ratio), shortSide > 0 else { return nil }
        for entry in sizes {
            let parts = entry.lowercased().split(separator: "x").compactMap { Int($0) }
            guard parts.count == 2, parts[0] > 0, parts[1] > 0, min(parts[0], parts[1]) == shortSide else { continue }
            let value = Double(parts[0]) / Double(parts[1])
            if abs(value - wanted) / wanted < 0.04 { return PixelSize(width: parts[0], height: parts[1]) }
        }
        return nil
    }

    static func nearestRatio(_ value: Double, among ratios: [String]) -> String? {
        guard value > 0 else { return nil }
        return ratios.min { a, b in
            abs(log((VideoModel.ratioValue(a) ?? 1) / value)) < abs(log((VideoModel.ratioValue(b) ?? 1) / value))
        }
    }
}

extension VideoInput {
    public var image: InputImage? {
        if case .image(let image) = self { return image }
        return nil
    }
}
