import AppKit
import AVFoundation
import FreefieldCore
import SwiftUI
import UniformTypeIdentifiers

extension AppModel {
    static let videoConfirmationThreshold = 1.0

    func videoState(for tool: VideoTool) -> VideoState {
        if let state = videoStates[tool.id] { return state }
        let state = VideoState(tool: tool)
        if tool.takes(.product) { state.productID = lastProduct?.id }
        videoStates[tool.id] = state
        return state
    }

    func openVideo(_ toolID: String, startImage: Data?) {
        if let startImage, let tool = VideoCatalog.tool(toolID), tool.takes(.firstFrame) {
            let state = videoState(for: tool)
            state.firstFrame = startImage
            state.firstFrameIsKeyframe = false
        }
        openVideo(toolID)
    }

    func openVideo(_ toolID: String, clip: VideoClipPick) {
        if !clip.isEmpty, let tool = VideoCatalog.tool(toolID), tool.takes(.sourceVideo) {
            videoState(for: tool).source = clip
        }
        openVideo(toolID)
    }

    var latestVideoResult: Asset? {
        library.assets.first { $0.isVideo && $0.tool != .imported }
    }

    func openVideoTool(_ id: String, with asset: Asset) {
        guard let tool = VideoCatalog.tool(id), asset.isVideo else { return }
        let state = videoState(for: tool)
        state.source = VideoClipPick(assetID: asset.id, link: pastedLink(for: asset) ?? "")
        openVideo(id)
    }

    func videoModelChoices(_ tool: VideoTool, inputs: VideoToolInputs) -> (featured: [VideoModelChoice], others: [VideoModelChoice]) {
        let filter = VideoRecipes.modelFilter(for: tool, state: inputs)
        let featured = catalog.featuredVideoChoices(kinds: filter.kinds).filter { filter.allows($0.model) }
        let locked = catalog.lockedVideoChoices(kinds: filter.kinds, configured: keys.configuredProviders).filter { filter.allows($0.model) }
        let others = catalog.otherVideoChoices(kinds: filter.kinds).filter { filter.allows($0.model) }
        return (featured + locked, others)
    }

    func resolvedVideoModel(_ tool: VideoTool, state: VideoState, inputs: VideoToolInputs) -> VideoModel? {
        guard tool.engine == .model, !tool.runsOnDevice(for: state.choices) else { return nil }
        return videoModel(tool, pick: state.modelID, resolution: state.resolution, inputs: inputs)
    }

    func videoModel(_ tool: VideoTool, pick: String?, resolution: String?, inputs: VideoToolInputs) -> VideoModel? {
        let all = selectableVideoModels(tool, inputs: inputs)
        if let pick, let match = all.first(where: { $0.id == pick }) { return match }
        let preferred = preferredVideoModels(tool, inputs: inputs, among: all)
        if let resolution {
            let fitting = sizeCandidates(tool, inputs: inputs, among: all).filter { $0.makes(resolution) }
            if let fit = fitting.first(where: isHealthy) ?? fitting.first { return fit }
        }
        return preferred.first(where: isHealthy) ?? preferred.first ?? all.first(where: isHealthy) ?? all.first
    }

    func videoSizeOptions(_ tool: VideoTool, state: VideoState, inputs: VideoToolInputs) -> [VideoSizeOption] {
        let all = selectableVideoModels(tool, inputs: inputs)
        let picked = state.modelID.flatMap { id in all.first { $0.id == id } }
        var seen = Set<String>()
        let sizes = ((picked.map { [$0] } ?? []) + sizeCandidates(tool, inputs: inputs, among: all)).flatMap(\.resolutions)
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted { VideoModel.rank(of: $0) < VideoModel.rank(of: $1) }
        return sizes.compactMap { size in
            let pick = picked.flatMap { $0.makes(size) ? $0.id : nil }
            guard let model = videoModel(tool, pick: pick, resolution: size, inputs: inputs), model.makes(size) else { return nil }
            var sized = inputs
            sized.resolution = size
            return VideoSizeOption(size: size, model: model, cost: videoRunEstimate(tool, state: state, inputs: sized, model: model).cost.total)
        }
    }

    func selectableVideoModels(_ tool: VideoTool, inputs: VideoToolInputs) -> [VideoModel] {
        let fitting = videoModelChoices(tool, inputs: inputs)
        return (fitting.featured + fitting.others).filter(\.isSelectable).map(\.model)
    }

    private func sizeCandidates(_ tool: VideoTool, inputs: VideoToolInputs, among all: [VideoModel]) -> [VideoModel] {
        let preferred = preferredVideoModels(tool, inputs: inputs, among: all)
        guard let usual = preferred.first ?? all.first else { return [] }
        let curated = Set(videoModelChoices(tool, inputs: inputs).featured.map(\.model.id))
        var seen = Set<String>()
        return (preferred + all.filter { curated.contains($0.id) })
            .filter { $0.kind == usual.kind && seen.insert($0.id).inserted }
    }

    private func preferredVideoModels(_ tool: VideoTool, inputs: VideoToolInputs, among all: [VideoModel]) -> [VideoModel] {
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        return (VideoRecipes.preferredModelIDs(for: tool, state: inputs) + VideoLineup.defaultModelIDs(for: tool.id))
            .filter { seen.insert($0).inserted }
            .compactMap { byID[$0] }
    }

    private func isHealthy(_ model: VideoModel) -> Bool {
        model.isBusy != true && !catalog.strained.contains(model.id)
    }

    func videoInputs(_ tool: VideoTool, state: VideoState, forRun: Bool) -> VideoToolInputs {
        var s = VideoToolInputs(tool: tool)
        s.firstFrameIsKeyframe = state.firstFrameIsKeyframe
        s.choices = tool.initialChoices.merging(state.choices) { _, chosen in chosen }
        s.texts = state.texts
        if tool.group("language") != nil, !state.languageIsPicked,
           let detected = VideoLanguageGuess.language(of: VideoLanguageGuess.spokenText(state.texts)) {
            s.choices["language"] = detected
        }
        s.prompt = tool.takes(.prompt) ? state.prompt : ""

        func image(_ data: Data?, role: String, maxPixel: Int = 2048) -> InputImage? {
            guard let data else { return nil }
            if forRun { return ImageCoding.prepareForUpload(data, maxPixel: maxPixel, role: role) }
            return InputImage(data: data, mimeType: "image/jpeg", role: role)
        }
        func counted(_ count: Int, role: String) -> [InputImage] {
            (0..<max(0, count)).map { _ in InputImage(data: Data(), mimeType: "image/jpeg", role: role) }
        }

        switch tool.id {
        case "extendVideo":
            s.firstFrame = image(state.sourceLastFrame, role: "previous clip's last frame")
        case "transitions" where state.transitionFromClips:
            s.firstFrame = image(state.clipsStartFrame, role: "first frame")
            s.lastFrame = image(state.clipsEndFrame, role: "last frame")
        default:
            if tool.takes(.firstFrame) || tool.takes(.drawing) { s.firstFrame = image(state.firstFrame, role: "first frame") }
            if tool.takes(.lastFrame) { s.lastFrame = image(state.lastFrame, role: "last frame") }
        }
        if let slot = tool.slot(.imageReferences) {
            s.references = state.references.prefix(slot.maxCount).compactMap { image($0, role: "reference") }
        }

        if tool.takes(.character) {
            if let character = library.character(state.characterID) {
                let photos = forRun ? library.referenceImages(for: character, limit: 4)
                    : counted(min(4, character.photoFileNames.count), role: "character")
                s.character = VideoSubject(name: character.name, details: character.details, photos: photos,
                                           isPhotoreal: state.subjectIsPhotoreal)
            } else if let photo = image(state.characterPhoto, role: "person", maxPixel: 1536) {
                s.character = VideoSubject(photos: [photo], isPhotoreal: state.subjectIsPhotoreal)
            }
        }
        if tool.takes(.product) {
            if let product = library.product(state.productID) {
                let photos = forRun ? library.productImages(for: product, limit: 3)
                    : counted(min(3, product.photoFileNames.count), role: "product")
                s.product = VideoSubject(name: product.name, details: product.details, photos: photos)
            } else if !state.productPhotos.isEmpty {
                s.product = VideoSubject(photos: state.productPhotos.prefix(3).compactMap { image($0, role: "product", maxPixel: 1536) })
            }
        }

        if tool.takes(.sourceVideo) {
            let clip = clipInputs(state.source)
            s.sourceVideoFile = clip.file
            s.sourceVideoURL = clip.link
            s.sourceDuration = clip.asset?.duration
            s.sourceSize = clip.asset.map { CGSize(width: $0.width, height: $0.height) }
            if let asset = clip.asset, asset.remoteJobID != nil {
                s.sourceModelID = asset.modelID.split(separator: ":", maxSplits: 1).last.map(String.init)
                s.sourceJobID = asset.remoteJobID
            }
        }
        if tool.takes(.drivingVideo) {
            let clip = clipInputs(state.driving)
            s.drivingVideoFile = clip.file
            s.drivingVideoURL = clip.link
            s.drivingDuration = clip.asset?.duration
            s.drivingSize = clip.asset.map { CGSize(width: $0.width, height: $0.height) }
        }
        if tool.takes(.audio) {
            s.audioFile = state.audioFile
            let link = state.audioLink.trimmingCharacters(in: .whitespacesAndNewlines)
            s.audioURL = link.isEmpty ? nil : link
            s.audioDuration = state.audioDuration
        }

        if let preset = state.presetID.flatMap(StylePresets.preset) {
            s.style = preset.prompt
        } else if let board = library.moodboard(state.moodboardID), !board.styleDescription.isEmpty {
            s.style = board.styleDescription
        }
        s.cameraMoves = state.cameraMoves
        s.strength = state.cameraStrength
        if tool.takes(.shots) {
            s.shots = state.shots.map { shot in
                VideoShot(action: shot.action, camera: shot.camera, emotion: shot.emotion, image: image(shot.image, role: "storyboard frame"))
            }
        }
        if tool.id == "videoEffects" { s.effectID = state.effectID }
        if tool.takes(.drawing), !state.drawStrokes.isEmpty || !state.drawNotes.isEmpty {
            if forRun {
                s.drawing = state.firstFrame
                    .flatMap { CanvasRenderer.annotated($0, strokes: state.drawStrokes, notes: state.drawNotes) }
                    .flatMap { ImageCoding.prepareForUpload($0, role: "drawing") }
            } else {
                s.drawing = InputImage(data: Data(), mimeType: "image/jpeg", role: "drawing")
            }
        }

        s.duration = state.duration
        s.resolution = state.resolution
        s.aspect = state.aspect
        s.audio = state.audio
        s.seed = state.seed
        s.consent = state.consent
        return s
    }

    private func clipInputs(_ pick: VideoClipPick) -> (file: URL?, link: String?, asset: Asset?) {
        let asset = pick.assetID.flatMap(library.asset)
        let file = asset.map { library.url(for: $0) }
        let typed = pick.trimmedLink
        let link = typed.isEmpty ? asset.flatMap(pastedLink(for:)) : typed
        return (file, link, asset)
    }

    func loadDerivedFrames(_ tool: VideoTool, state: VideoState) async {
        switch tool.id {
        case "extendVideo":
            guard let asset = state.source.assetID.flatMap(library.asset) else {
                state.sourceLastFrame = nil
                return
            }
            state.sourceLastFrame = try? await VideoMedia.lastFrame(library.url(for: asset), maxPixel: 2048)
        case "transitions":
            let assets = state.clipIDs.prefix(2).compactMap(library.asset)
            guard assets.count == 2 else {
                state.clipsStartFrame = nil
                state.clipsEndFrame = nil
                return
            }
            state.clipsStartFrame = try? await VideoMedia.lastFrame(library.url(for: assets[0]), maxPixel: 2048)
            state.clipsEndFrame = try? await VideoMedia.frame(library.url(for: assets[1]), at: 0, maxPixel: 2048)
        default:
            break
        }
    }

    func checkPhotoreal(_ tool: VideoTool, state: VideoState) async {
        var data: Data?
        if let character = library.character(state.characterID), let name = character.photoFileNames.first {
            data = try? Data(contentsOf: library.characterPhotoURL(name))
        } else {
            data = state.characterPhoto
        }
        guard let data else {
            state.subjectIsPhotoreal = false
            return
        }
        state.subjectIsPhotoreal = await PhotorealCheck.showsRealPerson(data, using: self)
    }

    private struct VideoRun {
        let tool: VideoTool
        var recipeTool: VideoTool
        var model: VideoModel
        var inputs: VideoToolInputs
        let count: Int
        var parent: Asset?
        var titleSuffix = ""
        var recordSuffix = ""
    }

    func runVideoTool(_ tool: VideoTool, state: VideoState, model: VideoModel? = nil, confirmed: Bool = false) {
        guard !state.isPreparing else { return }
        state.runNotes = []
        if tool.engine == .onDevice || tool.runsOnDevice(for: state.choices) {
            runVideoOnDevice(tool, state: state)
            return
        }
        if tool.engine == .promptHelper {
            guard let asset = state.source.assetID.flatMap(library.asset), asset.isVideo else {
                presentError(FreefieldError.unsupported(L("Choose a video")))
                return
            }
            checkHook(asset, tool: tool, state: state)
            return
        }
        guard canMakeVideos || keys.google != nil else {
            presentError(FreefieldError.unsupported(GenerationEngine.videoKeyMessage))
            return
        }
        let screenInputs = videoInputs(tool, state: state, forRun: false)
        guard let model = model ?? resolvedVideoModel(tool, state: state, inputs: screenInputs) else {
            presentError(FreefieldError.unsupported(L("No compatible model available")))
            return
        }
        let count = max(1, min(4, state.count))
        let fingerprint = videoRunFingerprint(tool, state: state, model: model, count: count)
        if !confirmed {
            if let last = recentVideoRuns[fingerprint], Date().timeIntervalSince(last) < 90 {
                state.confirmation = VideoRunConfirmation(total: nil, clips: count, isRepeat: true)
                return
            }
            let plan = frameModePlan(tool, state: state, inputs: screenInputs, model: model, count: count)
            let cost = plan?.cost ?? videoToolCost(tool, inputs: screenInputs, model: model, count: count)
            let runModel = plan?.model ?? model
            if let total = cost.total, total >= Self.videoConfirmationThreshold {
                state.confirmation = VideoRunConfirmation(total: total, clips: max(1, cost.clips))
                return
            }
            if cost.total == nil, cost.clips > 0 {
                state.confirmation = VideoRunConfirmation(total: nil, clips: cost.clips,
                                                          modelName: VideoLineup.displayName(for: runModel.id, fallback: runModel.name))
                return
            }
        }
        recentVideoRuns[fingerprint] = Date()
        let parent = tool.takes(.sourceVideo) ? state.source.assetID.flatMap(library.asset) : nil
        let run = VideoRun(tool: tool, recipeTool: tool, model: model, inputs: videoInputs(tool, state: state, forRun: true),
                           count: count, parent: parent)
        prepare(state) { await self.proceed(run, state: state) }
    }

    private func prepare(_ state: VideoState, _ work: @escaping () async -> Void) {
        let token = UUID()
        state.preparingID = token
        state.isPreparing = true
        state.preparingTask = Task {
            await work()
            guard state.preparingID == token else { return }
            state.isPreparing = false
            state.preparingStep = nil
            state.preparingTask = nil
            state.preparingID = nil
        }
    }

    func cancelVideoPreparation(_ state: VideoState) {
        state.preparingTask?.cancel()
        state.preparingTask = nil
        state.preparingID = nil
        state.isPreparing = false
        state.preparingStep = nil
    }

    private func proceed(_ run: VideoRun, state: VideoState) async {
        var run = run
        do {
            if run.tool.id == "drawToVideo", let frame = run.inputs.firstFrame, let drawing = run.inputs.drawing {
                state.preparingStep = L("Reading your drawing…")
                let motion = try await helperComplete(title: E("Read drawing"), tool: .video, system: VideoRecipes.drawHelperInstructions,
                                                      user: "Describe the motion.", images: [frame, drawing])
                run.inputs.prompt = motion.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”").union(.whitespacesAndNewlines))
            } else if Self.autoEnhancesDescriptions, Self.enhancesDescription(of: run.tool) {
                state.preparingStep = L("Improving the description…")
                await enhanceVideoDescriptions(&run.inputs, tool: run.recipeTool, model: run.model)
            }
            if run.tool.id == "extendVideo", run.inputs.firstFrame == nil, let file = run.inputs.sourceVideoFile {
                state.preparingStep = L("Reading the clip's last frame…")
                let data = try await VideoMedia.lastFrame(file, maxPixel: 2048)
                run.inputs.firstFrame = ImageCoding.prepareForUpload(data, role: "previous clip's last frame")
            }
            try Task.checkCancellation()
        } catch {
            if !(error is CancellationError) { presentError(error) }
            return
        }

        if state.usesFrames, needsSharedClip(run) {
            await proceedFromFrames(run, state: state)
            return
        }

        let recipes = VideoRecipes.requests(for: run.recipeTool, state: run.inputs, model: run.model)
        guard let first = recipes.first else {
            presentError(FreefieldError.unsupported(L("This tool can't run with these settings.")))
            return
        }
        let priced = jobSpec(first, run: run, state: state, cropping: false)
        if let message = engine.videoLimitMessage(for: priced, count: recipes.count * run.count) {
            presentError(FreefieldError.limitReached(message))
            return
        }
        if let plan = first.keyframe {
            state.runNotes = [plan.reason].filter { !$0.isEmpty }
            guard let spec = keyframeSpec(plan, run: run, state: state) else {
                presentError(FreefieldError.unsupported(L("No image model is available to make the start frame.")))
                return
            }
            startImageStep(spec) { [weak self] frame in
                var next = run
                next.inputs.firstFrame = frame
                next.inputs.firstFrameIsKeyframe = true
                self?.continueAfterImageStep(next, state: state)
            }
            return
        }
        await shareAndLaunch(run, state: state)
    }

    private func continueAfterImageStep(_ run: VideoRun, state: VideoState) {
        guard !state.isPreparing else {
            Task {
                try? await Task.sleep(for: .seconds(2))
                self.continueAfterImageStep(run, state: state)
            }
            return
        }
        prepare(state) { await self.shareAndLaunch(run, state: state) }
    }

    private func shareAndLaunch(_ run: VideoRun, state: VideoState) async {
        var run = run
        var recipes = VideoRecipes.requests(for: run.recipeTool, state: run.inputs, model: run.model)
        var opened: [String] = []
        defer { clipSharing.discardUnclaimed(opened) }
        if recipes.contains(where: \.needsLinks) {
            state.preparingStep = L("Sharing the clip from this Mac…")
            do {
                run.inputs = try await resolveLinks(run, recipes: recipes, opened: &opened)
            } catch let error as VideoInputError {
                state.inputProblem = VideoInputProblem(message: error.localizedDescription,
                                                       offersFrames: offersFrameMode(run.tool, inputs: run.inputs))
                return
            } catch is CancellationError {
                return
            } catch {
                presentError(error)
                return
            }
            recipes = VideoRecipes.requests(for: run.recipeTool, state: run.inputs, model: run.model)
        }
        recipes = await Self.croppingFrames(recipes)
        guard !Task.isCancelled, !recipes.isEmpty else { return }
        launch(recipes, run: run, state: state)
    }

    private func resolveLinks(_ run: VideoRun, recipes: [VideoRecipe], opened: inout [String]) async throws -> VideoToolInputs {
        var s = run.inputs
        let references = recipes.flatMap(\.request.references)
        let wantsVideo = references.contains { if case .videoURL(VideoRecipes.pendingLinkPlaceholder) = $0 { true } else { false } }
        let wantsAudio = references.contains { if case .audioURL(VideoRecipes.pendingLinkPlaceholder) = $0 { true } else { false } }
        let fullSize = ClipSharing.sharesFullSize(run.recipeTool.id)
        func given(_ link: String?) throws -> String? {
            guard let link = link?.trimmingCharacters(in: .whitespacesAndNewlines), !link.isEmpty else { return nil }
            do { return try InputLink.checked(link) } catch { throw FreefieldError.unsupported(error.localizedDescription) }
        }
        if wantsVideo {
            let motion = run.recipeTool.id == "motionTransfer"
            let current = motion ? s.drivingVideoURL : s.sourceVideoURL
            var link = try given(current)
            if link == nil, let file = motion ? s.drivingVideoFile : s.sourceVideoFile {
                let shared = try await videoSourceURL(forFile: file, fullSize: fullSize)
                opened.append(shared)
                link = shared
            }
            if motion { s.drivingVideoURL = link } else { s.sourceVideoURL = link }
        }
        if wantsAudio {
            var link = try given(s.audioURL)
            if link == nil, let file = s.audioFile {
                let shared = try await videoSourceURL(forFile: file)
                opened.append(shared)
                link = shared
            }
            s.audioURL = link
        }
        return s
    }

    @concurrent
    private nonisolated static func croppingFrames(_ recipes: [VideoRecipe]) async -> [VideoRecipe] {
        recipes.map { recipe in
            guard let ratio = recipe.cropFirstFrameTo else { return recipe }
            var recipe = recipe
            if let frame = recipe.request.firstFrame { recipe.request.firstFrame = cropped(frame, to: ratio) ?? frame }
            if let frame = recipe.request.lastFrame { recipe.request.lastFrame = cropped(frame, to: ratio) ?? frame }
            recipe.cropFirstFrameTo = nil
            return recipe
        }
    }

    private func launch(_ recipes: [VideoRecipe], run: VideoRun, state: VideoState) {
        pruneRunRecords(state)
        let batchID = UUID()
        for note in recipes.flatMap(\.notes) where !state.runNotes.contains(note) { state.runNotes.append(note) }
        var started: [Job] = []
        launching: for recipe in recipes {
            var spec = jobSpec(recipe, run: run, state: state)
            spec.batchID = batchID
            for _ in 0..<run.count {
                let job = engine.startVideo(spec)
                state.runs[job.id] = VideoRunRecord(toolID: run.tool.id, inputs: run.inputs, modelID: run.model.id,
                                                    parentAssetID: run.parent?.id, batchID: batchID)
                guard job.isRunning else { break launching }
                started.append(job)
                attachFinishStep(job, run: run, state: state)
            }
        }
        if run.tool.id == "storyboardVideo", recipes.count > 1, run.count == 1, started.count == recipes.count {
            joinStoryboardWhenFinished(started, run: run, state: state)
        }
    }

    private func pruneRunRecords(_ state: VideoState) {
        let kept = Set(engine.jobs.filter { job in
            if job.isRunning { return true }
            if case .failed = job.status { return true }
            return false
        }.map(\.id))
        state.runs = state.runs.filter { kept.contains($0.key) }
    }

    private func jobSpec(_ recipe: VideoRecipe, run: VideoRun, state: VideoState, cropping: Bool = true) -> VideoJobSpec {
        var request = recipe.request
        if cropping, let ratio = recipe.cropFirstFrameTo {
            if let frame = request.firstFrame { request.firstFrame = Self.cropped(frame, to: ratio) ?? frame }
            if let frame = request.lastFrame { request.lastFrame = Self.cropped(frame, to: ratio) ?? frame }
        }
        return VideoJobSpec(
            toolID: run.tool.id, title: recipe.title + run.titleSuffix, record: recipe.record + run.recordSuffix,
            userTexts: recipe.userTexts, literalTexts: recipe.literalTexts, request: request,
            characterID: library.character(state.characterID)?.id, productID: library.product(state.productID)?.id,
            presetID: state.presetID, parentAssetID: run.parent?.id, sourceDuration: recipe.sourceSeconds,
            sourceSize: recipe.sourceSize
        )
    }

    private func keyframeSpec(_ plan: VideoKeyframePlan, run: VideoRun, state: VideoState) -> JobSpec? {
        guard let model = keyframeImageModel(for: plan) else { return nil }
        let inputs = run.inputs
        let ratio = (run.inputs.aspect ?? VideoRecipes.request(for: run.recipeTool, state: inputs, model: run.model)?.request.aspectRatio)
            .flatMap(AspectRatio.init(rawValue:))
        var spec: JobSpec
        switch plan.kind {
        case .subject:
            let limit = max(0, model.maxReferences)
            let character = plan.showsPerson ? inputs.character : nil
            let characterPhotos = Array((character?.photos ?? []).prefix(min(4, limit)))
            let productPhotos = Array((inputs.product?.photos ?? []).prefix(max(0, min(3, limit - characterPhotos.count))))
            let extraPhotos = Array(inputs.references.prefix(max(0, limit - characterPhotos.count - productPhotos.count)))
            if extraPhotos.count < inputs.references.count {
                state.runNotes.append(L("Some reference images didn't fit in the start frame and were left out."))
            }
            let person = character.map {
                Character(id: UUID(), name: $0.name, details: $0.details, photoFileNames: [], createdAt: .now)
            }
            var prompt = Recipes.create(prompt: plan.scene, preset: nil, character: person, referenceCount: extraPhotos.count,
                                        characterImageCount: characterPhotos.count, rendersQuotedText: false)
            if let subject = inputs.product, !productPhotos.isEmpty {
                let product = Product(id: UUID(), name: subject.name.isEmpty ? "the product" : subject.name, details: subject.details,
                                      photoFileNames: [], createdAt: .now)
                let first = characterPhotos.count + 1
                prompt += "\n\n" + Recipes.productReference(product, imageRange: first...(first + productPhotos.count - 1))
            }
            if !extraPhotos.isEmpty {
                let first = characterPhotos.count + productPhotos.count + 1, last = first + extraPhotos.count - 1
                let names = first == last ? "Image \(first) is an extra reference" : "Images \(first)–\(last) are extra references"
                prompt += "\n\n\(names) for the setting, props or details the description names."
            }
            if let style = inputs.style?.trimmingCharacters(in: .whitespacesAndNewlines), !style.isEmpty {
                prompt += "\n\nRender it in this style: \(style)"
            }
            prompt += "\n\nOne full-frame still with no text, captions or watermarks."
            spec = JobSpec(tool: .video, title: L("Start frame") + " · " + run.tool.name, prompt: prompt, model: model,
                           aspectRatio: ratio ?? .landscape16x9, count: 1, images: characterPhotos + productPhotos + extraPhotos,
                           characterID: character == nil ? nil : library.character(state.characterID)?.id,
                           productID: library.product(state.productID)?.id, appID: run.tool.id)
            spec.userTexts = (plan.userTexts + [character?.details ?? "", inputs.product?.details ?? "", inputs.style ?? ""])
                .filter { !$0.isEmpty }
        case .quickStyle(let id):
            guard let item = AppCatalog.item(id), let photo = inputs.firstFrame else { return nil }
            spec = JobSpec(tool: .video, title: item.name + " · " + run.tool.name, prompt: item.prompt(option: item.options.first, text: ""),
                           model: model, aspectRatio: ratio ?? item.aspect, count: 1, images: [photo], appID: run.tool.id)
            spec.record = english(item.name) + " · " + english(run.tool.name)
        case .adShot(let id):
            guard let ad = AdCatalog.tool(id) else { return nil }
            let settings = AdSettings(choices: ad.options.map { $0.values.first ?? "" }, text: "", text2: "",
                                      product: library.product(state.productID), character: library.character(state.characterID),
                                      aspect: ratio ?? ad.aspect, count: 1)
            let limit = max(1, model.maxReferences)
            let productPhotos = Array((inputs.product?.photos ?? []).prefix(min(3, limit)))
            let personPhotos = ad.usesPerson ? Array((inputs.character?.photos ?? []).prefix(max(0, min(3, limit - productPhotos.count)))) : []
            spec = JobSpec(tool: .video, title: ad.name + " · " + run.tool.name, prompt: Self.adPrompt(ad, settings: settings, text: ""),
                           model: model, aspectRatio: settings.aspect, count: 1, images: productPhotos + personPhotos,
                           characterID: settings.character?.id, productID: settings.product?.id, appID: run.tool.id)
            spec.record = english(ad.name) + " · " + english(run.tool.name)
            spec.userTexts = [inputs.product?.details ?? ""].filter { !$0.isEmpty }
        }
        if spec.record == nil { spec.record = E("Start frame") + " · " + english(run.tool.name) }
        return spec
    }

    private func startImageStep(_ spec: JobSpec, then: @escaping (InputImage) -> Void) {
        let job = engine.start(spec)
        guard job.isRunning else { return }
        job.onFinish = { [weak self] job in
            guard let self, let id = job.assetIDs.first, let asset = self.library.asset(id),
                  let data = self.library.imageData(for: asset),
                  let frame = ImageCoding.prepareForUpload(data, maxPixel: 2048, role: "first frame") else { return }
            then(frame)
        }
    }

    private func needsSharedClip(_ run: VideoRun) -> Bool {
        VideoRecipes.requests(for: run.recipeTool, state: run.inputs, model: run.model).contains(where: \.needsLinks)
    }

    func offersFrameMode(_ tool: VideoTool, inputs: VideoToolInputs) -> Bool {
        switch tool.id {
        case "editVideo": tool.choice("mode", in: inputs.choices) != "Translate dialogue" && inputs.sourceVideoFile != nil
        case "swapVideo": inputs.sourceVideoFile != nil
        case "motionTransfer": inputs.drivingVideoFile != nil
        case "createVideo": inputs.sourceVideoFile != nil
        default: false
        }
    }

    static let motionDescriptionEstimate = 0.02

    private func proceedFromFrames(_ run: VideoRun, state: VideoState) async {
        guard offersFrameMode(run.tool, inputs: run.inputs),
              let clip = run.tool.id == "motionTransfer" ? run.inputs.drivingVideoFile : run.inputs.sourceVideoFile else {
            presentError(FreefieldError.unsupported(L("This tool can't work from frames. Paste a link to the clip (https) instead.")))
            return
        }
        let work = VideoLocalWork(title: L("Frame-based mode"), step: L("Reading the clip's frames…"))
        state.localWork.insert(work, at: 0)
        defer { if work.failure == nil { state.localWork.removeAll { $0.id == work.id } } }
        let firstData: Data, lastData: Data, motion: String
        do {
            state.preparingStep = L("Reading the clip's frames…")
            firstData = try await VideoMedia.frame(clip, at: 0, maxPixel: 2048)
            lastData = try await VideoMedia.lastFrame(clip, maxPixel: 2048)
            state.preparingStep = L("Describing the clip's motion…")
            work.step = L("Describing the clip's motion…")
            motion = try await describeClipMotion(clip)
            try Task.checkCancellation()
        } catch is CancellationError {
            return
        } catch {
            work.failure = error.localizedDescription
            return
        }
        guard let first = ImageCoding.prepareForUpload(firstData, role: "first frame"),
              let last = ImageCoding.prepareForUpload(lastData, role: "last frame") else {
            work.failure = VideoMediaError.frame.localizedDescription
            return
        }
        guard let frames = frameRun(run, first: first, last: last, motion: motion, state: state) else {
            presentError(FreefieldError.unsupported(L("No compatible model available")))
            return
        }
        for note in frames.notes where !state.runNotes.contains(note) { state.runNotes.append(note) }
        let next = frames.run
        if let imageStep = frames.imageStep {
            startImageStep(imageStep) { [weak self] frame in
                var after = next
                after.inputs.firstFrame = frame
                after.inputs.firstFrameIsKeyframe = true
                self?.continueAfterImageStep(after, state: state)
            }
            return
        }
        await shareAndLaunch(next, state: state)
    }

    private func frameRun(_ run: VideoRun, first: InputImage, last: InputImage, motion: String,
                          state: VideoState) -> (run: VideoRun, imageStep: JobSpec?, notes: [String])? {
        var notes: [String] = []
        if run.tool.id == "createVideo" {
            var next = run
            next.inputs.sourceVideoFile = nil
            next.inputs.sourceVideoURL = nil
            next.inputs.motionHint = motion
            if next.inputs.hasAudio, next.inputs.audioURL == nil {
                next.inputs.audioFile = nil
                notes.append(L("The reference audio was left out in frame-based mode."))
            }
            next.titleSuffix = " · " + L("From frames")
            next.recordSuffix = " · " + E("From frames")
            guard let model = resolvedFrameModel(for: next.recipeTool, inputs: next.inputs, current: run.model) else { return nil }
            next.model = model
            return (next, nil, notes)
        }

        guard let createTool = VideoCatalog.tool("createVideo") else { return nil }
        var inputs = VideoToolInputs(tool: createTool)
        let seconds = run.tool.id == "motionTransfer" ? run.inputs.drivingDuration : run.inputs.sourceDuration
        inputs.duration = seconds.map { max(4, Int(min($0, VideoMedia.shareMaxSeconds).rounded())) } ?? 5
        inputs.resolution = run.inputs.resolution ?? "720p"
        inputs.audio = run.inputs.audio ?? false
        inputs.seed = run.inputs.seed
        var imageStep: JobSpec?
        switch run.tool.id {
        case "motionTransfer":
            guard let photo = run.inputs.character?.photos.first else { return nil }
            inputs.firstFrame = photo
            inputs.firstFrameIsKeyframe = true
            inputs.character = run.inputs.character
            inputs.prompt = "The character performs these movements, in this order: \(motion)"
        default:
            inputs.firstFrame = first
            inputs.prompt = motion
            imageStep = frameEditSpec(run, frame: first, state: state)
            if imageStep == nil { inputs.lastFrame = last }
        }
        var next = run
        next.recipeTool = createTool
        next.inputs = inputs
        next.titleSuffix = " · " + L("From frames")
        next.recordSuffix = " · " + E("From frames")
        guard let model = resolvedFrameModel(for: createTool, inputs: inputs, current: nil) else { return nil }
        next.model = model
        notes.append(L("Made from the clip's frames and a description of its motion: a new clip, not an edit of the original."))
        return (next, imageStep, notes)
    }

    func frameModePlan(_ tool: VideoTool, state: VideoState, inputs: VideoToolInputs, model: VideoModel,
                       count: Int) -> (model: VideoModel, cost: VideoCostEstimate)? {
        guard state.usesFrames, offersFrameMode(tool, inputs: inputs),
              VideoRecipes.requests(for: tool, state: inputs, model: model).contains(where: \.needsLinks) else { return nil }
        let frame = InputImage(data: Data(), mimeType: "image/jpeg", role: "first frame")
        let run = VideoRun(tool: tool, recipeTool: tool, model: model, inputs: inputs, count: count)
        guard let frames = frameRun(run, first: frame, last: frame, motion: "The subject moves as in the clip.", state: state) else {
            return nil
        }
        var cost = videoToolCost(frames.run.recipeTool, inputs: frames.run.inputs, model: frames.run.model, count: count)
        if let edit = frames.imageStep {
            if let price = estimatedCost(model: edit.model, count: 1, resolution: .oneK) {
                cost.keyframe = (cost.keyframe ?? 0) + price
            } else {
                cost.keyframeUnpriced = true
            }
        }
        cost.video = cost.video.map { $0 + Self.motionDescriptionEstimate }
        return (frames.run.model, cost)
    }

    func videoRunEstimate(_ tool: VideoTool, state: VideoState, inputs: VideoToolInputs,
                          model: VideoModel) -> (cost: VideoCostEstimate, frameModel: VideoModel?) {
        let count = max(1, min(4, state.count))
        if let plan = frameModePlan(tool, state: state, inputs: inputs, model: model, count: count) { return (plan.cost, plan.model) }
        return (videoToolCost(tool, inputs: inputs, model: model, count: count), nil)
    }

    private func frameEditSpec(_ run: VideoRun, frame: InputImage, state: VideoState) -> JobSpec? {
        let tool = run.tool
        let inputs = run.inputs
        let mode = tool.choice("mode", in: inputs.choices)
        var prompt: String
        var images = [frame]
        var userTexts: [String] = []
        let extra = tool.textField(VideoCatalog.extraFieldID)
            .flatMap { tool.isShown($0.shownWhen, choices: inputs.choices) ? inputs.text($0.id) : nil } ?? ""
        if !extra.isEmpty { userTexts.append(extra) }
        switch tool.id {
        case "editVideo":
            var instruction: String
            switch mode {
            case "Restyle":
                let choice = tool.choice("restyle", in: inputs.choices)
                let look = choice == "My moodboard" ? (inputs.style ?? "the moodboard's look") : (VideoPhrases.restyles[choice] ?? choice.lowercased())
                if choice == "My moodboard", let style = inputs.style { userTexts.append(style) }
                instruction = "Restyle the whole image as \(look), keeping the same people, pose and composition"
            case "Relight":
                instruction = "Relight the scene with \(VideoPhrases.relights[tool.choice("relight", in: inputs.choices)] ?? "soft natural light")"
            case "Weather & time":
                instruction = "Change the weather and time of day to \(VideoPhrases.weather[tool.choice("weather", in: inputs.choices)] ?? "a different weather")"
            default:
                let change = inputs.text("change")
                if !change.isEmpty { userTexts.append(change) }
                instruction = change.isEmpty ? "Add what Image 2 shows to the scene" : change
            }
            if !extra.isEmpty { instruction += ". Also: " + extra }
            let references = Array(inputs.references.prefix(1))
            images += references
            prompt = Recipes.edit(instruction, referenceCount: references.count)
        case "swapVideo":
            guard let photos = inputs.character?.photos, let photo = photos.first else { return nil }
            switch tool.choice("swap", in: inputs.choices) {
            case "Whole character":
                images += Array(photos.prefix(3))
                prompt = Recipes.characterSwap(details: inputs.character?.details ?? "", extra: extra)
                if let details = inputs.character?.details, !details.isEmpty { userTexts.append(details) }
            case "Outfit only":
                images.append(photo)
                prompt = Recipes.outfitSwap(extra: extra)
            default:
                images.append(photo)
                prompt = Recipes.faceSwap(keepExpression: true, extra: extra)
            }
        default:
            return nil
        }
        guard let model = frameEditImageModel(images: images.count) else { return nil }
        var spec = JobSpec(tool: .video, title: L("Edited frame") + " · " + tool.name, prompt: prompt, model: model,
                           count: 1, images: Array(images.prefix(max(1, model.maxReferences))),
                           characterID: library.character(state.characterID)?.id, appID: tool.id)
        spec.record = E("Edited frame") + " · " + english(tool.name)
        spec.userTexts = userTexts
        return spec
    }

    private func frameEditImageModel(images: Int) -> ImageModel? {
        let featured = choices(for: ModelRequirement(images: images, minimumImages: images)).featured
        for id in Lineup.defaultModelIDs(for: .edit) {
            if let match = featured.first(where: { $0.lineup?.id == id && !catalog.strained.contains($0.model.id) }) { return match.model }
        }
        return featured.first?.model
    }

    private func resolvedFrameModel(for tool: VideoTool, inputs: VideoToolInputs, current: VideoModel?) -> VideoModel? {
        let filter = VideoRecipes.modelFilter(for: tool, state: inputs)
        if let current, filter.allows(current) { return current }
        let available = Dictionary(videoModels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ids = (inputs.lastFrame != nil ? VideoLineup.defaultModelIDs(for: "transitions") : [])
            + VideoLineup.defaultModelIDs(for: "animateImage") + VideoLineup.defaultModelIDs(for: tool.id)
        let candidates = ids.compactMap { available[$0] }.filter { filter.allows($0) }
        return candidates.first(where: isHealthy) ?? candidates.first
    }

    func describeClipMotion(_ file: URL) async throws -> String {
        let system = """
        You describe a video clip's motion for a video generator that will recreate it from its first frame. Write one English paragraph of at most 90 words: who or what moves and how (body movements, gestures, objects), in order with timing words (first, then, at the end), and the camera movement. Do not describe the static scene, colors or style, and do not mention the video, frames or images.
        """
        if let key = keys.openRouter, let model = videoUnderstandingModelID {
            if let message = limitViolation(adding: Self.motionDescriptionEstimate) { throw FreefieldError.limitReached(message) }
            do {
                let copy = try await VideoMedia.shareableCopy(file, maxSeconds: 15)
                defer { if let copy { try? FileManager.default.removeItem(at: copy) } }
                let reply = try await VideoUnderstanding.complete(clip: copy ?? file, model: model, system: system,
                                                                  user: "Describe the motion in this clip.", apiKey: key)
                library.record(UsageEntry(
                    date: .now, kind: .text, tool: .video, title: E("Describe clip motion"), modelID: "\(Provider.openRouter.rawValue):\(model)",
                    modelName: model, provider: .openRouter, cost: reply.cost ?? 0.01, isEstimated: reply.cost == nil,
                    imageCount: 0, assetIDs: []
                ))
                return reply.text
            } catch is CancellationError {
                throw CancellationError()
            } catch {
            }
        }
        let info = try await VideoMedia.probe(file)
        var images: [InputImage] = []
        for index in 0..<6 {
            let seconds = max(0, info.duration - 0.05) * Double(index) / 5
            if let data = try? await VideoMedia.frame(file, at: seconds, maxPixel: 768),
               let image = ImageCoding.prepareForUpload(data, maxPixel: 768, role: "frame \(index + 1)") {
                images.append(image)
            }
        }
        guard !images.isEmpty else { throw VideoMediaError.frame }
        return try await helperComplete(title: E("Describe clip motion"), tool: .video,
                                        system: system + " The images are frames of the clip in time order.",
                                        user: "Describe the motion.", images: images)
    }

    private var videoUnderstandingModelID: String? {
        if let helper = helperModel, helper.provider == .openRouter, helper.modelID.contains("gemini") { return helper.modelID }
        let available = catalog.textModels[.openRouter] ?? []
        let ids = ["google/gemini-3-flash-preview", "google/gemini-3-flash", "google/gemini-2.5-flash"]
        return ids.first { id in available.contains { $0.modelID == id } }
    }

    private func attachFinishStep(_ job: Job, run: VideoRun, state: VideoState) {
        let tool = run.tool
        let choices = run.inputs.choices
        let title: String
        let make: (Asset) async throws -> (URL, String)?
        switch tool.id {
        case "extendVideo" where state.joinsExtension && run.recipeTool.id == "extendVideo":
            guard let source = run.parent else { return }
            title = L("Joining the clip and its continuation…")
            make = { [library] result in
                let url = try await VideoMedia.join([library.url(for: source), library.url(for: result)], trimSeams: true, keepsEnds: true)
                return (url, E("Joined"))
            }
        case "transitions" where state.transitionFromClips && tool.choice("join", in: choices) == "Join with clips"
            && run.recipeTool.id == "transitions":
            let clips = state.clipIDs.prefix(2).compactMap(library.asset)
            guard clips.count == 2 else { return }
            title = L("Joining the transition with the clips…")
            make = { [library] result in
                let url = try await VideoMedia.join([clips[0], result, clips[1]].map { library.url(for: $0) }, trimSeams: true,
                                                    keepsEnds: true)
                return (url, E("Joined"))
            }
        case "swapVideo", "motionTransfer":
            let keepsSound = tool.id == "swapVideo" || tool.choice("sound", in: choices) == "Keep original sound"
            let original = tool.id == "swapVideo" ? run.parent : state.driving.assetID.flatMap(library.asset)
            guard keepsSound, let original, original.hasAudio == true else { return }
            title = L("Adding the original sound…")
            make = { [library] result in
                guard result.hasAudio != true else { return nil }
                let url = try await VideoMedia.muxAudio(from: library.url(for: original), into: library.url(for: result))
                return (url, E("With original sound"))
            }
        default:
            return
        }
        job.onFinish = { [weak self] job in
            guard let self, job.status == .finished, let id = job.assetIDs.first, let result = self.library.asset(id) else { return }
            Task { await self.finishOnMac(result, title: title, state: state, make: make) }
        }
    }

    private func finishOnMac(_ result: Asset, title: String, state: VideoState, make: (Asset) async throws -> (URL, String)?) async {
        let work = VideoLocalWork(title: title)
        state.localWork.insert(work, at: 0)
        do {
            guard let (url, suffix) = try await make(result) else {
                state.localWork.removeAll { $0.id == work.id }
                return
            }
            var template = result
            template.id = UUID()
            template.prompt = result.prompt + " · " + suffix
            template.cost = nil
            template.remoteJobID = nil
            template.parentAssetID = result.id
            guard let asset = await library.addVideo(file: url, template: template) else { throw VideoMediaError.unreadable }
            engine.recordLocal(title: template.prompt, tool: .video, modelName: E("On this Mac"), assetIDs: [asset.id], appID: template.appID)
            state.localWork.removeAll { $0.id == work.id }
        } catch {
            work.failure = error.localizedDescription
        }
    }

    private func joinStoryboardWhenFinished(_ jobs: [Job], run: VideoRun, state: VideoState) {
        final class Progress {
            var remaining: Set<UUID>
            var clips: [UUID: UUID] = [:]
            var failed = false
            init(_ ids: [UUID]) { remaining = Set(ids) }
        }
        let order = jobs.map(\.id)
        let progress = Progress(order)
        let tool = run.tool
        let flows = tool.choice("flow", in: run.inputs.choices) == "Flow into next frame"
        let crossfade = tool.choice("between", in: run.inputs.choices) == "Crossfade" ? 0.5 : 0
        let music = run.inputs.audioFile
        for job in jobs {
            job.onFinish = { [weak self] job in
                progress.remaining.remove(job.id)
                if job.status == .finished, let id = job.assetIDs.first { progress.clips[job.id] = id } else { progress.failed = true }
                guard let self, progress.remaining.isEmpty, !progress.failed else { return }
                let clips = order.compactMap { progress.clips[$0].flatMap(self.library.asset) }
                guard clips.count == order.count, let first = clips.first else { return }
                let files = clips.map { self.library.url(for: $0) }
                Task {
                    await self.finishOnMac(first, title: L("Joining the storyboard clips…"), state: state) { _ in
                        var url = try await VideoMedia.join(files, trimSeams: flows, crossfade: crossfade)
                        if let music {
                            let mixed = try await VideoMedia.muxAudio(from: music, into: url)
                            try? FileManager.default.removeItem(at: url)
                            url = mixed
                        }
                        return (url, E("%ld shots joined", clips.count))
                    }
                }
            }
        }
    }

    private func runVideoOnDevice(_ tool: VideoTool, state: VideoState) {
        switch tool.id {
        case "reframeVideo":
            guard let source = state.source.assetID.flatMap(library.asset) else {
                presentError(FreefieldError.unsupported(L("Choose a video")))
                return
            }
            let target = state.choice("target", in: tool)
            guard let ratio = VideoModel.ratioValue(target) else { return }
            let file = library.url(for: source)
            runLocal(title: tool.name + " · " + target, tool: tool, state: state) {
                let url = try await VideoMedia.smartCrop(file, toAspect: ratio)
                return (url, [source], english(tool.name) + " · " + target)
            }
        case "colorGradeVideo":
            guard let source = state.source.assetID.flatMap(library.asset), source.isVideo else {
                presentError(FreefieldError.unsupported(L("Choose a video")))
                return
            }
            let lookID = state.choice("look", in: tool)
            let plan = VideoGradeLooks.plan(look: lookID, strength: state.choice("strength", in: tool))
            let name = VideoGradeLooks.look(lookID)?.name ?? lookID
            let file = library.url(for: source)
            runLocal(title: tool.name + " · " + name, tool: tool, state: state) {
                let url = try await VideoGrade.apply(file, plan: plan)
                return (url, [source], english(tool.name) + " · " + english(name))
            }
        case "joinClips":
            let edits = JoinTrimEdits.shared
            let parts = state.clipIDs.compactMap(library.asset).filter(\.isVideo)
                .map { VideoJoinPart(asset: $0, range: edits.ranges[$0.id]) }
            joinOnMac(parts, crossfade: edits.crossfade, trimSeams: edits.trimsSeams, music: state.audioFile, title: tool.name,
                      record: english(tool.name) + " · " + E("%ld clips", parts.count), tool: tool, state: state)
        default:
            presentError(FreefieldError.unsupported(L("This tool can't run with these settings.")))
        }
    }

    private func runLocal(title: String, tool: VideoTool, state: VideoState, _ body: @escaping () async throws -> (URL, [Asset], String)) {
        let work = VideoLocalWork(title: title)
        state.localWork.insert(work, at: 0)
        work.task = Task {
            do {
                let (url, sources, record) = try await body()
                let first = sources.first
                let template = Asset(
                    id: UUID(), fileName: "", createdAt: .now, width: 0, height: 0, tool: .video, prompt: record, finalPrompt: "",
                    modelID: "local", modelName: E("On this Mac"), provider: .openRouter, aspectRatio: .auto, resolution: .oneK,
                    batchID: UUID(), appID: tool.id, inputFileNames: [], cost: 0, isFavorite: false, mediaKind: .video,
                    parentAssetID: first?.id
                )
                guard let asset = await self.library.addVideo(file: url, template: template) else { throw VideoMediaError.unreadable }
                self.engine.recordLocal(title: record, tool: .video, modelName: E("On this Mac"), assetIDs: [asset.id], appID: tool.id)
                work.isDone = true
                state.localWork.removeAll { $0.id == work.id }
            } catch is CancellationError {
                state.localWork.removeAll { $0.id == work.id }
            } catch {
                work.failure = error.localizedDescription
            }
        }
    }

    func capacityFallback(for job: Job, tool: VideoTool, state: VideoState) -> VideoModel? {
        guard let spec = job.videoSpec, let record = state.runs[job.id], isCapacityFailure(job) else { return nil }
        let current = spec.request.model.id
        let filter = VideoRecipes.modelFilter(for: tool, state: record.inputs)
        let available = Dictionary(videoModels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ids = VideoRecipes.preferredModelIDs(for: tool, state: record.inputs) + VideoLineup.defaultModelIDs(for: tool.id)
        return ids.filter { $0 != current }.compactMap { available[$0] }.first { filter.allows($0) && isHealthy($0) }
    }

    func isCapacityFailure(_ job: Job) -> Bool {
        guard case .failed(let message) = job.status, !job.isStillAtProvider, let spec = job.videoSpec else { return false }
        if catalog.strained.contains(spec.request.model.id) { return true }
        let text = message.lowercased()
        return ["capacity", "overloaded", "busy", "503", "529", "rate limit", "out of quota", "sobrecarg", "capacidad"]
            .contains { text.contains($0) }
    }

    func retryVideo(_ job: Job, with model: VideoModel, tool: VideoTool, state: VideoState) {
        guard let record = state.runs[job.id],
              let recipe = VideoRecipes.request(for: tool, state: record.inputs, model: model) else {
            engine.retry(job)
            return
        }
        engine.dismiss(job)
        pruneRunRecords(state)
        let run = VideoRun(tool: tool, recipeTool: tool, model: model, inputs: record.inputs, count: 1,
                           parent: record.parentAssetID.flatMap(library.asset))
        var spec = jobSpec(recipe, run: run, state: state)
        spec.batchID = record.batchID
        let retried = engine.startVideo(spec)
        state.runs[retried.id] = VideoRunRecord(toolID: tool.id, inputs: record.inputs, modelID: model.id,
                                                parentAssetID: record.parentAssetID, batchID: record.batchID)
    }

    nonisolated static func cropped(_ image: InputImage, to ratio: String) -> InputImage? {
        guard let target = VideoModel.ratioValue(ratio), target > 0, let picture = ImageCoding.cgImage(from: image.data) else { return nil }
        let width = Double(picture.width), height = Double(picture.height)
        guard width > 0, height > 0 else { return nil }
        let current = width / height
        guard abs(current - target) / target > 0.01 else { return image }
        let rect = current > target
            ? CGRect(x: (width - height * target) / 2, y: 0, width: height * target, height: height)
            : CGRect(x: 0, y: (height - width / target) / 2, width: width, height: width / target)
        guard let cut = picture.cropping(to: rect.integral), let data = ImageCoding.encode(cut, as: .jpeg, quality: 0.92) else { return nil }
        return InputImage(data: data, mimeType: "image/jpeg", role: image.role)
    }
}

enum PhotorealCheck {
    static let instructions = """
    You check a photo before it's used as a reference for an AI video model. Answer whether it shows a photorealistic person: a photograph of a real human, or an image realistic enough to pass for one (AI-generated photos included). Drawings, cartoons, anime, paintings, illustrations, stylized 3D characters, toys, statues and pictures without a person don't count. Reply with JSON only: {"real_person": true} or {"real_person": false}.
    """

    static func showsRealPerson(_ data: Data, using app: AppModel) async -> Bool {
        guard app.canLookWithAI else { return false }
        let fingerprint = await AIChecks.fingerprint(data)
        let answer = await AIChecks.answer("real:" + fingerprint) {
            guard let image = await AIChecks.upload(data, maxPixel: 512),
                  let reply = try? await app.helperComplete(title: E("Check photo"), tool: .video, system: instructions,
                                                            user: "Check this photo.", images: [image]),
                  let real = AIChecks.flag((AIChecks.json(in: reply) as? [String: Any])?["real_person"]) else { return nil }
            return real ? 1 : 0
        }
        return answer == 1
    }
}

nonisolated enum VideoUnderstanding {
    struct Reply: Sendable {
        let text: String
        let cost: Double?
    }

    static let maxBytes = 20 * 1024 * 1024

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 300
        return URLSession(configuration: configuration)
    }()

    @concurrent
    static func complete(clip: URL, model: String, system: String, user: String, apiKey: String) async throws -> Reply {
        let data = try Data(contentsOf: clip)
        guard data.count <= maxBytes else { throw FreefieldError.unsupported(L("The clip is too large to describe.")) }
        let mime = UTType(filenameExtension: clip.pathExtension.lowercased())?.preferredMIMEType ?? "video/mp4"
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://freefield.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Freefield", forHTTPHeaderField: "X-OpenRouter-Title")
        let content: [[String: Any]] = [
            ["type": "text", "text": user],
            ["type": "video_url", "video_url": ["url": "data:\(mime);base64,\(data.base64EncodedString())"]],
        ]
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": content]],
            "temperature": 0.3,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.withoutEscapingSlashes])
        let (reply, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FreefieldError.decoding(L("no HTTP response")) }
        let object = try? JSONSerialization.jsonObject(with: reply) as? [String: Any]
        guard (200..<300).contains(http.statusCode) else {
            let message = ((object?["error"] as? [String: Any])?["message"] as? String) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw FreefieldError.http(status: http.statusCode, message: message)
        }
        let choices = object?["choices"] as? [[String: Any]]
        let text = ((choices?.first?["message"] as? [String: Any])?["content"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw FreefieldError.decoding(L("empty text response")) }
        let cost = ((object?["usage"] as? [String: Any])?["cost"] as? NSNumber)?.doubleValue
        return Reply(text: text, cost: cost)
    }
}

extension AppModel {
    func videoRunFingerprint(_ tool: VideoTool, state: VideoState, model: VideoModel, count: Int) -> Int {
        var hasher = Hasher()
        hasher.combine(tool.id)
        hasher.combine(model.id)
        hasher.combine(count)
        hasher.combine(state.prompt)
        hasher.combine(state.choices.sorted { $0.key < $1.key }.map { $0.key + "=" + $0.value })
        hasher.combine(state.texts.sorted { $0.key < $1.key }.map { $0.key + "=" + $0.value })
        hasher.combine(state.firstFrame)
        hasher.combine(state.lastFrame)
        hasher.combine(state.references)
        hasher.combine(state.characterID)
        hasher.combine(state.productID)
        hasher.combine(state.source.assetID)
        hasher.combine(state.source.link)
        hasher.combine(state.driving.assetID)
        hasher.combine(state.driving.link)
        hasher.combine(state.clipIDs)
        hasher.combine(state.shots.map { $0.action + "|" + ($0.camera ?? "") })
        hasher.combine(state.shots.map(\.image))
        hasher.combine(state.cameraMoves)
        hasher.combine(state.effectID)
        hasher.combine(state.duration)
        hasher.combine(state.resolution)
        hasher.combine(state.aspect)
        hasher.combine(state.audio)
        return hasher.finalize()
    }
}

struct VideoSizeOption: Hashable {
    let size: String
    let model: VideoModel
    let cost: Double?
}
