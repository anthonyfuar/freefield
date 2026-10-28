import FreefieldCore
import SwiftUI

enum PromptBudget {
    static func modelLimit(_ model: ImageModel?) -> Int {
        guard let model else { return 2_000 }
        let id = model.modelID.lowercased()
        if id.contains("gemini") || id.contains("nano-banana") { return 20_000 }
        if id.contains("gpt-image") || id.contains("gpt-5") { return 30_000 }
        if id.contains("recraft-v3") || id.contains("recraftv3") { return 1_000 }
        if id.contains("recraft") { return 10_000 }
        if id.contains("seedream") { return 3_500 }
        if id.contains("flux-3") || id.contains("flux3") { return 2_000 }
        if id.contains("flux") || id.contains("kontext") { return 1_800 }
        if id.contains("grok") { return 1_000 }
        if id.contains("ideogram") { return 1_800 }
        if id.contains("kling") { return 2_500 }
        if id.contains("wan2.2") || id.contains("wan-2.2") || id.contains("wan2.1") { return 500 }
        if id.contains("wan") { return 2_000 }
        if id.contains("z-image") || id.contains("zimage") { return 800 }
        if id.contains("qwen") { return 2_400 }
        return 2_000
    }

    static let interfaceCap = 2_500
    static let minimum = 80

    static func userLimit(model: ImageModel?, overhead: Int) -> Int {
        let available = modelLimit(model) - overhead - 40
        return max(minimum, min(interfaceCap, available))
    }
}

extension AppModel {
    func promptOverhead(for tool: Tool, state: ComposerState) -> Int {
        let character = library.character(state.characterID)
        switch tool {
        case .create:
            let moodboard = library.moodboard(state.moodboardID)
            var overhead = Recipes.create(
                prompt: "", preset: state.presetID.flatMap(StylePresets.preset), character: character,
                referenceCount: state.references.count,
                camera: CinemaCamera.prompt(body: state.cameraBody, lens: state.cameraLens, focalLength: state.cameraFocalLength,
                                            aperture: state.cameraAperture),
                palette: state.palette, moodboard: moodboard, styleImages: moodboard == nil ? nil : 10...12
            ).utf16.count + 1 + Recipes.quotedTextRule.utf16.count + 2
            if let product = library.product(state.productID) {
                overhead += 1 + Recipes.productReference(product, imageRange: 5...7).utf16.count
            }
            return overhead
        case .edit: return Recipes.edit("", referenceCount: state.references.count).utf16.count
        case .inpaint: return Recipes.inpaint("").utf16.count
        case .drawToEdit: return Recipes.drawToEdit("").utf16.count + 200
        case .relight:
            return Recipes.relight(preset: LightPreset.preset(state.lightPreset), direction: state.lightDirection,
                                   color: state.lightColor, intensity: state.lightIntensity, hard: state.lightHard, extra: "").utf16.count
        case .expand: return Recipes.expand(extra: "").utf16.count
        case .background: return Recipes.replaceBackground("").utf16.count
        case .characterSwap: return Recipes.characterSwap(details: character?.details ?? "", extra: "").utf16.count
        case .outfitSwap: return Recipes.outfitSwap(extra: "").utf16.count
        case .product: return Recipes.placement(withZones: true, placement: "").utf16.count
        case .upscale: return Recipes.upscale(creativity: 1).utf16.count + 7
        case .faceSwap: return max(Recipes.faceSwap(keepExpression: true).utf16.count, Recipes.faceSwap(keepExpression: false).utf16.count) + 7
        case .angles where state.anglesMode == "orbit":
            return Recipes.orbit(rotation: 150, tilt: 60, zoom: 2.5).utf16.count + 7
        case .angles:
            return (CameraAngle.all.map { Recipes.angle($0).utf16.count }.max() ?? 0) + 7
        case .editText:
            let lines = state.textEdits.map { $0.original.utf16.count + 128 }.reduce(0, +)
            return Recipes.editText([]).utf16.count + lines + 7
        case .storyboard:
            return Recipes.storyboard(scene: "", index: 0, total: 8, context: "", preset: state.presetID.flatMap(StylePresets.preset),
                                      character: character, referenceCount: state.references.count).utf16.count + 460
        default: return 800
        }
    }

    func promptLimit(for tool: Tool, state: ComposerState, model: ImageModel?) -> Int {
        PromptBudget.userLimit(model: model, overhead: promptOverhead(for: tool, state: state))
    }
}

struct CharacterLimit: ViewModifier {
    @Binding var text: String
    let limit: Int
    var clampsWhenLimitDrops = true

    static func clamp(_ value: String, to limit: Int) -> String {
        guard value.utf16.count > limit else { return value }
        var result = value
        while result.utf16.count > limit { result.removeLast() }
        return result
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: text) { oldValue, newValue in
                guard newValue.utf16.count > limit else { return }
                if !clampsWhenLimitDrops, oldValue.utf16.count > limit {
                    if newValue.utf16.count > oldValue.utf16.count { text = oldValue }
                    return
                }
                text = Self.clamp(newValue, to: limit)
            }
            .onChange(of: limit) { _, newLimit in
                guard clampsWhenLimitDrops else { return }
                let clamped = Self.clamp(text, to: newLimit)
                if clamped != text { text = clamped }
            }
            .overlay(alignment: .bottomTrailing) {
                let used = text.utf16.count
                let ratio = Double(used) / Double(max(limit, 1))
                if ratio > 0.6 {
                    Text("\(used)/\(limit)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(ratio >= 1 ? Color.red : ratio > 0.9 ? Color.orange : Color.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.background.opacity(0.8), in: .capsule)
                        .padding(4)
                        .help(L("Character limit for this field with the selected model and tool"))
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    func characterLimit(_ text: Binding<String>, _ limit: Int, clampsWhenLimitDrops: Bool = true) -> some View {
        modifier(CharacterLimit(text: text, limit: limit, clampsWhenLimitDrops: clampsWhenLimitDrops))
    }
}
