import AppKit
import FreefieldCore
import SwiftUI

extension AppModel {
    func runTool(_ tool: Tool, state: ComposerState, model: ImageModel) {
        guard let sourceData = state.source,
              let source = ImageCoding.prepareForUpload(sourceData, role: "source") else { return }
        let instruction = state.trimmedPrompt
        let seed = state.useSeed ? state.seed : nil
        var spec = JobSpec(tool: tool, title: tool.title, prompt: "", model: model,
                           aspectRatio: state.aspectRatio, resolution: state.resolution, count: state.count,
                           seed: seed, quality: model.qualities.isEmpty ? nil : state.quality, images: [source])
        spec.userTexts = [instruction].filter { !$0.isEmpty }
        let extra = instruction.isEmpty ? "" : " · \(instruction)"

        switch tool {
        case .edit:
            let references = Array(state.references.compactMap { ImageCoding.prepareForUpload($0, role: "reference") }
                .prefix(max(0, model.maxReferences - 1)))
            spec.images += references
            spec.title = instruction
            spec.prompt = Recipes.edit(instruction, referenceCount: references.count)

        case .inpaint:
            guard let highlighted = CanvasRenderer.annotated(sourceData, strokes: state.strokes, notes: [], tint: .systemRed, alpha: 0.6),
                  let mask = ImageCoding.prepareForUpload(highlighted, role: "mask") else { return }
            spec.images = [source, mask]
            if instruction.isEmpty {
                spec.title = L("Erase the painted area")
                spec.record = E("Erase the painted area")
                spec.prompt = Recipes.erase()
            } else {
                spec.title = instruction
                spec.prompt = Recipes.inpaint(instruction)
            }

        case .drawToEdit:
            guard let annotated = CanvasRenderer.annotated(sourceData, strokes: state.strokes, notes: state.notes),
                  let sketch = ImageCoding.prepareForUpload(annotated, role: "sketch") else { return }
            spec.images = [source, sketch]
            let notes = state.notes.map(\.text).joined(separator: ", ")
            spec.userTexts += state.notes.map(\.text).filter { !$0.isEmpty }
            spec.title = [instruction, notes].filter { !$0.isEmpty }.joined(separator: " · ").nilIfEmpty ?? L("Draw Instructions")
            spec.record = [instruction, notes].filter { !$0.isEmpty }.joined(separator: " · ").nilIfEmpty ?? E("Draw Instructions")
            spec.prompt = Recipes.drawToEdit([instruction, notes.isEmpty ? "" : "The notes on Image 2 read: \(notes)"]
                .filter { !$0.isEmpty }.joined(separator: "\n"))

        case .upscale:
            spec.count = 1
            spec.aspectRatio = closestRatio(to: sourceData, in: model)
            spec.resolution = state.resolution == .oneK ? .fourK : state.resolution
            spec.title = L("Upscale %@", spec.resolution.rawValue) + extra
            spec.record = E("Upscale %@", spec.resolution.rawValue) + extra
            spec.prompt = Recipes.upscale(creativity: state.upscaleCreativity, extra: instruction)

        case .relight:
            let preset = LightPreset.preset(state.lightPreset)
            spec.title = L("Light: %@", preset.name) + extra
            spec.record = E("Light: %@", english(preset.name)) + extra
            spec.prompt = Recipes.relight(preset: preset, direction: state.lightDirection, color: state.lightColor,
                                          intensity: state.lightIntensity, hard: state.lightHard, extra: instruction)

        case .angles where state.anglesMode == "orbit":
            spec.title = L("Orbit: %ld° · tilt %ld° · zoom %.1f×", Int(state.orbitRotation), Int(state.orbitTilt), state.orbitZoom) + extra
            spec.record = E("Orbit: %ld° · tilt %ld° · zoom %.1f×", Int(state.orbitRotation), Int(state.orbitTilt), state.orbitZoom) + extra
            spec.prompt = Recipes.orbit(rotation: state.orbitRotation, tilt: state.orbitTilt, zoom: state.orbitZoom, extra: instruction)

        case .angles:
            let selected = CameraAngle.all.filter { state.angles.contains($0.id) }
            if let message = engine.limitMessage(model: model, resolution: spec.resolution, images: selected.count) {
                presentError(FreefieldError.limitReached(message))
                return
            }
            for angle in selected {
                var angleSpec = spec
                angleSpec.count = 1
                angleSpec.title = L("Angle: %@", angle.name) + extra
                angleSpec.record = E("Angle: %@", english(angle.name)) + extra
                angleSpec.prompt = Recipes.angle(angle, extra: instruction)
                engine.start(angleSpec)
            }
            return

        case .expand:
            guard let padded = Self.paddedCanvas(sourceData, ratio: state.expandTarget),
                  let canvas = ImageCoding.prepareForUpload(padded, role: "canvas") else { return }
            spec.images = [canvas]
            spec.aspectRatio = state.expandTarget
            spec.title = L("Expand to %@", state.expandTarget.label) + extra
            spec.record = E("Expand to %@", state.expandTarget.label) + extra
            spec.prompt = Recipes.expand(extra: instruction)

        case .background where state.backgroundMode == "remove":
            spec.count = 1
            if spec.aspectRatio == .auto { spec.aspectRatio = closestRatio(to: sourceData, in: model) }
            spec.transparentBackground = model.supportsTransparency
            spec.userTexts = []
            spec.title = L("Remove Background")
            spec.record = E("Remove Background")
            spec.prompt = Self.cutoutRecipe(transparent: model.supportsTransparency)

        case .background:
            spec.title = L("Background: %@", instruction)
            spec.record = E("Background: %@", instruction)
            spec.prompt = Recipes.replaceBackground(instruction)

        case .faceSwap:
            guard let face = state.secondary.flatMap({ ImageCoding.prepareForUpload($0, role: "face") }) else { return }
            spec.images = [source, face]
            spec.title = L("Face Swap") + extra
            spec.record = E("Face Swap") + extra
            spec.prompt = Recipes.faceSwap(keepExpression: state.swapKeepExpression, extra: instruction)

        case .characterSwap:
            var characterImages: [InputImage] = []
            var details = ""
            if let character = library.character(state.characterID) {
                characterImages = library.referenceImages(for: character, limit: 3)
                details = character.details
                spec.characterID = character.id
                spec.title = L("Character: %@", character.name)
                spec.record = E("Character: %@", character.name)
                spec.userTexts += [character.details].filter { !$0.isEmpty }
            } else if let photo = state.secondary.flatMap({ ImageCoding.prepareForUpload($0, role: "character") }) {
                characterImages = [photo]
                spec.title = L("Character Swap")
            }
            spec.images = [source] + characterImages
            spec.prompt = Recipes.characterSwap(details: details, extra: instruction)

        case .outfitSwap:
            guard let garment = state.secondary.flatMap({ ImageCoding.prepareForUpload($0, role: "garment") }) else { return }
            spec.images = [source, garment]
            spec.title = L("Outfit Swap") + extra
            spec.record = E("Outfit Swap") + extra
            spec.prompt = Recipes.outfitSwap(extra: instruction)

        case .editText:
            let edits = state.textEdits
                .filter { !$0.replacement.isEmpty && $0.replacement != $0.original }
                .map { ($0.original, $0.replacement) }
            guard !edits.isEmpty else { return }
            spec.title = edits.map { L("“%@” → “%@”", $0.0, $0.1) }.joined(separator: " · ") + extra
            spec.record = edits.map { E("“%@” → “%@”", $0.0, $0.1) }.joined(separator: " · ") + extra
            spec.prompt = Recipes.editText(edits, extra: instruction)
            spec.literalTexts = edits.flatMap { [$0.0, $0.1] }

        case .product:
            guard let product = state.secondary.flatMap({ ImageCoding.prepareForUpload($0, role: "product") }) else { return }
            if state.hasPaint, model.maxReferences >= 3,
               let zones = CanvasRenderer.annotated(sourceData, strokes: state.strokes, notes: [], tint: .systemRed, alpha: 0.6),
               let zonesImage = ImageCoding.prepareForUpload(zones, role: "zones") {
                spec.images = [source, zonesImage, product]
                spec.prompt = Recipes.placement(withZones: true, placement: instruction)
            } else {
                spec.images = [source, product]
                spec.prompt = Recipes.placement(withZones: false, placement: instruction)
            }
            spec.title = instruction.isEmpty ? L("Product in Scene") : instruction

        default:
            return
        }
        spec.images = Array(spec.images.prefix(max(1, model.maxReferences)))
        engine.start(spec)
    }

    private func closestRatio(to data: Data, in model: ImageModel) -> AspectRatio {
        guard let size = ImageCoding.pixelSize(of: data), size.height > 0 else { return .auto }
        let value = size.width / size.height
        let candidates = AspectRatio.standard.filter { $0 != .auto }
        let best = candidates.min { abs(log($0.ratio / value)) < abs(log($1.ratio / value)) } ?? .auto
        return model.aspectRatios.contains(.auto) ? .auto : best
    }

    static func paddedCanvas(_ data: Data, ratio: AspectRatio) -> Data? {
        guard let image = ImageCoding.cgImage(from: data, maxPixel: 1600) else { return nil }
        let sourceWidth = CGFloat(image.width), sourceHeight = CGFloat(image.height)
        var canvasWidth = sourceWidth / 0.8
        var canvasHeight = canvasWidth / ratio.ratio
        if canvasHeight < sourceHeight / 0.8 {
            canvasHeight = sourceHeight / 0.8
            canvasWidth = canvasHeight * ratio.ratio
        }
        let width = Int(canvasWidth.rounded()), height = Int(canvasHeight.rounded())
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: (canvasWidth - sourceWidth) / 2, y: (canvasHeight - sourceHeight) / 2,
                                       width: sourceWidth, height: sourceHeight))
        return context.makeImage().flatMap { ImageCoding.encode($0, as: .png) }
    }

    func readText(in data: Data) async throws -> [String] {
        let fingerprint = await AIChecks.fingerprint(data)
        if let known = AIChecks.textLines[fingerprint] { return known }
        guard let image = await AIChecks.upload(data, maxPixel: 1536) else {
            throw FreefieldError.unsupported(L("Couldn't read the image."))
        }
        let reply = try await helperComplete(title: E("Read text"), tool: .editText, system: AIChecks.textInstructions,
                                             user: "Read the text in this image.", images: [image])
        guard let lines = AIChecks.lines(from: reply) else {
            throw FreefieldError.unsupported(L("The AI's answer couldn't be read. Try again."))
        }
        AIChecks.textLines[fingerprint] = lines
        return lines
    }

    @concurrent
    nonisolated static func extractPalette(_ data: Data, count: Int = 5) async -> [String] {
        guard let image = ImageCoding.cgImage(from: data, maxPixel: 64) else { return [] }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var buckets: [Int: (count: Int, r: Int, g: Int, b: Int)] = [:]
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = Int(pixels[index]), g = Int(pixels[index + 1]), b = Int(pixels[index + 2])
            let key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
            let entry = buckets[key] ?? (0, 0, 0, 0)
            buckets[key] = (entry.count + 1, entry.r + r, entry.g + g, entry.b + b)
        }
        var chosen: [(r: Int, g: Int, b: Int)] = []
        for entry in buckets.values.sorted(by: { $0.count > $1.count }) {
            let color = (r: entry.r / entry.count, g: entry.g / entry.count, b: entry.b / entry.count)
            let distinct = chosen.allSatisfy { abs($0.r - color.r) + abs($0.g - color.g) + abs($0.b - color.b) > 90 }
            if distinct { chosen.append(color) }
            if chosen.count == count { break }
        }
        return chosen.map { String(format: "#%02X%02X%02X", $0.r, $0.g, $0.b) }
    }

    func toolModel(for state: ComposerState, requirement: ModelRequirement) -> ImageModel? {
        guard state.tool == .background, state.backgroundMode == "remove", state.modelID == nil else {
            return resolvedModel(for: state, requirement: requirement)
        }
        let (featured, others) = choices(for: requirement)
        let transparent = (featured + others).filter { $0.model.supportsTransparency && !catalog.strained.contains($0.model.id) }
        let preferred = ["gpt-image-2.5-sunburst", "gpt-image-2.5-flare"].compactMap { id in transparent.first { $0.lineup?.id == id } }
        return (preferred + transparent).first?.model ?? resolvedModel(for: state, requirement: requirement)
    }

    static func cutoutRecipe(transparent: Bool) -> String {
        let background = transparent
            ? "on a fully transparent background"
            : "on a pure, flat white background (#FFFFFF) with no shadow, gradient or texture"
        return """
        Remove the background of Image 1 and keep only the main subject (every person, object or product in the foreground), cut out cleanly \(background).
        Keep the subject exactly as it is: the same position, size and framing, pose, colors, lighting, texture, text and logos. Preserve fine edges such as hair, fur and see-through parts. Don't add a shadow, outline, glow or border.
        """
    }
}

enum RelatedTool: Hashable {
    case tool(Tool)
    case quickStyle(String)
    case ad(String)
    case video(String)

    var name: String {
        switch self {
        case .tool(let tool): tool.title
        case .quickStyle(let id): AppCatalog.item(id)?.name ?? ""
        case .ad(let id): AdCatalog.tool(id)?.name ?? ""
        case .video(let id): VideoCatalog.tool(id)?.name ?? ""
        }
    }
}

extension AppModel {
    func openRelated(_ related: RelatedTool, image: Data?) {
        switch related {
        case .tool(let tool):
            if let image, Tool.editingTools.contains(tool) || tool == .create { handoff[tool] = image }
            selection = .tool(tool)
        case .quickStyle(let id):
            if let image { handoff[.app] = image }
            pendingQuickStyle = id
            selection = .apps
        case .ad(let id):
            if let image, let tool = AdCatalog.tool(id) {
                let state = adState(for: tool)
                state.productID = nil
                state.productPhoto = image
            }
            selection = .ad(id)
        case .video(let id):
            openVideo(id)
        }
    }

    func relatedLink(_ related: RelatedTool, title: String? = nil, image: Data?) -> RelatedToolHint.Link {
        RelatedToolHint.Link(title: title ?? related.name) { [weak self] in self?.openRelated(related, image: image) }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension ComposerState {
    var hasPaint: Bool { strokes.contains { !$0.isEraser } }
}
