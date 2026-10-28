import AppKit
import CoreGraphics
import Foundation
import FreefieldCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct DesignGroup: Identifiable {
    enum Step {
        case basics
        case face
        case clothes
        case details
        case personality
    }

    let id: String
    let title: String
    let step: Step
    let values: [String]
    var isMultiple = false
    var isRequired = false
    var swatches: [String: String] = [:]
    var hasPictures = false

    var pictures: [String: OptionPicture]? {
        hasPictures ? OptionImages.pictures(family: "character/\(id)", values: values) : nil
    }
}

enum DesignCatalog {
    static let groups: [DesignGroup] = [
        DesignGroup(id: "who", title: L("Who"), step: .basics,
                    values: ["Woman", "Man", "Androgynous person"], isRequired: true),
        DesignGroup(id: "age", title: L("Age"), step: .basics,
                    values: ["Early 20s", "Late 20s", "30s", "40s", "50s", "60s", "70 or older"], isRequired: true),
        DesignGroup(id: "skin", title: L("Skin tone"), step: .basics,
                    values: ["Very fair", "Fair", "Light beige", "Warm beige", "Olive", "Golden tan", "Rich brown", "Deep brown"],
                    isRequired: true,
                    swatches: ["Very fair": "F6E1D3", "Fair": "EFCFB8", "Light beige": "E3B897", "Warm beige": "C99A73",
                               "Olive": "B8875B", "Golden tan": "A87245", "Rich brown": "7D4E2D", "Deep brown": "4A2C1A"]),
        DesignGroup(id: "heritage", title: L("Heritage"), step: .basics,
                    values: ["African", "East Asian", "South Asian", "Southeast Asian", "Latin American", "Middle Eastern",
                             "European", "Pacific Islander", "Indigenous American", "Mixed"]),
        DesignGroup(id: "build", title: L("Body type"), step: .basics,
                    values: ["Slim", "Athletic", "Average", "Curvy", "Muscular", "Broad", "Plus-size"], hasPictures: true),
        DesignGroup(id: "height", title: L("Height"), step: .basics,
                    values: ["Short", "Average height", "Tall"]),
        DesignGroup(id: "face", title: L("Face shape"), step: .face,
                    values: ["Oval", "Round", "Angular", "Heart-shaped", "Oblong", "Diamond"], hasPictures: true),
        DesignGroup(id: "eyeShape", title: L("Eye shape"), step: .face,
                    values: ["Almond", "Round eyes", "Hooded", "Monolid", "Upturned", "Downturned"]),
        DesignGroup(id: "eyeColor", title: L("Eye color"), step: .face,
                    values: ["Very dark brown", "Warm brown", "Hazel", "Amber", "Green", "Blue", "Gray"],
                    swatches: ["Very dark brown": "3B2416", "Warm brown": "6B4226", "Hazel": "8E7043", "Amber": "B07A2A",
                               "Green": "5E7F4A", "Blue": "4F7BAE", "Gray": "8A949C"]),
        DesignGroup(id: "brows", title: L("Eyebrows"), step: .face,
                    values: ["Natural", "Thick", "Thin", "Arched", "Straight"]),
        DesignGroup(id: "hair", title: L("Hairstyle"), step: .face,
                    values: ["Long straight", "Long wavy", "Long curly", "Shoulder-length", "Bob", "Pixie cut", "Short crop",
                             "Buzz cut", "Afro", "Braids", "Locs", "Bun", "Ponytail", "Slicked back", "Bald"],
                    isRequired: true, hasPictures: true),
        DesignGroup(id: "hairColor", title: L("Hair color"), step: .face,
                    values: ["Black", "Dark brown", "Brown", "Light brown", "Auburn", "Copper red", "Blonde", "Platinum",
                             "Gray", "White", "Pastel pink", "Blue"],
                    isRequired: true,
                    swatches: ["Black": "1C1A19", "Dark brown": "3B2A20", "Brown": "5C4030", "Light brown": "8A6A4C",
                               "Auburn": "7E3B22", "Copper red": "B5532A", "Blonde": "D8B878", "Platinum": "ECE6D6",
                               "Gray": "9C9C9C", "White": "F2F2F0", "Pastel pink": "F0B6C8", "Blue": "4C78C9"]),
        DesignGroup(id: "facialHair", title: L("Facial hair"), step: .face,
                    values: ["Clean-shaven", "Stubble", "Short beard", "Full beard", "Mustache", "Goatee"]),
        DesignGroup(id: "clothing", title: L("Clothing style"), step: .clothes,
                    values: ["Casual", "Streetwear", "Smart casual", "Business", "Elegant", "Sporty", "Bohemian", "Minimal",
                             "Vintage", "Rock", "Cozy knitwear", "Techwear"], hasPictures: true),
        DesignGroup(id: "colors", title: L("Outfit colors"), step: .clothes,
                    values: ["Neutrals", "Black", "White", "Earth tones", "Pastels", "Bright colors", "Denim blue", "Jewel tones"],
                    swatches: ["Neutrals": "CBBBA6", "Black": "222222", "White": "F4F4F2", "Earth tones": "8B6B47",
                               "Pastels": "C9DDF0", "Bright colors": "E8483C", "Denim blue": "4A6A90", "Jewel tones": "1F6E5E"]),
        DesignGroup(id: "accessories", title: L("Accessories"), step: .details,
                    values: ["Glasses", "Sunglasses", "Earrings", "Necklace", "Hat", "Cap", "Watch", "Scarf", "Nose ring", "Headband"],
                    isMultiple: true),
        DesignGroup(id: "features", title: L("Distinctive features"), step: .details,
                    values: ["Freckles", "Dimples", "Beauty mark", "Rosy cheeks", "Tattoos", "Small scar", "Vitiligo",
                             "Gap between the front teeth", "Strong jawline", "High cheekbones"],
                    isMultiple: true),
        DesignGroup(id: "makeup", title: L("Makeup"), step: .details,
                    values: ["No makeup", "Natural", "Soft glam", "Bold lips", "Smoky eyes"]),
        DesignGroup(id: "expression", title: L("Expression"), step: .personality,
                    values: ["Soft smile", "Big smile", "Neutral", "Serious", "Confident look"]),
        DesignGroup(id: "vibe", title: L("Vibe"), step: .personality,
                    values: ["Friendly", "Confident", "Mysterious", "Fun-loving", "Calm", "Classy", "Edgy", "Energetic"]),
    ]

    static func group(_ id: String) -> DesignGroup? { groups.first { $0.id == id } }
    static func groups(in step: DesignGroup.Step) -> [DesignGroup] { groups.filter { $0.step == step } }

    static let defaults: [String: String] = [
        "who": "Woman", "age": "Late 20s", "skin": "Warm beige", "hair": "Long wavy", "hairColor": "Dark brown",
    ]

    static let hairPhrases: [String: String] = [
        "Long straight": "long straight %@ hair",
        "Long wavy": "long wavy %@ hair",
        "Long curly": "long curly %@ hair",
        "Shoulder-length": "shoulder-length %@ hair",
        "Bob": "a %@ bob haircut",
        "Pixie cut": "a short %@ pixie cut",
        "Short crop": "short cropped %@ hair",
        "Buzz cut": "a %@ buzz cut",
        "Afro": "a full %@ afro",
        "Braids": "long %@ box braids",
        "Locs": "%@ locs",
        "Bun": "%@ hair tied in a bun",
        "Ponytail": "%@ hair in a ponytail",
        "Slicked back": "slicked-back %@ hair",
    ]

    static let expressionPhrases: [String: String] = [
        "Soft smile": "a soft, natural smile",
        "Big smile": "a big, warm smile",
        "Neutral": "a relaxed, neutral expression",
        "Serious": "a serious expression",
        "Confident look": "a confident look",
    ]

    static let agePhrases: [String: String] = [
        "Early 20s": "in their early 20s", "Late 20s": "in their late 20s", "30s": "in their 30s", "40s": "in their 40s",
        "50s": "in their 50s", "60s": "in their 60s", "70 or older": "aged 70 or older",
    ]
}

@Observable
final class CharacterDesign {
    static let shared = CharacterDesign()

    var choices: [String: String] = DesignCatalog.defaults
    var multiple: [String: Set<String>] = [:]
    var extra = ""
    var modelID: String?
    var name = ""
    var change = ""
    var sheetID: UUID?
    var savedCharacterID: UUID?

    func isSelected(_ value: String, in group: DesignGroup) -> Bool {
        group.isMultiple ? multiple[group.id, default: []].contains(value) : choices[group.id] == value
    }

    func toggle(_ value: String, in group: DesignGroup) {
        if group.isMultiple {
            var set = multiple[group.id, default: []]
            if set.contains(value) { set.remove(value) } else { set.insert(value) }
            multiple[group.id] = set
        } else if choices[group.id] == value, !group.isRequired {
            choices[group.id] = nil
        } else {
            choices[group.id] = value
        }
    }

    func summary(of group: DesignGroup) -> String? {
        if group.isMultiple {
            let picked = group.values.filter { multiple[group.id, default: []].contains($0) }
            return picked.isEmpty ? nil : picked.map { L($0) }.joined(separator: ", ")
        }
        return choices[group.id].map { L($0) }
    }

    func summary(of step: DesignGroup.Step) -> String {
        DesignCatalog.groups(in: step).compactMap(summary(of:)).joined(separator: " · ")
    }

    func isFilled(_ step: DesignGroup.Step) -> Bool {
        DesignCatalog.groups(in: step).contains { summary(of: $0) != nil }
    }

    func surprise() {
        var picked: [String: String] = [:]
        var sets: [String: Set<String>] = [:]
        for group in DesignCatalog.groups {
            if group.isMultiple {
                sets[group.id] = Set(group.values.shuffled().prefix(Int.random(in: 0...2)))
            } else if group.isRequired || Bool.random() {
                picked[group.id] = group.values.randomElement()
            }
        }
        if picked["who"] == "Woman" { picked["facialHair"] = nil }
        if picked["who"] == "Man", picked["makeup"] != nil { picked["makeup"] = "No makeup" }
        choices = picked
        multiple = sets
    }

    func reset() {
        choices = DesignCatalog.defaults
        multiple = [:]
        extra = ""
        change = ""
        name = ""
        sheetID = nil
        savedCharacterID = nil
    }

    var storedChoices: [String: String] {
        var stored = choices
        for (id, set) in multiple where !set.isEmpty {
            stored[id] = set.sorted().joined(separator: "|")
        }
        stored["extra"] = extra.isEmpty ? nil : extra
        return stored
    }

    func load(_ stored: [String: String]) {
        var picked: [String: String] = [:]
        var sets: [String: Set<String>] = [:]
        for group in DesignCatalog.groups {
            guard let value = stored[group.id] else { continue }
            if group.isMultiple {
                sets[group.id] = Set(value.split(separator: "|").map(String.init).filter(group.values.contains))
            } else if group.values.contains(value) {
                picked[group.id] = value
            }
        }
        choices = picked.merging(DesignCatalog.defaults) { current, _ in current }
        multiple = sets
        extra = stored["extra"] ?? ""
    }

    private func value(_ id: String) -> String? { choices[id] }
    private func lower(_ id: String) -> String? { choices[id]?.lowercased() }

    private func list(_ id: String) -> [String] {
        let group = DesignCatalog.group(id)
        return (group?.values ?? []).filter { multiple[id, default: []].contains($0) }.map { $0.lowercased() }
    }

    private static func joined(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        case 2: "\(items[0]) and \(items[1])"
        default: items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }

    private static func article(_ phrase: String) -> String {
        guard let first = phrase.lowercased().first else { return phrase }
        return ("aeiou".contains(first) ? "an " : "a ") + phrase
    }

    var personDescription: String {
        var sentences: [String] = []
        let who = Self.article(lower("who") ?? "person")
        let pronoun = value("who") == "Woman" ? "her" : value("who") == "Man" ? "his" : "their"
        let subject = value("who") == "Woman" ? "She has" : value("who") == "Man" ? "He has" : "They have"
        var lead = who
        if let age = value("age").flatMap({ DesignCatalog.agePhrases[$0] }) {
            lead += " " + age.replacingOccurrences(of: "their", with: pronoun)
        }
        var body: [String] = []
        if let skin = lower("skin") { body.append("\(skin) skin") }
        if let heritage = value("heritage") { body.append("\(heritage) heritage") }
        if let build = lower("build") { body.append(Self.article(build) + " build") }
        if let height = lower("height") { body.append(height == "average height" ? "average height" : "a \(height) stature") }
        sentences.append(body.isEmpty ? lead : "\(lead), with \(Self.joined(body))")

        var face: [String] = []
        if let shape = lower("face") { face.append(Self.article(shape) + " face") }
        let eyes = [lower("eyeShape")?.replacingOccurrences(of: " eyes", with: ""), lower("eyeColor")].compactMap { $0 }
        if !eyes.isEmpty { face.append(eyes.joined(separator: " ") + " eyes") }
        if let brows = lower("brows") { face.append("\(brows) eyebrows") }
        if let style = value("hair") {
            let color = lower("hairColor") ?? "natural"
            face.append(style == "Bald" ? "a shaved bald head" : String(format: DesignCatalog.hairPhrases[style] ?? "%@ hair", color))
        } else if let color = lower("hairColor") {
            face.append("\(color) hair")
        }
        if let beard = lower("facialHair") { face.append(beard == "clean-shaven" ? "a clean-shaven face" : beard) }
        if !face.isEmpty { sentences.append("\(subject) \(Self.joined(face))") }

        var outfit: [String] = []
        if let clothing = lower("clothing") { outfit.append(Self.article(clothing) + " outfit") }
        if let colors = lower("colors") { outfit.append(outfit.isEmpty ? "clothes in \(colors)" : "in \(colors)") }
        let accessories = list("accessories")
        if !outfit.isEmpty || !accessories.isEmpty {
            var wearing = "Wearing " + (outfit.isEmpty ? "simple everyday clothes" : outfit.joined(separator: " "))
            if !accessories.isEmpty { wearing += ", with \(Self.joined(accessories))" }
            sentences.append(wearing)
        }

        var details: [String] = list("features")
        if let makeup = lower("makeup") { details.append(makeup == "no makeup" ? "no makeup" : "\(makeup) makeup") }
        if !details.isEmpty { sentences.append("Details: \(Self.joined(details))") }

        var mood: [String] = []
        if let expression = value("expression").flatMap({ DesignCatalog.expressionPhrases[$0] }) { mood.append(expression) }
        if let vibe = lower("vibe") { mood.append(Self.article(vibe) + " vibe") }
        if !mood.isEmpty { sentences.append("\(subject) \(Self.joined(mood))") }
        return sentences.map { $0 + "." }.joined(separator: " ")
    }

    var shortDetails: String {
        var parts: [String] = []
        for id in ["who", "age"] { if let value = choices[id] { parts.append(L(value).lowercased()) } }
        if let skin = choices["skin"] { parts.append(L("%@ skin", L(skin).lowercased())) }
        if let hair = choices["hair"] {
            parts.append(hair == "Bald" ? L(hair).lowercased()
                         : L("%@, %@ hair", L(hair).lowercased(), L(choices["hairColor"] ?? "Brown").lowercased()))
        }
        if let eyes = choices["eyeColor"] { parts.append(L("%@ eyes", L(eyes).lowercased())) }
        if let clothing = choices["clothing"] { parts.append(L("%@ style", L(clothing).lowercased())) }
        return parts.joined(separator: ", ")
    }

    var sheetPrompt: String {
        var prompt = """
        Generate a character reference sheet of one original, fictional adult (not a real or famous person): \(personDescription)
        Layout: a 2×2 grid of four equal square panels separated by thin solid black lines, with the same plain light-gray seamless studio background in every panel.
        Top left: front view, head and shoulders, looking straight into the camera. Top right: three-quarter view, head and shoulders, turned slightly to the side. Bottom left: side profile, head and shoulders. Bottom right: full-body front view standing naturally, from head to shoes, all of the body visible.
        The exact same person in all four panels: identical face, facial structure, skin, hair, outfit and accessories.
        Photorealistic studio photography: soft, even key light, true-to-life skin texture with visible pores, natural proportions, sharp focus, 85mm lens look. No text, labels, captions, numbers or watermarks.
        """
        let extra = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty { prompt += "\nAlso: \(extra)" }
        return prompt
    }

    static func changePrompt(_ change: String) -> String {
        """
        Image 1 is a character reference sheet: a 2×2 grid showing the same person from the front, at three-quarters, in profile and in full body.
        Change only this, the same way in all four panels: \(change)
        Keep everything else exactly the same: the 2×2 layout and the thin black lines between panels, the poses, the gray studio background, the light and the person's identity. No text, labels or watermarks.
        """
    }
}

enum CharacterSheet {
    static let appID = "character-builder"
    static let preferredModels = ["nano-banana-pro", "seedream-4.5", "nano-banana-2", "gpt-image-2.5-flare"]

    nonisolated static func panels(from data: Data) -> [Data] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
        let width = image.width, height = image.height
        guard width > 64, height > 64 else { return [] }
        let sampleWidth = 256
        let sampleHeight = max(64, Int(Double(sampleWidth) * Double(height) / Double(width)))
        var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: sampleWidth, height: sampleHeight, bitsPerComponent: 8,
                                          bytesPerRow: sampleWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))
            return true
        }
        guard drawn else { return [] }
        func isDark(_ x: Int, _ y: Int) -> Bool {
            let index = (y * sampleWidth + x) * 4
            let luma = 0.299 * Double(pixels[index]) + 0.587 * Double(pixels[index + 1]) + 0.114 * Double(pixels[index + 2])
            return luma < 60
        }
        func darkRun(count: Int, length: Int, dark: (Int, Int) -> Bool) -> ClosedRange<Double> {
            let low = Int(Double(count) * 0.3), high = Int(Double(count) * 0.7)
            var scores: [(Int, Double)] = []
            for line in low...high {
                var hits = 0
                for step in 0..<length where dark(line, step) { hits += 1 }
                scores.append((line, Double(hits) / Double(length)))
            }
            guard let best = scores.max(by: { $0.1 < $1.1 }), best.1 > 0.75 else {
                let middle = Double(count) / 2
                return middle...middle
            }
            let lines = scores.filter { $0.1 > 0.6 && abs($0.0 - best.0) <= 6 }.map(\.0)
            return Double(lines.min() ?? best.0)...Double((lines.max() ?? best.0) + 1)
        }
        let column = darkRun(count: sampleWidth, length: sampleHeight) { isDark($0, $1) }
        let row = darkRun(count: sampleHeight, length: sampleWidth) { isDark($1, $0) }
        let scaleX = Double(width) / Double(sampleWidth), scaleY = Double(height) / Double(sampleHeight)
        let margin = 2.0
        let left = 0.0...(column.lowerBound * scaleX - margin)
        let right = (column.upperBound * scaleX + margin)...Double(width)
        let top = 0.0...(row.lowerBound * scaleY - margin)
        let bottom = (row.upperBound * scaleY + margin)...Double(height)
        let cells = [(left, top), (right, top), (left, bottom), (right, bottom)]
        return cells.compactMap { horizontal, vertical in
            let rect = CGRect(x: horizontal.lowerBound, y: vertical.lowerBound,
                              width: horizontal.upperBound - horizontal.lowerBound, height: vertical.upperBound - vertical.lowerBound)
                .integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
            guard rect.width > 32, rect.height > 32, let crop = image.cropping(to: rect) else { return nil }
            return encode(crop)
        }
    }

    nonisolated private static func encode(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    @concurrent
    nonisolated static func panelsInBackground(from data: Data) async -> [Data] {
        panels(from: data)
    }
}

extension AppModel {
    func characterSheetModel(selection: String?, needsImage: Bool = false) -> ImageModel? {
        let (featured, others) = choices(for: ModelRequirement(images: needsImage ? 1 : 0, minimumImages: needsImage ? 1 : 0))
        let all = featured + others
        if let selection, let match = all.first(where: { $0.model.id == selection }) { return match.model }
        for lineupID in CharacterSheet.preferredModels {
            if let match = featured.first(where: { $0.lineup?.id == lineupID && !catalog.strained.contains($0.model.id) }) {
                return match.model
            }
        }
        return featured.first { !catalog.strained.contains($0.model.id) }?.model ?? featured.first?.model ?? others.first?.model
    }

    static func sheetResolution(for model: ImageModel) -> Resolution {
        model.resolutions.contains(.twoK) ? .twoK : model.bestResolution(for: .twoK) ?? .oneK
    }

    func characterSheetCost(_ model: ImageModel?) -> Double? {
        guard let model else { return nil }
        return estimatedCost(model: model, count: 1, resolution: Self.sheetResolution(for: model))
    }

    var characterSheetJobs: [Job] {
        engine.jobs.filter { $0.spec?.appID == CharacterSheet.appID && $0.isRunning }
    }

    var characterSheets: [Asset] {
        library.assets.filter { $0.appID == CharacterSheet.appID && !$0.isVideo }
    }

    func runCharacterSheet(_ design: CharacterDesign, model: ImageModel) {
        let extra = design.extra.trimmingCharacters(in: .whitespacesAndNewlines)
        var spec = JobSpec(
            tool: .create,
            title: L("Character sheet"),
            prompt: design.sheetPrompt,
            model: model,
            aspectRatio: .square,
            resolution: Self.sheetResolution(for: model),
            count: 1,
            appID: CharacterSheet.appID
        )
        spec.record = "Character sheet: " + design.personDescription
        spec.userTexts = extra.isEmpty ? [] : [extra]
        watchSheet(engine.start(spec), design: design)
    }

    func changeCharacterSheet(_ sheet: Asset, design: CharacterDesign, model: ImageModel) {
        let change = design.change.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !change.isEmpty, let data = library.imageData(for: sheet),
              let image = ImageCoding.prepareForUpload(data, maxPixel: 2048, role: "character sheet") else { return }
        var spec = JobSpec(
            tool: .create,
            title: L("Character sheet"),
            prompt: CharacterDesign.changePrompt(change),
            model: model,
            aspectRatio: .square,
            resolution: Self.sheetResolution(for: model),
            count: 1,
            images: [image],
            appID: CharacterSheet.appID
        )
        spec.record = "Character sheet change: " + change
        spec.userTexts = [change]
        spec.literalTexts = Recipes.quotedTexts(in: change)
        watchSheet(engine.start(spec), design: design)
    }

    private func watchSheet(_ job: Job, design: CharacterDesign) {
        job.onFinish = { finished in
            if let id = finished.assetIDs.first {
                design.sheetID = id
                design.change = ""
                design.savedCharacterID = nil
            }
        }
    }

    @discardableResult
    func saveCharacter(from sheet: Asset, design: CharacterDesign, panels: [Data]) -> Character? {
        guard !panels.isEmpty else { return nil }
        let typed = design.name.trimmingCharacters(in: .whitespaces)
        let name = typed.isEmpty ? L("My Character") : typed
        return library.addCharacter(name: name, details: design.shortDetails, photos: panels, designChoices: design.storedChoices)
    }
}
