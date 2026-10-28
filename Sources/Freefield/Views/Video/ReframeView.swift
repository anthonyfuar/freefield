import FreefieldCore
import SwiftUI

struct ReframeView: View {
    let tool: VideoTool

    @Environment(AppModel.self) private var app

    var body: some View {
        let state = app.videoState(for: tool)
        let inputs = app.videoInputs(tool, state: state, forRun: false)
        let expands = !tool.runsOnDevice(for: state.choices)
        let model = expands ? app.resolvedVideoModel(tool, state: state, inputs: inputs) : nil
        let recipe = model.flatMap { VideoRecipes.request(for: tool, state: inputs, model: $0) }
        let source = state.source.assetID.flatMap(app.library.asset)
        let target = state.choice("target", in: tool)
        VideoToolScreen(tool: tool, state: state, model: model) {
            HStack(alignment: .top, spacing: 16) {
                clip(state, expands: expands)
                    .frame(maxWidth: source == nil ? VideoLayout.singleInputWidth : 420)
                if let source {
                    ReframePreview(asset: source, target: VideoModel.ratioValue(target) ?? 1, expands: expands)
                        .frame(maxWidth: .infinity, minHeight: 260, maxHeight: 300)
                }
            }
            targets(state, current: source.map(\.aspect))
            modes(state, inputs: inputs)
            if expands {
                if let field = tool.textField(VideoCatalog.extraFieldID) {
                    ExtraInstructionField(text: Binding(get: { state.texts[field.id] ?? "" }, set: { state.texts[field.id] = $0 }),
                                          placeholder: field.placeholder, caption: L("What to paint in the new space at the sides."),
                                          limit: VideoTextBudget.limit(tool, inputs: inputs, model: model, field: field))
                }
                VideoRunNotes(state: state, recipe: recipe)
            }
        } bar: {
            if expands {
                VideoRunBar(tool: tool, state: state, inputs: inputs, model: model,
                            blockedReason: sameShape(source, target: target) ? L("The clip already has this shape.")
                                : textIsTooLong(state, inputs: inputs, model: model) ? L("Shorten the text to fit the selected model") : nil,
                            followsSource: true)
            } else {
                cropBar(state, source: source, target: target)
            }
        }
        .onChange(of: source?.id, initial: true) { _, _ in
            guard !state.pickedChoices.contains("target"), let source, source.aspect > 0, let group = tool.group("target") else { return }
            if let fresh = group.values.first(where: { !sameShape(source, target: $0) }) { state.choices["target"] = fresh }
        }
    }

    @ViewBuilder private func clip(_ state: VideoState, expands: Bool) -> some View {
        @Bindable var state = state
        if let slot = tool.slot(.sourceVideo) {
            PanelSection(title: slot.title, systemImage: slot.symbol, step: 1, isDone: !state.source.isEmpty) {
                VideoSourceWell(pick: $state.source, title: slot.title, hint: slot.hint, showsSharingNote: expands, showsTitle: false)
            }
        }
    }

    @ViewBuilder private func targets(_ state: VideoState, current: Double?) -> some View {
        if let group = tool.group("target") {
            PanelSection(title: group.title, systemImage: "aspectratio", step: 2, isDone: !state.source.isEmpty) {
                VideoColumns(minimum: 110, spacing: 8, fillsRowHeight: true) {
                    ForEach(group.values, id: \.self) { value in
                        let ratio = VideoModel.ratioValue(value) ?? 1
                        RatioTile(title: value, subtitle: VideoAspectMenu.uses[value] ?? "", ratio: ratio,
                                  isCurrent: current.map { abs($0 - ratio) / ratio < 0.02 } ?? false,
                                  isSelected: state.choice(group.id, in: tool) == value) {
                            state.pick(value, for: group.id)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func modes(_ state: VideoState, inputs: VideoToolInputs) -> some View {
        if let group = tool.group("mode") {
            let pictures = OptionImages.pictures(videoTool: tool.id, group: group)
            PanelSection(title: group.title, systemImage: "aspectratio", step: 3, isDone: !state.source.isEmpty) {
                VideoColumns(minimum: 200, maximum: pictures == nil ? .infinity : 300, spacing: 10, fillsRowHeight: true) {
                    ForEach(group.values, id: \.self) { value in
                        let isCrop = value == "Smart crop"
                        OptionTile(title: L(value),
                                   subtitle: isCrop ? cropSubtitle
                                       : expandCost(inputs).map { L("Paints the missing sides so nothing is cut · %@", $0) }
                                       ?? L("Paints the missing sides so nothing is cut; it costs more"),
                                   systemImage: isCrop ? "crop" : Tool.expand.systemImage,
                                   picture: pictures?[value],
                                   isSelected: state.choice(group.id, in: tool) == value, compact: pictures != nil) {
                            state.choices[group.id] = value
                            state.modelID = nil
                        }
                        .help(isCrop ? "" : L("Made with Runway Aleph 2"))
                    }
                }
            }
        }
    }

    private var cropSubtitle: String {
        app.canLookWithAI
            ? L("The AI follows the subject and the edges are cut · %@", VideoCostLabel.price(AIChecks.subjectPathEstimate))
            : L("Cuts the edges and keeps the center. Add a key so the AI follows the subject.")
    }

    private func expandCost(_ inputs: VideoToolInputs) -> String? {
        var expanded = inputs
        expanded.choices["mode"] = "AI expand"
        guard inputs.hasSourceVideo, let model = app.videoModels.first(where: { $0.id == tool.defaultModel }),
              let cost = app.videoToolCost(tool, inputs: expanded, model: model, count: 1).total else { return nil }
        return VideoCostLabel.price(cost)
    }

    private func textIsTooLong(_ state: VideoState, inputs: VideoToolInputs, model: VideoModel?) -> Bool {
        tool.textFields.contains { field in
            tool.isShown(field.shownWhen, choices: state.choices)
                && state.text(field.id).utf16.count > VideoTextBudget.limit(tool, inputs: inputs, model: model, field: field)
        }
    }

    private func cropBar(_ state: VideoState, source: Asset?, target: String) -> some View {
        let isWorking = state.localWork.contains(where: \.isRunning)
        let reason: String? = source == nil ? (state.source.isEmpty ? L("Add a clip.") : L("Smart crop needs a clip on this Mac, not a link."))
            : sameShape(source, target: target) ? L("The clip already has this shape.")
            : isWorking ? L("Reframing…") : nil
        let usesAI = app.canLookWithAI
        return VideoLocalBar(title: L("Reframe"), reason: reason, isWorking: isWorking,
                             label: usesAI ? Label(L("Cut on this Mac; the AI follows the subject"), systemImage: "sparkle.magnifyingglass")
                                 : Label(L("Centered crop on this Mac, free"), systemImage: "desktopcomputer"),
                             detail: usesAI ? L("Only a few small frames go to the AI, with your key.") : nil,
                             estimatedCost: usesAI ? AIChecks.subjectPathEstimate : nil, costLabel: usesAI ? nil : L("Free")) {
            app.runVideoTool(tool, state: state)
        }
    }

    private func sameShape(_ source: Asset?, target: String) -> Bool {
        guard let source, source.aspect > 0, let ratio = VideoModel.ratioValue(target) else { return false }
        return abs(source.aspect - ratio) / ratio < 0.02
    }
}

private struct RatioTile: View {
    let title: String
    let subtitle: String
    let ratio: Double
    var isCurrent = false
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                let box: CGFloat = 34
                RoundedRectangle(cornerRadius: Radius.small)
                    .strokeBorder(isSelected ? Color.appAccent : .secondary, lineWidth: 2)
                    .frame(width: ratio >= 1 ? box : box * ratio, height: ratio >= 1 ? box / ratio : box)
                    .frame(width: box, height: box)
                Text(title).font(.headline.monospacedDigit())
                Text(isCurrent ? L("The clip's shape now") : subtitle)
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(3).multilineTextAlignment(.center)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 104, maxHeight: .infinity, alignment: .top)
            .background(isSelected ? Color.appAccent.opacity(0.14) : Color.primary.opacity(0.04), in: .rect(cornerRadius: Radius.tile))
            .overlay(RoundedRectangle(cornerRadius: Radius.tile).strokeBorder(isSelected ? Color.appAccent : .clear, lineWidth: 2.5))
            .overlay(alignment: .topTrailing) {
                if isCurrent {
                    Text(L("Current"))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: .capsule)
                        .padding(6)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct ReframePreview: View {
    let asset: Asset
    let target: Double
    let expands: Bool

    @Environment(AppModel.self) private var app

    var body: some View {
        GeometryReader { proxy in
            let source = asset.aspect > 0 ? asset.aspect : 16.0 / 9
            let container = proxy.size
            if expands {
                let canvas = fittedRect(for: CGSize(width: target, height: 1), in: container)
                let inner = fittedRect(for: CGSize(width: source, height: 1), in: canvas.size)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: Radius.tile)
                        .fill(.quaternary.opacity(0.5))
                        .overlay(RoundedRectangle(cornerRadius: Radius.tile).strokeBorder(Color.brand, style: StrokeStyle(lineWidth: 1.5, dash: [7, 6])))
                        .frame(width: canvas.width, height: canvas.height)
                        .offset(x: canvas.minX, y: canvas.minY)
                    poster
                        .frame(width: inner.width, height: inner.height)
                        .clipShape(.rect(cornerRadius: Radius.small))
                        .offset(x: canvas.minX + inner.minX, y: canvas.minY + inner.minY)
                }
                .overlay(alignment: .bottom) { caption(L("The AI paints the dotted area")) }
            } else {
                let frame = fittedRect(for: CGSize(width: source, height: 1), in: container)
                let kept = fittedRect(for: CGSize(width: target, height: 1), in: frame.size)
                ZStack(alignment: .topLeading) {
                    poster
                        .frame(width: frame.width, height: frame.height)
                        .clipShape(.rect(cornerRadius: Radius.thumb))
                        .offset(x: frame.minX, y: frame.minY)
                    Path { path in
                        path.addRect(frame)
                        path.addRect(kept.offsetBy(dx: frame.minX, dy: frame.minY))
                    }
                    .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))
                    RoundedRectangle(cornerRadius: Radius.small)
                        .strokeBorder(Color.yellow, lineWidth: 2)
                        .frame(width: kept.width, height: kept.height)
                        .offset(x: frame.minX + kept.minX, y: frame.minY + kept.minY)
                }
                .overlay(alignment: .bottom) { caption(L("The frame moves with the subject; the dimmed edges are cut")) }
            }
        }
    }

    private var poster: some View {
        VideoPoster(url: app.library.url(for: asset), posterURL: app.library.posterURL(for: asset), maxPixel: 900)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .glassEffect(in: .capsule)
            .padding(.bottom, 8)
    }
}
