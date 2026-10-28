import FreefieldCore
import Foundation

struct LineupModel: Identifiable, Hashable {
    let id: String
    let name: String
    let tagline: String
    var badge: String?
    var isFeatured = false
    let ids: [Provider: [String]]

    init(id: String, name: String, tagline: String, badge: String? = nil, isFeatured: Bool = false,
         openRouter: [String] = [], google: [String] = []) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.badge = badge
        self.isFeatured = isFeatured
        ids = [.openRouter: openRouter, .google: google]
    }

    func ids(for provider: Provider) -> [String] { ids[provider] ?? [] }

    func matches(_ model: ImageModel) -> Bool { ids(for: model.provider).contains(model.modelID) }
}

enum Lineup {
    static let models: [LineupModel] = [
        LineupModel(id: "nano-banana-2.1", name: "Nano Banana 2.1", tagline: L("Google's next-generation flagship model"),
                    badge: L("NEW"), isFeatured: true,
                    openRouter: ["google/gemini-nano-banana-2.1"], google: ["gemini-nano-banana-2.1"]),
        LineupModel(id: "nano-banana-pro", name: "Nano Banana Pro", tagline: L("Google's flagship generation model · up to 4K"),
                    isFeatured: true,
                    openRouter: ["google/gemini-3-pro-image", "google/gemini-3-pro-image-preview"],
                    google: ["gemini-3-pro-image", "gemini-3-pro-image-preview"]),
        LineupModel(id: "gpt-image-2.5-sunburst", name: "GPT Image 2.5 Sunburst", tagline: L("Exceptional quality, precise edits"),
                    isFeatured: true, openRouter: ["openai/gpt-image-2.5-sunburst"]),
        LineupModel(id: "gpt-image-2.5-flare", name: "GPT Image 2.5 Flare", tagline: L("Stunning everyday images, fast"),
                    isFeatured: true, openRouter: ["openai/gpt-image-2.5-flare"]),
        LineupModel(id: "seedream-5-pro", name: "Seedream 5.0 Pro", tagline: L("Logically coherent images with visual reasoning"),
                    isFeatured: true, openRouter: ["bytedance-seed/seedream-5-0-pro"]),
        LineupModel(id: "seedream-5-flash", name: "Seedream 5.0 Flash", tagline: L("Smart visual reasoning at full speed"),
                    isFeatured: true, openRouter: ["bytedance-seed/seedream-5-0-flash"]),
        LineupModel(id: "seedream-5-lite", name: "Seedream 5.0 Lite", tagline: L("Smart visual reasoning · 2K and 4K"),
                    isFeatured: true, openRouter: ["bytedance-seed/seedream-5-0-lite"]),
        LineupModel(id: "seedream-4.5", name: "Seedream 4.5", tagline: L("ByteDance's next-generation 4K model"),
                    isFeatured: true, openRouter: ["bytedance-seed/seedream-4.5"]),
        LineupModel(id: "nano-banana-2-lite", name: "Nano Banana 2 Lite", tagline: L("Lightweight generation at full speed"),
                    isFeatured: true,
                    openRouter: ["google/gemini-3.1-flash-lite-image"], google: ["gemini-3.1-flash-lite-image"]),
        LineupModel(id: "flux-3", name: "FLUX 3 Image", tagline: L("Black Forest Labs' next-generation creation and editing"),
                    isFeatured: true, openRouter: ["black-forest-labs/flux-3-image"]),
        LineupModel(id: "recraft-v4.1", name: "Recraft V4.1", tagline: L("Photorealistic and expressive generation"),
                    isFeatured: true, openRouter: ["recraft/recraft-v4.1"]),

        LineupModel(id: "nano-banana-2", name: "Nano Banana 2", tagline: L("Pro quality at Flash speed"),
                    openRouter: ["google/gemini-3.1-flash-image", "google/gemini-3.1-flash-image-preview"],
                    google: ["gemini-3.1-flash-image", "gemini-3.1-flash-image-preview"]),
        LineupModel(id: "nano-banana", name: "Nano Banana", tagline: L("Google's standard generation model"),
                    openRouter: ["google/gemini-2.5-flash-image"], google: ["gemini-2.5-flash-image"]),
        LineupModel(id: "gpt-image-2", name: "GPT Image 2", tagline: L("4K images with near-perfect text"),
                    openRouter: ["openai/gpt-image-2"]),
        LineupModel(id: "gpt-image", name: "GPT Image", tagline: L("ChatGPT's image generator"),
                    openRouter: ["openai/gpt-5.4-image-2", "openai/gpt-image-1", "openai/gpt-5-image"]),
        LineupModel(id: "grok-imagine-2", name: "Grok Imagine 2.0", tagline: L("xAI images with quality and style"),
                    openRouter: ["x-ai/grok-imagine-image-2.0"]),
        LineupModel(id: "grok-imagine", name: "Grok Imagine", tagline: L("xAI image generation"),
                    openRouter: ["x-ai/grok-imagine-image-quality"]),
        LineupModel(id: "flux-2-pro", name: "FLUX.2 Pro", tagline: L("Detail tuned for speed"),
                    openRouter: ["black-forest-labs/flux.2-pro"]),
        LineupModel(id: "flux-2-flex", name: "FLUX.2 Flex", tagline: L("Advanced control over generation"),
                    openRouter: ["black-forest-labs/flux.2-flex"]),
        LineupModel(id: "flux-2-max", name: "FLUX.2 Max", tagline: L("The highest FLUX.2 quality"),
                    openRouter: ["black-forest-labs/flux.2-max"]),
        LineupModel(id: "recraft-v4.1-utility", name: "Recraft V4.1 Utility", tagline: L("Simple scenes with flat, even light"),
                    openRouter: ["recraft/recraft-v4.1-utility"]),
        LineupModel(id: "recraft-v4.1-vector", name: "Recraft V4.1 Vector", tagline: L("Vector illustrations in SVG"),
                    openRouter: ["recraft/recraft-v4.1-vector"]),
        LineupModel(id: "recraft-v4-styles", name: "Recraft V4 Styles", tagline: L("Generates consistently in the style of your references"),
                    openRouter: ["recraft/recraft-v4-styles"]),
    ]

    static func entry(_ id: String) -> LineupModel? { models.first { $0.id == id } }

    static func displayName(forAssetModelID id: String, fallback: String) -> String {
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let provider = Provider(rawValue: parts[0]) else { return fallback }
        return models.first { $0.ids(for: provider).contains(parts[1]) }?.name ?? fallback
    }

    static func defaultModelIDs(for tool: Tool) -> [String] {
        let preferred: [String] = switch tool {
        case .create, .imported: ["seedream-4.5", "gpt-image-2.5-flare", "flux-2-pro"]
        case .photoSession: ["seedream-4.5", "seedream-5-pro"]
        case .storyboard: ["nano-banana-2", "seedream-5-pro"]
        case .edit: ["gpt-image-2.5-sunburst", "seedream-5-pro"]
        case .inpaint: ["nano-banana-2", "gpt-image-2.5-sunburst"]
        case .drawToEdit: ["nano-banana-2", "nano-banana-pro"]
        case .editText: ["gpt-image-2.5-sunburst", "gpt-image-2"]
        case .relight: ["seedream-5-pro", "gpt-image-2.5-flare"]
        case .upscale: ["seedream-4.5", "flux-3"]
        case .angles: ["seedream-5-pro", "nano-banana-2"]
        case .expand: ["seedream-4.5", "flux-3"]
        case .background: ["seedream-4.5", "gpt-image-2.5-flare"]
        case .faceSwap: ["nano-banana-2", "seedream-4.5"]
        case .characterSwap: ["seedream-4.5", "nano-banana-2"]
        case .outfitSwap: ["gpt-image-2.5-flare", "seedream-4.5"]
        case .product: ["gpt-image-2.5-sunburst", "seedream-5-pro"]
        case .app: ["seedream-4.5", "gpt-image-2.5-flare"]
        case .ad: ["nano-banana-pro", "gpt-image-2.5-sunburst", "seedream-4.5"]
        case .colorGrade, .video: []
        }
        guard !preferred.isEmpty else { return [] }
        return preferred + ["nano-banana-2", "nano-banana-pro", "nano-banana-2.1"].filter { !preferred.contains($0) }
    }
}
