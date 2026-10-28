import FreefieldCore
import SwiftUI

struct DirectorChoiceButton: View {
    let group: VideoOptionGroup
    let toolID: String
    @Binding var selection: String

    @State private var isOpen = false

    private static let symbols: [String: [String: String]] = [
        "genre": ["Epic": "mountain.2", "Drama": "theatermasks", "Noir": "cloud.rain", "Comedy": "face.smiling",
                  "Horror": "exclamationmark.triangle", "Action": "bolt"],
        "pacing": ["Chaotic": "tornado", "Dynamic": "hare", "Calm": "tortoise", "Single shot": "film"],
        "speed": ["Linear": "arrow.right", "Slow motion": "tortoise", "Speed-up": "hare", "Impact": "burst", "Bullet time": "scope",
                  "Ramp up": "chart.line.uptrend.xyaxis", "Flash in": "bolt.horizontal", "Flash out": "wind",
                  "Hero moment": "star"],
    ]

    private static let groupSymbols: [String: String] = [
        "genre": "theatermasks", "era": "calendar", "body": "camera", "lens": "camera.aperture", "aperture": "camera.aperture",
        "light": "lightbulb", "pacing": "metronome", "speed": "speedometer", "emotion": "face.smiling",
    ]

    private static let details: [String: [String: String]] = [
        "speed": ["Linear": L("Normal speed"), "Ramp up": L("Slow, then full speed"), "Flash in": L("Fast, then normal"),
                  "Flash out": L("Normal, then a fast exit"), "Hero moment": L("Slows down at the peak")],
        "aperture": ["f/1.4 wide open": L("Blurry background"), "f/4 moderate": L("Background a little soft"),
                     "f/11 deep focus": L("Everything sharp")],
    ]

    private var pictures: [String: OptionPicture]? { OptionImages.pictures(videoTool: toolID, group: group) }

    private func symbol(_ value: String) -> String {
        value == "Auto" ? "wand.and.stars" : Self.symbols[group.id]?[value] ?? Self.groupSymbols[group.id] ?? "circle.dashed"
    }

    var body: some View {
        let pictures = pictures
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                if let url = pictures?[selection]?.url {
                    ThumbnailImage(url: url, maxPixel: 120, contentMode: .fill)
                        .frame(width: 30, height: 18)
                        .clipShape(.rect(cornerRadius: 3))
                } else {
                    Image(systemName: symbol(selection)).foregroundStyle(.secondary)
                }
                Text(group.label(selection)).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .help(group.title)
        .accessibilityLabel(Text("\(group.title): \(group.label(selection))"))
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text(group.title).font(.headline)
                OptionGrid(minimum: pictures == nil ? 112 : 128, spacing: 8) {
                    ForEach(group.values, id: \.self) { value in
                        OptionTile(title: value == "Auto" ? L("Auto") : group.label(value),
                                   subtitle: value == "Auto" ? L("Freefield chooses") : Self.details[group.id]?[value],
                                   systemImage: symbol(value),
                                   picture: pictures.map { $0[value] ?? OptionPicture(url: nil, aspect: 16.0 / 9) },
                                   isSelected: selection == value, compact: true) {
                            selection = value
                            isOpen = false
                        }
                    }
                }
            }
            .padding(14)
            .frame(width: Self.popoverWidth(count: group.values.count, hasPictures: pictures != nil))
        }
    }

    private static func popoverWidth(count: Int, hasPictures: Bool) -> CGFloat {
        let columns = CGFloat(min(count <= 4 ? count : count <= 6 ? 3 : 4, 4))
        let tile: CGFloat = hasPictures ? 150 : 124
        return columns * tile + (columns - 1) * 8 + 28
    }
}

struct ScriptToShotsPanel: View {
    let tool: VideoTool
    let state: VideoState
    let maxShots: Int
    let onDone: () -> Void

    @Environment(AppModel.self) private var app
    @AppStorage("video.cinemaStudio.script") private var script = ""
    @State private var task: Task<Void, Never>?
    @State private var failure: String?

    private var isWorking: Bool { task != nil }

    var body: some View {
        let hasShots = state.shots.contains { !$0.action.trimmingCharacters(in: .whitespaces).isEmpty }
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason: String? = if !app.hasAnyKey {
            L("Add an API key in Settings")
        } else if app.helperModel == nil {
            L("No text model is available for Freefield's AI.")
        } else if trimmed.isEmpty {
            L("Write or paste your script first.")
        } else {
            nil
        }
        VStack(alignment: .leading, spacing: 10) {
            Label(L("Write the shots for me"), systemImage: "wand.and.stars").font(.headline)
            Text(L("Paste a script or describe your idea in any language. Freefield's AI splits it into up to %ld shots and picks a camera move for each, plus the lens and light.", maxShots))
                .helperTextStyle()
                .fixedSize(horizontal: false, vertical: true)
            TextField(L("e.g. A detective walks into a rainy alley, finds a letter, and looks up as a car's headlights hit her face."),
                      text: $script, axis: .vertical)
                .lineLimit(4...10)
                .inputBox()
                .characterLimit($script, ScriptShots.scriptLimit)
                .disabled(isWorking)
            if hasShots {
                Label(L("Replaces the shots you have now."), systemImage: "arrow.triangle.2.circlepath")
                    .font(.callout).foregroundStyle(.orange)
            }
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Text(L("Uses Freefield's AI · %@", VideoCostLabel.price(ScriptShots.estimate))).fineTextStyle()
                Spacer(minLength: 0)
                if isWorking {
                    ProgressView().controlSize(.small)
                    Button(L("Cancel")) { cancel() }
                } else {
                    Button(L("Write Shots"), systemImage: "sparkles") { write(trimmed) }
                        .buttonStyle(.glassProminent)
                        .tint(.brandFill)
                        .disabled(reason != nil)
                        .help(reason ?? "")
                }
            }
            if let reason, !isWorking, !trimmed.isEmpty || app.helperModel == nil {
                DisabledReasonLabel(reason: reason)
            }
        }
        .padding(16)
        .frame(width: 460, alignment: .leading)
        .onDisappear { cancel() }
    }

    private func write(_ text: String) {
        failure = nil
        task = Task {
            defer { task = nil }
            do {
                _ = try await app.writeShots(from: text, tool: tool, state: state)
                onDone()
            } catch is CancellationError {
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    private func cancel() {
        task?.cancel()
        task = nil
    }
}
