import FreefieldCore
import SwiftUI

extension AppModel {
    func makeVideo(from asset: Asset, in toolID: String) {
        if toolID == "videoEffects", let effect = pairedEffect(for: asset) {
            animate(asset, with: effect)
            return
        }
        guard let tool = VideoCatalog.tool(toolID), let data = library.imageData(for: asset) else { return }
        let state = videoState(for: tool)
        if tool.takes(.firstFrame) {
            state.firstFrame = data
            switch toolID {
            case "videoEffects":
                state.firstFrameIsKeyframe = false
            case "createVideo":
                state.aspect = nil
            default:
                break
            }
        } else if tool.takes(.character) {
            state.characterID = nil
            state.characterPhoto = data
        } else {
            return
        }
        openVideo(toolID)
    }

    func pairedEffect(for asset: Asset) -> VideoEffect? {
        guard !asset.isVideo, asset.tool == .app, let style = asset.appID else { return nil }
        return VideoEffects.paired(withQuickStyle: style)
    }

    func animate(_ asset: Asset, with effect: VideoEffect) {
        guard let tool = VideoCatalog.tool("videoEffects"), let data = library.imageData(for: asset) else { return }
        let state = videoState(for: tool)
        state.firstFrame = data
        state.apply(effect)
        state.firstFrameIsKeyframe = true
        pendingVideoEffect = effect.id
        openVideo(tool.id)
    }

    func animateAsAd(_ asset: Asset) {
        guard let tool = VideoCatalog.tool("videoAd"), let data = library.imageData(for: asset) else { return }
        let state = videoState(for: tool)
        state.firstFrame = data
        state.choices["mode"] = "Hook to video"
        state.aspect = nil
        if let product = library.product(asset.productID) { state.productID = product.id }
        if let character = library.character(asset.characterID) { state.characterID = character.id }
        openVideo(tool.id)
    }

    func makeStoryboardVideo(_ frames: [(asset: Asset, action: String)]) {
        guard let tool = VideoCatalog.tool("storyboardVideo") else { return }
        let shots = frames.compactMap { frame in
            library.imageData(for: frame.asset).map { VideoShotDraft(action: frame.action, image: $0) }
        }
        guard !shots.isEmpty else { return }
        videoState(for: tool).shots = Array(shots.prefix(tool.slot(.shots)?.maxCount ?? 8))
        openVideo(tool.id)
    }

    func makeVideo(with character: Character) {
        guard let tool = VideoCatalog.tool("createVideo") else { return }
        videoState(for: tool).characterID = character.id
        openVideo(tool.id)
    }

    func makeVideoAd(with product: Product) {
        guard let tool = VideoCatalog.tool("videoAd") else { return }
        videoState(for: tool).productID = product.id
        openVideo(tool.id)
    }
}
