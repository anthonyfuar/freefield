import AppKit
import FreefieldCore
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

extension AppModel {
    func useAsReference(_ asset: Asset) {
        guard let data = library.imageData(for: asset) else { return }
        let composer = composer(for: .create)
        if composer.references.count < 14 { composer.references.append(data) }
        selection = .tool(.create)
    }

    func reuse(_ asset: Asset) {
        guard !asset.isVideo else { return }
        let target: Tool = asset.tool.isPromptDriven ? asset.tool : .create
        let composer = composer(for: target)
        composer.prompt = asset.prompt
        composer.aspectRatio = asset.aspectRatio
        composer.resolution = asset.resolution
        composer.presetID = asset.presetID
        composer.characterID = asset.characterID
        composer.productID = library.product(asset.productID)?.id
        composer.modelID = asset.modelID
        selection = .tool(target)
    }

    func copyToPasteboard(_ asset: Asset) {
        let url = library.url(for: asset)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if asset.isVideo {
            pasteboard.writeObjects([url as NSURL])
        } else if let image = NSImage(contentsOf: url) {
            pasteboard.writeObjects([image, url as NSURL])
        }
    }

    func export(_ assets: [Asset]) {
        guard !assets.isEmpty else { return }
        if assets.count == 1, let asset = assets.first {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = asset.exportFileName
            panel.allowedContentTypes = [UTType(filenameExtension: (asset.fileName as NSString).pathExtension) ?? .png]
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.copyItem(at: library.url(for: asset), to: destination)
        } else {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = L("Export Here")
            panel.message = L("Choose where to save %ld images", assets.count)
            guard panel.runModal() == .OK, let folder = panel.url else { return }
            for asset in assets {
                try? FileManager.default.copyItem(at: library.url(for: asset), to: folder.appendingPathComponent(asset.exportFileName))
            }
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        }
    }

    func quickLook(_ asset: Asset) {
        quickLookURL = library.url(for: asset)
    }
}
