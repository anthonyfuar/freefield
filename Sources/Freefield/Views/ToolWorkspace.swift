import FreefieldCore
import SwiftUI

enum PanelLayout {
    static let canvasMinWidth: CGFloat = 420
    static let panelMinWidth: CGFloat = 280
    static let panelIdealWidth: CGFloat = 340
    static let panelWideIdealWidth: CGFloat = 420
    static let wideWindowWidth: CGFloat = 1500
    static let panelMaxWidth: CGFloat = 460
    static let pictureCardMinimum: CGFloat = 112

    static var startingWidth: CGFloat {
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        return (window?.frame.width ?? 0) >= wideWindowWidth ? panelWideIdealWidth : panelIdealWidth
    }
    static let subtitleMinCanvasWidth: CGFloat = 640
}

extension View {
    func toolPanelWidth() -> some View {
        frame(maxWidth: .infinity, alignment: .topLeading)
            .inspectorColumnWidth(min: PanelLayout.panelMinWidth, ideal: PanelLayout.startingWidth, max: PanelLayout.panelMaxWidth)
    }

    func canvasSubtitle(_ subtitle: String, canvasWidth: CGFloat) -> some View {
        navigationSubtitle(canvasWidth >= PanelLayout.subtitleMinCanvasWidth ? subtitle : "")
    }
}

struct ToolWorkspace: View {
    let tool: Tool

    @Environment(AppModel.self) private var app
    @State private var showControls = true
    @State private var selectedResultID: UUID?
    @State private var placingText = false
    @State private var erasing = false
    @State private var pendingNotePosition: CGPoint?
    @State private var noteText = ""
    @State private var showingExample = false
    @State private var canvasWidth: CGFloat = 0

    private var state: ComposerState { app.composer(for: tool) }

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            canvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
            ResultsStrip(tool: tool, selectedID: $selectedResultID)
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { canvasWidth = $0 }
        .navigationTitle(SwapModePicker.modes.contains(tool) ? L("Swap a Person") : tool.title)
        .canvasSubtitle(tool.subtitle, canvasWidth: canvasWidth)
        .inspector(isPresented: $showControls) {
            ToolControls(tool: tool, state: state, placingText: $placingText, onNewSource: { selectedResultID = nil })
                .toolPanelWidth()
        }
        .toolbar {
            if state.source != nil, let example = Examples.tool(tool) {
                ToolbarItem {
                    Button(L("See example"), systemImage: "sparkles.rectangle.stack") { showingExample.toggle() }
                        .help(L("A real example made with this tool"))
                        .popover(isPresented: $showingExample, arrowEdge: .bottom) {
                            let aspect = example.aspect ?? 1
                            let pictureHeight = min(360, 480 / aspect)
                            ToolExampleCard(example: example, extraLabel: Examples.extraLabel(for: tool))
                                .frame(width: pictureHeight * aspect, height: pictureHeight + 30)
                                .padding(14)
                        }
                }
            }
            if state.source != nil {
                ToolbarItem {
                    Button(L("Change Photo"), systemImage: "photo.badge.arrow.down") {
                        if let data = ImageIntake.pick(multiple: false).first {
                            state.source = data
                            state.clearCanvas()
                            selectedResultID = nil
                        }
                    }
                    .help(L("Choose a different source image"))
                }
            }
            ToolbarItem {
                Button(L("Controls"), systemImage: "sidebar.right") { showControls.toggle() }
                    .help(L("Show or hide controls (⌥⌘I)"))
                    .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
        .onAppear {
            if let data = app.takeHandoff(for: tool) {
                state.source = data
                state.clearCanvas()
            }
        }
        .alert(L("Note on the image"), isPresented: Binding(get: { pendingNotePosition != nil }, set: { if !$0 { pendingNotePosition = nil } })) {
            TextField(L("E.g. “red hat here”"), text: $noteText)
                .characterLimit($noteText, 60)
            Button(L("Add")) {
                if let position = pendingNotePosition, !noteText.isEmpty {
                    state.notes.append(TextNote(position: position, text: noteText, color: state.inkColor))
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
            Text(L("Write a short instruction; it will be drawn on the image for the AI to follow."))
        }
    }

    private var canvas: some View {
        ZStack { canvasContent }
            .animation(Motion.emphasized, value: selectedResultID)
    }

    @ViewBuilder private var canvasContent: some View {
        @Bindable var state = state
        let swap = Motion.transition(AnyTransition(.blurReplace))
        if let source = state.source {
            if let resultID = selectedResultID, let result = app.library.asset(resultID) {
                BeforeAfterView(beforeData: source, after: app.library.url(for: result))
                    .overlay(alignment: .bottom) {
                        resultActions(result)
                    }
                    .id(resultID)
                    .transition(swap)
            } else if tool == .inpaint || tool == .drawToEdit || tool == .product {
                DrawingCanvas(
                    imageData: source,
                    strokes: $state.strokes,
                    notes: $state.notes,
                    brushWidth: state.brushWidth,
                    color: tool == .drawToEdit ? state.inkColor : .systemRed,
                    isEraser: erasing,
                    maskMode: tool != .drawToEdit,
                    placingText: placingText,
                    onPlaceText: { pendingNotePosition = $0 }
                )
                .overlay(alignment: .top) {
                    CanvasToolbar(tool: tool, state: state, placingText: $placingText, erasing: $erasing)
                        .padding(.top, 4)
                }
                .transition(swap)
            } else if tool == .expand {
                ExpandPreview(source: source, target: state.expandTarget)
                    .transition(swap)
            } else {
                DataImage(data: source, maxPixel: 2400)
                    .clipShape(.rect(cornerRadius: Radius.tile))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                    .transition(swap)
            }
        } else {
            ToolEmptyState(tool: tool, source: $state.source, title: ToolControls.primaryLabel(for: tool),
                           sources: ToolControls.primarySources(for: tool))
                .transition(swap)
        }
    }

    private func resultActions(_ result: Asset) -> some View {
        GlassEffectContainer {
            ViewThatFits(in: .horizontal) {
                resultButtons(result).labelStyle(.titleAndIcon)
                resultButtons(result).labelStyle(.iconOnly)
            }
            .buttonStyle(.glass)
        }
        .padding(12)
    }

    private func resultButtons(_ result: Asset) -> some View {
        HStack(spacing: 8) {
            Button(L("Back to the Image"), systemImage: "arrow.uturn.backward") { selectedResultID = nil }
                .help(L("Hide the result and go back to the image you're editing"))
            if tool == .background, result.prompt == "Remove Background" {
                Button(L("Put It on a New Background"), systemImage: "photo.badge.plus") {
                    if let data = try? Data(contentsOf: app.library.url(for: result)) {
                        state.source = data
                        state.clearCanvas()
                        state.backgroundMode = "replace"
                        selectedResultID = nil
                        showControls = true
                    }
                }
                .help(L("Uses the cut-out as the photo and lets you describe the new background"))
            } else {
                Button(L("Keep Editing This One"), systemImage: "square.and.pencil") {
                    if let data = try? Data(contentsOf: app.library.url(for: result)) {
                        state.source = data
                        state.clearCanvas()
                        selectedResultID = nil
                    }
                }
                .help(L("Use the result as the new source image"))
            }
            Button(L("Export…"), systemImage: "square.and.arrow.up") { app.export([result]) }
                .help(L("Export…"))
            Menu(L("More"), systemImage: "ellipsis") { AssetMenu(assets: [result]) }
                .menuIndicator(.hidden)
                .help(L("More"))
        }
        .fixedSize()
    }
}

struct ToolEmptyState: View {
    let tool: Tool
    @Binding var source: Data?
    var title: String
    var sources: WellSources = .standard

    @FocusState private var isFocused: Bool
    @State private var isTargeted = false
    @State private var visibleSize: CGSize = .zero

    private static let stepsInRowWidth: CGFloat = 640
    private static let contentMaxWidth: CGFloat = 980

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, minHeight: visibleSize.height)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self, of: \.size) { visibleSize = $0 }
        .background {
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(Color.appAccent, lineWidth: 2)
                .opacity(isTargeted ? 1 : 0)
                .animation(Motion.press, value: isTargeted)
        }
        .contentShape(.rect)
        .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { providers in
            Task { await take(providers) }
            return true
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onPasteCommand(of: [.fileURL, .image]) { providers in
            Task { await take(providers) }
        }
        .onAppear { isFocused = true }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !tool.steps.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("How it works")).sectionTitleStyle()
                        .accessibilityAddTraits(.isHeader)
                    if visibleSize.width >= Self.stepsInRowWidth * CGFloat(max(3, tool.steps.count)) / 3 {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(Array(tool.steps.enumerated()), id: \.offset) { index, text in
                                ExampleStep(number: index + 1, text: text)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                        }
                        .frame(maxWidth: Self.contentMaxWidth, alignment: .leading)
                    } else {
                        ForEach(Array(tool.steps.enumerated()), id: \.offset) { index, text in
                            ExampleStep(number: index + 1, text: text)
                        }
                    }
                }
            }
            WellAndExampleLayout {
                ImageWell(title: title, data: $source, minHeight: 200, sources: sources)
                    .overlay(alignment: .topLeading) {
                        StepBadge(number: SwapModePicker.modes.contains(tool) ? 2 : 1).padding(12)
                    }
                if let example = Examples.tool(tool) {
                    ToolExampleCard(example: example, extraLabel: Examples.extraLabel(for: tool))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 28)
    }

    private func take(_ providers: [NSItemProvider]) async {
        if let first = await ImageIntake.data(from: providers).first {
            withAnimation(Motion.standard) { source = first }
        }
    }
}

private struct WellAndExampleLayout: Layout {
    private static let gap: CGFloat = 20
    private static let narrowest: CGFloat = 250
    private static let widest: CGFloat = 480

    private func frames(width proposed: CGFloat?, subviews: Subviews) -> [CGRect] {
        let width = proposed.flatMap { $0.isFinite ? $0 : nil } ?? 760
        let column = min(Self.widest, width)
        guard subviews.count > 1 else { return [CGRect(x: 0, y: 0, width: column, height: 330)] }
        let example = subviews[1]
        if width >= Self.narrowest * 2 + Self.gap {
            let side = min(Self.widest, (width - Self.gap) / 2)
            let fitted = example.sizeThatFits(ProposedViewSize(width: side, height: min(460, max(330, side))))
            return [CGRect(x: 0, y: 0, width: side, height: max(220, fitted.height)),
                    CGRect(x: side + Self.gap, y: 0, width: fitted.width, height: fitted.height)]
        }
        let fitted = example.sizeThatFits(ProposedViewSize(width: column, height: 340))
        return [CGRect(x: 0, y: 0, width: column, height: 300),
                CGRect(x: max(0, (column - fitted.width) / 2), y: 300 + Self.gap, width: fitted.width, height: fitted.height)]
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        return frames(width: proposal.width, subviews: subviews).reduce(CGRect.null) { $0.union($1) }.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        for (subview, frame) in zip(subviews, frames(width: proposal.width, subviews: subviews)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(frame.size))
        }
    }
}

struct CanvasToolbar: View {
    let tool: Tool
    @Bindable var state: ComposerState
    @Binding var placingText: Bool
    @Binding var erasing: Bool

    private var inks: [(color: NSColor, name: String)] {
        [(.systemRed, L("Red")), (.systemYellow, L("Yellow")), (.systemGreen, L("Green")), (.systemBlue, L("Blue")),
         (.white, L("White")), (.black, L("Black"))]
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(Capsule()) {
                HStack(spacing: 10) {
                    brushControls
                    if tool == .drawToEdit {
                        Divider().frame(height: 18)
                        inkButtons
                        textToggle
                    }
                    Divider().frame(height: 18)
                    historyButtons
                }
            }
            if tool == .drawToEdit {
                bar(Capsule()) {
                    HStack(spacing: 10) {
                        brushControls
                        Divider().frame(height: 18)
                        inkMenu
                        textToggle
                        Divider().frame(height: 18)
                        historyButtons
                    }
                }
            }
            bar(RoundedRectangle(cornerRadius: Radius.panel)) {
                VStack(spacing: 6) {
                    brushControls
                    HStack(spacing: 10) {
                        if tool == .drawToEdit {
                            inkMenu
                            textToggle
                            Divider().frame(height: 18)
                        }
                        historyButtons
                    }
                }
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.regular)
        .onChange(of: erasing) { _, isOn in if isOn { placingText = false } }
    }

    private func bar<Content: View>(_ shape: some Shape, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(in: shape)
    }

    private var brushControls: some View {
        HStack(spacing: 10) {
            Picker(L("Brush"), selection: $erasing) {
                Text(L("Brush")).tag(false)
                Text(L("Eraser")).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help(L("Paint, or erase part of what you painted"))
            Image(systemName: "circle.fill").font(.system(size: 6))
            Slider(value: $state.brushWidth, in: 0.01...0.2)
                .frame(width: 90)
                .help(L("Brush size"))
            Image(systemName: "circle.fill").font(.system(size: 14))
        }
    }

    private var inkButtons: some View {
        ForEach(inks, id: \.color) { ink in
            Button {
                pick(ink.color)
            } label: {
                Circle()
                    .fill(Color(nsColor: ink.color))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(.primary.opacity(state.inkColor == ink.color ? 0.9 : 0.15), lineWidth: state.inkColor == ink.color ? 2 : 1))
            }
            .buttonStyle(.plain)
            .help(ink.name)
        }
    }

    private var inkMenu: some View {
        Menu {
            Picker(L("Ink color"), selection: Binding(get: { state.inkColor }, set: { pick($0) })) {
                ForEach(inks, id: \.color) { ink in
                    Label { Text(ink.name) } icon: { Image(nsImage: Self.swatch(ink.color)) }
                        .tag(ink.color)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 3) {
                Circle()
                    .fill(Color(nsColor: state.inkColor))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(.primary.opacity(0.9), lineWidth: 2))
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("Ink color"))
    }

    private var textToggle: some View {
        Toggle(isOn: $placingText) {
            Label(L("Text"), systemImage: "textformat")
        }
        .toggleStyle(.button)
        .fixedSize()
        .help(L("Click the image to add a text note"))
    }

    private var historyButtons: some View {
        HStack(spacing: 10) {
            Button {
                if !state.strokes.isEmpty { state.strokes.removeLast() } else if !state.notes.isEmpty { state.notes.removeLast() }
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(state.strokes.isEmpty && state.notes.isEmpty)
            .help(L("Undo stroke (⌘Z)"))
            Button {
                state.clearCanvas()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(state.strokes.isEmpty && state.notes.isEmpty)
            .help(L("Clear all"))
        }
    }

    private func pick(_ ink: NSColor) {
        state.inkColor = ink
        placingText = false
        erasing = false
    }

    private static func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            color.setFill()
            circle.fill()
            NSColor.secondaryLabelColor.setStroke()
            circle.lineWidth = 0.5
            circle.stroke()
            return true
        }
    }
}

struct ExpandPreview: View {
    let source: Data
    let target: AspectRatio

    var body: some View {
        GeometryReader { proxy in
            let canvasRect = fittedRect(for: CGSize(width: target.ratio, height: 1), in: proxy.size)
            let sourceSize = ImageCoding.pixelSize(of: source) ?? CGSize(width: 1, height: 1)
            let inner = fittedRect(for: sourceSize, in: CGSize(width: canvasRect.width * 0.8, height: canvasRect.height * 0.8))
            ZStack {
                RoundedRectangle(cornerRadius: Radius.tile)
                    .fill(.quaternary.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.tile).strokeBorder(Color.brand, style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                    )
                    .frame(width: canvasRect.width, height: canvasRect.height)
                DataImage(data: source, maxPixel: 1600)
                    .frame(width: inner.width, height: inner.height)
                    .clipShape(.rect(cornerRadius: Radius.small))
                Text(L("The AI will fill the dotted area"))
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glassEffect(in: .capsule)
                    .frame(width: canvasRect.width, height: canvasRect.height, alignment: .bottom)
                    .padding(.bottom, 10)
            }
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}

struct ResultsStrip: View {
    let tool: Tool
    @Binding var selectedID: UUID?
    var appID: String?

    @Environment(AppModel.self) private var app

    var body: some View {
        let feed = FeedModel(app: app, tool: tool, appID: appID)
        if !feed.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(L("Results")).groupTitleStyle()
                        .fixedSize()
                    Label(L("Saved to your Library automatically"), systemImage: "checkmark.circle")
                        .fineTextStyle()
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(L("Saved to your Library automatically"))
                    Text(feed.subtitle).fineTextStyle()
                        .fixedSize()
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(feed.batches) { batch in
                            ForEach(batch.slots) { slot in
                                FeedSlotView(slot: slot, batch: batch, pendingLabel: "", failedAspect: 1.4, height: 104) { asset in
                                    AssetCard(asset: asset, isSelected: selectedID == asset.id, maxPixel: 320)
                                        .onTapGesture {
                                            withAnimation(Motion.standard) { selectedID = selectedID == asset.id ? nil : asset.id }
                                        }
                                        .onTapGesture(count: 2) { app.quickLook(asset) }
                                }
                                .frame(height: 104)
                            }
                        }
                    }
                    .animation(Motion.emphasized, value: feed.slotKeys)
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.never)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
            .onChange(of: feed.batches.first?.assets.last?.id) { _, newest in
                if let newest { withAnimation(Motion.standard) { selectedID = newest } }
            }
        }
    }
}
