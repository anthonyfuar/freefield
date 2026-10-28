import AppKit
import FreefieldCore
import SwiftUI

@Observable
final class ComposerState {
    let tool: Tool

    var prompt = ""
    var modelID: String?
    var aspectRatio: AspectRatio
    var resolution: Resolution = .oneK
    var count: Int
    var quality = "auto"
    var useSeed = false
    var seed = Int.random(in: 1...999_999)
    var presetID: String?
    var moodboardID: UUID?
    var characterID: UUID?
    var productID: UUID?
    var castIDs: [UUID] = []
    var elementIDs: [UUID] = []
    var references: [Data] = []
    var cameraBody = "auto"
    var cameraLens = "auto"
    var cameraFocalLength = "auto"
    var cameraAperture = "auto"
    var paletteID: String?
    var customPalette: [String] = []
    var enhance = UserDefaults.standard.bool(forKey: SettingsKey.autoEnhance)
    var transparentBackground = false
    var isEnhancing = false

    var source: Data? {
        didSet { if tool == .expand { fitExpandTarget() } }
    }
    var secondary: Data?
    var strokes: [Stroke] = []
    var notes: [TextNote] = []
    var brushWidth: CGFloat = 0.06
    var inkColor: NSColor = .systemRed

    var lightPreset = "golden-hour"
    var lightDirection = CGPoint(x: -0.6, y: -0.5)
    var lightColor = Color(red: 1.0, green: 0.82, blue: 0.6)
    var lightIntensity = 0.6
    var lightHard = false
    var angles: Set<String> = ["three-quarter-left", "profile-right", "low-angle"]
    var anglesMode = "presets"
    var orbitRotation = 35.0
    var orbitTilt = 15.0
    var orbitZoom = 1.0
    var textEdits: [TextEdit] = []
    var isDetectingText = false
    var upscaleCreativity = 0.2
    var grade = GradeSettings.natural
    var backgroundMode = "remove"
    var expandTarget: AspectRatio = .landscape16x9
    var expandTargetIsChosen = false
    var swapKeepExpression = true
    var appID: String?
    var appText = ""

    var story = ""
    var storyScenes: [StoryScene] = [StoryScene(text: ""), StoryScene(text: ""), StoryScene(text: "")]
    var storyTemplate = "movie"
    var storyFrames = 4

    var sessionSetID = "candid-glow"
    var sessionShots = 6

    init(tool: Tool) {
        self.tool = tool
        aspectRatio = tool == .create ? .portrait3x4 : .auto
        count = tool == .create ? 2 : 1
        if tool == .upscale { resolution = .fourK }
    }

    var trimmedPrompt: String { prompt.trimmingCharacters(in: .whitespacesAndNewlines) }

    func clearCanvas() {
        strokes.removeAll()
        notes.removeAll()
        textEdits.removeAll()
    }

    private func fitExpandTarget() {
        guard let source, let current = ToolControls.closestRatio(source),
              !expandTargetIsChosen || expandTarget == current else { return }
        expandTarget = current.ratio <= 1 ? .landscape16x9 : .portrait9x16
        expandTargetIsChosen = false
    }

    var palette: ColorPalette? {
        if paletteID == "custom", !customPalette.isEmpty {
            return ColorPalette(id: "custom", name: L("From Your Image"), hexes: customPalette)
        }
        return paletteID.flatMap { id in ColorPalette.builtIn.first { $0.id == id } }
    }
}

struct StoryScene: Identifiable, Equatable {
    let id = UUID()
    var text: String
}

struct TextEdit: Identifiable, Equatable {
    let id = UUID()
    var original: String
    var replacement: String
}
