import Foundation
import FreefieldCore
import SwiftUI

enum Recipes {
    static let preserve = "Keep everything else in Image 1 exactly the same: faces, identity, pose, objects, any text, camera angle, framing, lighting and colors."

    private static func images(_ range: ClosedRange<Int>) -> String {
        range.count == 1 ? "Image \(range.lowerBound)" : "Images \(range.lowerBound)–\(range.upperBound)"
    }

    private static func imageLead(_ prompt: String) -> String {
        guard !prompt.isEmpty else { return "Generate an image." }
        let verbs = ["generate", "create", "draw", "design", "render", "paint", "illustrate", "make", "turn", "transform",
                     "photograph", "edit", "using image", "show", "depict"]
        let start = prompt.lowercased()
        return verbs.contains(where: { start.hasPrefix($0 + " ") }) ? prompt : "Generate an image: \(prompt)"
    }

    private static let quoted = try! NSRegularExpression(pattern: "(?<![0-9])[\"\u{201C}]([^\"\u{201D}]+)[\"\u{201D}]")

    static func quotedTexts(in text: String) -> [String] {
        quoted.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } }
    }

    static let quotedTextRule = "Render the quoted text exactly once, verbatim, with no extra characters. Add no other text, logos or watermarks, apart from a product's own label."

    static func create(
        prompt: String, preset: StylePreset?, character: Character?, referenceCount: Int,
        camera: String? = nil, palette: ColorPalette? = nil, moodboard: Moodboard? = nil,
        styleImages: ClosedRange<Int>? = nil, characterImageCount: Int? = nil, rendersQuotedText: Bool = true
    ) -> String {
        var parts: [String] = []
        if let character {
            let count = characterImageCount ?? max(1, min(character.photoFileNames.count, 4))
            let name = character.name.trimmingCharacters(in: .whitespaces)
            let who = name.isEmpty ? "one person" : "one person, \(name)"
            let detail = character.details.isEmpty ? "" : " (\(character.details))"
            if count > 0 {
                parts.append("\(images(1...count)) \(count == 1 ? "is the identity reference" : "are identity references") for \(who)\(detail). Keep their face, facial structure, skin tone and hair identical to the reference\(count == 1 ? "" : "s"); change only what is described.")
            } else {
                parts.append("The main subject is \(who)\(detail).")
            }
        }
        parts.append(imageLead(prompt))
        if let preset {
            parts.append("Render it in this style: \(preset.prompt)")
        }
        if let moodboard {
            let description = moodboard.styleDescription.isEmpty ? "" : " \(moodboard.styleDescription)"
            if let styleImages {
                let one = styleImages.count == 1
                parts.append("Moodboard style:\(description) \(images(styleImages)) \(one ? "is a style reference" : "are style references") only: match \(one ? "its" : "their") color grade, light, texture and mood, not \(one ? "its" : "their") subjects or layout.")
            } else if !description.isEmpty {
                parts.append("Moodboard style:\(description)")
            }
        }
        if let camera {
            parts.append("Camera look: \(camera).")
        }
        if let palette {
            parts.append(palette.prompt)
        }
        if referenceCount > 0 {
            parts.append("Use each of the user's reference images only for what the description says it provides, and take nothing else from it.")
        }
        if rendersQuotedText, !quotedTexts(in: prompt).isEmpty {
            parts.append(quotedTextRule)
        }
        return parts.joined(separator: "\n\n")
    }

    static func storyboard(scene: String, index: Int, total: Int, context: String, preset: StylePreset?, character: Character?,
                           characterImageCount: Int? = nil, referenceCount: Int = 0) -> String {
        let text = """
        Generate one full-frame cinematic still, shot \(index + 1) of \(total) of a continuous story. Story: \(context)
        This shot: \(scene)
        Same characters (faces, hair, wardrobe), world and color grade as the rest of the sequence. One borderless image, with no captions, subtitles or shot numbers.
        """
        let count = characterImageCount ?? character.map { max(1, min($0.photoFileNames.count, 3)) }
        return create(prompt: text, preset: preset, character: character, referenceCount: referenceCount,
                      characterImageCount: count, rendersQuotedText: false)
    }

    static func edit(_ instruction: String, referenceCount: Int) -> String {
        var text = "Using Image 1, change only this: \(instruction)"
        if referenceCount > 0 {
            text += "\n\(images(2...(referenceCount + 1))) \(referenceCount == 1 ? "is a reference" : "are references") for this change only; take from \(referenceCount == 1 ? "it" : "each") just what the instruction names."
        }
        return text + "\n\(preserve) Match Image 1's lighting, perspective and texture so the change blends in."
    }

    static func inpaint(_ instruction: String) -> String {
        """
        Image 1 is the image to edit. Image 2 is the same image with the area to change tinted translucent red; the tint only marks that area.
        In Image 1, change only the red-marked area: \(instruction)
        Keep everything outside it exactly as in Image 1, including faces, text and framing. Blend the edit in with matching light, shadows, perspective and grain. Return the full image at the same framing, with no red tint or mask edges.
        """
    }

    static func erase() -> String {
        """
        Image 1 is the image to edit. Image 2 is the same image with the area to remove tinted translucent red; the tint only marks that area.
        In Image 1, remove everything inside the red-marked area and fill it with what would naturally be behind it, continuing the surrounding background, textures, lines and lighting so nothing looks erased or smudged.
        Keep everything outside it exactly as in Image 1, including faces, text and framing. Return the full image at the same framing, with no red tint or mask edges.
        """
    }

    static func drawToEdit(_ instruction: String) -> String {
        var text = """
        Image 1 is the image to edit. Image 2 is the same image with the user's marks drawn on it: sketched shapes, arrows and handwritten notes. The marks are instructions, not content.
        Apply them to Image 1: each sketched shape becomes a real object in Image 1's style, scale and lighting; an arrow means move or extend that way; follow the notes.
        """
        if !instruction.isEmpty { text += "\nAlso: \(instruction)" }
        text += "\nKeep everything the marks do not point to exactly as in Image 1. The result shows no sketch lines, arrows or handwriting."
        return text
    }

    private static func also(_ extra: String) -> String {
        extra.isEmpty ? "" : "\nAlso: \(extra)"
    }

    static func upscale(creativity: Double, extra: String = "") -> String {
        let fidelity = creativity < 0.34
            ? "Restore only: add, remove or reinterpret nothing."
            : creativity < 0.67
                ? "Restore detail and gently refine soft or blurry textures without inventing new elements."
                : "Rebuild fine texture generously (skin pores, fabric weave, hair strands, foliage) while keeping every shape and feature as it is."
        return """
        Recreate Image 1 as a sharp, high-resolution version of itself: crisp edges, clean fine detail and natural texture, with blur, noise, banding and compression artifacts removed. \(fidelity)
        Keep the composition, framing, every face and identity, any text, the colors and the lighting identical to Image 1.
        """ + also(extra)
    }

    static func relight(preset: LightPreset, direction: CGPoint, color: Color, intensity: Double, hard: Bool, extra: String) -> String {
        let horizontal = direction.x < -0.33 ? "the left side of the frame" : direction.x > 0.33 ? "the right side of the frame" : "the front, near the camera"
        let vertical = direction.y < -0.33 ? "placed high and angled down" : direction.y > 0.33 ? "placed low and angled up" : "at eye level"
        let strength = intensity < 0.34 ? "a subtle but visible" : intensity < 0.67 ? "a clear" : "a strong, dramatic"
        var text = """
        Relight Image 1 with \(strength) change of lighting. New lighting: \(preset.prompt)
        The main light comes from \(horizontal), \(vertical), with a \(color.lightDescription) color. \(hard ? "Hard light: crisp, well-defined shadows and bright specular highlights." : "Soft light: diffused, with gradual shadow falloff.")
        Re-render highlights, shadows, reflections, color casts and skin shading to follow the new light. Keep the subject, face, pose, clothing, background and framing exactly as in Image 1.
        """
        if !extra.isEmpty { text += "\nAlso: \(extra)" }
        return text
    }

    static func angle(_ angle: CameraAngle, extra: String = "") -> String {
        """
        Generate a new view of the scene in Image 1 from a different camera position: \(angle.prompt)
        Keep the same subject (identity, face, outfit, materials, colors), setting and lighting, like another frame from the same shoot. Re-render the perspective for the new viewpoint rather than returning the original framing.
        """ + also(extra)
    }

    static func orbit(rotation: Double, tilt: Double, zoom: Double, extra: String = "") -> String {
        let amount = abs(rotation)
        let side = rotation < 0 ? "right" : "left"
        let view = amount < 15 ? "a front view"
            : amount < 60 ? "a three-quarter view from the subject's \(side)"
            : amount < 120 ? "a full side profile view from the subject's \(side)"
            : amount < 165 ? "a three-quarter rear view from behind the subject's \(side) shoulder"
            : "a view from directly behind the subject"
        let vertical = tilt > 10 ? "a high camera \(Int(tilt))° above, looking down" : tilt < -10 ? "a low camera \(Int(-tilt))° below, looking up" : "eye level"
        let distance = zoom > 1.15 ? "a tighter framing (about \(String(format: "%.1f", zoom))× closer)" : zoom < 0.85 ? "a wider framing that shows more of the surroundings" : "a similar framing distance"
        return """
        Generate a new view of the exact scene in Image 1: \(view) (the camera orbited \(Int(amount))° around the subject), from \(vertical), with \(distance).
        Make the change of viewpoint clearly visible: show the sides of the subject and the surroundings this position reveals, with re-rendered perspective, not the original framing.
        Keep the subject's identity, design, materials and colors, the setting and the lighting consistent, like another shot from the same shoot.
        """ + also(extra)
    }

    static func editText(_ edits: [(String, String)], extra: String = "") -> String {
        let list = edits.map { "\"\($0.0)\" → \"\($0.1)\"" }.joined(separator: "\n")
        return """
        In Image 1, replace only these texts, each in its original place (original → new):
        \(list)
        Write each new text once, verbatim, spelled exactly as given with no extra characters, in the original's font, weight, size, color, effects, perspective and alignment; if it is longer, tighten spacing or size slightly to fit. Keep all other text and everything else in Image 1 exactly the same.
        """ + also(extra)
    }

    static func expand(extra: String) -> String {
        var text = """
        Image 1 is an image centered on a larger canvas; the flat mid-gray area around it is empty padding.
        Extend the scene to fill all of the gray padding, so the result is one seamless, complete image with no border or seam. Continue the perspective, horizon, lighting, colors, grain and style, and keep the original central area exactly as it is.
        """
        text += extra.isEmpty ? "\nContinue the setting already visible." : "\nThe new area shows: \(extra)"
        return text
    }

    static func replaceBackground(_ description: String) -> String {
        """
        In Image 1, replace only the background with: \(description)
        Keep the main subject exactly the same: face, identity, pose, clothing, hair edges and anything they hold. Relight the subject to match the new background's light direction, color temperature and depth of field, with a natural contact shadow, so they look photographed there.
        """
    }

    static func productReference(_ product: Product, imageRange: ClosedRange<Int>) -> String {
        let details = product.details.isEmpty ? "" : " (\(product.details))"
        return "\(images(imageRange)) \(imageRange.count == 1 ? "shows" : "show") the product to feature: \(product.name)\(details). Use this exact product: identical shape, proportions, materials, colors, label text and logo, with no redesign or relabeling."
    }

    static func faceSwap(keepExpression: Bool, extra: String = "") -> String {
        """
        Image 1 is the target photo. Image 2 is the face reference.
        In Image 1, replace only the main person's face with the face from Image 2: same facial structure, eyes, nose, mouth, skin tone and marks, unmistakably that person.
        \(keepExpression ? "Keep Image 1's expression, head angle and gaze." : "Use Image 2's expression at Image 1's head angle.") Keep Image 1's hair, body, clothing, background, lighting and camera unchanged, blending jawline, neck, light and grain seamlessly.
        """ + also(extra)
    }

    static func characterSwap(details: String, extra: String) -> String {
        var text = """
        Image 1 is the scene. The other images show one person, the identity reference\(details.isEmpty ? "" : " (\(details))").
        In Image 1, replace only the main person with that person: same face, facial structure, skin tone, hairstyle and hair color. Keep Image 1's pose, action, clothing, framing, setting, lighting and color grade; other people stay unchanged.
        Match Image 1's medium: in a photo, a real person shot with the same camera, light and grain; in an illustration, the same drawing style.
        """
        if !extra.isEmpty { text += "\nAlso: \(extra)" }
        return text
    }

    static func outfitSwap(extra: String) -> String {
        var text = """
        Image 1 shows the person. Image 2 shows the garment or outfit.
        Dress the person from Image 1 in the clothing from Image 2, replacing only their clothes: same design, cut, fabric, color, pattern, logos and print, fitted to their body and pose with natural folds.
        Keep their face, skin tone, body shape, hair, pose and expression, and Image 1's background, framing and lighting, exactly the same. Take nothing from Image 2 except the clothing.
        """
        if !extra.isEmpty { text += "\nAlso: \(extra)" }
        return text
    }

    static func placement(withZones: Bool, placement: String) -> String {
        if withZones {
            return """
            Image 1 is the scene. Image 2 is the same scene with the target zone(s) tinted red, marking only where the product goes. Image 3 is the product.
            Edit Image 1: add the product from Image 3 inside the red zone(s)\(placement.isEmpty ? "" : ": \(placement)"). Use this exact product: identical shape, proportions, label text, logo and colors. Re-render it to the scene's scale, perspective and light, with contact shadows and reflections, not pasted flat.
            Keep the rest of Image 1 exactly as it is, with no red tint.
            """
        }
        return product(sceneProvided: true, placement: placement)
    }

    static func product(sceneProvided: Bool, placement: String) -> String {
        if sceneProvided {
            return """
            Image 1 is the scene. Image 2 is the product.
            Edit Image 1: add the product from Image 2\(placement.isEmpty ? " in a natural, plausible spot" : ": \(placement)"). Use this exact product: identical shape, proportions, label text, logo and colors. Re-render it to the scene's scale, perspective and lighting with matching reflections and contact shadows, not pasted flat. Keep the rest of Image 1 exactly as it is.
            """
        }
        return """
        Image 1 is the product. Create an advertising photograph of this exact product\(placement.isEmpty ? " in a setting that suits its brand and use" : ": \(placement)").
        Use this exact product: identical shape, proportions, label text, logo and colors. Light it with soft directional light that shows its materials, with realistic reflections and a grounded contact shadow.
        """
    }
}

struct LightPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let symbol: String
    let prompt: String
    var direction = CGPoint(x: -0.6, y: -0.5)
    var color = Color(red: 1.0, green: 0.82, blue: 0.6)
    var hard = false

    static let all: [LightPreset] = [
        LightPreset(id: "golden-hour", name: L("Golden hour"), detail: L("warm, low sun"), symbol: "sun.horizon",
                    prompt: "warm low golden-hour sunlight with long soft shadows and a gentle glow.",
                    direction: CGPoint(x: -0.8, y: -0.2), color: Color(red: 1.0, green: 0.74, blue: 0.42)),
        LightPreset(id: "studio-soft", name: L("Soft studio"), detail: L("even and flattering"), symbol: "light.panel",
                    prompt: "large softbox studio key light with a fill, clean even skin and soft shadows.",
                    direction: CGPoint(x: -0.45, y: -0.6), color: .white),
        LightPreset(id: "rembrandt", name: "Rembrandt", detail: L("dramatic side light"), symbol: "theatermasks",
                    prompt: "dramatic Rembrandt lighting, single key light with a triangle of light on the shadow cheek, deep chiaroscuro.",
                    direction: CGPoint(x: -0.7, y: -0.6), color: Color(red: 1.0, green: 0.95, blue: 0.88), hard: true),
        LightPreset(id: "neon", name: L("Neon"), detail: L("pink and blue"), symbol: "lightspectrum.horizontal",
                    prompt: "vivid magenta and cyan neon lights from both sides, nighttime city glow, colored rim light.",
                    direction: CGPoint(x: 0.9, y: 0), color: Color(red: 1.0, green: 0.3, blue: 0.8)),
        LightPreset(id: "window", name: L("Window"), detail: L("soft daylight"), symbol: "window.casement",
                    prompt: "soft natural daylight from a large window, gentle falloff, airy indoor ambience.",
                    direction: CGPoint(x: -0.9, y: -0.2), color: Color(red: 0.92, green: 0.95, blue: 1.0)),
        LightPreset(id: "backlight", name: L("Backlight"), detail: L("a glow from behind"), symbol: "circle.lefthalf.filled",
                    prompt: "strong backlight creating a bright rim around the subject's hair and shoulders, slight lens flare.",
                    direction: CGPoint(x: 0.6, y: -0.7), color: Color(red: 1.0, green: 0.86, blue: 0.6)),
        LightPreset(id: "blue-hour", name: L("Blue hour"), detail: L("cool twilight"), symbol: "moon.haze",
                    prompt: "cool blue-hour twilight ambient light with warm practical lights in the background.",
                    direction: CGPoint(x: -0.6, y: -0.3), color: Color(red: 0.6, green: 0.55, blue: 1.0)),
        LightPreset(id: "flash", name: L("Direct flash"), detail: L("party snapshot"), symbol: "bolt",
                    prompt: "on-camera direct flash, hard shadow behind the subject, glossy highlights, editorial party look.",
                    direction: .zero, color: .white, hard: true),
        LightPreset(id: "candle", name: L("Candlelight"), detail: L("warm and intimate"), symbol: "flame",
                    prompt: "warm flickering candlelight from below and the side, intimate dark surroundings.",
                    direction: CGPoint(x: -0.6, y: 0.6), color: Color(red: 1.0, green: 0.6, blue: 0.3)),
        LightPreset(id: "overcast", name: L("Overcast"), detail: L("no harsh shadows"), symbol: "cloud",
                    prompt: "flat soft overcast daylight, no harsh shadows, muted natural colors.",
                    direction: CGPoint(x: 0, y: -0.8), color: Color(red: 0.93, green: 0.95, blue: 1.0)),
        LightPreset(id: "sunset-hard", name: L("Hard sun"), detail: L("crisp shadows"), symbol: "sun.max",
                    prompt: "hard midday sun with crisp defined shadows and high contrast.",
                    direction: CGPoint(x: 0.5, y: -0.85), color: Color(red: 1.0, green: 0.95, blue: 0.86), hard: true),
        LightPreset(id: "cinematic", name: L("Cinematic light"), detail: L("teal and orange"), symbol: "film",
                    prompt: "moody cinematic teal-and-orange lighting, motivated practical sources, haze in the air.",
                    direction: CGPoint(x: -0.8, y: -0.2), color: Color(red: 1.0, green: 0.65, blue: 0.4)),
    ]

    static func preset(_ id: String) -> LightPreset { all.first { $0.id == id } ?? all[0] }

    static func == (lhs: LightPreset, rhs: LightPreset) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    func apply(to state: ComposerState) {
        state.lightPreset = id
        state.lightDirection = direction
        state.lightColor = color
        state.lightHard = hard
    }
}

struct CameraAngle: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let symbol: String
    let prompt: String

    static let all: [CameraAngle] = [
        CameraAngle(id: "front", name: L("Front view"), detail: L("at eye level"), symbol: "person.fill",
                    prompt: "straight-on front view at eye level."),
        CameraAngle(id: "three-quarter-left", name: L("3/4 left"), detail: L("turned a little to the left"), symbol: "arrow.turn.up.left",
                    prompt: "three-quarter view, camera rotated about 45° to the subject's left."),
        CameraAngle(id: "three-quarter-right", name: L("3/4 right"), detail: L("turned a little to the right"), symbol: "arrow.turn.up.right",
                    prompt: "three-quarter view, camera rotated about 45° to the subject's right."),
        CameraAngle(id: "profile-left", name: L("Left profile"), detail: L("side view from the left"), symbol: "arrow.left",
                    prompt: "full side profile view from the subject's left (90°)."),
        CameraAngle(id: "profile-right", name: L("Right profile"), detail: L("side view from the right"), symbol: "arrow.right",
                    prompt: "full side profile view from the subject's right (90°)."),
        CameraAngle(id: "back", name: L("Back view"), detail: L("from behind"), symbol: "rotate.3d",
                    prompt: "view from directly behind the subject."),
        CameraAngle(id: "low-angle", name: L("Low angle"), detail: L("from below"), symbol: "arrow.up",
                    prompt: "low-angle shot looking up at the subject from near the ground, heroic perspective."),
        CameraAngle(id: "high-angle", name: L("High angle"), detail: L("from above"), symbol: "arrow.down",
                    prompt: "high-angle shot looking down at the subject from above."),
        CameraAngle(id: "top-down", name: L("Top-down"), detail: L("straight down, bird's-eye"), symbol: "square.dashed",
                    prompt: "top-down bird's-eye view directly overhead."),
        CameraAngle(id: "close-up", name: L("Close-up"), detail: L("the face or a detail"), symbol: "plus.magnifyingglass",
                    prompt: "tight close-up shot of the subject's face or key detail."),
        CameraAngle(id: "wide", name: L("Wide shot"), detail: L("the whole place"), symbol: "minus.magnifyingglass",
                    prompt: "wide establishing shot showing the subject small within the full environment."),
        CameraAngle(id: "dutch", name: L("Dutch angle"), detail: L("tilted camera"), symbol: "rotate.right",
                    prompt: "dutch angle with the camera tilted about 20°, dynamic tension."),
    ]
}

extension Color {
    var lightDescription: String {
        let resolved = NSColor(self).usingColorSpace(.sRGB) ?? .white
        let red = resolved.redComponent, green = resolved.greenComponent, blue = resolved.blueComponent
        if red > 0.85, green > 0.85, blue > 0.85 { return "neutral white" }
        if red > blue + 0.2 && green > blue { return red - green > 0.3 ? "warm orange" : "warm amber" }
        if blue > red + 0.2 { return green > red ? "cool cyan-blue" : "cool blue" }
        if red > green + 0.2 && blue > green { return "magenta-pink" }
        if green > red + 0.15 && green > blue { return "green" }
        if red > green + 0.25 { return "red" }
        return "soft neutral"
    }
}
