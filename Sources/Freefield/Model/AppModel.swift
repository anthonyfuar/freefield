import AppKit
import AVFoundation
import Foundation
import FreefieldCore
import SwiftUI
import UniformTypeIdentifiers

enum SettingsKey {
    static let preferredProvider = "preferredProvider"
    static let showAllModels = "showAllModels"
    static let helperModelID = "helperModelID"
    static let autoEnhance = "autoEnhance"
    static let defaultModelID = "defaultModelID"
    static let autoExport = "autoExport"
    static let exportFolder = "exportFolder"
    static let confirmCostAbove = "confirmCostAbove"
    static let appearance = "appearance"
    static let language = "language"
    static let shareClipsWithTunnel = "shareClipsWithTunnel"
    static let recentTools = "home.recentTools"

    static var sharesClips: Bool {
        UserDefaults.standard.object(forKey: shareClipsWithTunnel) as? Bool ?? true
    }

    static var exportFolderURL: URL {
        if let path = UserDefaults.standard.string(forKey: exportFolder), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Freefield", isDirectory: true)
    }
}

@Observable
final class AppModel {
    var keys: APIKeys
    let library: Library
    let catalog = ModelCatalog()
    @ObservationIgnored private(set) var engine: GenerationEngine!

    var selection: SidebarItem? = .home {
        didSet { if let selection, selection != oldValue { noteRecent(selection) } }
    }
    private(set) var recentToolIDs: [String] = AppModel.loadRecentTools()
    var showOnboarding = false
    var inspectedAssetID: UUID?
    var quickLookURL: URL?
    var creatingCharacter = false
    var creatingProduct = false
    var creatingElement: SceneElementKind?
    var charactersPage: CharactersPage = .people
    var presentedError: String?
    var adStates: [String: AdState] = [:]
    var videoStates: [String: VideoState] = [:]
    var recentVideoRuns: [Int: Date] = [:]
    var pendingQuickStyle: String?
    var pendingVideoEffect: String?
    var composers: [Tool: ComposerState] = [:]
    var handoff: [Tool: Data] = [:]
    let clipSharing = ClipSharing()
    private(set) var pastedInputLinks: [String: String] = [:]
    private(set) var sharesClipsFromMac = SettingsKey.sharesClips
    @ObservationIgnored private var defaultsObserver: (any NSObjectProtocol)?

    init() {
        keys = CredentialStore.loadKeys()
        library = Library()
        engine = GenerationEngine(library: library) { [unowned self] in self.keys }
        engine.onModelStrained = { [unowned self] id in self.catalog.markStrained(id) }
        engine.estimator = { [unowned self] model, resolution in
            self.estimatedCost(model: model, count: 1, resolution: resolution)
        }
        engine.guardrail = { [unowned self] estimate, inFlight in self.limitViolation(adding: estimate, inFlight: inFlight) }
        engine.translator = { [unowned self] spec in await self.translateUserTexts(spec) }
        engine.videoTranslator = { [unowned self] spec in await self.translateVideoTexts(spec) }
        engine.clipSharing = clipSharing
        clipSharing.stopLeftovers()
        showOnboarding = keys.configuredProviders.isEmpty
        engine.resumePendingVideos()
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                                                  queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let shares = SettingsKey.sharesClips
                if self.sharesClipsFromMac != shares { self.sharesClipsFromMac = shares }
            }
        }
    }

    var preferredProvider: Provider {
        let raw = UserDefaults.standard.string(forKey: SettingsKey.preferredProvider)
        let preferred = raw.flatMap(Provider.init(rawValue:)) ?? .openRouter
        return keys.key(for: preferred) != nil ? preferred : (keys.configuredProviders.first ?? .openRouter)
    }

    var hasAnyKey: Bool { !keys.configuredProviders.isEmpty }

    func composer(for tool: Tool) -> ComposerState {
        if let existing = composers[tool] { return existing }
        let state = ComposerState(tool: tool)
        composers[tool] = state
        return state
    }

    func limitViolation(adding estimate: Double, inFlight: Double = 0) -> String? {
        for limit in UsageLimits.load().all {
            let spent = library.spent(in: limit.period.interval())
            if spent + inFlight + estimate > limit.amount + 0.000_1 {
                if inFlight > 0.000_1 {
                    return L("Your %@ limit of %@ has been reached (spent %@, about %@ more for runs in progress, and this would add about %@). Change it in Usage & Limits.",
                             limit.name, Self.money(limit.amount), Self.money(spent), Self.money(inFlight), Self.money(estimate))
                }
                return L("Your %@ limit of %@ has been reached (spent %@, this would add about %@). Change it in Usage & Limits.",
                         limit.name, Self.money(limit.amount), Self.money(spent), Self.money(estimate))
            }
        }
        return nil
    }

    static func money(_ value: Double, decimals: Int? = nil) -> String {
        if decimals == nil, value > 0, value < 0.0005 { return "<$0.001" }
        let places = decimals ?? (value != 0 && abs(value) < 1 ? 3 : 2)
        let number = abs(value).formatted(.number.precision(.fractionLength(places)).locale(Locale(identifier: "en_US")))
        return (value < 0 ? "-$" : "$") + number
    }

    func saveKey(_ value: String?, for provider: Provider) -> Bool {
        let saved = CredentialStore.save(value, for: provider)
        keys = CredentialStore.loadKeys()
        Task { await refreshModels() }
        return saved
    }

    func refreshModels() async {
        if catalog.lastRefresh == nil { await catalog.restoreSaved(keys: keys) }
        await catalog.refresh(keys: keys)
    }

    func open(_ tool: Tool, with asset: Asset? = nil) {
        guard asset?.isVideo != true else { return }
        if let asset, let data = library.imageData(for: asset) {
            handoff[tool] = data
        }
        selection = .tool(tool)
    }

    func takeHandoff(for tool: Tool) -> Data? {
        defer { handoff[tool] = nil }
        return handoff[tool]
    }

    private static let recentLimit = 6

    var recentTools: [SidebarItem] { recentToolIDs.compactMap(SidebarItem.init(recentID:)) }

    private func noteRecent(_ item: SidebarItem) {
        guard let id = item.recentID else { return }
        var ids = recentToolIDs.filter { $0 != id }
        ids.insert(id, at: 0)
        recentToolIDs = Array(ids.prefix(Self.recentLimit))
        UserDefaults.standard.set(recentToolIDs.joined(separator: ","), forKey: SettingsKey.recentTools)
    }

    private static func loadRecentTools() -> [String] {
        (UserDefaults.standard.string(forKey: SettingsKey.recentTools) ?? "").split(separator: ",").map(String.init)
    }
}

extension AppModel {
    var canMakeVideos: Bool { keys.openRouter != nil || keys.google != nil }

    var videoModels: [VideoModel] { catalog.availableVideoModels }

    func defaultVideoModel(for toolID: String) -> VideoModel? {
        catalog.defaultVideoModel(for: toolID)
    }

    func openVideo(_ toolID: String) {
        selection = .video(toolID)
    }

    func videoSourceURL(for asset: Asset, link: String? = nil) async throws -> String {
        guard asset.isVideo else {
            throw FreefieldError.unsupported(L("Choose a video clip."))
        }
        return try await videoSourceURL(forFile: library.url(for: asset), link: link)
    }

    func videoSourceURL(forFile file: URL, link: String? = nil, fullSize: Bool = false) async throws -> String {
        if let link = link?.trimmingCharacters(in: .whitespacesAndNewlines), !link.isEmpty {
            return try InputLink.checked(link)
        }
        let key = try inputFileKey(file)
        if let pasted = pastedInputLinks[key] { return pasted }
        guard SettingsKey.sharesClips else { throw VideoInputError.sharingOff }
        return try await clipSharing.link(for: file, key: key, fullSize: fullSize)
    }

    func pastedLink(forFile file: URL) -> String? {
        (try? inputFileKey(file)).flatMap { pastedInputLinks[$0] }
    }

    func setPastedLink(_ link: String?, forFile file: URL) throws {
        let key = try inputFileKey(file)
        guard let link = link?.trimmingCharacters(in: .whitespacesAndNewlines), !link.isEmpty else {
            pastedInputLinks[key] = nil
            return
        }
        pastedInputLinks[key] = try InputLink.checked(link)
    }

    func pastedLink(for asset: Asset) -> String? {
        pastedLink(forFile: library.url(for: asset))
    }

    func setPastedLink(_ link: String?, for asset: Asset) throws {
        try setPastedLink(link, forFile: library.url(for: asset))
    }

    private func inputFileKey(_ file: URL) throws -> String {
        try ClipSharing.fileKey(file)
    }

    func translateVideoTexts(_ spec: VideoJobSpec) async -> VideoJobSpec {
        let carrier = ImageModel(provider: .openRouter, modelID: spec.request.model.id, name: spec.request.model.name,
                                 vendor: spec.request.model.vendor, summary: "", endpoint: .openRouterImages,
                                 aspectRatios: [], resolutions: [])
        let wrapped = JobSpec(tool: .video, title: spec.title, record: spec.record, userTexts: spec.userTexts,
                              literalTexts: spec.literalTexts, prompt: spec.request.prompt, model: carrier)
        let translated = await translateUserTexts(wrapped)
        var result = spec
        result.request.prompt = translated.prompt
        result.record = translated.record
        result.userTexts = translated.userTexts
        return result
    }
}

enum VideoInputError: LocalizedError, Equatable {
    case sharingOff
    case couldNotShare(String)
    case busy
    case linkExpired

    var errorDescription: String? {
        switch self {
        case .sharingOff:
            L("Sharing clips from this Mac is off (Settings ▸ General ▸ Privacy). Paste a link to the file (https) or use frame-based mode.")
        case .couldNotShare(let reason):
            L("Couldn't share the file from this Mac. %@ You can paste a link to the file (https) or use frame-based mode.", reason)
        case .busy:
            L("Freefield is already sharing 3 files for videos on their way. Try again in a moment, or paste a link to the file (https).")
        case .linkExpired:
            L("The clip was shared from this Mac in an earlier session and that link has closed. Pick the clip again in the tool and press Generate.")
        }
    }
}

@Observable
final class ClipSharing {
    private struct Share {
        let id: UUID
        let key: String
        let session: TunnelSession
        let copy: URL?
        var claims: Set<UUID> = []
        var fetched = 0
        var closeTask: Task<Void, Never>?

        var link: String { session.publicURL.absoluteString }
    }

    static let maxShares = 3
    static let unclaimedLifetime: Duration = .seconds(120)
    static let grace: Duration = .seconds(10)

    private struct Source {
        let file: URL
        let fullSize: Bool
    }

    @ObservationIgnored private let setup: TunnelSetup
    private var shares: [UUID: Share] = [:]
    @ObservationIgnored private var opening: [String: Task<String, any Error>] = [:]
    @ObservationIgnored private var issued: [String: Source] = [:]

    init(setup: TunnelSetup = .standard) {
        self.setup = setup
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeAll() }
        }
    }

    func stopLeftovers() {
        let file = setup.processFile
        Task.detached(priority: .utility) { QuickTunnel.stopLeftovers(processFile: file) }
    }

    var openCount: Int {
        prune()
        return shares.count
    }

    func link(for file: URL, key fileKey: String, fullSize: Bool = false) async throws -> String {
        prune()
        let key = fullSize ? fileKey + "|full" : fileKey
        if let share = shares.values.first(where: { $0.key == key }) {
            if share.claims.isEmpty { scheduleClose(share.id, after: Self.unclaimedLifetime) }
            return share.link
        }
        if let running = opening[key] { return try await running.value }
        guard shares.count + opening.count < Self.maxShares else { throw VideoInputError.busy }
        let task = Task { try await self.open(file, key: key, fullSize: fullSize) }
        opening[key] = task
        defer { if opening[key] == task { opening[key] = nil } }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    static func links(in request: VideoRequest) -> [String] {
        request.references.compactMap { input in
            switch input {
            case .videoURL(let url), .audioURL(let url): url
            case .image: nil
            }
        }
    }

    func claim(_ request: VideoRequest, job: UUID) -> [String] {
        prune()
        var closed: [String] = []
        for link in Set(Self.links(in: request)) where !claim(link, job: job) && (issued[link] != nil || Self.isTunnelLink(link)) {
            closed.append(link)
        }
        return closed
    }

    func reshare(_ links: [String], job: UUID, fallbacks: [String: URL] = [:],
                 fullSize: Bool = false) async throws -> [String: String] {
        var replaced: [String: String] = [:]
        for link in links {
            guard let source = issued[link] ?? fallbacks[link].map({ Source(file: $0, fullSize: fullSize) }) else {
                throw VideoInputError.linkExpired
            }
            guard SettingsKey.sharesClips else { throw VideoInputError.sharingOff }
            let key: String
            do {
                key = try Self.fileKey(source.file)
            } catch {
                throw VideoInputError.couldNotShare(error.localizedDescription)
            }
            let fresh = try await self.link(for: source.file, key: key, fullSize: source.fullSize)
            _ = claim(fresh, job: job)
            replaced[link] = fresh
        }
        return replaced
    }

    func discardUnclaimed(_ links: [String]) {
        for link in Set(links) {
            guard let share = shares.values.first(where: { $0.link == link }), share.claims.isEmpty else { continue }
            close(share.id)
        }
    }

    func isSharing(for job: UUID) -> Bool {
        shares.values.contains { $0.claims.contains(job) }
    }

    nonisolated static func isTunnelLink(_ link: String) -> Bool {
        guard let url = URL(string: link), url.scheme == "https", let host = url.host()?.lowercased(),
              host.hasSuffix(".trycloudflare.com") else { return false }
        let name = url.deletingPathExtension().lastPathComponent
        return url.pathComponents.count == 2 && UUID(uuidString: name) != nil
    }

    nonisolated static func sharesFullSize(_ toolID: String) -> Bool {
        ["upscaleVideo", "reframeVideo"].contains(toolID)
    }

    func release(_ job: UUID) {
        for (id, share) in shares where share.claims.contains(job) {
            shares[id]?.claims.remove(job)
            if shares[id]?.claims.isEmpty == true { close(id) }
        }
    }

    func jobAdvanced(_ job: UUID) {
        for (id, share) in shares where share.claims.contains(job) && share.session.completedDownloads > share.fetched {
            shares[id]?.fetched += 1
            shares[id]?.claims.remove(job)
            if shares[id]?.claims.isEmpty == true { scheduleClose(id, after: Self.grace) }
        }
    }

    func closeAll() {
        QuickTunnel.closeAll()
        opening.values.forEach { $0.cancel() }
        for id in Array(shares.keys) { close(id) }
    }

    static func fileKey(_ file: URL) throws -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let size = (attributes[.size] as? NSNumber)?.int64Value, size > 0 else {
            throw FreefieldError.unsupported(L("Couldn't open this file. It may have been moved or deleted."))
        }
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
        return "\(file.standardizedFileURL.path)|\(size)|\(modified)"
    }

    private func open(_ file: URL, key: String, fullSize: Bool) async throws -> String {
        let copy: URL?
        do {
            copy = try await (VideoMedia.isAudioFile(file) ? VideoMedia.shareableAudioCopy(file)
                              : VideoMedia.shareableCopy(file, fullSize: fullSize))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw VideoInputError.couldNotShare(error.localizedDescription)
        }
        let session: TunnelSession
        do {
            session = try await TunnelSession.open(serving: copy ?? file, setup: setup)
        } catch {
            if let copy { try? FileManager.default.removeItem(at: copy) }
            if error is CancellationError { throw error }
            throw VideoInputError.couldNotShare(error.localizedDescription)
        }
        let share = Share(id: session.id, key: key, session: session, copy: copy)
        shares[share.id] = share
        issued[share.link] = Source(file: file, fullSize: fullSize)
        scheduleClose(share.id, after: Self.unclaimedLifetime)
        let id = share.id
        Task { [weak self] in
            try? await Task.sleep(for: TunnelSession.defaultLifetime + .seconds(1))
            self?.close(id)
        }
        return share.link
    }

    private func claim(_ link: String, job: UUID) -> Bool {
        guard let id = shares.values.first(where: { $0.link == link })?.id else { return false }
        shares[id]?.claims.insert(job)
        shares[id]?.closeTask?.cancel()
        shares[id]?.closeTask = nil
        return true
    }

    private func scheduleClose(_ id: UUID, after delay: Duration) {
        shares[id]?.closeTask?.cancel()
        shares[id]?.closeTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.shares[id]?.claims.isEmpty == true else { return }
            self.close(id)
        }
    }

    private func close(_ id: UUID) {
        guard let share = shares.removeValue(forKey: id) else { return }
        share.closeTask?.cancel()
        share.session.close()
        if let copy = share.copy { try? FileManager.default.removeItem(at: copy) }
    }

    private func prune() {
        for (id, share) in shares where !share.session.isOpen { close(id) }
    }
}

nonisolated extension VideoMedia {
    static let shareMaxSeconds: Double = 15
    static let shareMaxBytes: Int64 = 100 * 1024 * 1024
    static let shareMaxAudioBytes: Int64 = 15 * 1024 * 1024

    static func isAudioFile(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension.lowercased())?.conforms(to: .audio) ?? false
    }

    static func sharedSize(of size: CGSize, fullSize: Bool = false) -> CGSize {
        guard size.width > 0, size.height > 0 else { return size }
        let (short, long): (CGFloat, CGFloat) = fullSize ? (2160, 3840) : (720, 1280)
        let scale = min(1, short / min(size.width, size.height), long / max(size.width, size.height))
        guard scale < 1 else { return size }
        return CGSize(width: max(2, (size.width * scale / 2).rounded(.down) * 2),
                      height: max(2, (size.height * scale / 2).rounded(.down) * 2))
    }

    @concurrent
    static func shareableCopy(_ url: URL, maxSeconds: Double = shareMaxSeconds, fullSize: Bool = false) async throws -> URL? {
        let asset = AVURLAsset(url: url)
        let tracks: [AVAssetTrack], duration: CMTime
        do {
            tracks = try await asset.loadTracks(withMediaType: .video)
            duration = try await asset.load(.duration)
        } catch {
            throw error is CancellationError ? error : VideoMediaError.unreadable
        }
        guard let track = tracks.first else { throw VideoMediaError.noVideo }
        let natural: CGSize, transform: CGAffineTransform, formats: [CMFormatDescription], rate: Float
        do {
            (natural, transform, formats, rate) = try await track.load(.naturalSize, .preferredTransform, .formatDescriptions, .nominalFrameRate)
        } catch {
            throw error is CancellationError ? error : VideoMediaError.unreadable
        }
        let display = displaySize(natural, transform)
        guard display.width > 0, display.height > 0 else { throw VideoMediaError.unreadable }
        let target = sharedSize(of: display, fullSize: fullSize)
        let scale = min(1, target.width / display.width, target.height / display.height)
        let isH264 = !formats.isEmpty && formats.allSatisfy { $0.mediaSubType == .h264 }
        if url.pathExtension.lowercased() == "mp4", isH264, scale >= 1, duration.seconds <= maxSeconds + 0.05,
           shareFileSize(url) <= shareMaxBytes {
            return nil
        }

        let render = scale >= 1 ? CGSize(width: max(2, (display.width / 2).rounded(.down) * 2),
                                         height: max(2, (display.height / 2).rounded(.down) * 2)) : target
        let rotated = CGRect(origin: .zero, size: natural).applying(transform)
        let placement = transform
            .concatenating(CGAffineTransform(translationX: -rotated.minX, y: -rotated.minY))
            .concatenating(CGAffineTransform(scaleX: render.width / display.width, y: render.height / display.height))
        var layer = AVVideoCompositionLayerInstruction.Configuration(trackID: track.trackID)
        layer.setTransform(placement, at: .zero)
        let fps = min(30, rate > 0 ? Double(rate) : 30)
        let composition = AVVideoComposition(configuration: .init(
            frameDuration: CMTime(value: 1000, timescale: CMTimeScale((fps * 1000).rounded())),
            instructions: [AVVideoCompositionInstruction(configuration: .init(
                backgroundColor: CGColor(gray: 0, alpha: 1),
                layerInstructions: [AVVideoCompositionLayerInstruction(configuration: layer)],
                timeRange: CMTimeRange(start: .zero, duration: duration)
            ))],
            renderSize: render
        ))
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoMediaError.export(L("this Mac can't encode H.264"))
        }
        session.videoComposition = composition
        session.timeRange = CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, CMTime(seconds: maxSeconds, preferredTimescale: 600)))
        session.shouldOptimizeForNetworkUse = true
        return try await writeShareableCopy(session, as: .mp4, extension: "mp4")
    }

    @concurrent
    static func shareableAudioCopy(_ url: URL) async throws -> URL? {
        if ["m4a", "mp3"].contains(url.pathExtension.lowercased()), shareFileSize(url) <= shareMaxAudioBytes {
            return nil
        }
        let asset = AVURLAsset(url: url)
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw error is CancellationError ? error : VideoMediaError.unreadable
        }
        guard !tracks.isEmpty else { throw VideoMediaError.noAudio }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw VideoMediaError.export(L("this Mac can't encode AAC"))
        }
        session.shouldOptimizeForNetworkUse = true
        return try await writeShareableCopy(session, as: .m4a, extension: "m4a")
    }

    private static func writeShareableCopy(_ session: AVAssetExportSession, as type: AVFileType, extension ext: String) async throws -> URL {
        try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true)
        let output = workFolder.appendingPathComponent("share-\(UUID().uuidString).\(ext)")
        do {
            try await session.export(to: output, as: type)
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: output)
            throw CancellationError()
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw VideoMediaError.export(error.localizedDescription)
        }
        return output
    }

    private static func shareFileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
