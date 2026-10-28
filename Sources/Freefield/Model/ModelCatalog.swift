import Foundation
import FreefieldCore

struct ModelChoice: Identifiable, Hashable {
    let model: ImageModel
    let lineup: LineupModel?

    var id: String { model.id }
    var displayName: String { lineup?.name ?? model.name }
    var tagline: String { lineup?.tagline ?? model.summary }
    var badge: String? { lineup?.badge }
    var isFeatured: Bool { lineup != nil }
}

struct VideoModelChoice: Identifiable, Hashable {
    let model: VideoModel
    let lineup: VideoLineupModel?
    var lockedReason: String?

    var id: String { model.id }
    var isSelectable: Bool { lockedReason == nil }
    var displayName: String { lineup?.name ?? model.name }
    var tagline: String { lineup?.tagline ?? model.summary }
    var strengths: String? { lineup?.strengths }
    var badge: String? { lineup?.badge }
    var isFeatured: Bool { lineup?.isFeatured == true }
}

@Observable
final class ModelCatalog {
    private(set) var models: [Provider: [ImageModel]] = [:]
    private(set) var textModels: [Provider: [TextModel]] = [:]
    private(set) var accounts: [Provider: AccountStatus] = [:]
    private(set) var errors: [Provider: String] = [:]
    private(set) var loading: Set<Provider> = []
    private(set) var lastRefresh: Date?
    private(set) var strained: Set<String> = []
    private(set) var videoModels: [VideoModel] = []
    private(set) var googleVideoModels: [VideoModel] = []
    private(set) var videoError: String?
    private var loadingOpenRouterVideo = false
    private var loadingGoogleVideo = false

    var loadingVideoModels: Bool { loadingOpenRouterVideo || loadingGoogleVideo }

    func markStrained(_ modelID: String) {
        strained.insert(modelID)
    }

    var isLoading: Bool { !loading.isEmpty }

    var allModels: [ImageModel] { Provider.allCases.flatMap { models[$0] ?? [] } }

    func model(id: String?) -> ImageModel? {
        guard let id else { return nil }
        return allModels.first { $0.id == id }
    }

    func featuredChoices(preferring provider: Provider) -> [ModelChoice] {
        Lineup.models.compactMap { entry in
            resolve(entry, preferring: provider).map { ModelChoice(model: $0, lineup: entry) }
        }
    }

    func lockedEntries(configured: [Provider]) -> [(entry: LineupModel, provider: Provider)] {
        guard !configured.isEmpty else { return [] }
        return Lineup.models.compactMap { entry in
            let offering = Provider.allCases.filter { !entry.ids(for: $0).isEmpty }
            guard !offering.contains(where: configured.contains), let missing = offering.first else { return nil }
            return (entry, missing)
        }
    }

    func otherChoices(preferring provider: Provider) -> [ModelChoice] {
        let featuredIDs = Set(featuredChoices(preferring: provider).map(\.model.id))
        return allModels
            .filter { !featuredIDs.contains($0.id) }
            .sorted { ($0.vendor, $0.name) < ($1.vendor, $1.name) }
            .map { ModelChoice(model: $0, lineup: nil) }
    }

    func choice(for model: ImageModel) -> ModelChoice {
        let entry = Lineup.models.first { $0.matches(model) }
        return ModelChoice(model: model, lineup: entry)
    }

    func resolve(_ entry: LineupModel, preferring provider: Provider) -> ImageModel? {
        let order = [provider] + Provider.allCases.filter { $0 != provider }
        for candidateProvider in order {
            let available = models[candidateProvider] ?? []
            for id in entry.ids(for: candidateProvider) {
                if let match = available.first(where: { $0.modelID == id }) { return match }
            }
        }
        return nil
    }

    nonisolated private struct Snapshot: Codable, Sendable {
        var models: [String: [ImageModel]] = [:]
        var textModels: [String: [TextModel]] = [:]
        var videoModels: [VideoModel] = []
        var googleVideoModels: [VideoModel]?
    }

    nonisolated private static var snapshotURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Freefield/model-catalog.json")
    }

    func restoreSaved(keys: APIKeys) async {
        guard let snapshot = await Self.readSnapshot() else { return }
        for provider in keys.configuredProviders where models[provider] == nil {
            models[provider] = snapshot.models[provider.rawValue]
            textModels[provider] = snapshot.textModels[provider.rawValue]
        }
        if keys.openRouter != nil, videoModels.isEmpty { videoModels = snapshot.videoModels }
        if keys.google != nil, googleVideoModels.isEmpty {
            var saved = (snapshot.googleVideoModels ?? []).filter { !($0.providerModelID ?? $0.apiModelID).lowercased().hasPrefix("veo-") }
            if !saved.contains(where: { GeminiClient.isOmniID($0.providerModelID ?? $0.apiModelID) }) {
                saved.insert(GeminiClient.makeOmniModel(id: GeminiClient.omniModelID), at: 0)
            }
            googleVideoModels = saved
        }
    }

    @concurrent
    nonisolated private static func readSnapshot() async -> Snapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    private func saveSnapshot() {
        var snapshot = Snapshot()
        for (provider, list) in models where !list.isEmpty { snapshot.models[provider.rawValue] = list }
        for (provider, list) in textModels where !list.isEmpty { snapshot.textModels[provider.rawValue] = list }
        snapshot.videoModels = videoModels
        snapshot.googleVideoModels = googleVideoModels
        let url = Self.snapshotURL
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    func refresh(keys: APIKeys) async {
        let service = ImageService(keys: keys)
        for provider in Provider.allCases where keys.key(for: provider) == nil {
            models[provider] = nil
            textModels[provider] = nil
            accounts[provider] = nil
            errors[provider] = nil
        }
        if keys.openRouter == nil {
            videoModels = []
            videoError = nil
        }
        if keys.google == nil { googleVideoModels = [] }
        await withTaskGroup(of: Void.self) { group in
            for provider in keys.configuredProviders {
                if models[provider]?.isEmpty ?? true { loading.insert(provider) }
                group.addTask {
                    await self.load(provider, service: service)
                }
            }
            if let key = keys.openRouter {
                group.addTask {
                    await self.loadVideoModels(apiKey: key)
                }
            }
            if let key = keys.google {
                group.addTask {
                    await self.loadGoogleVideoModels(apiKey: key)
                }
            }
        }
        lastRefresh = .now
        saveSnapshot()
    }

    private func loadVideoModels(apiKey: String) async {
        loadingOpenRouterVideo = true
        defer { loadingOpenRouterVideo = false }
        do {
            videoModels = try await OpenRouterClient(apiKey: apiKey).videoModels()
            videoError = nil
        } catch {
            videoError = error.localizedDescription
            if case FreefieldError.invalidKey = error { videoModels = [] }
        }
    }

    private func loadGoogleVideoModels(apiKey: String) async {
        loadingGoogleVideo = true
        defer { loadingGoogleVideo = false }
        do {
            googleVideoModels = try await GeminiClient(apiKey: apiKey).videoModels()
        } catch {
            if case FreefieldError.invalidKey = error { googleVideoModels = [] }
        }
    }

    private func load(_ provider: Provider, service: ImageService) async {
        defer { loading.remove(provider) }
        do {
            async let account = service.accountStatus(for: provider)
            async let imageModels = service.imageModels(for: provider)
            async let helpers = service.textModels(for: provider)
            accounts[provider] = try await account
            models[provider] = try await imageModels
            textModels[provider] = (try? await helpers) ?? []
            errors[provider] = nil
        } catch {
            errors[provider] = error.localizedDescription
            if case FreefieldError.invalidKey = error {
                models[provider] = []
                accounts[provider] = nil
            }
        }
    }

    var availableVideoModels: [VideoModel] {
        let now = Date()
        let preferred = UserDefaults.standard.string(forKey: SettingsKey.preferredProvider).flatMap(Provider.init(rawValue:))
        let lists = preferred == .google ? [googleVideoModels, videoModels] : [videoModels, googleVideoModels]
        var seen = Set<String>()
        return lists.joined().filter {
            ($0.expiresAt ?? .distantFuture) > now && !VideoLineup.hidden.contains($0.id) && seen.insert($0.id).inserted
        }
    }

    func videoModel(id: String?) -> VideoModel? {
        guard let id else { return nil }
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        let slug = parts.last ?? id
        let host = parts.count == 2 ? Provider(rawValue: parts[0]) : nil
        let lists = switch host {
        case .google: [googleVideoModels, videoModels]
        case .openRouter: [videoModels, googleVideoModels]
        case nil: [availableVideoModels, videoModels, googleVideoModels]
        }
        return lists.lazy.compactMap { $0.first { $0.id == slug } }.first
    }

    func videoChoice(for model: VideoModel) -> VideoModelChoice {
        VideoModelChoice(model: model, lineup: VideoLineup.entry(model.id))
    }

    func featuredVideoChoices(kinds: Set<VideoModelKind>? = nil) -> [VideoModelChoice] {
        let available = Dictionary(availableVideoModels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return VideoLineup.models.filter(\.isFeatured).compactMap { entry in
            guard let model = available[entry.id], kinds?.contains(model.kind) ?? true else { return nil }
            return VideoModelChoice(model: model, lineup: entry)
        }
    }

    func lockedVideoChoices(kinds: Set<VideoModelKind>? = nil, configured: [Provider]) -> [VideoModelChoice] {
        guard !configured.isEmpty else { return [] }
        return VideoLineup.models.filter(\.isFeatured).compactMap { entry in
            guard !entry.providers.contains(where: configured.contains), let missing = entry.providers.first else { return nil }
            let kind = VideoModelKind.infer(entry.id)
            guard kinds?.contains(kind) ?? true else { return nil }
            let vendor = entry.id.split(separator: "/").first.map(String.init) ?? ""
            let standIn = VideoModel(id: entry.id, name: entry.name, vendor: vendor, summary: entry.tagline,
                                     frameTypes: kind == .generate ? ["first_frame", "last_frame"] : [],
                                     audio: kind == .generate ? true : nil, kind: kind, provider: missing)
            return VideoModelChoice(model: standIn, lineup: entry, lockedReason: missing.missingKeyReason)
        }
    }

    func otherVideoChoices(kinds: Set<VideoModelKind>? = nil) -> [VideoModelChoice] {
        let featured = Set(VideoLineup.models.filter(\.isFeatured).map(\.id))
        let order = Dictionary(VideoLineup.models.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        return availableVideoModels
            .filter { !featured.contains($0.id) && (kinds?.contains($0.kind) ?? true) }
            .sorted { lhs, rhs in
                let left = order[lhs.id] ?? Int.max, right = order[rhs.id] ?? Int.max
                return left != right ? left < right : (lhs.vendor, lhs.name) < (rhs.vendor, rhs.name)
            }
            .map(videoChoice(for:))
    }

    func defaultVideoModel(for toolID: String) -> VideoModel? {
        VideoLineup.defaultVideoModel(for: toolID, among: availableVideoModels, avoiding: strained)
    }

    func refreshAccount(_ provider: Provider, keys: APIKeys) async {
        accounts[provider] = try? await ImageService(keys: keys).accountStatus(for: provider)
    }

    func helperModel(preferredID: String?, provider: Provider) -> TextModel? {
        let all = Provider.allCases.flatMap { textModels[$0] ?? [] }
        if let preferredID, let match = all.first(where: { $0.id == preferredID }) { return match }
        let defaults: [(Provider, [String])] = [
            (.openRouter, ["google/gemini-3-flash-preview", "google/gemini-3-flash", "google/gemini-2.5-flash", "openai/gpt-5-mini"]),
            (.google, ["gemini-3-flash-preview", "gemini-3-flash", "gemini-2.5-flash", "gemini-flash-latest"]),
        ]
        let order = defaults.sorted { lhs, _ in lhs.0 == provider }
        for (candidate, ids) in order {
            let available = textModels[candidate] ?? []
            for id in ids {
                if let match = available.first(where: { $0.modelID == id }) { return match }
            }
        }
        return (textModels[provider] ?? []).first ?? all.first
    }
}

extension Provider {
    var missingKeyReason: String {
        self == .openRouter ? L("Needs an OpenRouter key") : L("Needs a Google key")
    }
}
