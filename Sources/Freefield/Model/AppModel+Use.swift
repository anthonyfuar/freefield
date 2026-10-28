import FreefieldCore
import SwiftUI

enum CharacterDestination: CaseIterable, Identifiable {
    case create, photoSession, storyboard, characterSwap, createVideo, talkingAvatar

    var id: Self { self }

    var tool: Tool? {
        switch self {
        case .create: .create
        case .photoSession: .photoSession
        case .storyboard: .storyboard
        case .characterSwap: .characterSwap
        case .createVideo, .talkingAvatar: nil
        }
    }

    var videoTool: VideoTool? {
        switch self {
        case .createVideo: VideoCatalog.tool("createVideo")
        case .talkingAvatar: VideoCatalog.tool("talkingAvatar")
        default: nil
        }
    }

    var title: String { tool?.title ?? videoTool?.name ?? "" }
    var systemImage: String { tool?.systemImage ?? videoTool?.symbol ?? Tool.create.systemImage }

    var startsVideo: Bool { self == .createVideo }
}

extension AppModel {
    func use(_ character: Character, in destination: CharacterDestination) {
        if let tool = destination.tool {
            composer(for: tool).characterID = character.id
            selection = .tool(tool)
            return
        }
        switch destination {
        case .createVideo:
            makeVideo(with: character)
        case .talkingAvatar:
            guard let tool = destination.videoTool, let photo = library.coverPhotoData(character) else { return }
            videoState(for: tool).firstFrame = photo
            openVideo(tool.id)
        default:
            break
        }
    }
}
