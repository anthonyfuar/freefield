import Foundation
import FreefieldCore

struct VideoLineupModel: Identifiable, Hashable {
    let id: String
    let name: String
    let tagline: String
    let strengths: String
    var badge: String?
    var isFeatured = false
    var providers: [Provider] = [.openRouter]
}

enum VideoLineup {
    static let models: [VideoLineupModel] = [
        VideoLineupModel(id: "bytedance/seedance-2.0-fast", name: "Seedance 2.0 Fast",
                         tagline: L("The best quality for the price, with free sound"),
                         strengths: L("Seedance 2.0's look at 60% of its price, with image, video and audio references. Sound costs nothing extra."),
                         badge: L("Best value"), isFeatured: true),
        VideoLineupModel(id: "bytedance/seedance-2.5", name: "Seedance 2.5",
                         tagline: L("ByteDance's flagship: long clips and many references"),
                         strengths: L("Clips up to 30 s, up to 50 references, multilingual sound, and edits or extensions by prompt."),
                         badge: L("Max"), isFeatured: true),
        VideoLineupModel(id: "bytedance/seedance-2.0", name: "Seedance 2.0",
                         tagline: L("The Seedance for 1080p and 4K"),
                         strengths: L("Strong motion and references, and the only Seedance with 1080p and 4K."),
                         isFeatured: true),
        VideoLineupModel(id: "kwaivgi/kling-v3.0-std", name: "Kling 3.0",
                         tagline: L("Reliable people and camera moves"),
                         strengths: L("Start and end frames, native voices, and it works with photos of real people."),
                         isFeatured: true),
        VideoLineupModel(id: "kwaivgi/kling-v3.0-pro", name: "Kling 3.0 Pro",
                         tagline: L("Higher-fidelity Kling for hero shots of people"),
                         strengths: L("Sharper people and detail than Kling 3.0, with start and end frames and sound."),
                         isFeatured: true),
        VideoLineupModel(id: "google/veo-3.1-lite", name: "Veo 3.1 Lite",
                         tagline: L("Talking scenes with dialogue and sound, on a budget"),
                         strengths: L("Native dialogue, sound effects and ambience at the lowest price. Horizontal or vertical."),
                         isFeatured: true),
        VideoLineupModel(id: "google/veo-3.1-fast", name: "Veo 3.1 Fast",
                         tagline: L("Veo quality up to 4K, with sound"),
                         strengths: L("Google's cinematic look with audio at a mid price, up to 4K."),
                         isFeatured: true),
        VideoLineupModel(id: "google/veo-3.1", name: "Veo 3.1",
                         tagline: L("Top cinematic quality and lip sync"),
                         strengths: L("Google's best video model: cinematic quality, dialogue and lip sync."),
                         badge: L("Premium"), isFeatured: true),
        VideoLineupModel(id: omniModelID, name: "Gemini Omni Flash",
                         tagline: L("Google's video model, with sound, on your Google key"),
                         strengths: L("Text or images to video with native sound, start and end frames and up to 3 references. 3 to 10 s, up to 4K."),
                         isFeatured: true, providers: [.google]),
        VideoLineupModel(id: "alibaba/wan-3.0", name: "Wan 3.0",
                         tagline: L("Long clips and several subjects, from 480p"),
                         strengths: L("Up to 30 s, with image, video and audio references, and several subjects kept consistent."),
                         isFeatured: true),
        VideoLineupModel(id: "minimax/hailuo-3", name: "MiniMax H3",
                         tagline: L("2K clips with sharp text and brands"),
                         strengths: L("2K output, edits guided by instructions, clean text and logos, and motion taken from a video."),
                         isFeatured: true),
        VideoLineupModel(id: "x-ai/grok-imagine-video-1.5", name: "Grok Imagine 1.5",
                         tagline: L("Up to 1080p with sound, from 1 to 15 s"),
                         strengths: L("Makes its own sound and takes any length from 1 to 15 seconds."),
                         isFeatured: true),
        VideoLineupModel(id: "black-forest-labs/flux-3-video", name: "FLUX.3 Video",
                         tagline: L("Up to 4K and 20 s, with opening and closing frames"),
                         strengths: L("4K, clips up to 20 s, start and end keyframes, and native continuation."),
                         isFeatured: true),
        VideoLineupModel(id: "black-forest-labs/flux-video-edit", name: "FLUX Video Edit",
                         tagline: L("Change a clip by describing it"),
                         strengths: L("Keeps the clip's length, framing and sound. Takes clips up to 15 s."),
                         isFeatured: true),
        VideoLineupModel(id: "black-forest-labs/flux-video-upscale", name: "FLUX Video Upscale",
                         tagline: L("Sharper, larger clips"),
                         strengths: L("Doubles a clip's resolution, precisely or creatively."),
                         isFeatured: true),
        VideoLineupModel(id: "runway/aleph-2", name: "Runway Aleph 2",
                         tagline: L("Add, remove or replace anything in a clip"),
                         strengths: L("Swaps people, outfits and backgrounds, relights, restyles and widens the frame. The result keeps the clip's length."),
                         isFeatured: true),
        VideoLineupModel(id: "heygen/avatar-iv", name: "HeyGen Avatar IV",
                         tagline: L("A photo that talks, with lip sync"),
                         strengths: L("Speaks your script or lip-syncs your audio. The length follows the speech."),
                         isFeatured: true),

        VideoLineupModel(id: "bytedance/seedance-2.0-mini", name: "Seedance 2.0 Mini",
                         tagline: L("The cheapest Seedance, for drafts"),
                         strengths: L("Seedance 2.x quality at the lowest price. Good for drafts."),
                         badge: L("Draft")),
        VideoLineupModel(id: "kwaivgi/kling-video-o1", name: "Kling O1",
                         tagline: L("Kling that follows instructions closely"),
                         strengths: L("Start and end frames, 5 or 10 s."),
                         badge: nil),
        VideoLineupModel(id: "alibaba/wan-3.0-prime", name: "Wan 3.0 Prime",
                         tagline: L("Faster, higher-quality Wan 3.0"),
                         strengths: L("Everything Wan 3.0 does, with better quality and speed."),
                         badge: nil),
        VideoLineupModel(id: "alibaba/wan-2.7", name: "Wan 2.7",
                         tagline: L("A flat price at 1080p"),
                         strengths: L("Start and end frames at 720p or 1080p."),
                         badge: nil),
        VideoLineupModel(id: "alibaba/wan-2.6", name: "Wan 2.6",
                         tagline: L("Cheap text to video and lip sync"),
                         strengths: L("Can lip-sync to an audio track you provide."),
                         badge: nil),
        VideoLineupModel(id: "alibaba/happyhorse-1.1", name: "HappyHorse 1.1",
                         tagline: L("Cheap 1080p in many shapes"),
                         strengths: L("Seven aspect ratios at 720p or 1080p."),
                         badge: nil),
        VideoLineupModel(id: "minimax/hailuo-3-max", name: "MiniMax H3 Max",
                         tagline: L("Cheap start and end frames"),
                         strengths: L("480p or 768p, without sound."),
                         badge: nil),
        VideoLineupModel(id: "minimax/hailuo-2.3", name: "Hailuo 2.3",
                         tagline: L("Expressive motion at 1080p"),
                         strengths: L("6-second horizontal clips at 1080p."),
                         badge: nil),
        VideoLineupModel(id: "x-ai/grok-imagine-video-1.5-lite", name: "Grok Imagine 1.5 Lite",
                         tagline: L("The cheapest model, for quick drafts"),
                         strengths: L("Fast and very cheap. Good for drafts and light effects."),
                         badge: L("Cheapest")),
        VideoLineupModel(id: "x-ai/grok-imagine-video", name: "Grok Imagine Video",
                         tagline: L("Cheap clips from text or images"),
                         strengths: L("Text or image to video at 480p or 720p."),
                         badge: nil),
        VideoLineupModel(id: "runway/gen-4.5", name: "Runway Gen-4.5",
                         tagline: L("Clean, cinematic image to video"),
                         strengths: L("Animates a still with a polished, cinematic look."),
                         badge: nil),
        VideoLineupModel(id: "heygen/heygen-video-1", name: "HeyGen Video 1",
                         tagline: L("Presenter videos with voice and references"),
                         strengths: L("Takes image, video and audio references."),
                         badge: nil),
    ]

    static let hidden: Set<String> = ["bytedance/seedance-1-5-pro", "alibaba/happyhorse-1.0"]

    static let draftModelID = "bytedance/seedance-2.0-mini"
    static let cinemaMaxModelID = "bytedance/seedance-2.5"
    static let talkingSceneModelID = "google/veo-3.1-lite"
    static let omniModelID = GeminiClient.omniSlug
    static let budgetSwapModelID = "alibaba/wan-3.0"
    static let peopleModelID = "kwaivgi/kling-v3.0-std"

    static func entry(_ slug: String) -> VideoLineupModel? { models.first { $0.id == slug } }

    static func displayName(for slug: String, fallback: String) -> String {
        entry(slug)?.name ?? fallback
    }

    static func displayName(forAssetModelID id: String, fallback: String) -> String {
        let slug = id.split(separator: ":", maxSplits: 1).last.map(String.init) ?? id
        return displayName(for: slug, fallback: fallback)
    }

    static func defaultModelIDs(for toolID: String) -> [String] {
        let ids = curatedModelIDs(for: toolID)
        guard let first = ids.first, VideoModelKind.infer(first) == .generate else { return ids }
        return ids + [omniModelID]
    }

    private static func curatedModelIDs(for toolID: String) -> [String] {
        switch toolID {
        case "createVideo":
            ["bytedance/seedance-2.0-fast", "bytedance/seedance-2.0", "bytedance/seedance-2.5", "kwaivgi/kling-v3.0-std", "google/veo-3.1-lite"]
        case "animateImage":
            ["kwaivgi/kling-v3.0-std", "kwaivgi/kling-v3.0-pro", "google/veo-3.1-lite"]
        case "cinemaStudio":
            ["bytedance/seedance-2.0-fast", "bytedance/seedance-2.5", "bytedance/seedance-2.0"]
        case "storyboardVideo":
            ["bytedance/seedance-2.0-fast", "bytedance/seedance-2.0", "kwaivgi/kling-v3.0-std"]
        case "talkingAvatar":
            ["heygen/avatar-iv", "google/veo-3.1-lite", omniModelID]
        case "videoEffects":
            ["bytedance/seedance-2.0-fast", "kwaivgi/kling-v3.0-std", "google/veo-3.1-lite", "x-ai/grok-imagine-video-1.5-lite"]
        case "transitions":
            ["kwaivgi/kling-v3.0-std", "kwaivgi/kling-v3.0-pro", "bytedance/seedance-2.0-fast"]
        case "drawToVideo":
            ["kwaivgi/kling-v3.0-std", "kwaivgi/kling-v3.0-pro"]
        case "editVideo":
            ["black-forest-labs/flux-video-edit", "runway/aleph-2"]
        case "extendVideo":
            ["bytedance/seedance-2.0-fast", "bytedance/seedance-2.0", "kwaivgi/kling-v3.0-std"]
        case "motionTransfer":
            ["alibaba/wan-3.0", "alibaba/wan-3.0-prime", "minimax/hailuo-3"]
        case "swapVideo":
            ["runway/aleph-2", "alibaba/wan-3.0"]
        case "upscaleVideo":
            ["black-forest-labs/flux-video-upscale"]
        case "reframeVideo":
            ["runway/aleph-2"]
        case "videoAd":
            ["bytedance/seedance-2.0-fast", "google/veo-3.1-lite", "kwaivgi/kling-v3.0-std"]
        case "joinClips", "hookCheck", "colorGradeVideo":
            []
        default:
            ["bytedance/seedance-2.0-fast", "kwaivgi/kling-v3.0-std"]
        }
    }

    static func defaultVideoModel(for toolID: String, among available: [VideoModel], avoiding strained: Set<String> = []) -> VideoModel? {
        let preferred = defaultModelIDs(for: toolID)
        guard let primary = preferred.first else { return nil }
        let byID = Dictionary(available.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let healthy: (VideoModel) -> Bool = { $0.isBusy != true && !strained.contains($0.id) }
        let candidates = preferred.compactMap { byID[$0] }
        if let pick = candidates.first(where: healthy) ?? candidates.first { return pick }
        let kind = VideoModelKind.infer(primary)
        guard kind == .generate else { return nil }
        let featured = models.filter(\.isFeatured).compactMap { byID[$0.id] }.filter { $0.kind == kind }
        return featured.first(where: healthy) ?? featured.first
    }
}
