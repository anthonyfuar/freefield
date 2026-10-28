import AppKit
import Foundation
import FreefieldCore
import UserNotifications

struct JobSpec {
    var tool: Tool
    var title: String
    var record: String?
    var userTexts: [String] = []
    var literalTexts: [String] = []
    var prompt: String
    var model: ImageModel
    var aspectRatio: AspectRatio = .auto
    var resolution: Resolution = .oneK
    var count: Int = 1
    var seed: Int?
    var quality: String?
    var transparentBackground = false
    var images: [InputImage] = []
    var presetID: String?
    var characterID: UUID?
    var productID: UUID?
    var appID: String?

    private static let generationTools: Set<Tool> = [.create, .storyboard, .photoSession, .app, .ad]

    var sentPrompt: String {
        guard Self.generationTools.contains(tool) else { return prompt }
        let ratio = model.aspectRatios.isEmpty ? (aspectRatio == .auto ? nil : aspectRatio) : model.bestAspectRatio(for: aspectRatio)
        guard let ratio else { return prompt }
        let shape = ratio.ratio > 1.01 ? "horizontal" : ratio.ratio < 0.99 ? "vertical" : "square"
        let sentence = "Aspect ratio: \(shape) \(ratio.rawValue)."
        return prompt.contains(sentence) ? prompt : prompt + "\n\n" + sentence
    }
}

@Observable
final class GenerationEngine {
    private(set) var jobs: [Job] = []
    private let library: Library
    private let keys: () -> APIKeys
    var onModelStrained: ((String) -> Void)?
    var estimator: ((ImageModel, Resolution) -> Double?)?
    var guardrail: ((_ estimate: Double, _ inFlight: Double) -> String?)?
    var translator: ((JobSpec) async -> JobSpec)?
    var videoTranslator: ((VideoJobSpec) async -> VideoJobSpec)?
    let translations = TranslationCache()
    private(set) var quietJobs: [Job] = []
    @ObservationIgnored private var videoRecords: [UUID: PendingVideoJob] = [:]
    @ObservationIgnored private var unreadablePendingVideos: [JSONValue] = []
    @ObservationIgnored var clipSharing: ClipSharing?

    init(library: Library, keys: @escaping () -> APIKeys) {
        self.library = library
        self.keys = keys
    }

    var runningCount: Int { jobs.filter(\.isRunning).count }

    func jobs(for tool: Tool) -> [Job] { jobs.filter { $0.tool == tool } }

    var inFlightEstimate: Double {
        let images = jobs.filter(\.isRunning).reduce(0) { total, job in
            guard let spec = job.spec else { return total }
            return total + (estimator?(spec.model, spec.resolution) ?? 0) * Double(job.pending)
        }
        let videos = (jobs + quietJobs)
            .filter { $0.isVideo && ($0.isRunning || $0.isStillAtProvider) && !$0.costRecorded }
            .reduce(0) { total, job in
                total + (job.estimate ?? job.videoSpec.map { VideoPricing.ceiling(for: $0.request.model) } ?? 0)
            }
        return images + videos
    }

    func limitMessage(model: ImageModel, resolution: Resolution, images: Int) -> String? {
        let perImage = estimator?(model, resolution) ?? 0
        return guardrail?(perImage * Double(images), inFlightEstimate)
    }

    @discardableResult
    func start(_ spec: JobSpec) -> Job {
        let message = limitMessage(model: spec.model, resolution: spec.resolution, images: spec.count)
        let job = Job(tool: spec.tool, title: spec.title, requested: spec.count, aspectRatio: spec.aspectRatio, spec: spec)
        jobs.insert(job, at: 0)
        if let message {
            job.failures.append(message)
            job.status = .failed(message)
            return job
        }
        let service = ImageService(keys: keys())
        let count = spec.count
        let translator = translator
        updateDockBadge()
        job.task = Task {
            var spec = spec
            if spec.images.contains(where: { $0.uploadMaxPixel != nil }) {
                spec.images = await ImageCoding.preparedForUpload(spec.images)
                job.spec = spec
            }
            let inputNames = spec.images.map { self.library.storeInput($0) }
            if let translator, !spec.userTexts.isEmpty {
                spec = await translator(spec)
                job.spec = spec
            }
            let prompt = spec.sentPrompt
            let template = Asset(
                id: UUID(), fileName: "", createdAt: .now, width: 0, height: 0, tool: spec.tool,
                prompt: spec.record ?? english(spec.title), finalPrompt: prompt, modelID: spec.model.id,
                modelName: Lineup.models.first { $0.matches(spec.model) }?.name ?? spec.model.name,
                provider: spec.model.provider, aspectRatio: spec.aspectRatio, resolution: spec.resolution,
                batchID: job.id, presetID: spec.presetID, characterID: spec.characterID, productID: spec.productID, appID: spec.appID,
                inputFileNames: inputNames, cost: nil, seed: spec.seed, isFavorite: false
            )
            let request = ImageRequest(
                model: spec.model, prompt: prompt, images: spec.images, aspectRatio: spec.aspectRatio,
                resolution: spec.resolution, seed: spec.seed, count: spec.count, quality: spec.quality,
                transparentBackground: spec.transparentBackground
            )
            await service.generate(request, count: count) { [weak self] result in
                await self?.receive(result, for: job, template: template)
            }
            if job.received == 0, job.sawRateLimit {
                self.onModelStrained?(template.modelID)
            }
            self.finish(job)
        }
        return job
    }

    private func receive(_ result: Result<ImageResponse, Error>, for job: Job, template: Asset) {
        guard job.status == .running else { return }
        switch result {
        case .success(let response):
            let perImageCost = response.cost.map { $0 / Double(max(response.images.count, 1)) }
            var savedIDs: [UUID] = []
            for image in response.images {
                guard job.received < job.requested else { break }
                var asset = template
                asset.id = UUID()
                asset.createdAt = .now
                asset.cost = perImageCost
                asset.modelNote = response.text
                let saved = library.add(image, template: asset)
                job.assetIDs.append(saved.id)
                savedIDs.append(saved.id)
                job.received += 1
            }
            guard !savedIDs.isEmpty, let spec = job.spec else { return }
            let estimate = (estimator?(spec.model, spec.resolution) ?? 0) * Double(savedIDs.count)
            library.record(UsageEntry(
                date: .now, kind: .image, tool: template.tool, title: template.prompt,
                modelID: template.modelID, modelName: template.modelName, provider: template.provider,
                cost: response.cost ?? estimate, isEstimated: response.cost == nil,
                imageCount: savedIDs.count, assetIDs: savedIDs
            ))
        case .failure(let error):
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            if case FreefieldError.rateLimited = error { job.sawRateLimit = true }
            job.failures.append(error.localizedDescription)
        }
    }

    private func finish(_ job: Job) {
        guard job.status == .running else { return }
        if job.received == 0 {
            job.status = .failed(job.failures.first ?? L("No image was generated."))
        } else {
            job.status = .finished
        }
        updateDockBadge()
        notifyIfInBackground(job)
        job.onFinish?(job)
        job.onFinish = nil
    }

    func insert(_ job: Job) {
        jobs.insert(job, at: 0)
    }

    func libraryAdd(_ image: GeneratedImage, template: Asset) -> Asset {
        library.add(image, template: template)
    }

    func recordLocal(title: String, tool: Tool, modelName: String, assetIDs: [UUID], appID: String? = nil) {
        library.record(UsageEntry(
            date: .now, kind: .local, tool: tool, title: english(title), modelID: "local", modelName: english(modelName),
            provider: nil, cost: 0, isEstimated: false, imageCount: assetIDs.count, assetIDs: assetIDs, appID: appID
        ))
    }

    func cancel(_ job: Job) {
        if job.isVideo, job.isRunning, job.remoteID != nil || job.isSendingVideo {
            stopWaiting(job)
            return
        }
        job.task?.cancel()
        job.status = .cancelled
        if job.isVideo {
            clipSharing?.release(job.id)
            forgetVideo(job)
        }
        updateDockBadge()
    }

    func retry(_ job: Job) {
        if let videoSpec = job.videoSpec {
            if job.isStillAtProvider {
                checkAgain(job)
                return
            }
            dismiss(job)
            startVideo(videoSpec)
            return
        }
        guard let spec = job.spec else { return }
        dismiss(job)
        start(spec)
    }

    func dismiss(_ job: Job) {
        if job.isRunning { cancel(job) }
        if job.isVideo, !job.isRunning, !job.isQuiet {
            if job.isStillAtProvider {
                keepQuietly(job)
            } else {
                forgetVideo(job)
            }
        }
        jobs.removeAll { $0.id == job.id }
    }

    func dismissFinished(for tool: Tool) {
        jobs.removeAll { $0.tool == tool && !$0.isRunning }
    }

    private func updateDockBadge() {
        let running = runningCount
        NSApp?.dockTile.badgeLabel = running > 0 ? "\(running)" : nil
    }

    private func notifyIfInBackground(_ job: Job) {
        guard NSApp?.isActive == false else { return }
        let content = UNMutableNotificationContent()
        switch job.status {
        case .finished where job.isVideo:
            content.title = job.isQuiet ? L("A video you stopped waiting for is ready") : L("Your video is ready")
        case .finished:
            content.title = job.received == 1 ? L("Your image is ready") : L("Your %ld images are ready", job.received)
        case .failed(let message):
            content.title = job.isVideo ? L("Couldn't make the video") : L("Couldn't generate")
            content.subtitle = message
        default:
            return
        }
        content.body = job.title
        let request = UNNotificationRequest(identifier: job.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

extension GenerationEngine {
    static var videoKeyMessage: String { L("Video needs an OpenRouter or Google key. Add one in Settings.") }

    static func videoKeyMessage(for provider: Provider) -> String {
        provider == .google ? L("This video model runs on your Google key. Add it again in Settings.")
            : L("Video needs an OpenRouter key. Add one in Settings.")
    }

    func videoJobs(for toolID: String) -> [Job] {
        jobs.filter { $0.videoSpec?.toolID == toolID }
    }

    func videoLimitMessage(for spec: VideoJobSpec, count: Int = 1) -> String? {
        guardrail?(spec.guardedCost * Double(count), inFlightEstimate)
    }

    var isSendingVideos: Bool { (jobs + quietJobs).contains { $0.isSendingVideo } }

    @discardableResult
    func startVideo(_ spec: VideoJobSpec) -> Job {
        let estimate = spec.estimatedCost
        let message = guardrail?(spec.guardedCost, inFlightEstimate)
        let job = Job(tool: .video, title: spec.title, requested: 1,
                      aspectRatio: spec.request.aspectRatio.flatMap(AspectRatio.init(rawValue:)) ?? .auto)
        job.videoSpec = spec
        job.estimate = estimate
        job.videoPhase = .submitting
        jobs.insert(job, at: 0)
        let closedLinks = clipSharing?.claim(spec.request, job: job.id) ?? []
        let host = spec.request.model.host
        guard let apiKey = keys().key(for: host) else {
            failVideo(job, Self.videoKeyMessage(for: host))
            return job
        }
        if let message {
            failVideo(job, message)
            return job
        }
        var stored = StoredVideoSpec(spec) { library.storeInput($0) }
        stored.batchID = stored.batchID ?? job.id
        videoRecords[job.id] = PendingVideoJob(remoteID: "", submittedAt: .now, estimate: estimate, spec: stored,
                                               inputFileNames: stored.inputFileNames)
        let translator = videoTranslator
        updateDockBadge()
        job.task = Task {
            var spec = spec
            if let translator, !spec.userTexts.isEmpty {
                spec = await translator(spec)
                job.videoSpec = spec
                self.videoRecords[job.id]?.spec.update(from: spec)
            }
            guard !Task.isCancelled, job.isRunning else { return }
            if !closedLinks.isEmpty, let sharing = self.clipSharing {
                do {
                    let fallbacks = self.sourceFiles(for: spec, links: closedLinks)
                    let replaced = try await sharing.reshare(closedLinks, job: job.id, fallbacks: fallbacks,
                                                             fullSize: ClipSharing.sharesFullSize(spec.toolID))
                    spec.request.references = spec.request.references.map { Self.replacingLink(in: $0, replaced) }
                    job.videoSpec = spec
                    if var record = self.videoRecords[job.id] {
                        for index in record.spec.references.indices where record.spec.references[index].kind != .image {
                            if let fresh = replaced[record.spec.references[index].value] { record.spec.references[index].value = fresh }
                        }
                        self.videoRecords[job.id] = record
                    }
                } catch {
                    guard !Self.isCancellation(error), job.isRunning else { return }
                    self.failVideo(job, error.localizedDescription)
                    self.forgetVideo(job)
                    return
                }
                guard !Task.isCancelled, job.isRunning else {
                    sharing.release(job.id)
                    return
                }
            }
            job.isSendingVideo = true
            let remoteID: String
            do {
                remoteID = try await self.submitVideo(spec.request, apiKey: apiKey)
                job.isSendingVideo = false
            } catch {
                job.isSendingVideo = false
                guard !Self.isCancellation(error), job.isRunning else { return }
                if case FreefieldError.rateLimited = error { self.onModelStrained?(spec.request.model.id) }
                let message = Self.mayHaveBeenAccepted(error)
                    ? (host == .google
                        ? L("Google didn't confirm this video (%@). It may still have been created and billed, so Freefield didn't send it again. Check your usage in Google AI Studio before retrying.", error.localizedDescription)
                        : L("OpenRouter didn't confirm this video (%@). It may still have been created and billed, so Freefield didn't send it again. Check your activity at openrouter.ai before retrying.", error.localizedDescription))
                    : VideoFailure.message(for: error, request: spec.request)
                self.failVideo(job, message)
                self.forgetVideo(job)
                return
            }
            let submittedAt = Date()
            job.remoteID = remoteID
            job.submittedAt = submittedAt
            job.remoteState = .pending
            job.videoPhase = .waiting
            self.videoRecords[job.id]?.remoteID = remoteID
            self.videoRecords[job.id]?.submittedAt = submittedAt
            self.savePendingVideos()
            await self.pollVideo(job, until: submittedAt.addingTimeInterval(VideoPolling.patience))
        }
        return job
    }

    func stopWaiting(_ job: Job, discardResult: Bool = false) {
        guard job.isVideo, job.isRunning else { return }
        guard job.remoteID != nil || job.isSendingVideo else {
            cancel(job)
            jobs.removeAll { $0.id == job.id }
            return
        }
        job.isQuiet = true
        job.discardsResult = discardResult
        jobs.removeAll { $0.id == job.id }
        if !quietJobs.contains(where: { $0.id == job.id }) { quietJobs.append(job) }
        videoRecords[job.id]?.isQuiet = true
        videoRecords[job.id]?.discardsResult = discardResult
        savePendingVideos()
        updateDockBadge()
    }

    private func keepQuietly(_ job: Job) {
        job.isQuiet = true
        videoRecords[job.id]?.isQuiet = true
        savePendingVideos()
        if !quietJobs.contains(where: { $0.id == job.id }) { quietJobs.append(job) }
    }

    func suspendVideosForRelaunch() {
        for job in jobs + quietJobs where job.isVideo && job.isRunning && job.remoteID != nil && !job.isSendingVideo {
            job.task?.cancel()
            job.task = nil
            job.status = .cancelled
            job.videoPhase = nil
        }
        updateDockBadge()
    }

    func checkAgain(_ job: Job) {
        guard job.isVideo, job.remoteID != nil, !job.isRunning, job.isStillAtProvider else { return }
        job.status = .running
        job.videoPhase = .waiting
        job.failures = []
        updateDockBadge()
        job.task = Task {
            await self.pollVideo(job, until: Date().addingTimeInterval(VideoPolling.recheckPatience))
        }
    }

    func resumeSuspendedVideos() {
        for job in jobs + quietJobs
        where job.isVideo && job.status == .cancelled && job.remoteID != nil && videoRecords[job.id] != nil {
            job.status = .running
            job.videoPhase = .waiting
            let deadline = (job.submittedAt ?? .now).addingTimeInterval(VideoPolling.patience)
            job.task = Task { await self.pollVideo(job, until: deadline) }
        }
        updateDockBadge()
    }

    func resumePendingVideos() {
        let url = library.pendingVideosURL
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let entries = try? decoder.decode([PendingVideoEntry].self, from: data) else {
            let aside = library.root.appendingPathComponent("pending-videos-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            return
        }
        unreadablePendingVideos = entries.compactMap(\.unreadable)
        let known = Set((jobs + quietJobs).compactMap(\.remoteID))
        var finishedBefore = false
        for record in entries.compactMap(\.record).sorted(by: { $0.submittedAt < $1.submittedAt })
        where !record.remoteID.isEmpty && !known.contains(record.remoteID) {
            let filed = max(record.filedOutputs ?? 0, library.assets.count { $0.remoteJobID == record.remoteID })
            if let outputs = record.outputCount, filed >= outputs, record.usageEntryID != nil {
                finishedBefore = true
                continue
            }
            let library = library
            let spec = record.spec.restored { name in try? Data(contentsOf: library.inputURL(name)) }
            let job = Job(tool: .video, title: spec.title, requested: 1,
                          aspectRatio: spec.request.aspectRatio.flatMap(AspectRatio.init(rawValue:)) ?? .auto)
            job.videoSpec = spec
            job.remoteID = record.remoteID
            job.submittedAt = record.submittedAt
            job.estimate = record.estimate
            job.remoteState = .pending
            job.videoPhase = .waiting
            job.isQuiet = record.isQuiet ?? false
            job.discardsResult = record.discardsResult ?? false
            job.costRecorded = record.usageEntryID != nil
            videoRecords[job.id] = record
            if job.isQuiet { quietJobs.append(job) } else { jobs.insert(job, at: 0) }
            job.task = Task {
                await self.pollVideo(job, until: record.submittedAt.addingTimeInterval(VideoPolling.patience))
            }
        }
        if finishedBefore { savePendingVideos() }
        updateDockBadge()
    }

    private func submitVideo(_ request: VideoRequest, apiKey: String) async throws -> String {
        var attempt = 0
        while true {
            do {
                switch request.model.host {
                case .google: return try await GeminiClient(apiKey: apiKey).submitVideo(request)
                case .openRouter: return try await OpenRouterClient(apiKey: apiKey).submitVideo(request)
                }
            } catch {
                attempt += 1
                guard case FreefieldError.rateLimited = error, attempt <= 3, !Self.isCancellation(error) else { throw error }
                try await Task.sleep(for: .seconds([5.0, 20, 45][min(attempt - 1, 2)]))
            }
        }
    }

    private static func mayHaveBeenAccepted(_ error: any Error) -> Bool {
        switch error {
        case FreefieldError.http(let status, _): [408, 500, 502, 504, 520, 522, 524].contains(status)
        case let error as URLError: [.timedOut, .networkConnectionLost].contains(error.code)
        default: false
        }
    }

    private func pollVideo(_ job: Job, until deadline: Date) async {
        guard let remoteID = job.remoteID, let spec = job.videoSpec else { return }
        let submittedAt = job.submittedAt ?? .now
        let host = spec.request.model.host
        var checks = 0
        var failures = 0
        while true {
            let wait = VideoPolling.delay(elapsed: Date().timeIntervalSince(submittedAt), checks: checks, failures: failures)
            do { try await Task.sleep(for: .seconds(wait)) } catch { return }
            guard job.isRunning else { return }
            guard let apiKey = keys().key(for: host) else {
                stillAtProvider(job, host == .google
                    ? L("This video is still at Google. Add your Google key again to get it.")
                    : L("This video is still at OpenRouter. Add your OpenRouter key again to get it."))
                return
            }
            checks += 1
            do {
                let status = switch host {
                case .google: try await GeminiClient(apiKey: apiKey).videoStatus(remoteID)
                case .openRouter: try await OpenRouterClient(apiKey: apiKey).videoStatus(remoteID)
                }
                guard job.isRunning else { return }
                failures = 0
                job.remoteState = status.state
                switch status.state {
                case .completed:
                    clipSharing?.release(job.id)
                    await deliverVideo(job, status: status, apiKey: apiKey)
                    return
                case .failed, .cancelled, .expired:
                    failVideo(job, VideoFailure.message(for: status, request: spec.request))
                    forgetVideo(job)
                    return
                case .inProgress:
                    clipSharing?.jobAdvanced(job.id)
                case .pending:
                    break
                }
            } catch {
                if Self.isCancellation(error) { return }
                switch error {
                case is VideoJobGone:
                    failVideo(job, error.localizedDescription)
                    forgetVideo(job)
                    return
                case FreefieldError.invalidKey, FreefieldError.limitReached, FreefieldError.insufficientCredits:
                    stillAtProvider(job, error.localizedDescription)
                    return
                default:
                    failures += 1
                }
            }
            if Date() >= deadline {
                stillAtProvider(job, L("This video is still at the provider after a long wait. It may still finish: check again later, and it's filed in the library when it does."))
                return
            }
        }
    }

    private func deliverVideo(_ job: Job, status: VideoJobStatus, apiKey: String) async {
        guard let spec = job.videoSpec, let remoteID = job.remoteID else { return }
        let outputs = max(1, status.contentURLs.count)
        videoRecords[job.id]?.outputCount = outputs
        if job.discardsResult {
            recordVideoUsage(job, status: status, assets: [])
            forgetVideo(job)
            finishVideo(job, notifies: false)
            return
        }
        job.videoPhase = .downloading
        let inputs = videoRecords[job.id]?.inputFileNames ?? []
        let filedBefore = Array(library.assets.filter { $0.remoteJobID == remoteID }.reversed())
        var filed = max(videoRecords[job.id]?.filedOutputs ?? 0, filedBefore.count)
        var saved: [Asset] = []
        var failure: (any Error)?
        while filed < outputs {
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Freefield-\(UUID().uuidString).mp4")
            do {
                try await downloadVideo(spec.request.model.host, apiKey: apiKey, status: status, id: remoteID, index: filed, to: temporary)
            } catch {
                if Self.isCancellation(error) { return }
                failure = error
                break
            }
            guard !Task.isCancelled else {
                try? FileManager.default.removeItem(at: temporary)
                return
            }
            var template = videoTemplate(spec, job: job, remoteID: remoteID, inputs: inputs)
            template.cost = status.cost.map { $0 / Double(outputs) }
            guard let asset = await library.addVideo(file: temporary, template: template) else {
                try? FileManager.default.removeItem(at: temporary)
                failure = VideoMediaError.unreadable
                break
            }
            saved.append(asset)
            filed += 1
            library.flush()
            videoRecords[job.id]?.filedOutputs = filed
            savePendingVideos()
        }
        recordVideoUsage(job, status: status, assets: videoRecords[job.id]?.usageEntryID == nil ? filedBefore + saved : saved)
        job.assetIDs = (filedBefore + saved).map(\.id)
        job.received = job.assetIDs.count
        guard filed < outputs else {
            forgetVideo(job)
            finishVideo(job)
            return
        }
        let reason = failure.map { VideoFailure.message(for: $0, request: spec.request) } ?? L("No video was returned.")
        if failure is VideoJobGone {
            failVideo(job, reason)
            forgetVideo(job)
        } else {
            stillAtProvider(job, L("The video is ready but couldn't be downloaded (%@). Check again to retry the download.", reason))
        }
    }

    private func downloadVideo(_ host: Provider, apiKey: String, status: VideoJobStatus, id: String, index: Int,
                               to destination: URL) async throws {
        var attempt = 0
        while true {
            do {
                switch host {
                case .google:
                    guard status.contentURLs.indices.contains(index) else {
                        throw VideoJobGone(message: L("Google finished the job without a video."))
                    }
                    try await GeminiClient(apiKey: apiKey).downloadVideo(from: status.contentURLs[index], to: destination)
                case .openRouter:
                    try await OpenRouterClient(apiKey: apiKey).downloadVideo(id, index: index, to: destination)
                }
                return
            } catch {
                attempt += 1
                let temporary = switch error {
                case FreefieldError.http(409, _): true
                case let error as FreefieldError: error.isTransient
                default: error is URLError
                }
                guard temporary, attempt < 4, !Self.isCancellation(error) else { throw error }
                try await Task.sleep(for: .seconds(5 * Double(attempt)))
            }
        }
    }

    private func recordVideoUsage(_ job: Job, status: VideoJobStatus, assets: [Asset]) {
        guard let spec = job.videoSpec else { return }
        let model = spec.request.model
        let seconds = assets.compactMap(\.duration).reduce(0, +)
        job.costRecorded = true
        if let entryID = videoRecords[job.id]?.usageEntryID {
            library.addAssets(assets.map(\.id), toUsage: entryID, seconds: seconds > 0 ? seconds : nil)
            return
        }
        let requested = OpenRouterClient.videoDuration(for: spec.request).map(Double.init) ?? spec.sourceDuration
        let entry = UsageEntry(
            date: .now, kind: .video, tool: .video, title: spec.record ?? english(spec.title),
            modelID: "\(model.host.rawValue):\(model.id)",
            modelName: VideoLineup.displayName(for: model.id, fallback: model.name), provider: model.host,
            cost: status.cost ?? job.estimate ?? 0, isEstimated: status.cost == nil,
            imageCount: assets.count, assetIDs: assets.map(\.id), seconds: seconds > 0 ? seconds : requested,
            appID: spec.toolID
        )
        library.record(entry)
        library.flush()
        videoRecords[job.id]?.usageEntryID = entry.id
        savePendingVideos()
    }

    private func videoTemplate(_ spec: VideoJobSpec, job: Job, remoteID: String, inputs: [String]) -> Asset {
        let request = spec.request
        let model = request.model
        let label = model.clampedResolution(request.resolution) ?? request.resolution
        let tier: Resolution = switch VideoModel.rank(of: label ?? "") {
        case 2160...: .fourK
        case 1440..<2160: .twoK
        default: .oneK
        }
        return Asset(
            id: UUID(), fileName: "", createdAt: .now, width: 0, height: 0, tool: .video,
            prompt: spec.record ?? english(spec.title), finalPrompt: request.prompt,
            modelID: "\(model.host.rawValue):\(model.id)",
            modelName: VideoLineup.displayName(for: model.id, fallback: model.name), provider: model.host,
            aspectRatio: request.aspectRatio.flatMap(AspectRatio.init(rawValue:)) ?? .auto, resolution: tier,
            batchID: spec.batchID ?? job.id, presetID: spec.presetID, characterID: spec.characterID, productID: spec.productID,
            appID: spec.toolID, inputFileNames: inputs, cost: nil, seed: model.supportsSeed ? request.seed : nil,
            isFavorite: false, mediaKind: .video, videoResolution: label, remoteJobID: remoteID, parentAssetID: spec.parentAssetID
        )
    }

    private func finishVideo(_ job: Job, notifies: Bool = true) {
        clipSharing?.release(job.id)
        job.status = .finished
        job.videoPhase = nil
        if job.isQuiet { quietJobs.removeAll { $0.id == job.id } }
        updateDockBadge()
        if notifies { notifyIfInBackground(job) }
        job.onFinish?(job)
        job.onFinish = nil
    }

    private func failVideo(_ job: Job, _ message: String) {
        clipSharing?.release(job.id)
        job.failures.append(message)
        job.status = .failed(message)
        job.videoPhase = nil
        if job.isQuiet { quietJobs.removeAll { $0.id == job.id } }
        updateDockBadge()
        notifyIfInBackground(job)
        job.onFinish?(job)
        job.onFinish = nil
    }

    private func stillAtProvider(_ job: Job, _ message: String) {
        job.failures = [message]
        job.status = .failed(message)
        job.videoPhase = .stillAtProvider
        updateDockBadge()
    }

    private func forgetVideo(_ job: Job) {
        guard videoRecords.removeValue(forKey: job.id) != nil else { return }
        library.flush()
        savePendingVideos()
    }

    private func savePendingVideos() {
        let url = library.pendingVideosURL
        let pending = videoRecords.values.filter { !$0.remoteID.isEmpty }.sorted { $0.submittedAt < $1.submittedAt }
        guard !pending.isEmpty || !unreadablePendingVideos.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let entries = pending.map(PendingVideoEntry.init(record:)) + unreadablePendingVideos.map(PendingVideoEntry.init(unreadable:))
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private func sourceFiles(for spec: VideoJobSpec, links: [String]) -> [String: URL] {
        guard let asset = spec.parentAssetID.flatMap(library.asset), asset.isVideo else { return [:] }
        let file = library.url(for: asset)
        var files: [String: URL] = [:]
        for case .videoURL(let link) in spec.request.references where links.contains(link) { files[link] = file }
        return files
    }

    private static func replacingLink(in input: VideoInput, _ replaced: [String: String]) -> VideoInput {
        switch input {
        case .videoURL(let url): .videoURL(replaced[url] ?? url)
        case .audioURL(let url): .audioURL(replaced[url] ?? url)
        case .image: input
        }
    }
}
