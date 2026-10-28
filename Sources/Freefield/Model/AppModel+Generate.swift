import AppKit
import FreefieldCore
import NaturalLanguage
import SwiftUI

extension AppModel {
    static let enhancerInstructions = """
    You rewrite a user's idea as one image-generation prompt that works on any modern image model. \
    Write 2–5 connected sentences of plain English description, 40–90 words, in this order, skipping what the user did not imply: \
    what the image is for, the main subject with concrete materials, colors and counts, the action, the setting, the shot size and camera angle, \
    the style or medium, and the light (source, direction, quality). If the idea is already a detailed prompt, change as little as possible. \
    Keep every name, number, constraint and detail the user gave. Put text that must appear in the image in straight double quotes, \
    verbatim and in its original language, and never add text, logos or brands they did not ask for. \
    Describe what should be there instead of what should not ("an empty street", not "no cars"). \
    Use no quality tags such as 8k, masterpiece, ultra-detailed or award-winning, and use camera or lens terms only for photographic styles. \
    If images are attached, refer to each by what it shows ("the woman from the reference photo") and say what to take from it. \
    Reply with the prompt only, without surrounding quotation marks or preamble.
    """

    static let editEnhancerInstructions = """
    You rewrite a user's instruction for an AI image-editing tool as one precise English instruction that any modern image model follows. \
    Write one or two plain sentences, at most 50 words: what to change or add, where in the image, and how it should look (materials, colors, light). \
    Leave out everything the user did not ask to change; the tool already keeps the rest of the photo as it is. \
    Keep every name, number and detail the user gave, and keep text in quotation marks verbatim and in its original language. \
    Describe what should be there instead of what should not. Use no quality tags such as 8k or masterpiece. \
    If the instruction is already precise, change as little as possible. \
    Reply with the instruction only, without quotation marks or preamble.
    """

    static let videoEnhancerInstructions = """
    You rewrite a user's idea as one prompt for an AI video model. Write 1–3 connected sentences of plain English, at most 70 words, \
    in this order, skipping what the user did not imply: the subject and the one main action over the clip, the setting, \
    the camera (shot size and one movement), the style and the light. \
    If the tool changes an existing clip, rewrite the text instead as one precise instruction for that change. \
    Keep every name, number and detail the user gave, and keep words in quotation marks verbatim and in their original language \
    (they are spoken or shown exactly). Do not add dialogue, on-screen text, music, logos or brands the user did not ask for. \
    Describe what should be there instead of what should not. Use no quality tags such as 8k or masterpiece. \
    If the text is already a detailed prompt, change as little as possible. \
    Reply with the prompt only, without quotation marks or preamble.
    """

    static let helperEstimate = 0.001

    static var autoEnhancesDescriptions: Bool { UserDefaults.standard.bool(forKey: SettingsKey.autoEnhance) }

    static func enhancesDescription(of tool: Tool) -> Bool {
        switch tool {
        case .edit, .inpaint, .drawToEdit, .upscale, .relight, .angles, .expand, .background,
             .faceSwap, .characterSwap, .outfitSwap, .product: true
        default: false
        }
    }

    static func enhancesDescription(of tool: VideoTool) -> Bool {
        tool.engine == .model && (tool.takes(.prompt) || !enhanceableFields(of: tool).isEmpty)
    }

    static func enhanceableFields(of tool: VideoTool) -> [VideoTextField] {
        ["change"].compactMap(tool.textField).filter { !$0.isLiteral }
    }

    var helperModel: TextModel? {
        catalog.helperModel(preferredID: UserDefaults.standard.string(forKey: SettingsKey.helperModelID), provider: preferredProvider)
    }

    var automaticHelperModel: TextModel? {
        catalog.helperModel(preferredID: nil, provider: preferredProvider)
    }

    var helperModelChoices: [TextModel] {
        let preferred = ["gemini", "gpt-5", "claude", "qwen", "llama", "mistral"]
        return Provider.allCases.flatMap { catalog.textModels[$0] ?? [] }
            .filter { model in preferred.contains { model.modelID.localizedCaseInsensitiveContains($0) } }
            .prefix(60)
            .map { $0 }
    }

    func enhancePrompt(in state: ComposerState) async {
        guard !state.trimmedPrompt.isEmpty, helperModel != nil else { return }
        state.isEnhancing = true
        defer { state.isEnhancing = false }
        do {
            let limit = promptLimit(for: state.tool, state: state, model: resolvedModel(for: state, requirement: ModelRequirement(images: state.references.count)))
            state.prompt = String(try await enhance(state.trimmedPrompt).prefix(limit))
        } catch {
            presentError(error)
        }
    }

    func helperComplete(title: String, tool: Tool?, system: String, user: String, images: [InputImage] = []) async throws -> String {
        guard let helper = helperModel else { throw FreefieldError.unsupported(L("No text model is available for the AI assistant.")) }
        let estimate = Self.helperEstimate
        if let message = limitViolation(adding: estimate) { throw FreefieldError.limitReached(message) }
        let response = try await ImageService(keys: keys).complete(model: helper, system: system, user: user, images: images)
        library.record(UsageEntry(
            date: .now, kind: .text, tool: tool, title: english(title), modelID: helper.id, modelName: helper.name,
            provider: helper.provider, cost: response.cost ?? estimate, isEstimated: response.cost == nil,
            imageCount: 0, assetIDs: []
        ))
        return response.text
    }

    func enhance(_ prompt: String, images: [InputImage] = []) async throws -> String {
        guard helperModel != nil else { return prompt }
        let thumbnails = images.prefix(3).compactMap { ImageCoding.prepareForUpload($0.data, maxPixel: 768) }
        let text = try await helperComplete(title: E("Improve description"), tool: .create, system: Self.enhancerInstructions,
                                            user: prompt, images: Array(thumbnails))
        return text.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”").union(.whitespacesAndNewlines))
    }

    func enhanceInstruction(_ instruction: String, tool: Tool) async throws -> String {
        let text = try await helperComplete(title: E("Improve description"), tool: tool, system: Self.editEnhancerInstructions,
                                            user: "Tool: \(Self.toolPurpose(tool))\nInstruction: \(instruction)")
        return text.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”").union(.whitespacesAndNewlines))
    }

    func enhanceVideoDescriptions(_ inputs: inout VideoToolInputs, tool: VideoTool, model: VideoModel) async {
        if tool.takes(.prompt), !inputs.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let limit = VideoTextBudget.limit(tool, inputs: inputs, model: model)
            inputs.prompt = await enhancedVideoText(inputs.prompt, tool: tool, limit: limit)
        }
        for field in Self.enhanceableFields(of: tool) where tool.isShown(field.shownWhen, choices: inputs.choices) {
            let text = inputs.texts[field.id] ?? ""
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let limit = VideoTextBudget.limit(tool, inputs: inputs, model: model, field: field)
            inputs.texts[field.id] = await enhancedVideoText(text, tool: tool, limit: limit)
        }
    }

    private func enhancedVideoText(_ text: String, tool: VideoTool, limit: Int) async -> String {
        let user = "Tool: \(english(tool.name)) (\(english(tool.subtitle)))\nText: \(text)\nKeep it under \(limit) characters."
        guard let reply = try? await helperComplete(title: E("Improve description"), tool: .video, system: Self.videoEnhancerInstructions, user: user)
        else { return text }
        let better = reply.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”").union(.whitespacesAndNewlines))
        guard !better.isEmpty, better.utf16.count <= limit else { return text }
        return better
    }

    private static func toolPurpose(_ tool: Tool) -> String {
        switch tool {
        case .edit: "Edit: changes a photo as described."
        case .inpaint: "Inpaint: fills a painted area of the photo with what is described."
        case .drawToEdit: "Draw to Edit: an extra direction for an edit sketched on the photo."
        case .upscale: "Upscale: an extra direction for a sharper, larger copy of the photo."
        case .relight: "Relight: an extra direction for the photo's new lighting."
        case .angles: "Camera angles: an extra direction for the same scene seen from another angle."
        case .expand: "Expand: what appears in the new area around the photo."
        case .background: "Background: the new background behind the subject."
        case .faceSwap: "Face swap: an extra direction for the swapped face."
        case .characterSwap: "Character swap: an extra direction for the person placed in the scene."
        case .outfitSwap: "Outfit swap: an extra direction for how the garment is worn."
        case .product: "Product in scene: where and how the product is placed."
        default: "Image editing."
        }
    }

    func describe(_ asset: Asset) async -> String? {
        guard let data = library.imageData(for: asset),
              let image = ImageCoding.prepareForUpload(data, maxPixel: 1024) else { return nil }
        return try? await helperComplete(
            title: E("Describe image"), tool: asset.tool,
            system: "You turn an image into a reusable text-to-image prompt. Write 3–5 connected sentences of plain English, 60–110 words, in this order: what kind of image it is (photo, illustration, 3D render, poster…), the main subject with concrete materials, colors and counts, the action, the setting, the shot size and camera angle, the light (source, direction, quality, color) and the color palette, then the style, medium or film look. Quote any clearly legible text in straight double quotes exactly as written. Describe people by visible attributes only, never by name or identity. Name a lens or camera only when the image is photographic. No quality tags such as 8k, masterpiece or highly detailed. Reply with the prompt only.",
            user: "Write the prompt for this image.",
            images: [image]
        )
    }

    func runCreate(_ state: ComposerState, model: ImageModel) {
        let preset = state.presetID.flatMap(StylePresets.preset)
        let character = library.character(state.characterID)
        let product = library.product(state.productID)
        var images: [InputImage] = []
        if let character, model.acceptsImageInput {
            images += library.referenceImages(for: character, limit: primaryCharacterImageLimit(for: state, model: model))
        }
        let primaryCount = images.count
        let cast = sceneCast(for: state, model: model, firstImage: images.count + 1)
        images += cast.images
        let characterCount = images.count
        if let product, model.acceptsImageInput {
            images += library.productImages(for: product, limit: min(3, max(0, model.maxReferences - images.count)))
        }
        let productCount = images.count - characterCount
        images += state.references.compactMap { ImageCoding.prepareForUpload($0, role: "reference") }
        let sentReferenceCount = min(images.count, model.maxReferences) - characterCount - productCount
        let moodboard = library.moodboard(state.moodboardID)
        if let moodboard, model.acceptsImageInput {
            images += library.styleImages(for: moodboard, limit: 3)
        }
        images = Array(images.prefix(model.maxReferences))
        let styleCount = images.count - characterCount - productCount - sentReferenceCount
        let styleImages = styleCount > 0 ? (images.count - styleCount + 1)...images.count : nil
        let promptMoodboard = styleCount > 0 || moodboard?.styleDescription.isEmpty == false ? moodboard : nil
        let userPrompt = state.trimmedPrompt.isEmpty
            ? (preset.map { english($0.name) } ?? moodboard?.name ?? product?.name ?? "") : state.trimmedPrompt
        let title = state.trimmedPrompt.isEmpty ? (preset?.name ?? userPrompt) : userPrompt
        let references = state.references
        let shouldEnhance = Self.autoEnhancesDescriptions
        let camera = CinemaCamera.prompt(body: state.cameraBody, lens: state.cameraLens, focalLength: state.cameraFocalLength,
                                         aperture: state.cameraAperture)
        let palette = state.palette
        let aspectRatio = state.aspectRatio, resolution = state.resolution, count = state.count
        let seed = state.useSeed ? state.seed : nil
        let quality = model.qualities.isEmpty ? nil : state.quality
        let transparentBackground = state.transparentBackground

        Task {
            var prompt = userPrompt
            if shouldEnhance, !userPrompt.isEmpty {
                state.isEnhancing = true
                prompt = (try? await enhance(userPrompt, images: references.compactMap { ImageCoding.prepareForUpload($0, maxPixel: 768) })) ?? userPrompt
                state.isEnhancing = false
            }
            var recipe = Recipes.create(prompt: prompt, preset: preset, character: character, referenceCount: sentReferenceCount,
                                        camera: camera, palette: palette, moodboard: promptMoodboard, styleImages: styleImages,
                                        characterImageCount: primaryCount)
            if !cast.recipe.isEmpty {
                recipe += "\n" + cast.recipe
            }
            if let product, productCount > 0 {
                recipe += "\n" + Recipes.productReference(product, imageRange: (characterCount + 1)...(characterCount + productCount))
            }
            var spec = JobSpec(
                tool: .create,
                title: title,
                prompt: recipe,
                model: model,
                aspectRatio: aspectRatio,
                resolution: resolution,
                count: count,
                seed: seed,
                quality: quality,
                transparentBackground: transparentBackground,
                images: images,
                presetID: preset?.id,
                characterID: character?.id,
                productID: product?.id
            )
            spec.record = english(userPrompt)
            spec.userTexts = Array(Set([userPrompt, prompt, character?.name ?? "", character?.details ?? "", product?.details ?? ""]
                                       + cast.userTexts))
                .filter { !$0.isEmpty }
            spec.literalTexts = Array(Set(Recipes.quotedTexts(in: userPrompt) + Recipes.quotedTexts(in: prompt)))
            engine.start(spec)
        }
    }

    func translateUserTexts(_ original: JobSpec) async -> JobSpec {
        var spec = original
        if Self.autoEnhancesDescriptions, Self.enhancesDescription(of: spec.tool) {
            spec = await enhancingInstruction(spec)
        }
        let foreign = Array(Set(spec.userTexts)).filter(Self.isForeign).sorted { $0.count > $1.count }
        guard !foreign.isEmpty, helperModel != nil else { return spec }
        let tool = spec.tool
        let translations = await engine.translations.english(for: foreign) { [weak self] texts in
            await self?.requestTranslations(texts, tool: tool) ?? [:]
        }
        guard !translations.isEmpty else { return spec }
        var translated = spec
        var record = spec.record ?? english(spec.title)
        for original in foreign {
            guard let translation = translations[original] else { continue }
            translated.prompt = Self.replacing(original, with: translation, in: translated.prompt, keeping: spec.literalTexts)
            record = Self.replacing(original, with: translation, in: record, keeping: spec.literalTexts)
        }
        translated.record = record
        translated.userTexts = foreign.filter { translations[$0] == nil }
        return translated
    }

    private static let enhancements = TranslationCache()

    private func enhancingInstruction(_ spec: JobSpec) async -> JobSpec {
        guard let instruction = composers[spec.tool]?.trimmedPrompt, !instruction.isEmpty,
              spec.userTexts.contains(instruction), spec.prompt.contains(instruction), helperModel != nil else { return spec }
        let tool = spec.tool
        let key = "\(tool.rawValue)\u{1F}\(instruction)"
        let improved = await Self.enhancements.english(for: [key]) { [weak self] keys in
            guard let self, let better = try? await self.enhanceInstruction(instruction, tool: tool), !better.isEmpty else { return [:] }
            return Dictionary(uniqueKeysWithValues: keys.map { ($0, better) })
        }
        guard let better = improved[key] else { return spec }
        var enhanced = spec
        enhanced.prompt = Self.replacing(instruction, with: better, in: spec.prompt, keeping: spec.literalTexts)
        guard enhanced.prompt.utf16.count <= PromptBudget.modelLimit(spec.model) else { return spec }
        return enhanced
    }

    private func requestTranslations(_ texts: [String], tool: Tool) async -> [String: String] {
        guard let payload = try? String(decoding: JSONEncoder().encode(texts), as: UTF8.self),
              let reply = try? await helperComplete(title: E("Translate description to English"), tool: tool,
                                                    system: Self.translatorInstructions, user: payload),
              let start = reply.firstIndex(of: "["), let end = reply.lastIndex(of: "]"),
              let translations = try? JSONDecoder().decode([String].self, from: Data(reply[start...end].utf8)),
              translations.count == texts.count else { return [:] }
        return Dictionary(zip(texts, translations).filter { !$0.1.isEmpty }, uniquingKeysWith: { first, _ in first })
    }

    static func replacing(_ original: String, with replacement: String, in text: String, keeping literals: [String]) -> String {
        guard !original.isEmpty else { return text }
        let protected = literals.filter { !$0.isEmpty }.flatMap { literalRanges(of: $0, in: text) }
        var result = ""
        var cursor = text.startIndex
        for range in text.ranges(of: original) {
            let wrapsLiteral: (Range<String.Index>) -> Bool = { literal in
                range != literal && range.lowerBound <= literal.lowerBound && literal.upperBound <= range.upperBound
            }
            let keep = protected.contains { $0.overlaps(range) && !wrapsLiteral($0) }
            result += text[cursor..<range.lowerBound]
            result += keep ? String(text[range]) : replacement
            cursor = range.upperBound
        }
        return result + text[cursor...]
    }

    static func literalRanges(of literal: String, in text: String) -> [Range<String.Index>] {
        let all = text.ranges(of: literal)
        let quoted = all.filter { range in
            guard range.lowerBound > text.startIndex, range.upperBound < text.endIndex else { return false }
            let pair = (text[text.index(before: range.lowerBound)], text[range.upperBound])
            return pair == ("\"", "\"") || pair == ("\u{201C}", "\u{201D}")
        }
        return quoted.isEmpty ? all : quoted
    }

    static let translatorInstructions = """
    You translate text for an image-generation prompt into natural, precise English. You receive a JSON array of strings. \
    Translate each one, keeping its meaning, detail, order and tone; do not add, drop or explain anything. \
    Use the standard English term for photography, film and art vocabulary (for example "plano cenital" becomes "top-down shot"). \
    Keep exactly as written: proper names, brand names, numbers, units, hex color codes, references such as "Image 2", anything in angle brackets, \
    and anything inside quotation marks (that text will be drawn in the image). If a string is already English, return it unchanged. \
    Reply with only a valid JSON array of strings, same order and length, escaping inner quotation marks.
    """

    static func isForeign(_ text: String) -> Bool {
        guard text.count >= 4 else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, probability) = recognizer.languageHypotheses(withMaximum: 3).max(by: { $0.value < $1.value }) else { return false }
        return language != .english && probability > 0.55
    }

    func describeMoodboard(_ board: Moodboard) async {
        let images = library.styleImages(for: board, limit: 6).compactMap { ImageCoding.prepareForUpload($0.data, maxPixel: 768) }
        guard !images.isEmpty else { return }
        let text = try? await helperComplete(
            title: E("Analyze moodboard: %@", board.name), tool: .create,
            system: "You are an art director. Describe the visual style these images share, for an image generator, in 2–3 sentences of plain English, at most 45 words: color palette, light (direction, hardness, color), contrast, camera or film look, texture and composition habits. Describe the style only; never mention specific people, objects or places. No quality tags.",
            user: "Describe the common style.",
            images: images
        )
        if let text { library.setStyleDescription(text, for: board.id) }
    }

    func presentError(_ error: Error) {
        presentError(message: error.localizedDescription)
    }

    private func presentError(message: String) {
        guard let shown = presentedError else {
            presentedError = message
            return
        }
        guard shown != message else { return }
        Task {
            while presentedError != nil { try? await Task.sleep(for: .milliseconds(300)) }
            try? await Task.sleep(for: .milliseconds(300))
            presentError(message: message)
        }
    }
}

final class TranslationCache {
    private var known: [String: String] = [:]
    private var pending: [String: Task<[String: String], Never>] = [:]

    func english(for texts: [String], request: @escaping @Sendable @MainActor ([String]) async -> [String: String]) async -> [String: String] {
        let missing = texts.filter { known[$0] == nil && pending[$0] == nil }
        if !missing.isEmpty {
            let task = Task { await request(missing) }
            for text in missing { pending[text] = task }
        }
        var result: [String: String] = [:]
        for text in texts {
            if known[text] == nil, let task = pending[text] {
                for (original, translation) in await task.value { known[original] = translation }
                if pending[text] == task { pending[text] = nil }
            }
            if let translation = known[text] { result[text] = translation }
        }
        return result
    }
}
