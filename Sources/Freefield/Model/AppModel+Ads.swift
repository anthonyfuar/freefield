import FreefieldCore
import SwiftUI

@Observable
final class AdState {
    var productID: UUID?
    var productPhoto: Data?
    var characterID: UUID?
    var personPhoto: Data?
    var reference: Data?
    var choices: [Int: String] = [:]
    var text = ""
    var text2 = ""
    var extra = ""
    var modelID: String?
    var aspect: AspectRatio
    var count = 1
    var pickedGroups: Set<Int> = []
    var many: [Int: Set<String>] = [:]
    var productIDs: [UUID] = []
    var swapPhoto: Data?
    var brandID: UUID?
    var usesBrandColors = true
    var addsLogo = true
    var headlineCount = 5
    var isPreparing = false

    init(aspect: AspectRatio) {
        self.aspect = aspect
    }

    func choice(_ index: Int, in tool: AdTool) -> String {
        guard index < tool.options.count else { return "" }
        return choices[index] ?? tool.options[index].values.first ?? ""
    }

    func isOn(_ condition: AdCondition?, in tool: AdTool) -> Bool {
        guard let condition else { return true }
        return condition.values.contains(choice(condition.group, in: tool)) != condition.excluding
    }

    func picks(_ index: Int, in tool: AdTool) -> [String] {
        guard index < tool.options.count else { return [] }
        let values = tool.options[index].values
        let chosen = many[index] ?? Set(tool.manyDefault[index] ?? tool.manyExample[index] ?? Array(values.prefix(1)))
        return values.filter(chosen.contains)
    }

    func toggle(_ value: String, in index: Int, of tool: AdTool) {
        var chosen = Set(picks(index, in: tool))
        if chosen.contains(value) { chosen.remove(value) } else { chosen.insert(value) }
        many[index] = chosen
    }

    func usedText(in tool: AdTool) -> String { isOn(tool.text?.appliesWhen, in: tool) ? text : "" }
    func usedText2(in tool: AdTool) -> String { isOn(tool.text2?.appliesWhen, in: tool) ? text2 : "" }
}

struct AdSettings {
    var choices: [String]
    var text: String
    var text2: String
    var product: Product?
    var character: Character?
    var aspect: AspectRatio
    var count: Int
    var extra = ""
    var brand: BrandKit?
    var brandColors = true
    var logoAttached = false

    func choice(_ index: Int) -> String { index < choices.count ? choices[index] : "" }
}

struct AdInputs {
    var reference: [InputImage] = []
    var product: [InputImage] = []
    var person: [InputImage] = []
    var logo: [InputImage] = []

    func prefix(_ limit: Int) -> [InputImage] { Array((reference + product + person).prefix(max(0, limit))) }

    func withLogo(_ limit: Int) -> (images: [InputImage], hasLogo: Bool) {
        let room = limit - 1 - reference.count
        guard !logo.isEmpty, !product.isEmpty, room >= 1 else { return (prefix(limit), false) }
        let kept = min(product.count, max(1, room - person.count))
        let people = Array(person.prefix(max(0, room - kept)))
        return (reference + Array(product.prefix(kept)) + people + Array(logo.prefix(1)), true)
    }

    func productCount(within limit: Int) -> Int { min(product.count, max(0, limit - reference.count)) }
}

extension AppModel {
    func adState(for tool: AdTool) -> AdState {
        if let state = adStates[tool.id] { return state }
        let state = AdState(aspect: tool.aspect)
        state.choices = tool.example
        state.text = tool.text?.initial ?? ""
        state.text2 = tool.text2?.initial ?? ""
        state.productID = lastProduct?.id
        state.productIDs = lastProduct.map { [$0.id] } ?? []
        applyProductDefaults(tool, state: state)
        adStates[tool.id] = state
        return state
    }

    static let lastProductKey = "lastProductID"

    var lastProduct: Product? {
        library.product(UserDefaults.standard.string(forKey: Self.lastProductKey).flatMap(UUID.init(uuidString:)))
    }

    func rememberProduct(_ id: UUID?) {
        guard let id, library.product(id) != nil else { return }
        UserDefaults.standard.set(id.uuidString, forKey: Self.lastProductKey)
    }

    func applyProductDefaults(_ tool: AdTool, state: AdState) {
        guard tool.id == "model-shoot", !state.pickedGroups.contains(0) else { return }
        let worn = library.product(state.productID).map(Self.isWorn) ?? false
        state.choices[0] = worn ? "Wearing it (try-on)" : tool.example[0]
    }

    static func isWorn(_ product: Product) -> Bool {
        let words = "\(product.name) \(product.details)".lowercased()
            .split { !$0.isLetter }.map(String.init)
        return words.contains { word in
            garmentStems.contains { word.hasPrefix($0) }
                || garmentWords.contains { word == $0 || word == $0 + "s" || word == $0 + "es" }
        }
    }

    private static let garmentStems = ["ropa", "prenda", "camis", "playera", "blusa", "vestido", "falda", "pantal", "chaqueta",
                                       "chamarra", "abrigo", "sudadera", "suéter", "sueter", "traje", "leggin", "overol"]
    private static let garmentWords = ["clothing", "clothes", "garment", "apparel", "shirt", "tshirt", "tee", "blouse", "dress",
                                       "skirt", "pants", "trousers", "jeans", "jacket", "coat", "hoodie", "sweater",
                                       "sweatshirt", "outfit", "jumpsuit", "leggings", "bikini", "swimsuit"]

    func adSettings(_ tool: AdTool, state: AdState) -> AdSettings {
        AdSettings(choices: tool.options.indices.map { state.choice($0, in: tool) },
                   text: state.usedText(in: tool), text2: state.usedText2(in: tool),
                   product: library.product(state.productID), character: library.character(state.characterID),
                   aspect: state.aspect, count: state.count, extra: tool.directionField == nil ? state.extra : "",
                   brand: tool.usesBrand ? BrandStore.shared.brand(state.brandID) : nil, brandColors: state.usesBrandColors)
    }

    func adHasProduct(_ state: AdState) -> Bool {
        library.product(state.productID) != nil || state.productPhoto != nil
    }

    func batchProducts(_ state: AdState) -> [Product] {
        state.productIDs.compactMap(library.product)
    }

    func adSwapReady(_ tool: AdTool, state: AdState) -> Bool {
        switch state.choice(0, in: tool) {
        case "Product": adHasProduct(state)
        case "Person": library.character(state.characterID) != nil || state.personPhoto != nil
        case "Location": state.swapPhoto != nil || !state.extra.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: state.swapPhoto != nil
        }
    }

    func adWritesCopy(_ tool: AdTool, state: AdState) -> Bool {
        tool.kind == .batch && state.choice(3, in: tool) == "AI writes it"
    }

    func adHelperCost(_ tool: AdTool, state: AdState) -> Double {
        adWritesCopy(tool, state: state) ? Self.helperEstimate * Double(batchProducts(state).count) : 0
    }

    func adImageCount(_ tool: AdTool, state: AdState) -> Int {
        switch tool.kind {
        case .batch: return batchProducts(state).count * state.picks(1, in: tool).count * state.picks(2, in: tool).count
        case .resize, .translate: return state.picks(0, in: tool).count
        default: break
        }
        if tool.isCarousel { return Int(state.choice(1, in: tool)) ?? 5 }
        if tool.isUnboxing, state.choice(2, in: tool) == "3-photo sequence" { return 3 }
        if tool.makesFullSet(state.choice(0, in: tool)) { return AdTool.listingSet.count }
        if tool.text?.onePerLine == true { return max(1, Self.lines(state.usedText(in: tool)).count) * state.count }
        return state.count
    }

    func adInputs(_ tool: AdTool, state: AdState, settings: AdSettings) -> AdInputs {
        var inputs = AdInputs()
        if tool.needsReference, let reference = state.reference.flatMap({ ImageCoding.deferredUpload($0, role: "reference ad") }) {
            inputs.reference = [reference]
        }
        if let product = settings.product {
            inputs.product = library.productImages(for: product, limit: 3)
        } else if let photo = state.productPhoto.flatMap({ ImageCoding.deferredUpload($0, role: "product") }) {
            inputs.product = [photo]
        }
        if tool.usesPerson {
            if let character = settings.character {
                inputs.person = library.referenceImages(for: character, limit: 3)
            } else if let photo = state.personPhoto.flatMap({ ImageCoding.deferredUpload($0, role: "person") }) {
                inputs.person = [photo]
            }
        }
        if tool.placesLogo, state.addsLogo, let brand = settings.brand,
           let logo = BrandStore.shared.logoData(brand).flatMap({ ImageCoding.deferredUpload($0, maxPixel: 1024, role: "brand logo") }) {
            inputs.logo = [logo]
        }
        return inputs
    }

    static func brandDirection(_ settings: AdSettings) -> String {
        guard let brand = settings.brand else { return "" }
        var lines = ["\nBrand kit for \u{201C}\(brand.name)\u{201D}, applied to the ad's design (never write these instructions or the brand name as extra text):"]
        let colors = brand.cleanColors
        if settings.brandColors, !colors.isEmpty {
            lines.append("- Colors: build the design palette from these brand colors: \(colors.joined(separator: ", ")). Use them for backgrounds, shapes, buttons, icons and type, instead of a palette taken from the label. Keep the product's own colors exactly as they are.")
        }
        let fonts = brand.cleanFonts
        if !fonts.isEmpty {
            lines.append("- Type: set the ad's text in \(fonts.joined(separator: " or ")), or the closest matching typeface.")
        }
        if !brand.trimmedTone.isEmpty {
            lines.append("- Feel: the art direction should feel \(brand.trimmedTone).")
        }
        if settings.logoAttached {
            lines.append("- Logo: the last attached image is the brand logo. Place it once, small and clean, in a corner or near the call to action, reproduced exactly; never distort, recolor, redraw or crop it.")
        }
        return lines.count > 1 ? lines.joined(separator: "\n") : ""
    }

    static func shape(_ value: String) -> String {
        guard let ratio = AspectRatio(rawValue: value) else { return value }
        return ratio.ratio > 1.01 ? "horizontal" : ratio.ratio < 0.99 ? "vertical" : "square"
    }

    static let adExtraLead = "\nAdditional direction (never render it as text): "

    static func adPrompt(_ tool: AdTool, settings: AdSettings, text: String, overrides: [Int: String] = [:],
                         extra: [String: String] = [:]) -> String {
        func value(_ index: Int) -> String { overrides[index] ?? settings.choice(index) }
        var prompt = tool.recipe
            .replacingOccurrences(of: "{option3}", with: value(2))
            .replacingOccurrences(of: "{option2}", with: value(1))
            .replacingOccurrences(of: "{option}", with: value(0))
            .replacingOccurrences(of: "{text2}", with: adCopy(settings.text2.trimmingCharacters(in: .whitespacesAndNewlines), tool.text2))
            .replacingOccurrences(of: "{text}", with: adCopy(text, tool.text))
        for (key, value) in extra { prompt = prompt.replacingOccurrences(of: "{\(key)}", with: value) }
        if let product = settings.product {
            prompt += "\nThe product is \u{201C}\(product.name)\u{201D}" + (product.details.isEmpty ? "." : ": \(product.details)")
        }
        prompt += brandDirection(settings)
        let direction = settings.extra.trimmingCharacters(in: .whitespacesAndNewlines)
        if !direction.isEmpty { prompt += adExtraLead + direction }
        return prompt
    }

    static func adCopy(_ text: String, _ field: AdTextField?) -> String {
        guard field?.pipeSeparated == true, text.contains(where: \.isNewline) else { return text }
        return text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " | ")
    }

    func adPromptOverhead(_ tool: AdTool, state: AdState, includingExtra: Bool = true) -> Int {
        var settings = adSettings(tool, state: state)
        settings.text = ""
        settings.text2 = ""
        if !includingExtra { settings.extra = "" }
        var extra: [String: String] = [:]
        if tool.isCarousel {
            let count = adImageCount(tool, state: state)
            let beat = Self.carouselBeats(story: settings.choice(0), count: count).max { $0.utf16.count < $1.utf16.count } ?? ""
            extra = ["index": "\(count)", "count": "\(count)", "beat": beat, "caption": ""]
        }
        return Self.adPrompt(tool, settings: settings, text: "", extra: extra).utf16.count
    }

    func runAd(_ tool: AdTool, state: AdState, model: ImageModel) {
        switch tool.kind {
        case .batch: return runAdBatch(tool, state: state, model: model)
        case .resize, .translate: return runAdVariants(tool, state: state, model: model)
        case .multiply: return runAdMultiply(tool, state: state, model: model)
        case .single, .headlines: break
        }
        let base = adSettings(tool, state: state)
        let inputs = adInputs(tool, state: state, settings: base)
        let packed = inputs.withLogo(model.maxReferences)
        var adjusted = base
        adjusted.logoAttached = packed.hasLogo
        let settings = adjusted
        guard inputs.productCount(within: model.maxReferences) > 0 else {
            presentError(FreefieldError.unsupported(L("No product photo could be sent. Choose the product again or add a product photo.")))
            return
        }
        if let message = engine.limitMessage(model: model, resolution: .oneK, images: adImageCount(tool, state: state)) {
            presentError(FreefieldError.limitReached(message))
            return
        }
        let images = packed.images
        var descriptions = [settings.product?.details ?? "", settings.brand?.trimmedTone ?? ""]
        if tool.text?.isLiteral == false { descriptions.append(settings.text) }
        if tool.text2?.isLiteral == false { descriptions.append(settings.text2) }
        descriptions.append(settings.extra)
        let userTexts = descriptions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let literalTexts = Self.adLiterals(tool, settings: settings)

        func spec(_ prompt: String, images: [InputImage], count: Int, suffix: String = "", recordSuffix: String? = nil) -> JobSpec {
            var spec = JobSpec(tool: .ad, title: tool.name + suffix, prompt: prompt, model: model,
                               aspectRatio: settings.aspect, resolution: .oneK, count: count, images: images,
                               characterID: settings.character?.id, productID: settings.product?.id, appID: tool.id)
            spec.record = english(tool.name) + (recordSuffix ?? suffix)
            spec.userTexts = userTexts
            spec.literalTexts = literalTexts
            return spec
        }

        if tool.makesFullSet(settings.choice(0)) {
            let text = settings.text.trimmingCharacters(in: .whitespacesAndNewlines)
            for type in AdTool.listingSet {
                let prompt = Self.adPrompt(tool, settings: settings, text: type == "Feature callouts" ? text : "", overrides: [0: type])
                engine.start(spec(prompt, images: images, count: 1, suffix: " · " + tool.options[0].shortLabel(type), recordSuffix: " · " + type))
            }
        } else if tool.isCarousel {
            runCarousel(tool, settings: settings, inputs: inputs, model: model) { spec($0, images: $1, count: $2, suffix: $3) }
        } else if tool.isUnboxing, settings.choice(2) == "3-photo sequence" {
            let moments = Array(tool.options[0].values.prefix(3))
            runSequence(moments.indices.map { index in
                { previous in
                    let prompt = Self.adPrompt(tool, settings: settings, text: "", overrides: [0: moments[index]])
                    return spec(prompt, images: Self.sequenceImages(inputs, previous: previous, limit: model.maxReferences),
                                count: 1, suffix: " · \(index + 1)/3")
                }
            })
        } else if tool.text?.onePerLine == true {
            let lines = Self.lines(settings.text)
            for (index, line) in (lines.isEmpty ? [""] : lines).enumerated() {
                let variant = tool.kind == .headlines ? " · " + Self.variantLetter(index) : ""
                engine.start(spec(Self.adPrompt(tool, settings: settings, text: line), images: images, count: settings.count,
                                  suffix: line.isEmpty ? variant : variant + " · \(line.prefix(40))"))
            }
        } else {
            let text = settings.text.trimmingCharacters(in: .whitespacesAndNewlines)
            engine.start(spec(Self.adPrompt(tool, settings: settings, text: text), images: images, count: settings.count))
        }
    }

    static func suggestsCopy(_ tool: AdTool, field: AdTextField) -> Bool {
        guard field.role == .copy, field.isLiteral else { return false }
        switch tool.id {
        case "static-ad", "hook-frame", "carousel": return true
        case "marketplace": return field == tool.text
        case "ad-headlines": return field == tool.text2
        default: return false
        }
    }

    func suggestAdCopy(_ tool: AdTool, field: AdTextField, state: AdState) async throws -> [String] {
        let product = library.product(state.productID)
        var images: [InputImage] = []
        if product == nil, let photo = state.productPhoto.flatMap({ ImageCoding.prepareForUpload($0, maxPixel: 512, role: "product") }) {
            images = [photo]
        }
        guard product != nil || !images.isEmpty else { throw FreefieldError.unsupported(L("Choose a product first.")) }
        let language = VideoCatalog.interfaceLanguage
        let format = state.choice(0, in: tool)
        let ask: String
        var isSet = false
        switch (tool.kind == .headlines ? "static-ad" : tool.id, field == tool.text) {
        case ("static-ad", true):
            ask = "Write 5 different headlines for a \(format) static ad, each under 8 words. One headline per line."
        case ("static-ad", false):
            isSet = true
            let parts = Self.supportingParts(format)
            ask = "Write 3 alternative sets of supporting copy for a \(format) static ad. Each set is \(parts), under 6 words each. One set per line, its parts separated by \" | \"."
        case ("hook-frame", _):
            ask = "Write 6 different hook lines for the first second of a vertical video ad: curiosity, a relatable problem or a surprising result, in the voice of a real person, each under 10 words. One hook per line."
        case ("carousel", _):
            isSet = true
            let count = Int(state.choice(1, in: tool)) ?? 5
            let slides = Self.carouselSlideNames(story: state.choice(0, in: tool), count: count).map(english).joined(separator: ", ")
            ask = "Write 2 alternative sets of captions for a \(count)-slide social carousel (\(english(state.choice(0, in: tool)))). The slides, in order: \(slides). Each caption is under 7 words. One set per line, its \(count) captions separated by \" | \"."
        default:
            if format == "Styled cover" {
                ask = "Write 4 different short headlines for a product listing cover image, each under 6 words. One headline per line."
            } else {
                isSet = true
                ask = "Write 3 alternative sets of feature callouts for a product listing image. Each set is 3 or 4 callouts of 1 to 4 words, each about a real part or feature of the product. One set per line, its callouts separated by \" | \"."
            }
        }
        var user = ""
        if let product {
            user = "Product: \(product.name)" + (product.details.isEmpty ? "" : "\nDetails: \(product.details)")
        } else {
            user = "The product is in the attached photo."
        }
        let text = try await helperComplete(
            title: E("Suggest ad copy"), tool: .ad,
            system: "You are a direct-response copywriter. \(ask) Write in \(language). \(Self.copyRules)" + Self.brandVoice(tool.usesBrand ? BrandStore.shared.brand(state.brandID) : nil),
            user: user, images: images
        )
        let options = text.split(whereSeparator: \.isNewline)
            .map { String($0).replacingOccurrences(of: #"^\s*(?:[-•*]+\s+|\d+[.)](?!\d)\s*)"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "**", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”").union(.whitespaces)) }
            .filter { !$0.isEmpty && (!isSet || $0.contains("|")) }
        guard !options.isEmpty else { throw FreefieldError.unsupported(L("The AI returned no suggestions.")) }
        return Array(options.prefix(6))
    }

    static let copyRules = "Plain words a real brand would print, no hashtags, no emojis, no quotation marks. Never invent numbers, prices, discounts, ratings, reviews, testimonials, awards, certifications or claims that the product details don't state."

    static func supportingParts(_ format: String) -> String {
        switch format {
        case "Benefit bullets": "3 or 4 short benefit lines"
        case "Us vs. them": "3 or 4 short comparison rows, each naming one way this product beats a generic alternative"
        case "Offer / price": "a short offer line, then a short call to action (only an offer the details mention; otherwise a call to action alone)"
        default: "2 or 3 short supporting lines, the last one a call to action"
        }
    }

    static func brandVoice(_ brand: BrandKit?) -> String {
        guard let brand else { return "" }
        var text = " The brand is \u{201C}\(brand.name)\u{201D}."
        if !brand.trimmedTone.isEmpty { text += " Write in the brand's tone of voice: \(brand.trimmedTone)." }
        if !brand.trimmedAbout.isEmpty { text += " About the brand: \(brand.trimmedAbout)" }
        return text
    }

    static func productBrief(_ product: Product) -> String {
        "Product: \(product.name)" + (product.details.isEmpty ? "" : "\nDetails: \(product.details)")
    }

    static func variantLetter(_ index: Int) -> String {
        index < 26 ? String(UnicodeScalar(UInt8(65 + index))) : "\(index + 1)"
    }

    static func cleanLines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { String($0).replacingOccurrences(of: #"^\s*(?:[-•*]+\s+|\d+[.)](?!\d)\s*|[A-J][.):]\s+)"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "**", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”").union(.whitespaces)) }
            .filter { !$0.isEmpty }
    }

    func writeHeadlines(_ tool: AdTool, state: AdState) async throws -> [String] {
        let product = library.product(state.productID)
        var images: [InputImage] = []
        if product == nil, let photo = state.productPhoto.flatMap({ ImageCoding.prepareForUpload($0, maxPixel: 512, role: "product") }) {
            images = [photo]
        }
        guard product != nil || !images.isEmpty else { throw FreefieldError.unsupported(L("Choose a product first.")) }
        let count = min(max(state.headlineCount, 2), 10)
        let ask = "Write \(count) different headlines for an A/B test of a \(state.choice(0, in: tool)) static ad (scene angle: \(state.choice(1, in: tool))). Each headline is under 8 words and tests a different approach: the main benefit, the everyday problem it solves, curiosity, the end result, a direct question, a simple promise the details support, and so on. One headline per line, nothing else."
        let text = try await helperComplete(
            title: E("Write headline variants"), tool: .ad,
            system: "You are a direct-response copywriter. \(ask) Write in \(VideoCatalog.interfaceLanguage). \(Self.copyRules)" + Self.brandVoice(BrandStore.shared.brand(state.brandID)),
            user: product.map(Self.productBrief) ?? "The product is in the attached photo.", images: images
        )
        var seen = Set<String>()
        let headlines = Self.cleanLines(text).filter { !$0.contains("|") && seen.insert($0.lowercased()).inserted }
        guard !headlines.isEmpty else { throw FreefieldError.unsupported(L("The AI returned no suggestions.")) }
        return Array(headlines.prefix(count))
    }

    func batchCopy(for product: Product, format: String, angles: [String], brand: BrandKit?) async throws -> [String: (headline: String, lines: String)] {
        let list = angles.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let ask = "Write the copy for \(angles.count) static ads for the product below, one ad per selling angle, in this order:\n\(list)\nFormat of every ad: \(format). For each ad write one line: a headline under 8 words, then \" | \", then \(Self.supportingParts(format)), under 6 words each, separated by \" | \". Each headline speaks to its own selling angle. One ad per line, in the same order, with no numbering and nothing else."
        let text = try await helperComplete(
            title: E("Write ad batch copy"), tool: .ad,
            system: "You are a direct-response copywriter. \(ask) Write in \(VideoCatalog.interfaceLanguage). \(Self.copyRules)" + Self.brandVoice(brand),
            user: Self.productBrief(product)
        )
        let rows = Self.cleanLines(text).filter { $0.contains("|") }
        var copy: [String: (headline: String, lines: String)] = [:]
        for (angle, row) in zip(angles, rows) {
            let parts = row.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard let headline = parts.first else { continue }
            copy[angle] = (headline, parts.dropFirst().joined(separator: " | "))
        }
        guard !copy.isEmpty else { throw FreefieldError.unsupported(L("The AI returned no suggestions.")) }
        return copy
    }

    private func adSpec(_ tool: AdTool, title: String, record: String, prompt: String, model: ImageModel, settings: AdSettings,
                        images: [InputImage], count: Int = 1, userTexts: [String], literalTexts: [String]) -> JobSpec {
        var spec = JobSpec(tool: .ad, title: tool.name + title, prompt: prompt, model: model,
                           aspectRatio: settings.aspect, resolution: .oneK, count: count, images: images,
                           characterID: settings.character?.id, productID: settings.product?.id, appID: tool.id)
        spec.record = english(tool.name) + record
        spec.userTexts = userTexts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        spec.literalTexts = literalTexts.filter { !$0.isEmpty }
        return spec
    }

    private func runAdBatch(_ tool: AdTool, state: AdState, model: ImageModel) {
        let products = batchProducts(state)
        let angles = state.picks(1, in: tool)
        let sizes = state.picks(2, in: tool).compactMap(AspectRatio.init(rawValue:))
        let total = products.count * angles.count * sizes.count
        guard total > 0 else { return }
        if let message = engine.limitMessage(model: model, resolution: .oneK, images: total) {
            presentError(FreefieldError.limitReached(message))
            return
        }
        let base = adSettings(tool, state: state)
        let format = base.choice(0)
        let writes = adWritesCopy(tool, state: state)
        state.isPreparing = true
        Task {
            defer { state.isPreparing = false }
            for product in products {
                var copy: [String: (headline: String, lines: String)] = [:]
                if writes {
                    do {
                        copy = try await batchCopy(for: product, format: format, angles: angles, brand: base.brand)
                    } catch {
                        presentError(error)
                        return
                    }
                }
                var settings = base
                settings.product = product
                var inputs = AdInputs()
                inputs.product = library.productImages(for: product, limit: 3)
                if tool.placesLogo, state.addsLogo, let brand = base.brand,
                   let logo = BrandStore.shared.logoData(brand).flatMap({ ImageCoding.deferredUpload($0, maxPixel: 1024, role: "brand logo") }) {
                    inputs.logo = [logo]
                }
                guard inputs.productCount(within: model.maxReferences) > 0 else { continue }
                let packed = inputs.withLogo(model.maxReferences)
                settings.logoAttached = packed.hasLogo
                for angle in angles {
                    let words = copy[angle]
                    settings.text = words?.headline ?? ""
                    settings.text2 = words?.lines ?? ""
                    for size in sizes {
                        settings.aspect = size
                        let prompt = Self.adPrompt(tool, settings: settings, text: settings.text, overrides: [1: angle])
                        let label = " · \(product.name.prefix(30)) · \(tool.options[1].shortLabel(angle)) · \(size.rawValue)"
                        engine.start(adSpec(tool, title: label, record: " · \(product.name.prefix(30)) · \(angle) · \(size.rawValue)",
                                            prompt: prompt, model: model, settings: settings, images: packed.images,
                                            userTexts: [product.details, settings.extra, base.brand?.trimmedTone ?? ""],
                                            literalTexts: [settings.text, settings.text2]))
                    }
                }
            }
        }
    }

    private func runAdVariants(_ tool: AdTool, state: AdState, model: ImageModel) {
        guard let reference = state.reference.flatMap({ ImageCoding.deferredUpload($0, role: "finished ad") }) else { return }
        let values = state.picks(0, in: tool)
        guard !values.isEmpty else { return }
        if let message = engine.limitMessage(model: model, resolution: .oneK, images: values.count) {
            presentError(FreefieldError.limitReached(message))
            return
        }
        var settings = adSettings(tool, state: state)
        settings.product = nil
        settings.character = nil
        for value in values {
            if tool.kind == .resize { settings.aspect = AspectRatio(rawValue: value) ?? settings.aspect }
            let prompt = Self.adPrompt(tool, settings: settings, text: "", overrides: [0: value], extra: ["shape": Self.shape(value)])
            let label = tool.kind == .resize ? value : tool.options[0].shortLabel(value)
            engine.start(adSpec(tool, title: " · " + label, record: " · " + value, prompt: prompt, model: model, settings: settings,
                                images: [reference], userTexts: [settings.extra], literalTexts: []))
        }
    }

    private func runAdMultiply(_ tool: AdTool, state: AdState, model: ImageModel) {
        guard let reference = state.reference.flatMap({ ImageCoding.deferredUpload($0, role: "winning ad") }) else { return }
        var settings = adSettings(tool, state: state)
        let swap = settings.choice(0)
        var swapped: [InputImage] = []
        switch swap {
        case "Product":
            settings.character = nil
            if let product = settings.product {
                swapped = library.productImages(for: product, limit: 3)
            } else if let photo = state.productPhoto.flatMap({ ImageCoding.deferredUpload($0, role: "product") }) {
                swapped = [photo]
            }
        case "Person":
            settings.product = nil
            if let character = settings.character {
                swapped = library.referenceImages(for: character, limit: 3)
            } else if let photo = state.personPhoto.flatMap({ ImageCoding.deferredUpload($0, role: "person") }) {
                swapped = [photo]
            }
        default:
            settings.product = nil
            settings.character = nil
            swapped = state.swapPhoto.flatMap { ImageCoding.deferredUpload($0, role: swap.lowercased()) }.map { [$0] } ?? []
        }
        guard !swapped.isEmpty || swap == "Location" else {
            presentError(FreefieldError.unsupported(L("Add what you want to swap in.")))
            return
        }
        if let message = engine.limitMessage(model: model, resolution: .oneK, images: settings.count) {
            presentError(FreefieldError.limitReached(message))
            return
        }
        let text = settings.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = Self.adPrompt(tool, settings: settings, text: text, extra: ["swap": swap.lowercased()])
        let images = Array(([reference] + swapped).prefix(max(1, model.maxReferences)))
        engine.start(adSpec(tool, title: " · " + tool.options[0].shortLabel(swap), record: " · " + swap, prompt: prompt, model: model,
                            settings: settings, images: images, count: settings.count,
                            userTexts: [settings.product?.details ?? "", settings.extra], literalTexts: Self.adLiterals(tool, settings: settings)))
    }

    static func adLiterals(_ tool: AdTool, settings: AdSettings) -> [String] {
        var literals: [String] = []
        if let field = tool.text, field.isLiteral {
            literals += tool.isCarousel ? carouselCaptions(settings.text)
                : field.onePerLine ? lines(settings.text) : [adCopy(settings.text.trimmingCharacters(in: .whitespacesAndNewlines), field)]
        }
        if let field = tool.text2, field.isLiteral {
            literals.append(adCopy(settings.text2.trimmingCharacters(in: .whitespacesAndNewlines), field))
        }
        return literals.filter { !$0.isEmpty }
    }

    private func runCarousel(_ tool: AdTool, settings: AdSettings, inputs: AdInputs, model: ImageModel,
                             make: @escaping (String, [InputImage], Int, String) -> JobSpec) {
        let count = Int(settings.choice(1)) ?? 5
        let beats = Self.carouselBeats(story: settings.choice(0), count: count)
        let captions = Self.carouselCaptions(settings.text)
        runSequence((0..<count).map { index in
            { previous in
                let prompt = Self.adPrompt(tool, settings: settings, text: "", extra: [
                    "index": "\(index + 1)", "count": "\(count)", "beat": beats[index],
                    "caption": index < captions.count ? captions[index] : "",
                ])
                return make(prompt, Self.sequenceImages(inputs, previous: previous, limit: model.maxReferences), 1, " · \(index + 1)/\(count)")
            }
        }, keepFirst: true)
    }

    static func carouselCaptions(_ text: String) -> [String] {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        return text.split(omittingEmptySubsequences: false) { $0 == "|" || $0.isNewline }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    static func carouselSlideNames(story: String, count: Int) -> [String] {
        carouselBeats(story: story, count: count).enumerated().map { index, beat in
            if story.hasPrefix("How to use") { return L("Step %ld", index + 1) }
            if story.hasPrefix("Photo dump") { return L("Moment %ld", index + 1) }
            switch beat.prefix(while: { $0 != ":" }) {
            case "Hook": return L("Hook")
            case "Problem": return L("Problem")
            case "Product": return L("Product")
            case "Proof": return L("Proof")
            default: return L("Offer")
            }
        }
    }

    static func sequenceImages(_ inputs: AdInputs, previous: [InputImage], limit: Int) -> [InputImage] {
        Array((inputs.prefix(max(1, limit - previous.count)) + previous).prefix(limit))
    }

    private func runSequence(_ steps: [([InputImage]) -> JobSpec], keepFirst: Bool = false) {
        func run(_ index: Int, first: InputImage?, previous: InputImage?) {
            guard index < steps.count else { return }
            let attached = [keepFirst ? first : nil, previous].compactMap { $0 }
            let job = engine.start(steps[index](uniqueFrames(attached)))
            guard job.isRunning else {
                let left = steps.count - index - 1
                if left > 0, case .failed(let message) = job.status {
                    let note = left == 1 ? L("The next image in this run was not made.") : L("The next %ld images in this run were not made.", left)
                    job.status = .failed(message + " " + note)
                }
                return
            }
            job.onFinish = { [weak self] job in
                guard let self else { return }
                let frame = self.frame(from: job)
                guard frame == nil, job.sawRateLimit else {
                    return run(index + 1, first: first ?? frame, previous: frame ?? previous)
                }
                Task {
                    try? await Task.sleep(for: .seconds(20))
                    guard self.engine.jobs.contains(where: { $0.id == job.id }) else { return }
                    run(index + 1, first: first, previous: previous)
                }
            }
        }
        run(0, first: nil, previous: nil)
    }

    private func frame(from job: Job) -> InputImage? {
        guard let id = job.assetIDs.first, let asset = library.asset(id),
              let data = try? Data(contentsOf: library.url(for: asset)) else { return nil }
        return ImageCoding.deferredUpload(data, maxPixel: 1280, role: "previous frame")
    }

    private func uniqueFrames(_ frames: [InputImage]) -> [InputImage] {
        var seen = Set<Data>()
        return frames.filter { seen.insert($0.data).inserted }
    }

    static func lines(_ text: String) -> [String] {
        Array(text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(10))
    }

    static func carouselBeats(story: String, count: Int) -> [String] {
        if story.hasPrefix("How to use") {
            return (1...count).map { "Step \($0) of \(count): the hands perform this step of using the product, in order" }
        }
        if story.hasPrefix("Photo dump") {
            let moments = ["morning coffee", "getting ready", "at the desk", "outside in daylight", "an evening wind-down",
                           "out with friends", "a quiet moment before bed"]
            return (0..<count).map { "A candid moment: \(moments[$0 % moments.count]), with the product appearing naturally" }
        }
        let hook = "Hook: a scroll-stopping image that makes people want to swipe"
        let problem = "Problem: the everyday problem, without the product"
        let product = "Product: the product hero, in hand"
        let proof = "Proof: the product in use, with its visible result"
        let offer = "Offer: a clean product hero with space for a call to action"
        switch count {
        case ...3: return Array([hook, product, offer].prefix(max(1, count)))
        case 4: return [hook, problem, product, offer]
        case 5: return [hook, problem, product, proof, offer]
        default: return [hook, problem, product] + Array(repeating: proof, count: count - 4) + [offer]
        }
    }
}
