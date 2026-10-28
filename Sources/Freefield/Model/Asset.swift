import Foundation
import FreefieldCore

enum MediaKind: String, Codable {
    case image
    case video
}

struct Asset: Identifiable, Codable, Hashable {
    var id: UUID
    var fileName: String
    var createdAt: Date
    var width: Int
    var height: Int
    var tool: Tool
    var prompt: String
    var finalPrompt: String
    var modelID: String
    var modelName: String
    var provider: Provider
    var aspectRatio: AspectRatio
    var resolution: Resolution
    var batchID: UUID
    var presetID: String?
    var characterID: UUID?
    var productID: UUID?
    var appID: String?
    var inputFileNames: [String]
    var cost: Double?
    var seed: Int?
    var isFavorite: Bool
    var modelNote: String?

    var mediaKind: MediaKind?
    var duration: Double?
    var fps: Double?
    var hasAudio: Bool?
    var posterFileName: String?
    var videoResolution: String?
    var remoteJobID: String?
    var parentAssetID: UUID?

    var isVideo: Bool { mediaKind == .video }

    var pixelSizeLabel: String { "\(width) × \(height)" }

    var modelDisplayName: String {
        isVideo ? VideoLineup.displayName(forAssetModelID: modelID, fallback: L(modelName))
            : Lineup.displayName(forAssetModelID: modelID, fallback: L(modelName))
    }

    var aspect: Double { height > 0 ? Double(width) / Double(height) : 1 }
}

struct Character: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var details: String
    var photoFileNames: [String]
    var createdAt: Date
    var coverIndex: Int = 0
    var designChoices: [String: String]?
}

struct Product: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var details: String
    var photoFileNames: [String]
    var sourceURL: String?
    var createdAt: Date
}

struct Moodboard: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var imageFileNames: [String]
    var styleDescription: String
    var createdAt: Date
}

@Observable
final class Job: Identifiable {
    enum Status: Equatable {
        case running
        case finished
        case failed(String)
        case cancelled
    }

    let id = UUID()
    let tool: Tool
    let title: String
    let requested: Int
    let createdAt = Date()
    let aspectRatio: AspectRatio
    var spec: JobSpec?
    var status: Status = .running
    var received: Int = 0
    var failures: [String] = []
    var sawRateLimit = false
    var assetIDs: [UUID] = []
    var task: Task<Void, Never>?
    var onFinish: ((Job) -> Void)?

    var videoSpec: VideoJobSpec?
    var remoteID: String?
    var remoteState: VideoJobStatus.State?
    var videoPhase: VideoPhase?
    var submittedAt: Date?
    var estimate: Double?
    var isQuiet = false
    var discardsResult = false
    var isSendingVideo = false
    var costRecorded = false

    init(tool: Tool, title: String, requested: Int, aspectRatio: AspectRatio, spec: JobSpec? = nil) {
        self.tool = tool
        self.title = title
        self.requested = requested
        self.aspectRatio = aspectRatio
        self.spec = spec
    }

    var pending: Int { status == .running ? max(0, requested - received - failures.count) : 0 }
    var isRunning: Bool { status == .running }
    var isVideo: Bool { videoSpec != nil }
    var isStillAtProvider: Bool { videoPhase == .stillAtProvider }
}

enum VideoPhase: Equatable {
    case submitting
    case waiting
    case downloading
    case stillAtProvider
}
