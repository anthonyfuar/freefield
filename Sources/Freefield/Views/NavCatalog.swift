import FreefieldCore
import Foundation

struct SidebarRow: Identifiable {
    let item: SidebarItem
    let title: String
    let symbol: String
    var running = 0
    var count: Int?
    var keywords: [String] = []

    var id: SidebarItem { item }
}

struct SidebarPart: Identifiable {
    let id: String
    let title: String
    var rows: [SidebarRow]
}

struct SidebarGroup: Identifiable {
    let id: String
    let title: String
    var symbol: String?
    var parts: [SidebarPart]

    init(id: String, title: String, symbol: String? = nil, parts: [SidebarPart]) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.parts = parts
    }

    init(id: String, title: String, rows: [SidebarRow]) {
        self.init(id: id, title: title, parts: [SidebarPart(id: id, title: "", rows: rows)])
    }

    var rows: [SidebarRow] { parts.flatMap(\.rows) }
    var isFamily: Bool { symbol != nil }
    var running: Int { rows.reduce(0) { $0 + $1.running } }
}

enum NavCatalog {
    static let create: [SidebarItem] = [.tool(.create), .video("createVideo"), .apps, .video("videoEffects")]

    static let photo: [SidebarItem] = [
        Tool.background, .upscale, .edit, .inpaint, .relight, .colorGrade, .expand, .angles, .editText, .drawToEdit,
    ].map(SidebarItem.tool)

    static let people: [SidebarItem] = [.tool(.photoSession), .tool(.faceSwap), .tool(.storyboard)]

    static let swapTools: [Tool] = [.faceSwap, .characterSwap, .outfitSwap]

    static var moreVideo: [SidebarItem] {
        videos(in: .create, order: ["animateImage", "talkingAvatar", "cinemaStudio", "storyboardVideo", "transitions", "drawToVideo"],
               excluding: ["createVideo", "videoEffects"])
    }

    static var videoEdit: [SidebarItem] {
        videos(in: .edit, order: ["editVideo", "extendVideo", "joinClips", "colorGradeVideo", "reframeVideo", "upscaleVideo", "swapVideo",
                                 "motionTransfer"])
    }

    static var productPhotos: [SidebarItem] {
        [.ad("product-shoot"), .tool(.product), .ad("model-shoot"), .ad("marketplace"), .ad("unboxing"), .productEffects]
            .filter(exists)
    }

    static var ads: [SidebarItem] {
        let lead: [SidebarItem] = [
            .ad("static-ad"), .video("videoAd"), .ad("ugc-photo"), .ad("before-after"), .ad("testimonial"), .ad("carousel"),
            .ad("hook-frame"), .ad("recreate-ad"),
        ].filter(exists)
        let taken = Set(lead + productPhotos)
        let otherAds = AdCatalog.all.map { SidebarItem.ad($0.id) }.filter { !taken.contains($0) }
        let otherVideos = VideoCatalog.tools(in: .ad).map { SidebarItem.video($0.id) }.filter { !taken.contains($0) }
        return lead + otherAds + otherVideos
    }

    static let families: [(id: String, title: String, items: [SidebarItem])] = [
        ("photo", L("Improve a Photo"), photo),
        ("people", L("People & Faces"), people),
        ("video", L("More Video"), moreVideo),
        ("videoEdit", L("Edit a Video"), videoEdit),
        ("productPhotos", L("Product Photos"), productPhotos),
        ("ads", L("Ads"), ads),
    ]

    static let kinds: [(id: String, title: String, parts: [(id: String, title: String, items: [SidebarItem])])] = [
        ("image", L("Image"), [
            ("imageCreate", L("Create"), [.tool(.create), .apps]),
            ("photo", L("Improve a Photo"), photo),
            ("people", L("People & Faces"), people),
        ]),
        ("video", L("Video"), [
            ("videoCreate", L("Make a Video"), [.video("createVideo"), .video("videoEffects")] + moreVideo),
            ("videoEdit", L("Edit a Video"), videoEdit),
        ]),
        ("marketing", L("Products & Ads"), [
            ("productPhotos", L("Product Photos"), productPhotos),
            ("ads", L("Ads"), ads),
        ]),
    ]

    static var formerNames: [SidebarItem: [String]] = [
        .tool(.relight): ["Relight"],
        .tool(.expand): ["Expand"],
        .tool(.drawToEdit): ["Draw to Edit"],
        .tool(.angles): ["Angles"],
        .tool(.colorGrade): ["Color Grade"],
        .tool(.editText): ["Edit Text"],
        .tool(.storyboard): ["Storyboard"],
        .video("upscaleVideo"): ["Upscale Video"],
        .video("reframeVideo"): ["Reframe Video"],
        .video("motionTransfer"): ["Motion Transfer"],
        .video("hookCheck"): ["Hook Check"],
        .video("drawToVideo"): ["Draw to Video"],
        .video("storyboardVideo"): ["Storyboard to Video", "Storyboard"],
        .video("swapVideo"): ["Swap in Video"],
        .ad("static-ad"): ["Anuncio estático"],
    ]

    static func rowItem(for item: SidebarItem?) -> SidebarItem? {
        switch item {
        case .videoEffects: .video("videoEffects")
        case .tool(.video): .video("createVideo")
        case .tool(let tool) where swapTools.contains(tool): .tool(.faceSwap)
        case .favorites: .library
        default: item
        }
    }

    static func title(_ item: SidebarItem) -> String {
        switch item {
        case .home: L("Home")
        case .tool(let tool) where swapTools.contains(tool): L("Swap a Person")
        case .tool(.video): VideoCatalog.tool("createVideo")?.name ?? Tool.video.title
        case .tool(let tool): tool.title
        case .video(let id): VideoCatalog.tool(id)?.name ?? id
        case .videoEffects: VideoCatalog.tool("videoEffects")?.name ?? L("Video Effects")
        case .ad(let id): AdCatalog.tool(id)?.name ?? id
        case .apps: L("Photo Effects")
        case .productEffects: L("Product Effects")
        case .library, .favorites: L("Library")
        case .characters: L("Characters")
        case .products: L("Products")
        case .styles: L("Styles")
        case .usage: L("Usage & Limits")
        case .settings: L("Settings")
        }
    }

    static func symbol(_ item: SidebarItem) -> String {
        switch item {
        case .home: "house"
        case .tool(let tool) where swapTools.contains(tool): "person.line.dotted.person"
        case .tool(.video): VideoCatalog.tool("createVideo")?.symbol ?? Tool.video.systemImage
        case .tool(let tool): tool.systemImage
        case .video(let id): VideoCatalog.tool(id)?.symbol ?? "film"
        case .videoEffects: VideoCatalog.tool("videoEffects")?.symbol ?? "rectangle.stack.badge.play"
        case .ad(let id): AdCatalog.tool(id)?.symbol ?? "megaphone"
        case .apps: Tool.app.systemImage
        case .productEffects: Tool.app.systemImage
        case .library, .favorites: "photo.on.rectangle.angled"
        case .characters: "person.crop.square.filled.and.at.rectangle"
        case .products: "shippingbox"
        case .styles: "paintpalette"
        case .usage: "chart.bar.xaxis"
        case .settings: "gearshape"
        }
    }

    static func familySymbol(_ id: String) -> String {
        switch id {
        case "create": "square.and.pencil"
        case "image": "photo.on.rectangle"
        case "marketing": "megaphone"
        case "photo": "photo"
        case "people": "person.2"
        case "video": "video"
        case "videoEdit": "scissors"
        case "productPhotos": "shippingbox"
        case "ads": "megaphone"
        default: "folder"
        }
    }

    static var productEffects: [AppItem] { AppCatalog.filtered(category: L("Ads & Products"), search: "") }

    private static func exists(_ item: SidebarItem) -> Bool {
        switch item {
        case .ad(let id): AdCatalog.tool(id) != nil
        case .video(let id): VideoCatalog.tool(id) != nil
        default: true
        }
    }

    private static func videos(in section: VideoToolSection, order: [String], excluding: Set<String> = []) -> [SidebarItem] {
        let tools = VideoCatalog.tools(in: section).filter { !excluding.contains($0.id) }
        func rank(_ index: Int, _ id: String) -> Int { order.firstIndex(of: id) ?? order.count + index }
        return tools.enumerated()
            .sorted { rank($0.offset, $0.element.id) < rank($1.offset, $1.element.id) }
            .map { SidebarItem.video($0.element.id) }
    }
}
