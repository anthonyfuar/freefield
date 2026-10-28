import FreefieldCore
import SwiftUI

struct ToolControls: View {
    let tool: Tool
    @Bindable var state: ComposerState
    @Binding var placingText: Bool
    var onNewSource: () -> Void = {}

    @Environment(AppModel.self) private var app

    static func primaryLabel(for tool: Tool) -> String {
        switch tool {
        case .faceSwap, .characterSwap, .outfitSwap: L("Photo to change")
        case .product: L("Scene")
        case .editText: L("Image with text")
        case .upscale: L("Photo to improve")
        case .relight: L("Photo to relight")
        case .expand: L("Image to expand")
        case .angles: L("Original image")
        case .background: L("Photo")
        default: L("Image to edit")
        }
    }

    static func primarySources(for tool: Tool) -> WellSources {
        switch tool {
        case .faceSwap, .outfitSwap: .person
        case .characterSwap, .product: [.library]
        default: .standard
        }
    }

    private var requirement: ModelRequirement { ModelRequirement(images: max(1, inputCount), minimumImages: requiredInputs) }

    private var requiredInputs: Int {
        switch tool {
        case .inpaint, .drawToEdit, .faceSwap, .characterSwap, .outfitSwap, .product: 2
        default: 0
        }
    }

    private var inputCount: Int {
        var count = state.source == nil ? 0 : 1
        if state.secondary != nil { count += 1 }
        if tool == .inpaint || tool == .drawToEdit || (tool == .product && state.hasPaint) { count += 1 }
        return count + state.references.count
    }

    private var removesBackground: Bool { tool == .background && state.backgroundMode == "remove" }

    private var isSwap: Bool { SwapModePicker.modes.contains(tool) }

    private var firstInputStep: Int { isSwap ? 2 : 1 }

    private var inputSteps: Int {
        switch tool {
        case .faceSwap, .characterSwap, .outfitSwap: 3
        case .product: 2
        default: 1
        }
    }

    private var hasSource: Bool { state.source != nil }

    private var hasTextReplacement: Bool {
        state.textEdits.contains { !$0.replacement.isEmpty && $0.replacement != $0.original }
    }

    private var hasSecondary: Bool {
        state.secondary != nil || (tool == .characterSwap && state.characterID != nil)
    }

    private var hasPrimary: Bool {
        switch tool {
        case .edit, .inpaint, .drawToEdit, .upscale, .relight, .editText, .angles, .expand, .background: true
        default: false
        }
    }

    private var hasAdjustments: Bool {
        switch tool {
        case .edit, .upscale, .relight, .faceSwap: true
        default: false
        }
    }

    var body: some View {
        let model = app.toolModel(for: state, requirement: requirement)
        let instructionsFirst = !Self.instructionsAfterMainChoice.contains(tool)
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: Spacing.xl + 4) {
                        if isSwap {
                            SwapModePicker(tool: tool, state: state, step: 1, isDone: hasSource)
                        }
                        VStack(alignment: .leading, spacing: tool == .product ? Spacing.xl + 4 : Spacing.m) {
                            VStack(alignment: .leading, spacing: Spacing.xl + 4) { inputs }
                            if instructionsFirst { extraInstruction(model) }
                        }
                        if hasPrimary || !instructionsFirst {
                            VStack(alignment: .leading, spacing: Spacing.m) {
                                VStack(alignment: .leading, spacing: Spacing.xl + 4) { primary(model) }
                                if !instructionsFirst { extraInstruction(model) }
                            }
                        }
                    }
                    ExtrasHeader()
                    VStack(alignment: .leading, spacing: Spacing.l + 4) {
                        if hasAdjustments { adjustments }
                        output(model)
                    }
                }
                .padding(20)
            }
            Divider()
            actionBar(model)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        }
    }

    private func actionBar(_ model: ImageModel?) -> some View {
        let reason = disabledReason(model)
        let cost = app.estimatedCost(model: model, count: runCount, resolution: state.resolution)
        return VStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                generateButton(model, reason: reason, cost: cost, size: .extraLarge)
                generateButton(model, reason: reason, cost: cost, size: .large)
            }
            .frame(maxWidth: .infinity)
            DisabledReasonLabel(reason: reason)
        }
        .animation(Motion.standard, value: reason)
    }

    private func generateButton(_ model: ImageModel?, reason: String?, cost: Double?, size: ControlSize) -> some View {
        GenerateButton(title: actionTitle, isEnabled: reason == nil, disabledReason: reason, estimatedCost: cost,
                       isWorking: state.isEnhancing, size: size) {
            run(model)
        }
    }

    private func run(_ model: ImageModel?) {
        if let model { app.runTool(tool, state: state, model: model) }
    }

    private func submit(_ model: ImageModel?) {
        if disabledReason(model) == nil { run(model) }
    }

    private var actionTitle: String {
        switch tool {
        case .upscale: L("Improve Quality")
        case .relight: L("Change the Light")
        case .angles: state.anglesMode == "orbit" ? L("Move Camera") : runCount == 1 ? L("Generate 1 Angle") : L("Generate %ld Angles", runCount)
        case .editText: L("Replace Text")
        case .expand: L("Widen the Frame")
        case .background: removesBackground ? L("Remove Background") : L("Change Background")
        case .faceSwap: L("Swap Face")
        case .characterSwap: L("Swap In Character")
        case .outfitSwap: L("Dress Up")
        case .product: L("Place Product")
        case .inpaint where state.trimmedPrompt.isEmpty: L("Erase the painted area")
        default: runCount > 1 ? L("Generate %ld images", runCount) : L("Generate")
        }
    }

    private var runCount: Int {
        switch tool {
        case .angles: state.anglesMode == "orbit" ? state.count : max(1, state.angles.count)
        case .upscale, .background: 1
        default: state.count
        }
    }

    private func disabledReason(_ model: ImageModel?) -> String? {
        if !app.hasAnyKey { return L("Add an API key in Settings") }
        if state.source == nil { return DisabledReasonLabel.nextStep(Self.primaryLabel(for: tool).localizedLowercase) }
        if model == nil { return app.catalog.isLoading ? L("Loading models…") : L("No compatible model available") }
        switch tool {
        case .edit where state.trimmedPrompt.isEmpty: return L("Describe the change")
        case .inpaint where !state.hasPaint: return L("Paint the area to change")
        case .expand where state.source.flatMap(Self.closestRatio) == state.expandTarget: return L("Choose a shape other than your photo's")
        case .drawToEdit where !state.hasPaint && state.notes.isEmpty: return L("Draw or write on the image")
        case .faceSwap where state.secondary == nil: return DisabledReasonLabel.nextStep(L("Face photo").localizedLowercase)
        case .outfitSwap where state.secondary == nil: return DisabledReasonLabel.nextStep(L("Garment photo").localizedLowercase)
        case .characterSwap where state.secondary == nil && state.characterID == nil: return L("Choose a character or upload their photo")
        case .angles where state.anglesMode == "presets" && state.angles.isEmpty: return L("Choose at least one angle")
        case .product where state.secondary == nil: return DisabledReasonLabel.nextStep(L("Product photo").localizedLowercase)
        case .editText where !hasTextReplacement:
            if state.isDetectingText { return L("Looking for text…") }
            return state.textEdits.isEmpty ? L("Detect the text in the image") : L("Type the new text")
        case .background where !removesBackground && state.trimmedPrompt.isEmpty: return L("Describe the new background")
        default: return nil
        }
    }

    @ViewBuilder private var inputs: some View {
        PanelSection(title: Self.primaryLabel(for: tool), step: firstInputStep, isDone: hasSource) {
            InputRow(data: $state.source, onReplace: {
                state.clearCanvas()
                onNewSource()
            }) {
                EmptySourceRow {
                    state.source = $0
                    state.clearCanvas()
                    onNewSource()
                }
            }
            relatedHint
        }
        switch tool {
        case .faceSwap:
            PanelSection(title: L("Face photo"), step: firstInputStep + 1, isDone: hasSecondary) {
                secondaryInput(L("Face photo"), subtitle: L("A clear, front-facing photo"), systemImage: "face.dashed", sources: .person)
            }
        case .outfitSwap:
            PanelSection(title: L("Garment"), step: firstInputStep + 1, isDone: hasSecondary) {
                secondaryInput(L("Garment photo"), subtitle: L("The product alone or someone wearing it"), systemImage: "tshirt", sources: .standard)
                if state.secondary == nil {
                    RelatedToolHint(prompt: L("No photo of the garment?"),
                                    links: [app.relatedLink(.quickStyle("ai-stylist"), title: L("Try “%@”", RelatedTool.quickStyle("ai-stylist").name),
                                                            image: state.source)])
                }
            }
        case .characterSwap:
            PanelSection(title: L("Character"), step: firstInputStep + 1, isDone: hasSecondary) {
                VStack(alignment: .leading, spacing: 10) {
                    CharacterMenu(selection: $state.characterID, placeholder: L("Choose a saved character…"), fillsWidth: true)
                    if state.characterID == nil {
                        OrDivider()
                        secondaryInput(L("Upload their photo"), subtitle: L("A clear photo of the person"),
                                       systemImage: "person.crop.circle.badge.plus", sources: [.library])
                    }
                }
            }
        case .product:
            PanelSection(title: L("Product or object"), step: firstInputStep + 1, isDone: hasSecondary) {
                secondaryInput(L("Product photo"), subtitle: L("Works best with a clean background"), systemImage: "shippingbox", sources: .standard)
            }
        default:
            EmptyView()
        }
    }

    private func secondaryInput(_ title: String, subtitle: String, systemImage: String, sources: WellSources) -> some View {
        InputRow(data: $state.secondary) {
            ImageWell(title: title, subtitle: subtitle, systemImage: systemImage, data: $state.secondary, minHeight: 120, sources: sources,
                      isInPanel: true)
                .frame(height: 170)
        }
    }

    @ViewBuilder private var relatedHint: some View {
        let image = state.source
        switch tool {
        case .background:
            RelatedToolHint(prompt: L("Is it a product?"), links: [app.relatedLink(.ad("product-shoot"), image: image)])
        case .relight:
            RelatedToolHint(prompt: L("Only the colors?"),
                            links: [app.relatedLink(.tool(.colorGrade), title: L("%@ (free)", Tool.colorGrade.title), image: image)])
        case .inpaint:
            RelatedToolHint(prompt: L("Rather draw arrows and notes?"), links: [app.relatedLink(.tool(.drawToEdit), image: image)])
        case .drawToEdit:
            RelatedToolHint(prompt: L("Just one area?"), links: [app.relatedLink(.tool(.inpaint), image: image)])
        case .angles:
            RelatedToolHint(prompt: L("All the shots in one grid?"),
                            links: [app.relatedLink(.quickStyle("shots"), title: L("Try “%@”", RelatedTool.quickStyle("shots").name), image: image)])
        default:
            EmptyView()
        }
    }

    private var editKeywordLinks: [RelatedToolHint.Link] {
        let words = Set(state.trimmedPrompt.lowercased().split { !$0.isLetter }.map(String.init))
        guard !words.isEmpty else { return [] }
        let matches: [(words: Set<String>, tool: Tool)] = [
            (["fondo", "background"], .background),
            (["luz", "luces", "iluminación", "iluminacion", "light", "lighting"], .relight),
            (["texto", "textos", "letras", "letrero", "text", "lettering"], .editText),
        ]
        return matches.filter { !$0.words.isDisjoint(with: words) }
            .map { app.relatedLink(.tool($0.tool), image: state.source) }
    }

    @ViewBuilder private func primary(_ model: ImageModel?) -> some View {
        let step = inputSteps + 1
        switch tool {
        case .edit:
            VStack(alignment: .leading, spacing: Spacing.s) {
                promptSection(L("What do you want to change?"), step: step, isDone: hasSource && !state.trimmedPrompt.isEmpty,
                              model: model, placeholder: L("E.g. swap the jacket for a black leather one and add rain"),
                              suggestions: [L("Make it nighttime"), L("Add rain"), L("Remove the people in the background"),
                                            L("Change the sky to a sunset"), L("Make it look like a film photo")])
                RelatedToolHint(links: editKeywordLinks)
                    .animation(Motion.standard, value: editKeywordLinks.map(\.title))
            }
        case .inpaint:
            PanelSection(title: L("Paint the area"), step: step, isDone: hasSource && state.hasPaint) {
                Text(L("Fix mistakes with the eraser, or undo with ⌘Z."))
                    .helperTextStyle()
                    .fixedSize(horizontal: false, vertical: true)
            }
            promptSection(L("What goes there?"), step: step + 1, isDone: hasSource && !state.trimmedPrompt.isEmpty, isOptional: true,
                          model: model, placeholder: L("E.g. a vase of sunflowers"),
                          suggestions: [L("Change its color to red"), L("A potted plant"), L("Smooth the skin, keep it natural")],
                          caption: L("Leave it empty to erase what you painted."))
        case .drawToEdit:
            PanelSection(title: L("Draw on the image"), step: step, isDone: hasSource && (state.hasPaint || !state.notes.isEmpty)) {
                Text(state.source == nil ? L("Add the image, then draw arrows, circles or notes on it.")
                     : L("Add notes with the “Text” button. Fix mistakes with the eraser, or undo with ⌘Z."))
                    .helperTextStyle()
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .upscale:
            PanelSection(title: L("Resolution"), step: step, isDone: hasSource) {
                Picker(L("Resolution"), selection: $state.resolution) {
                    Text("2K").tag(Resolution.twoK)
                    Text("4K").tag(Resolution.fourK)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(L("2K: social media and screens · 4K: printing or cropping"))
                    .helperTextStyle()
                    .fixedSize(horizontal: false, vertical: true)
                if let line = upscaleSizeLine {
                    Text(line).fineTextStyle()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .relight:
            RelightControls(state: state, step: step, isDone: hasSource)
        case .editText:
            EditTextControls(state: state, step: step, isDone: hasSource && hasTextReplacement)
        case .angles:
            anglesSection(step: step)
        case .expand:
            expandSection(step: step)
        case .background:
            PanelSection(title: L("Mode"), step: step, isDone: hasSource) {
                backgroundModes
                Text(!removesBackground ? L("The AI replaces the background and matches the lighting and shadows.")
                     : model?.supportsTransparency == false
                     ? L("The AI cuts out the subject. This model can't make a transparent background, so it comes out on pure white; for transparency, choose a GPT Image model.")
                     : L("The AI cuts out the person or object and leaves the background transparent."))
                    .helperTextStyle()
                    .fixedSize(horizontal: false, vertical: true)
                if removesBackground {
                    Label(L("Works best with a clearly defined person or object."), systemImage: "lightbulb")
                        .helperTextStyle()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !removesBackground {
                promptSection(L("New background"), step: step + 1, isDone: hasSource && !state.trimmedPrompt.isEmpty, model: model,
                              placeholder: L("E.g. a studio with a beige backdrop and a soft shadow"),
                              suggestions: [L("White studio"), L("Beach at sunset"), L("Neon-lit street at night"), L("Misty forest"),
                                            L("Pastel gradient"), L("Modern office"), L("Bright kitchen"), L("Snowy mountains")])
            }
        default:
            EmptyView()
        }
    }

    private var backgroundModes: some View {
        let modes = [("remove", L("No background"), L("just the person or object"), "person.crop.rectangle"),
                     ("replace", L("Replace with AI"), L("the person or object in a new place"), "photo")]
        let pictures = OptionImages.pictures(family: "background", values: modes.map(\.0))
        return OptionGrid(columns: 2) {
            ForEach(modes, id: \.0) { mode in
                OptionTile(title: mode.1, subtitle: mode.2, systemImage: mode.3, picture: pictures?[mode.0],
                           isSelected: state.backgroundMode == mode.0) {
                    state.backgroundMode = mode.0
                }
            }
        }
    }

    private func anglesSection(step: Int) -> some View {
        PanelSection(title: L("Camera angles"), step: step,
                     isDone: hasSource && (state.anglesMode == "orbit" || !state.angles.isEmpty)) {
            VStack(alignment: .leading, spacing: 10) {
                Picker(L("Mode"), selection: $state.anglesMode) {
                    Text(L("Ready angles")).tag("presets")
                    Text(L("Move the camera")).tag("orbit")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                if state.anglesMode == "orbit" {
                    Text(L("Drag the camera around the person, or use the sliders."))
                        .helperTextStyle()
                        .fixedSize(horizontal: false, vertical: true)
                    OrbitControls(state: state)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text(L("Pick one or more · one image per angle"))
                            .helperTextStyle()
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 6)
                        Button(state.angles.count == CameraAngle.all.count ? L("Deselect All") : L("Select All 12")) {
                            state.angles = state.angles.count == CameraAngle.all.count ? [] : Set(CameraAngle.all.map(\.id))
                        }
                        .buttonStyle(.link)
                        .font(.callout)
                        .fixedSize()
                    }
                    let pictures = OptionImages.pictures(family: "angles", values: CameraAngle.all.map(\.id))
                    OptionGrid(minimum: pictures == nil ? 92 : PanelLayout.pictureCardMinimum) {
                        ForEach(CameraAngle.all) { angle in
                            OptionTile(title: angle.name, subtitle: angle.detail, systemImage: angle.symbol, picture: pictures?[angle.id],
                                       isSelected: state.angles.contains(angle.id), isMultiSelect: true) {
                                if state.angles.contains(angle.id) { state.angles.remove(angle.id) } else { state.angles.insert(angle.id) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func expandSection(step: Int) -> some View {
        let current = state.source.flatMap(Self.closestRatio)
        let shapes = AspectRatio.standard.filter { $0 != .auto }
        let groups: [(title: String, ratios: [AspectRatio])] = [
            (L("Vertical"), shapes.filter { $0.ratio < 1 }.sorted { $0.ratio > $1.ratio }),
            (L("Square"), shapes.filter { $0.ratio == 1 }),
            (L("Horizontal"), shapes.filter { $0.ratio > 1 }.sorted { $0.ratio < $1.ratio }),
        ]
        return PanelSection(title: L("New shape"), step: step, isDone: hasSource && current != state.expandTarget) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 42), spacing: 8)], spacing: 8) {
                            ForEach(group.ratios) { ratio in
                                shapeTile(ratio, isCurrent: ratio == current)
                            }
                        }
                    }
                }
                Text(state.expandTarget.label + " · " + state.expandTarget.usage)
                    .helperTextStyle()
                    .fixedSize(horizontal: false, vertical: true)
                if let current {
                    Text(L("Your photo is %@ now. Pick another shape to add space around it.", current.label))
                        .helperTextStyle()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func shapeTile(_ ratio: AspectRatio, isCurrent: Bool) -> some View {
        let isSelected = state.expandTarget == ratio
        return Button {
            state.expandTarget = ratio
            state.expandTargetIsChosen = true
        } label: {
            VStack(spacing: 3) {
                AspectGlyph(ratio: ratio, size: 22)
                Text(ratio.label).font(.subheadline.monospacedDigit())
                if isCurrent {
                    Text(L("Current")).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(isSelected ? Color.appAccent.opacity(0.15) : Color.primary.opacity(0.04), in: .rect(cornerRadius: Radius.thumb))
            .overlay(RoundedRectangle(cornerRadius: Radius.thumb).strokeBorder(isSelected ? Color.appAccent : .clear, lineWidth: 2))
            .contentShape(.rect(cornerRadius: Radius.thumb))
        }
        .buttonStyle(PressableStyle())
        .disabled(isCurrent)
        .opacity(isCurrent ? 0.5 : 1)
        .help(isCurrent ? L("Your photo already has this shape") : ratio.usage)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    static func closestRatio(_ data: Data) -> AspectRatio? {
        guard let size = ImageCoding.pixelSize(of: data), size.width > 0, size.height > 0 else { return nil }
        let value = size.width / size.height
        return AspectRatio.standard.filter { $0 != .auto }.min { abs(log($0.ratio / value)) < abs(log($1.ratio / value)) }
    }

    @ViewBuilder private var adjustments: some View {
        switch tool {
        case .edit:
            OptionalSection(L("References"), systemImage: "photo.stack",
                            summary: state.references.isEmpty ? L("Optional") : L("%ld reference photos", state.references.count),
                            isFilled: !state.references.isEmpty, storageKey: "tool.edit.references") {
                Text(L("Photos of what you want to add (e.g. the jacket)."))
                    .helperTextStyle()
                    .fixedSize(horizontal: false, vertical: true)
                ReferenceStrip(images: $state.references, limit: 6)
            }
        case .upscale:
            OptionalSection(L("Fine-tune"), systemImage: "dial.medium",
                            summary: creativityLabel, storageKey: "tool.upscale.finetune") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Creativity")).inspectorFieldLabel()
                    Slider(value: $state.upscaleCreativity, in: 0...1)
                    HStack(alignment: .firstTextBaseline) {
                        Text(L("Faithful to the original"))
                        Spacer(minLength: 6)
                        Text(L("More invented detail")).multilineTextAlignment(.trailing)
                    }
                    .fineTextStyle()
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .relight:
            RelightFineTune(state: state)
        case .faceSwap:
            PanelSection(title: L("Options"), systemImage: "slider.horizontal.3") {
                Toggle(L("Keep the expression of the photo to change"), isOn: $state.swapKeepExpression)
            }
        default:
            EmptyView()
        }
    }

    private var creativityLabel: String {
        state.upscaleCreativity < 0.34 ? L("Faithful to the original")
            : state.upscaleCreativity < 0.67 ? L("Some invented detail") : L("More invented detail")
    }

    private static let instructionsAfterMainChoice: Set<Tool> = [.drawToEdit, .editText]

    @ViewBuilder private func extraInstruction(_ model: ImageModel?) -> some View {
        let limit = app.promptLimit(for: tool, state: state, model: model)
        if tool == .product {
            PanelSection(title: L("Where to place it"), step: inputSteps + 1,
                         isDone: hasSource && (state.hasPaint || !state.trimmedPrompt.isEmpty), isOptional: true) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Paint on the scene, or describe it here:"))
                        .helperTextStyle()
                        .fixedSize(horizontal: false, vertical: true)
                    PromptField(text: $state.prompt, placeholder: L("E.g. on the table next to the mug, with a soft reflection"),
                                minLines: 2, maxLines: 5, focusOnAppear: false) { submit(model) }
                        .characterLimit($state.prompt, limit)
                    Text(L("If you do neither, the AI picks the best spot."))
                        .helperTextStyle()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if let placeholder = extraPlaceholder {
            ExtraInstructionField(text: $state.prompt, placeholder: placeholder, caption: extraCaption, limit: limit)
        }
    }

    private var extraPlaceholder: String? {
        switch tool {
        case .drawToEdit: L("E.g. make everything look like a magazine photo")
        case .editText: L("E.g. in gold and a bit bigger")
        case .upscale: L("E.g. keep the grain and don't smooth the skin")
        case .relight: L("E.g. a soft glow in the hair")
        case .angles: L("E.g. looking at the camera, blurred background")
        case .expand: L("E.g. a beach at sunset")
        case .faceSwap: L("E.g. keep the glasses and the beard")
        case .characterSwap: L("E.g. smiling and looking at the camera")
        case .outfitSwap: L("E.g. with the jacket open and the sleeves rolled up")
        default: nil
        }
    }

    private var extraCaption: String? {
        tool == .expand ? L("What should appear in the new area. Leave it empty to continue the scene.") : nil
    }

    private func promptSection(_ title: String, step: Int?, isDone: Bool = false, isOptional: Bool = false, model: ImageModel?,
                               placeholder: String, suggestions: [String] = [], caption: String? = nil) -> some View {
        PanelSection(title: title, systemImage: step == nil ? "text.bubble" : nil, step: step, isDone: isDone, isOptional: isOptional) {
            VStack(alignment: .leading, spacing: 8) {
                PromptField(text: $state.prompt, placeholder: placeholder, minLines: 3, maxLines: 8,
                            focusOnAppear: state.source != nil) { submit(model) }
                    .characterLimit($state.prompt, app.promptLimit(for: tool, state: state, model: model))
                if let caption {
                    Text(caption).helperTextStyle()
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !suggestions.isEmpty {
                    FlowChips(options: suggestions) { state.prompt = FlowChips.adding($0, to: state.prompt) }
                }
            }
        }
    }

    private var upscaleSizeLine: String? {
        guard let source = state.source, let size = ImageCoding.pixelSize(of: source), size.width > 0 else { return nil }
        let target = state.resolution == .twoK ? 2048.0 : 4096.0
        let current = L("Your photo: %ld×%ld", Int(size.width), Int(size.height))
        if max(size.width, size.height) >= target * 0.95 {
            return current + " · " + L("already this size or bigger")
        }
        return current + " → " + state.resolution.rawValue
    }

    @ViewBuilder private func output(_ model: ImageModel?) -> some View {
        let showsCount = tool != .upscale && tool != .background && !(tool == .angles && state.anglesMode == "presets")
        let ratios = tool == .upscale || tool == .expand ? [] : model?.aspectRatios ?? []
        let resolutions = tool == .upscale ? [] : model?.resolutions ?? []
        let qualities = model?.qualities ?? []
        let summary = [
            showsCount ? (state.count == 1 ? L("1 image") : L("%ld images", state.count)) : nil,
            ratios.isEmpty ? nil : state.aspectRatio == .auto ? L("original shape") : state.aspectRatio.label,
            resolutions.count > 1 && state.resolution != .oneK ? state.resolution.rawValue : nil,
            !qualities.isEmpty && state.quality != "auto" ? QualityMenu.label(state.quality) : nil,
            state.modelID == nil ? L("Auto") : model.map { app.catalog.choice(for: $0).displayName },
        ].compactMap(\.self).joined(separator: " · ")
        OptionalSection(L("More options"), systemImage: "slider.horizontal.3", summary: summary, storageKey: "tool.moreOptions") {
            if showsCount || !ratios.isEmpty || resolutions.count > 1 || !qualities.isEmpty {
                FlowLayout(spacing: 6) {
                    if showsCount { CountMenu(count: $state.count, maximum: 4) }
                    if !ratios.isEmpty { AspectRatioMenu(selection: $state.aspectRatio, available: ratios, autoTitle: L("Shape: original")) }
                    if resolutions.count > 1 { ResolutionMenu(selection: $state.resolution, available: resolutions) }
                    if !qualities.isEmpty { QualityMenu(selection: $state.quality, available: qualities) }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(L("AI model")).inspectorFieldLabel()
                ModelPicker(selectionID: $state.modelID, current: model, requirement: requirement)
                if let model {
                    Text(app.catalog.choice(for: model).tagline)
                        .helperTextStyle()
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if AppModel.enhancesDescription(of: tool), !removesBackground {
                    AutoEnhanceSwitch(style: .panel)
                        .padding(.top, 6)
                }
            }
        }
    }
}

struct InputRow<Empty: View>: View {
    @Binding var data: Data?
    var onReplace: () -> Void = {}
    @ViewBuilder var empty: () -> Empty

    @State private var isTargeted = false

    var body: some View {
        Group {
            if let data {
                HStack(spacing: 10) {
                    DataImage(data: data, maxPixel: 240, contentMode: .fill)
                        .frame(width: 52, height: 52)
                        .clipShape(.rect(cornerRadius: Radius.thumb))
                        .overlay(RoundedRectangle(cornerRadius: Radius.thumb).strokeBorder(.primary.opacity(0.1)))
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.brand)
                        .accessibilityLabel(L("Image added"))
                    Spacer(minLength: 4)
                    Button(L("Change…"), action: choose)
                        .fixedSize()
                    Button(L("Remove image"), systemImage: "xmark") { set(nil) }
                        .labelStyle(.iconOnly)
                        .help(L("Remove image"))
                }
                .buttonStyle(.glass)
                .controlSize(.regular)
                .padding(6)
                .background(isTargeted ? Color.appAccent.opacity(0.12) : Color.primary.opacity(0.04), in: .rect(cornerRadius: Radius.tile))
                .transition(.opacity)
            } else {
                empty()
            }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { providers in
            Task {
                if let first = await ImageIntake.data(from: providers).first { set(first) }
            }
            return true
        }
    }

    private func choose() {
        if let first = ImageIntake.pick(multiple: false).first { set(first) }
    }

    private func set(_ new: Data?) {
        withAnimation(Motion.standard) { data = new }
        onReplace()
    }
}

struct SwapModePicker: View {
    static let modes: [Tool] = [.faceSwap, .characterSwap, .outfitSwap]

    let tool: Tool
    let state: ComposerState
    var step: Int?
    var isDone = false

    @Environment(AppModel.self) private var app

    var body: some View {
        PanelSection(title: L("What do you want to swap?"), systemImage: "arrow.triangle.2.circlepath", step: step, isDone: isDone) {
            OptionGrid(columns: 3, minimum: 80, spacing: 6) {
                ForEach(Self.modes, id: \.self) { mode in
                    OptionTile(title: Self.title(mode), systemImage: Self.symbol(mode),
                               picture: Examples.tool(mode).map { OptionPicture(url: $0.after) },
                               isSelected: mode == tool, compact: true) {
                        if mode != tool { app.openRelated(.tool(mode), image: state.source) }
                    }
                }
            }
        }
    }

    static func title(_ mode: Tool) -> String {
        switch mode {
        case .faceSwap: L("Just the face")
        case .characterSwap: L("The whole person")
        default: L("Just the clothes")
        }
    }

    static func symbol(_ mode: Tool) -> String {
        switch mode {
        case .faceSwap: "face.smiling"
        case .characterSwap: "person.fill"
        default: "tshirt"
        }
    }
}

struct OrDivider: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(.quaternary).frame(height: 1)
            Text(L("or")).fineTextStyle()
            Rectangle().fill(.quaternary).frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}

struct RelightControls: View {
    @Bindable var state: ComposerState
    var step = 2
    var isDone = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pictures = OptionImages.pictures(family: "light", values: LightPreset.all.map(\.id))
        PanelSection(title: L("Lighting mood"), step: step, isDone: isDone) {
            OptionGrid(minimum: pictures == nil ? 92 : PanelLayout.pictureCardMinimum) {
                ForEach(LightPreset.all) { preset in
                    OptionTile(title: preset.name, subtitle: preset.detail, systemImage: preset.symbol,
                               picture: pictures?[preset.id], isSelected: state.lightPreset == preset.id) {
                        withAnimation(reduceMotion ? nil : Motion.standard) { preset.apply(to: state) }
                    }
                }
            }
        }
    }
}

struct RelightFineTune: View {
    @Bindable var state: ComposerState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OptionalSection(L("Fine-tune the light"), systemImage: "dial.medium", summary: summary,
                        storageKey: "tool.relight.finetune") {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Light direction")).inspectorFieldLabel()
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        directionButton(L("Top"), CGPoint(x: 0, y: -0.95))
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                    GridRow {
                        directionButton(L("Left"), CGPoint(x: -0.95, y: 0))
                        LightDirectionPad(direction: $state.lightDirection, color: state.lightColor)
                            .frame(width: 110, height: 110)
                        directionButton(L("Right"), CGPoint(x: 0.95, y: 0))
                    }
                    GridRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        directionButton(L("Bottom"), CGPoint(x: 0, y: 0.95))
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
                .frame(maxWidth: .infinity)
                HStack(alignment: .firstTextBaseline) {
                    Text(L("Drag the sun around the person."))
                        .helperTextStyle()
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    Button(L("From the Front")) { move(to: .zero) }
                        .buttonStyle(.link)
                        .font(.callout)
                        .fixedSize()
                }
            }
            ColorPicker(L("Color"), selection: $state.lightColor, supportsOpacity: false)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Hardness")).inspectorFieldLabel()
                Picker(L("Hardness"), selection: $state.lightHard) {
                    Text(L("Soft")).tag(false)
                    Text(L("Hard")).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Intensity")).inspectorFieldLabel()
                Slider(value: $state.lightIntensity, in: 0...1)
            }
        }
    }

    private var summary: String {
        let direction = state.lightDirection
        let side = abs(direction.x) < 0.33 && abs(direction.y) < 0.33 ? L("Light from the front")
            : abs(direction.x) >= abs(direction.y) ? (direction.x < 0 ? L("Light from the left") : L("Light from the right"))
            : (direction.y < 0 ? L("Light from above") : L("Light from below"))
        return side + " · " + (state.lightHard ? L("hard") : L("soft"))
    }

    @ViewBuilder private func directionButton(_ title: String, _ point: CGPoint) -> some View {
        let isSelected = abs(state.lightDirection.x - point.x) < 0.1 && abs(state.lightDirection.y - point.y) < 0.1
        if isSelected {
            Button(title) { move(to: point) }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .fixedSize()
                .accessibilityAddTraits(.isSelected)
        } else {
            Button(title) { move(to: point) }
                .buttonStyle(.glass)
                .controlSize(.small)
                .fixedSize()
        }
    }

    private func move(to point: CGPoint) {
        withAnimation(reduceMotion ? nil : Motion.standard) { state.lightDirection = point }
    }
}

struct LightDirectionPad: View {
    @Binding var direction: CGPoint
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let radius = min(proxy.size.width, proxy.size.height) / 2
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(colors: [color.opacity(0.55), .clear],
                                       center: UnitPoint(x: 0.5 + direction.x / 2, y: 0.5 + direction.y / 2),
                                       startRadius: 0, endRadius: radius * 1.6)
                    )
                    .overlay(Circle().strokeBorder(.secondary.opacity(0.35)))
                Image(systemName: "person.fill")
                    .font(.system(size: radius * 0.55))
                    .foregroundStyle(.secondary)
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(color, .yellow)
                    .shadow(color: color, radius: 6)
                    .position(x: center.x + direction.x * (radius - 12), y: center.y + direction.y * (radius - 12))
            }
            .contentShape(.circle)
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                var vector = CGPoint(x: (value.location.x - center.x) / (radius - 12), y: (value.location.y - center.y) / (radius - 12))
                let length = sqrt(vector.x * vector.x + vector.y * vector.y)
                if length > 1 { vector = CGPoint(x: vector.x / length, y: vector.y / length) }
                direction = vector
            })
            .accessibilityLabel(L("Light direction"))
        }
    }
}

struct FlowChips: View {
    let options: [String]
    let onPick: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(options, id: \.self) { option in
                Button(option) { onPick(option) }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .lineLimit(1)
                    .help(L("Adds this to your description"))
            }
        }
    }

    static func adding(_ suggestion: String, to text: String) -> String {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return suggestion }
        if typed.hasSuffix(".") || typed.hasSuffix("!") { return typed + " " + suggestion }
        return typed + (typed.hasSuffix(",") ? " " : ", ") + suggestion.prefix(1).lowercased() + suggestion.dropFirst()
    }
}

struct EditTextControls: View {
    @Bindable var state: ComposerState
    var step = 2
    var isDone = false

    @Environment(AppModel.self) private var app
    @State private var error: String?
    @State private var foundNoText = false

    private struct DetectionKey: Equatable {
        let size: Int?
        let isEmpty: Bool
        let canRead: Bool
    }

    var body: some View {
        PanelSection(title: L("Text in the image"), step: step, isDone: isDone) {
            VStack(alignment: .leading, spacing: 8) {
                if state.source == nil {
                    if app.canLookWithAI {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(L("Add the image first: the AI reads its text by itself."))
                                .helperTextStyle()
                                .fixedSize(horizontal: false, vertical: true)
                            PricePill(text: readingCost)
                        }
                    } else {
                        Text(L("Add the image, then type each line by hand. With a key in Settings, the AI reads the text for you."))
                            .helperTextStyle()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    HStack(spacing: 8) {
                        Button {
                            Task { await detect() }
                        } label: {
                            Label(state.textEdits.isEmpty ? L("Detect Text") : L("Detect Again"), systemImage: "text.viewfinder")
                        }
                        .buttonStyle(.glass)
                        .fixedSize()
                        .disabled(state.isDetectingText || !app.canLookWithAI)
                        if state.isDetectingText {
                            ProgressView().controlSize(.small)
                            Text(L("Looking for text…")).helperTextStyle()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(L("Read by AI with your key. Type the new text next to each line."))
                            .helperTextStyle()
                            .fixedSize(horizontal: false, vertical: true)
                        PricePill(text: readingCost)
                    }
                }
                if let error {
                    Text(error).font(.callout).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if foundNoText, state.textEdits.isEmpty, state.source != nil {
                    RelatedToolHint(prompt: L("No text here. Did you mean…"),
                                    links: [app.relatedLink(.tool(.edit), image: state.source)])
                }
                ForEach($state.textEdits) { $edit in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(edit.original).fineTextStyle().lineLimit(2)
                        TextField(L("New text"), text: $edit.replacement)
                            .textFieldStyle(.roundedBorder)
                            .characterLimit($edit.replacement, 120)
                    }
                }
                Button(L("Add Line Manually"), systemImage: "plus") {
                    state.textEdits.append(TextEdit(original: "", replacement: ""))
                }
                .buttonStyle(.link)
                .font(.callout)
            }
        }
        .task(id: DetectionKey(size: state.source?.count, isEmpty: state.textEdits.isEmpty, canRead: app.canLookWithAI)) {
            if state.source != nil, state.textEdits.isEmpty, !state.isDetectingText, app.canLookWithAI { await detect() }
        }
    }

    private var readingCost: String {
        VideoCostLabel.price(AIChecks.estimate)
    }

    private func detect() async {
        state.isDetectingText = true
        defer { state.isDetectingText = false }
        while let source = state.source {
            error = nil
            foundNoText = false
            do {
                let lines = try await app.readText(in: source)
                guard state.source == source else { continue }
                state.textEdits = lines.map { TextEdit(original: $0, replacement: $0) }
                foundNoText = lines.isEmpty
            } catch {
                self.error = error.localizedDescription
            }
            return
        }
    }
}

struct OrbitControls: View {
    @Bindable var state: ComposerState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            OrbitGlobe(rotation: $state.orbitRotation, tilt: $state.orbitTilt)
                .frame(height: 170)
            Grid(alignment: .leading, verticalSpacing: 6) {
                GridRow {
                    Text(L("Rotation")).fineTextStyle().fixedSize()
                    Slider(value: $state.orbitRotation, in: -180...180, step: 5)
                    Text("\(Int(state.orbitRotation))°").font(.subheadline.monospacedDigit()).frame(width: 44, alignment: .trailing)
                }
                GridRow {
                    Text(L("Tilt")).fineTextStyle().fixedSize()
                    Slider(value: $state.orbitTilt, in: -60...80, step: 5)
                    Text("\(Int(state.orbitTilt))°").font(.subheadline.monospacedDigit()).frame(width: 44, alignment: .trailing)
                }
                GridRow {
                    Text(L("Zoom")).fineTextStyle().fixedSize()
                    Slider(value: $state.orbitZoom, in: 0.5...2.5, step: 0.1)
                    Text(String(format: "%.1f×", state.orbitZoom)).font(.subheadline.monospacedDigit()).frame(width: 44, alignment: .trailing)
                }
            }
        }
    }
}

struct OrbitGlobe: View {
    @Binding var rotation: Double
    @Binding var tilt: Double

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = size / 2 - 8
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let azimuth = rotation * .pi / 180
            let elevation = tilt * .pi / 180
            let camera = CGPoint(x: center.x + radius * sin(azimuth) * cos(elevation),
                                 y: center.y - radius * sin(elevation))
            let isBehind = cos(azimuth) < 0
            ZStack {
                Circle().fill(.quaternary.opacity(0.35))
                Circle().strokeBorder(.secondary.opacity(0.5))
                ForEach([-60.0, -30, 0, 30, 60], id: \.self) { latitude in
                    let y = radius * sin(latitude * .pi / 180)
                    let width = radius * cos(latitude * .pi / 180)
                    Ellipse()
                        .stroke(.secondary.opacity(0.25), lineWidth: 0.8)
                        .frame(width: width * 2, height: width * 0.5)
                        .position(x: center.x, y: center.y - y)
                }
                ForEach([0.0, 45, 90, 135], id: \.self) { longitude in
                    Ellipse()
                        .stroke(.secondary.opacity(0.25), lineWidth: 0.8)
                        .frame(width: abs(radius * 2 * cos(longitude * .pi / 180)) + 1, height: radius * 2)
                        .position(center)
                }
                Image(systemName: "person.fill")
                    .font(.system(size: radius * 0.45))
                    .foregroundStyle(.secondary)
                    .position(center)
                Path { path in
                    path.move(to: camera)
                    path.addLine(to: center)
                }
                .stroke(Color.appAccent.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                Image(systemName: "camera.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Circle().fill(Color.appAccent.opacity(isBehind ? 0.5 : 1)))
                    .position(camera)
            }
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let dx = (value.location.x - center.x) / radius
                let dy = (center.y - value.location.y) / radius
                tilt = min(max(asin(min(max(dy, -1), 1)) * 180 / .pi, -60), 80).rounded()
                let horizontal = min(max(dx / max(cos(tilt * .pi / 180), 0.2), -1), 1)
                let front = asin(horizontal) * 180 / .pi
                rotation = (isBehind ? (front >= 0 ? 180 - front : -180 - front) : front).rounded()
            })
            .help(L("Drag the camera around the subject"))
        }
    }
}

private extension View {
    func inspectorFieldLabel() -> some View { font(.subheadline.weight(.semibold)).foregroundStyle(.secondary) }
}

struct EmptySourceRow: View {
    let onPick: (Data) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                label
                Spacer(minLength: 4)
                button
            }
            VStack(alignment: .leading, spacing: 8) {
                label
                button
            }
        }
    }

    private var label: some View {
        Label(L("Not added yet — drop it in the middle"), systemImage: "arrow.left")
            .helperTextStyle()
            .fixedSize(horizontal: false, vertical: true)
    }

    private var button: some View {
        Button(L("Choose Photo…")) {
            if let data = ImageIntake.pick(multiple: false).first {
                withAnimation(Motion.standard) { onPick(data) }
            }
        }
        .buttonStyle(.glass)
        .controlSize(.regular)
        .fixedSize()
    }
}
