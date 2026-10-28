import Foundation
import SwiftUI

enum Tool: String, Codable, CaseIterable, Identifiable {
    case create
    case storyboard
    case photoSession
    case edit
    case inpaint
    case drawToEdit
    case editText
    case upscale
    case relight
    case colorGrade
    case angles
    case expand
    case background
    case faceSwap
    case characterSwap
    case outfitSwap
    case product
    case video
    case ad
    case app
    case imported

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let tool = Tool(rawValue: raw == "photodump" ? "photoSession" : raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown tool \(raw)"))
        }
        self = tool
    }

    var title: String {
        switch self {
        case .create: L("Create Image")
        case .storyboard: L("Photo Story")
        case .photoSession: L("Photo Session")
        case .edit: L("Edit with Words")
        case .inpaint: L("Erase or Change an Area")
        case .drawToEdit: L("Draw Instructions")
        case .editText: L("Change Text")
        case .upscale: L("Improve Quality")
        case .relight: L("Change the Light")
        case .colorGrade: L("Color Filters")
        case .angles: L("Other Angles")
        case .expand: L("Widen the Frame")
        case .background: L("Change the Background")
        case .faceSwap: L("Face Swap")
        case .characterSwap: L("Character Swap")
        case .outfitSwap: L("Outfit Swap")
        case .product: L("Place Product")
        case .video: L("Video")
        case .ad: L("Ads & Products")
        case .app: L("Photo Effects")
        case .imported: L("Imported")
        }
    }

    var subtitle: String {
        switch self {
        case .create: L("Describe an idea; pick a style, character and model.")
        case .storyboard: L("Scenes in order, with the same character and style.")
        case .photoSession: L("A full photo session starring your character.")
        case .edit: L("Change anything in an image by describing it.")
        case .inpaint: L("Paint an area to erase it or change it.")
        case .drawToEdit: L("Draw and write on the image; the AI makes the edits.")
        case .editText: L("Rewrite the text in an image, keeping its lettering.")
        case .upscale: L("Make a photo sharper and bigger: 2K or 4K.")
        case .relight: L("Change the light: direction, color, hardness and mood.")
        case .colorGrade: L("Cinematic looks and fine-tuning, free on your Mac.")
        case .angles: L("Generate the same scene from other camera angles.")
        case .expand: L("Expand a photo to a new shape; AI fills in the rest.")
        case .background: L("Remove the background, or swap in a new one.")
        case .faceSwap: L("Put a face in another photo; light and expression stay.")
        case .characterSwap: L("Replace the person in a scene with your character.")
        case .outfitSwap: L("Dress a person in the clothing from another image.")
        case .product: L("Put your product in a scene with real light and shadow.")
        case .video: L("Clips from text, images and other videos.")
        case .ad: L("Ads and product photos for what you sell.")
        case .app: L("One-click effects.")
        case .imported: L("Imported image.")
        }
    }

    var systemImage: String {
        switch self {
        case .create: "photo.badge.plus"
        case .storyboard: "rectangle.split.3x1"
        case .photoSession: "photo.stack"
        case .edit: "bubble.and.pencil"
        case .inpaint: "eraser.line.dashed"
        case .drawToEdit: "pencil.and.scribble"
        case .editText: "textformat"
        case .upscale: "arrow.up.left.and.arrow.down.right"
        case .relight: "lightbulb.max"
        case .colorGrade: "camera.filters"
        case .angles: "camera.rotate"
        case .expand: "rectangle.arrowtriangle.2.outward"
        case .background: "person.and.background.dotted"
        case .faceSwap: "face.smiling"
        case .characterSwap: "person.line.dotted.person"
        case .outfitSwap: "tshirt"
        case .product: "shippingbox.and.arrow.backward"
        case .video: "film"
        case .ad: "megaphone"
        case .app: "photo.artframe"
        case .imported: "square.and.arrow.down"
        }
    }

    static let editingTools: [Tool] = [
        .edit, .inpaint, .drawToEdit, .editText, .upscale, .relight, .colorGrade, .angles, .expand, .background,
        .faceSwap, .characterSwap, .outfitSwap, .product,
    ]

    var isPromptDriven: Bool {
        switch self {
        case .create, .storyboard, .edit, .inpaint: true
        default: false
        }
    }

    var steps: [String] {
        switch self {
        case .edit: [L("Add the photo you want to change."), L("Write what should change, e.g. “add rain”."),
                     L("Generate: everything else stays as it was.")]
        case .inpaint: [L("Add the photo."), L("Paint over the part you want to change."), L("Say what goes there, or leave it empty to erase it.")]
        case .drawToEdit: [L("Add the photo."), L("Draw shapes and arrows, or write notes on it."),
                           L("Generate: the AI turns your marks into real edits.")]
        case .editText: [L("Add an image with text (a poster, a label…)."), L("Freefield finds the text; type the new words."),
                         L("Replace it, keeping the same lettering.")]
        case .upscale: [L("Add a small or blurry photo."), L("Choose 2K or 4K."), L("Get a sharper version with recovered detail.")]
        case .relight: [L("Add a photo."), L("Choose a light mood (golden hour, neon…)."), L("Relight it: the subject stays the same.")]
        case .colorGrade: [L("Add a photo."), L("Pick a color style and fine-tune the sliders."),
                           L("Save it to your Library. Free, on your Mac.")]
        case .angles: [L("Add a photo of a person or an object."), L("Pick one or more camera angles."),
                       L("Get one image per angle of the same scene.")]
        case .expand: [L("Add a photo."), L("Choose the new shape (for example 16:9)."), L("The AI fills in what was outside the frame.")]
        case .background: [L("Add a photo of a person or an object."), L("Remove the background, or describe a new one."),
                           L("Get a cutout, or your subject somewhere new.")]
        case .faceSwap: [L("Choose what to swap: the face, the whole person or the outfit."), L("Add the photo that gets the new face."), L("Add a clear photo of the face to use."),
                         L("Swap: the light and expression are kept.")]
        case .characterSwap: [L("Choose what to swap: the face, the whole person or the outfit."), L("Add a scene with a person in it."), L("Choose a saved character or upload their photo."),
                              L("Your character takes that person's place.")]
        case .outfitSwap: [L("Choose what to swap: the face, the whole person or the outfit."), L("Add a photo of the person."), L("Add the garment, alone or being worn."), L("The person appears wearing it.")]
        case .product: [L("Add the scene (a table, a shelf, a room…)."), L("Add a photo of your product."),
                        L("Optionally paint where it goes, then place it.")]
        default: []
        }
    }
}

enum SidebarItem: Hashable {
    case home
    case products
    case ad(String)
    case tool(Tool)
    case video(String)
    case videoEffects
    case styles
    case characters
    case apps
    case library
    case favorites
    case productEffects
    case usage
    case settings
}

extension SidebarItem {
    var recentID: String? {
        switch self {
        case .tool(.video): "video:createVideo"
        case .tool(let tool) where tool != .ad && tool != .app && tool != .imported: "tool:" + tool.rawValue
        case .video(let id): "video:" + id
        case .videoEffects: "video:videoEffects"
        case .ad(let id): "ad:" + id
        case .apps: "apps"
        case .productEffects: "productEffects"
        default: nil
        }
    }

    init?(recentID: String) {
        let parts = recentID.split(separator: ":", maxSplits: 1).map(String.init)
        switch (parts.first, parts.count == 2 ? parts[1] : nil) {
        case ("tool", let raw?): guard let tool = Tool(rawValue: raw) else { return nil }; self = .tool(tool)
        case ("video", let id?): guard VideoCatalog.tool(id) != nil else { return nil }; self = .video(id)
        case ("ad", let id?): guard AdCatalog.tool(id) != nil else { return nil }; self = .ad(id)
        case ("apps", nil): self = .apps
        case ("productEffects", nil): self = .productEffects
        default: return nil
        }
    }
}
