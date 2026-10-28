import FreefieldCore
import SwiftUI

extension AppModel {
    func runStoryboard(_ state: ComposerState, scenes texts: [String], model: ImageModel) {
        let preset = state.presetID.flatMap(StylePresets.preset)
        let character = library.character(state.characterID)
        var images: [InputImage] = []
        if let character { images = library.referenceImages(for: character, limit: min(3, model.maxReferences)) }
        let characterCount = images.count
        images += state.references.compactMap { ImageCoding.deferredUpload($0, role: "reference") }
        images = Array(images.prefix(model.maxReferences))
        let referenceCount = images.count - characterCount
        let style = StoryboardView.templates.first { $0.id == state.storyTemplate }?.style ?? ""
        let base = state.story.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = style.isEmpty ? base : "\(base) Look: \(style)."
        let aspectRatio = state.aspectRatio, resolution = state.resolution, seed = state.seed
        func spec(_ index: Int, references: [InputImage], anchor: Bool) -> JobSpec {
            var prompt = Recipes.storyboard(scene: texts[index], index: index, total: texts.count,
                                            context: context.isEmpty ? "A cinematic short story." : context,
                                            preset: preset, character: character,
                                            characterImageCount: characterCount, referenceCount: referenceCount)
            if anchor {
                prompt += "\n\nThe last attached image is shot 1 of this sequence: keep its characters (faces, hair, wardrobe), art style, palette and world identical, but compose this shot as described, not as a copy of shot 1."
            }
            var spec = JobSpec(
                tool: .storyboard,
                title: L("Scene %ld: %@", index + 1, texts[index]),
                prompt: prompt,
                model: model,
                aspectRatio: aspectRatio,
                resolution: resolution,
                count: 1,
                seed: seed,
                images: Array(references.prefix(model.maxReferences)),
                presetID: preset?.id,
                characterID: character?.id
            )
            spec.record = E("Scene %ld: %@", index + 1, texts[index])
            spec.userTexts = ((index == 0 ? texts : [texts[index]]) + [base, character?.name ?? "", character?.details ?? ""])
                .filter { !$0.isEmpty }
            return spec
        }
        guard !texts.isEmpty else { return }
        if let message = engine.limitMessage(model: model, resolution: resolution, images: texts.count) {
            presentError(FreefieldError.limitReached(message))
            return
        }
        let first = engine.start(spec(0, references: images, anchor: false))
        guard texts.count > 1 else { return }
        let canAnchor = model.acceptsImageInput && images.count < model.maxReferences
        first.onFinish = { [weak self] job in
            guard let self else { return }
            var references = images
            var anchored = false
            if canAnchor, let assetID = job.assetIDs.first, let asset = self.library.asset(assetID),
               let data = try? Data(contentsOf: self.library.url(for: asset)),
               let frame = ImageCoding.deferredUpload(data, maxPixel: 1536, role: "frame1") {
                references.append(frame)
                anchored = true
            }
            for index in 1..<texts.count {
                self.engine.start(spec(index, references: references, anchor: anchored))
            }
        }
    }

    func writeStoryScenes(_ state: ComposerState) async throws -> [String] {
        let templateName = english(StoryboardView.templates.first { $0.id == state.storyTemplate }?.name ?? "")
        let text = try await helperComplete(
            title: E("Write storyboard scenes"), tool: .storyboard,
            system: "You are a storyboard artist. Split the story into exactly \(state.storyFrames) shots for a \(templateName) storyboard. Each shot becomes a separate image, so each line must stand on its own: who is in it (named the same way every time), what they do, where, and the shot size or angle (wide, medium, close-up, low angle…). Vary shot sizes across the sequence. Describe only what the camera sees, with no dialogue, sounds, captions or on-screen text. Same language as the story, under 30 words per line. Reply with one shot per line, no numbering.",
            user: state.story
        )
        let lines = text.split(whereSeparator: \.isNewline)
            .map { String($0).replacingOccurrences(of: #"^\s*(?:[-•*]+\s+|\d+[.)](?!\d)\s*)"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "**", with: "") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { throw FreefieldError.unsupported(L("The AI returned no scenes.")) }
        return Array(lines.prefix(8))
    }

    func runPhotoSession(_ state: ComposerState, set: PhotoSessionSet, model: ImageModel, character: Character) {
        let references = library.referenceImages(for: character, limit: min(4, model.maxReferences))
        let scenes = set.scenes.shuffled().prefix(state.sessionShots)
        let extra = state.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if let message = engine.limitMessage(model: model, resolution: .oneK, images: scenes.count) {
            presentError(FreefieldError.limitReached(message))
            return
        }
        for scene in scenes {
            var spec = JobSpec(
                tool: .photoSession,
                title: "\(set.name): \(scene)",
                prompt: photoSessionPrompt(scene: scene, character: character, characterImageCount: references.count, extra: extra),
                model: model,
                aspectRatio: state.aspectRatio,
                count: 1,
                images: references,
                characterID: character.id
            )
            spec.record = "\(english(set.name)): \(scene)"
            spec.userTexts = [character.name, character.details, extra].filter { !$0.isEmpty }
            engine.start(spec)
        }
    }

    func photoSessionPrompt(scene: String, character: Character?, characterImageCount: Int, extra: String) -> String {
        var prompt = Recipes.create(prompt: "Generate a candid smartphone photo for a social media photo dump: the person \(scene). Casual, slightly imperfect framing, natural available light, true-to-life color, subtle grain and real skin texture with visible pores. No heavy retouching, no text.",
                                    preset: nil, character: character, referenceCount: 0, characterImageCount: characterImageCount)
        if !extra.isEmpty { prompt += "\nAlso: \(extra)" }
        return prompt
    }

    func photoSessionOverhead(set: PhotoSessionSet, character: Character?) -> Int {
        let scene = set.scenes.max { $0.utf16.count < $1.utf16.count } ?? ""
        return photoSessionPrompt(scene: scene, character: character, characterImageCount: 4, extra: "").utf16.count
            + "\nAlso: ".utf16.count
    }

    func runApp(_ item: AppItem, inputs: [Data], option: String?, text: String, extra: String = "", model: ImageModel,
                aspect: AspectRatio, count: Int) {
        let images = inputs.compactMap { ImageCoding.deferredUpload($0, role: "input") }
        let extra = item.takesExtraInstructions ? extra.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let prompt = item.prompt(option: option, text: text.trimmingCharacters(in: .whitespacesAndNewlines), extra: extra)
        var spec = JobSpec(
            tool: .app, title: item.name + (option.map { " · \(L($0))" } ?? ""), prompt: prompt, model: model,
            aspectRatio: aspect, resolution: item.resolution, count: count, images: images, appID: item.id
        )
        spec.record = english(item.name) + (option.map { " · \($0)" } ?? "")
        let typed = [text.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }
        if item.textIsLiteral { spec.literalTexts = typed } else { spec.userTexts = typed }
        if !extra.isEmpty { spec.userTexts.append(extra) }
        engine.start(spec)
    }
}
