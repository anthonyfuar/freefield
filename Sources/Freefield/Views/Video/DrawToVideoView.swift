import AppKit
import FreefieldCore
import SwiftUI

struct DrawToVideoView: View {
    let tool: VideoTool

    @Environment(AppModel.self) private var app
    @State private var placingText = false
    @State private var pendingNotePosition: CGPoint?
    @State private var noteText = ""

    private var draft: DrawToVideoDraft { .shared }
    private static let suggestedMarks = 6

    var body: some View {
        let state = app.videoState(for: tool)
        let inputs = app.videoInputs(tool, state: state, forRun: false)
        let model = app.resolvedVideoModel(tool, state: state, inputs: inputs)
        let recipe = model.flatMap { VideoRecipes.request(for: tool, state: inputs, model: $0) }
        VideoToolScreen(tool: tool, state: state, model: model) {
            VStack(alignment: .leading, spacing: Spacing.l) {
                canvas(state)
                RelatedToolHint(prompt: L("Just camera moves?"), links: [
                    RelatedToolHint.Link(title: VideoCatalog.tool("animateImage")?.name ?? "") {
                        app.openVideo("animateImage", startImage: state.firstFrame)
                    },
                ])
                if let field = tool.textField(VideoCatalog.extraFieldID) {
                    ExtraInstructionField(text: Binding(get: { state.texts[field.id] ?? "" }, set: { state.texts[field.id] = $0 }),
                                          placeholder: field.placeholder,
                                          limit: VideoTextBudget.limit(tool, inputs: inputs, model: model, field: field))
                }
            }
            reading(state)
            direction(state, recipe: recipe, step: showsReading(state) ? 3 : 2)
            VideoRunNotes(state: state, recipe: recipe)
        } bar: {
            VideoRunBar(tool: tool, state: state, inputs: inputs, model: model,
                        blockedReason: app.helperModel == nil ? L("No text model is available for Freefield's AI.")
                            : textIsTooLong(state, inputs: inputs, model: model) ? L("Shorten the text to fit the selected model") : nil,
                        note: L("Plus about $0.002 for the AI to read your drawing."))
        }
        .alert(L("Note on the image"), isPresented: Binding(get: { pendingNotePosition != nil }, set: { if !$0 { pendingNotePosition = nil } })) {
            TextField(L("E.g. “jumps”, “slowly”, “turns left”"), text: $noteText)
                .characterLimit($noteText, 40)
            Button(L("Add")) {
                if let position = pendingNotePosition, !noteText.trimmingCharacters(in: .whitespaces).isEmpty {
                    state.drawNotes.append(TextNote(position: position, text: noteText, color: draft.ink))
                }
                noteText = ""
                pendingNotePosition = nil
                placingText = false
            }
            Button(L("Cancel"), role: .cancel) {
                noteText = ""
                pendingNotePosition = nil
            }
        } message: {
            Text(L("A word or two about the motion, placed where it happens."))
        }
    }

    @ViewBuilder private func canvas(_ state: VideoState) -> some View {
        @Bindable var state = state
        let slot = tool.slot(.drawing)
        PanelSection(title: slot?.title ?? L("Your drawing"), systemImage: slot?.symbol ?? "pencil.and.scribble", step: 1,
                     isDone: state.firstFrame != nil && (!state.drawStrokes.isEmpty || !state.drawNotes.isEmpty)) {
            VStack(alignment: .leading, spacing: 8) {
                if let frame = state.firstFrame {
                    DrawingCanvas(imageData: frame, strokes: $state.drawStrokes, notes: $state.drawNotes, brushWidth: draft.brush,
                                  color: draft.ink, placingText: placingText, onPlaceText: { pendingNotePosition = $0 })
                        .frame(height: 420)
                        .clipShape(.rect(cornerRadius: Radius.tile))
                        .overlay(alignment: .top) { toolbar(state).padding(.top, 8) }
                    let marks = state.drawStrokes.count + state.drawNotes.count
                    if marks > Self.suggestedMarks {
                        Label(L("About %ld arrows and notes at most work best; simplify if the motion comes out wrong.", Self.suggestedMarks),
                              systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.orange)
                    } else {
                        Text(L("Draw an arrow from where something starts to where it goes. Add a note like “jumps” or “slowly” with the T button. The drawing never appears in the video."))
                            .helperTextStyle()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    AdaptiveImageWell(title: tool.slot(.firstFrame)?.title ?? L("Image"),
                                      subtitle: L("Add the image first, then draw on it."), data: $state.firstFrame, minHeight: 300)
                        .frame(height: 320)
                }
            }
        }
        .onChange(of: state.firstFrame) { _, _ in
            state.drawStrokes = []
            state.drawNotes = []
            draft.preview = nil
        }
    }

    private func toolbar(_ state: VideoState) -> some View {
        @Bindable var draft = self.draft
        return HStack(spacing: 10) {
            Image(systemName: "circle.fill").font(.system(size: 6))
            Slider(value: $draft.brush, in: 0.005...0.04).frame(width: 100).help(L("Brush size"))
            Image(systemName: "circle.fill").font(.system(size: 12))
            Divider().frame(height: 18)
            ForEach(DrawToVideoDraft.inks, id: \.self) { ink in
                Button {
                    draft.ink = ink
                    placingText = false
                } label: {
                    Circle()
                        .fill(Color(nsColor: ink))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(.primary.opacity(draft.ink == ink ? 0.9 : 0.15), lineWidth: draft.ink == ink ? 2 : 1))
                }
                .buttonStyle(.plain)
                .help(DrawToVideoDraft.name(of: ink))
                .accessibilityLabel(DrawToVideoDraft.name(of: ink))
                .accessibilityAddTraits(draft.ink == ink ? .isSelected : [])
            }
            Toggle(isOn: $placingText) {
                Image(systemName: "textformat")
            }
            .toggleStyle(.button)
            .help(L("Click the image to add a text note"))
            Divider().frame(height: 18)
            Button {
                if !state.drawStrokes.isEmpty { state.drawStrokes.removeLast() } else if !state.drawNotes.isEmpty { state.drawNotes.removeLast() }
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(state.drawStrokes.isEmpty && state.drawNotes.isEmpty)
            .help(L("Undo stroke (⌘Z)"))
            Button {
                state.drawStrokes = []
                state.drawNotes = []
            } label: {
                Image(systemName: "trash")
            }
            .disabled(state.drawStrokes.isEmpty && state.drawNotes.isEmpty)
            .help(L("Clear all"))
            Divider().frame(height: 18)
            Button {
                if let data = ImageIntake.pick(multiple: false).first { state.firstFrame = data }
            } label: {
                Image(systemName: "photo.badge.arrow.down")
            }
            .help(L("Choose a different source image"))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(in: .capsule)
    }

    private func showsReading(_ state: VideoState) -> Bool {
        state.firstFrame != nil && (!state.drawStrokes.isEmpty || !state.drawNotes.isEmpty || draft.preview != nil)
    }

    @ViewBuilder private func reading(_ state: VideoState) -> some View {
        let hasMarks = !state.drawStrokes.isEmpty || !state.drawNotes.isEmpty
        if showsReading(state) {
            let isStale = draft.previewKey != DrawToVideoDraft.key(state)
            PanelSection(title: L("How the drawing reads"), systemImage: "text.bubble", step: 2,
                         isDone: draft.preview != nil && !isStale, isOptional: true) {
                VStack(alignment: .leading, spacing: 8) {
                    if let preview = draft.preview {
                        Text(preview)
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: Radius.thumb))
                            .opacity(isStale ? 0.5 : 1)
                        if isStale {
                            Text(L("The drawing changed since this preview.")).font(.callout).foregroundStyle(.orange)
                        }
                    }
                    HStack(spacing: 8) {
                        Button(draft.preview == nil ? L("Preview Directions") : L("Preview Again"), systemImage: "eye") {
                            Task { await preview(state) }
                        }
                        .buttonStyle(.glass)
                        .fixedSize()
                        .disabled(draft.isReading || !hasMarks || app.helperModel == nil)
                        if draft.isReading { ProgressView().controlSize(.small) }
                        PricePill(text: "≈\u{00A0}" + AppModel.money(0.001, decimals: 3))
                        Text(L("Generate reads your latest drawing again, so the video follows it."))
                            .helperTextStyle()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func preview(_ state: VideoState) async {
        guard let frame = state.firstFrame,
              let clean = ImageCoding.prepareForUpload(frame, role: "first frame"),
              let annotated = CanvasRenderer.annotated(frame, strokes: state.drawStrokes, notes: state.drawNotes)
                .flatMap({ ImageCoding.prepareForUpload($0, role: "drawing") }) else { return }
        let key = DrawToVideoDraft.key(state)
        draft.isReading = true
        defer { draft.isReading = false }
        do {
            let text = try await app.helperComplete(title: E("Read drawing"), tool: .video, system: VideoRecipes.drawHelperInstructions,
                                                    user: "Describe the motion.", images: [clean, annotated])
            draft.preview = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”").union(.whitespacesAndNewlines))
            draft.previewKey = key
        } catch {
            app.presentError(error)
        }
    }

    @ViewBuilder private func direction(_ state: VideoState, recipe: VideoRecipe?, step: Int) -> some View {
        @Bindable var state = state
        let seconds = recipe.flatMap { OpenRouterClient.videoDuration(for: $0.request) }
        let limit = CameraMoves.maxMoves(forDuration: seconds)
        PanelSection(title: L("Camera"), systemImage: "video", step: step, isDone: !state.cameraMoves.isEmpty, isOptional: true) {
            VStack(alignment: .leading, spacing: 6) {
                CameraMoveChip(selection: $state.cameraMoves, strength: $state.strength, limit: limit, emptyTitle: L("Camera: still"))
                Text(state.cameraMoves.isEmpty ? L("No camera move: the camera stays locked off so the drawn motion reads clearly.")
                     : limit == 1 ? L("One camera move fits this clip.") : L("Up to %ld camera moves fit this clip; they play in order.", limit))
                    .helperTextStyle()
            }
        }
    }
}

extension DrawToVideoView {
    fileprivate func textIsTooLong(_ state: VideoState, inputs: VideoToolInputs, model: VideoModel?) -> Bool {
        tool.textFields.contains { state.text($0.id).utf16.count > VideoTextBudget.limit(tool, inputs: inputs, model: model, field: $0) }
    }
}

@Observable
final class DrawToVideoDraft {
    static let shared = DrawToVideoDraft()
    static let inks: [NSColor] = [.systemRed, .systemYellow, .systemGreen, .systemBlue, .white, .black]

    static func name(of ink: NSColor) -> String {
        switch ink {
        case .systemRed: L("Red")
        case .systemYellow: L("Yellow")
        case .systemGreen: L("Green")
        case .systemBlue: L("Blue")
        case .white: L("White")
        default: L("Black")
        }
    }

    var brush: CGFloat = 0.012
    var ink: NSColor = .systemRed
    var preview: String?
    var previewKey: String?
    var isReading = false

    static func key(_ state: VideoState) -> String {
        let points = state.drawStrokes.reduce(0) { $0 + $1.points.count }
        let notes = state.drawNotes.map(\.text).joined(separator: "|")
        return "\(state.firstFrame?.count ?? 0)-\(state.drawStrokes.count)-\(points)-\(notes)"
    }
}
