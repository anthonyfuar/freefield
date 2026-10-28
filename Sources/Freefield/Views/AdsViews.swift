import FreefieldCore
import SwiftUI

struct AdRunner: View {
    let tool: AdTool

    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedResultID: UUID?
    @State private var visibleHeight: CGFloat = 0

    private static let wellHeight: CGFloat = 190
    private static let columnWidth: CGFloat = VideoLayout.columnWidth
    private static let textWidth: CGFloat = VideoLayout.textWidth

    var body: some View {
        let state = app.adState(for: tool)
        let model = resolvedModel(state)
        let steps = Steps(tool: tool, state: state)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        if Examples.ad(tool.id) != nil {
                            CollapsibleExample(id: "ad.\(tool.id)",
                                               hasResults: !FeedModel(app: app, tool: .ad, appID: tool.id).isEmpty
                                                   || VideoExampleSizing.folds(visible: visibleHeight)) {
                                AdExample(tool: tool, state: state, rowHeight: AdExample.rowHeight(visible: visibleHeight))
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        inputs(state, model: model, steps: steps)
                            .frame(maxWidth: Self.textWidth, alignment: .leading)
                        extraInstruction(state, model: model)
                            .frame(maxWidth: Self.textWidth, alignment: .leading)
                        RelatedToolHint(links: hints(state))
                    }
                    if tool.copyFirst {
                        copy(state, model: model, step: steps.copy)
                        options(state, step: steps.style, isDone: inputsDone(state))
                    } else {
                        options(state, step: steps.style, isDone: inputsDone(state))
                        copy(state, model: model, step: steps.copy)
                    }
                    if tool.usesBrand {
                        VStack(alignment: .leading, spacing: 0) {
                            ExtrasHeader(topPadding: 0)
                            AdBrandSection(state: state, tool: tool)
                        }
                    }
                    ResultsGrid(tool: .ad, appID: tool.id, selectedID: $selectedResultID)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("results")
                }
                .padding(24)
                .frame(maxWidth: Self.columnWidth + 48, alignment: .leading)
            }
            .onVisibleHeightChange { visibleHeight = $0 }
            .pinnedActionBar(maxWidth: Self.columnWidth) { actionBar(state, model: model, proxy: proxy) }
        }
        .navigationTitle(tool.name)
    }

    private var family: String {
        NavCatalog.families.first { $0.items.contains(.ad(tool.id)) }?.id ?? "ads"
    }

    private func inputsDone(_ state: AdState) -> Bool {
        switch tool.kind {
        case .batch: !app.batchProducts(state).isEmpty
        case .resize, .translate: state.reference != nil
        case .multiply: state.reference != nil && app.adSwapReady(tool, state: state)
        case .single, .headlines: (!tool.needsReference || state.reference != nil) && app.adHasProduct(state)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            FamilyStyle.tile(symbol: tool.symbol, family: family, side: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(tool.name).toolTitleStyle()
                Text(tool.subtitle).foregroundStyle(.secondary)
                if let whenToUse = tool.whenToUse {
                    Label(whenToUse, systemImage: "lightbulb")
                        .helperTextStyle()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func hints(_ state: AdState) -> [RelatedToolHint.Link] {
        let productID = app.library.product(state.productID)?.id
        switch tool.id {
        case "product-shoot":
            return [
                RelatedToolHint.Link(title: Tool.product.title) {
                    if let productID { app.composer(for: .product).productID = productID }
                    app.selection = .tool(.product)
                },
                RelatedToolHint.Link(title: L("Product Effects")) { app.selection = .productEffects },
            ]
        case "ugc-photo":
            return [RelatedToolHint.Link(title: L("Video: person recommending it")) { openVideoAd("UGC talking", productID: productID) }]
        case "before-after":
            return [RelatedToolHint.Link(title: L("Video: before and after")) { openVideoAd("Before and after", productID: productID) }]
        case "model-shoot":
            return [RelatedToolHint.Link(title: Tool.outfitSwap.title) { app.open(.outfitSwap) }]
        default:
            return []
        }
    }

    private func openVideoAd(_ mode: String, productID: UUID?) {
        guard let video = VideoCatalog.tool("videoAd") else { return }
        let videoState = app.videoState(for: video)
        videoState.choices["mode"] = mode
        videoState.modelID = nil
        if let productID { videoState.productID = productID }
        app.openVideo(video.id)
    }

    private struct Steps {
        var swap: Int?
        var reference: Int?
        var product: Int?
        var person: Int?
        var copy: Int?
        var style: Int?

        init(tool: AdTool, state: AdState) {
            var next = 0
            func take() -> Int { next += 1; return next }
            if !tool.inputGroups.isEmpty { swap = take() }
            if tool.needsReference { reference = take() }
            if tool.takesProduct || [.batch, .multiply].contains(tool.kind) { product = take() }
            if tool.usesPerson { person = take() }
            let hasCopy = [tool.text, tool.text2].contains { field in
                guard let field, field.role == .copy else { return false }
                return state.isOn(field.appliesWhen, in: tool) || field.appliesWhen?.typingTurnsOn == true
            }
            let hasStyle = !tool.options.isEmpty
            if tool.copyFirst {
                if hasCopy { copy = take() }
                if hasStyle { style = take() }
            } else {
                if hasStyle { style = take() }
                if hasCopy { copy = take() }
            }
        }
    }

    @ViewBuilder private func inputs(_ state: AdState, model: ImageModel?, steps: Steps) -> some View {
        switch tool.kind {
        case .batch:
            PanelSection(title: L("Your products"), step: steps.product, isDone: !app.batchProducts(state).isEmpty) {
                AdBatchProducts(state: state)
            }
        case .resize, .translate:
            referencePanel(state, steps: steps)
        case .multiply:
            VStack(alignment: .leading, spacing: Spacing.m) {
                swapChoice(state, steps: steps)
                OptionGrid(columns: 2, minimum: 300, spacing: 14, stretchesLastRow: true) {
                    referencePanel(state, steps: steps)
                    swapPanel(state, steps: steps)
                }
            }
        case .single, .headlines:
            standardInputs(state, model: model, steps: steps)
        }
    }

    private func referencePanel(_ state: AdState, steps: Steps) -> some View {
        @Bindable var state = state
        return PanelSection(title: tool.referenceTitle, step: steps.reference, isDone: state.reference != nil) {
            ImageWell(title: tool.referenceTitle, subtitle: tool.referenceHint,
                      systemImage: "rectangle.on.rectangle", data: $state.reference, minHeight: 150, sources: [.library],
                      isInPanel: true)
                .wellFrame(Self.wellHeight)
        }
        .frame(maxWidth: .infinity)
    }

    private func swapChoice(_ state: AdState, steps: Steps) -> some View {
        PanelSection(title: tool.options[0].title, step: steps.swap,
                     isDone: state.pickedGroups.contains(0) || state.reference != nil) {
            singleGroup(0, state: state, showsTitle: false)
        }
    }

    private func swapPanel(_ state: AdState, steps: Steps) -> some View {
        @Bindable var state = state
        let swap = state.choice(0, in: tool)
        return PanelSection(title: L("What goes in"), step: steps.product, isDone: app.adSwapReady(tool, state: state)) {
            VStack(alignment: .leading, spacing: 12) {
                switch swap {
                case "Product":
                    AdProductPicker(state: state, tool: tool, wellHeight: Self.wellHeight)
                case "Person":
                    CharacterMenu(selection: $state.characterID, placeholder: L("Choose a saved character…"))
                    if app.library.character(state.characterID) == nil {
                        ImageWell(title: L("Person photo"), subtitle: L("A clear photo of the face"),
                                  systemImage: "person.crop.square", data: $state.personPhoto, minHeight: 150, sources: [.library],
                                  isInPanel: true)
                            .wellFrame(Self.wellHeight)
                    }
                case "Location":
                    ImageWell(title: L("Location photo"), subtitle: L("Optional if you describe the place in your instructions"),
                              systemImage: "mountain.2", data: $state.swapPhoto, minHeight: 150, sources: [.library], isInPanel: true)
                        .wellFrame(Self.wellHeight)
                default:
                    ImageWell(title: L("Outfit photo"), subtitle: L("The clothes, worn or laid flat"),
                              systemImage: "tshirt", data: $state.swapPhoto, minHeight: 150, sources: [.library], isInPanel: true)
                        .wellFrame(Self.wellHeight)
                }
            }
            .animation(Motion.standard, value: swap)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func standardInputs(_ state: AdState, model: ImageModel?, steps: Steps) -> some View {
        if tool.needsReference || tool.usesPerson {
            let three = tool.needsReference && tool.usesPerson
            OptionGrid(columns: three ? nil : 2, minimum: three ? 220 : 300, spacing: 14, stretchesLastRow: true) {
                inputPanels(state, model: model, steps: steps)
            }
        } else {
            inputPanels(state, model: model, steps: steps)
        }
    }

    @ViewBuilder private func inputPanels(_ state: AdState, model: ImageModel?, steps: Steps) -> some View {
        @Bindable var state = state
        if tool.needsReference {
            PanelSection(title: tool.referenceTitle, step: steps.reference, isDone: state.reference != nil) {
                ImageWell(title: tool.referenceTitle, subtitle: tool.referenceHint,
                          systemImage: "rectangle.on.rectangle", data: $state.reference, minHeight: 150, sources: [.library],
                          isInPanel: true)
                    .wellFrame(Self.wellHeight)
            }
            .frame(maxWidth: .infinity)
        }
        PanelSection(title: L("Your product"), step: steps.product, isDone: app.adHasProduct(state)) {
            AdProductPicker(state: state, tool: tool, wellHeight: Self.wellHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if tool.usesPerson {
            PanelSection(title: L("Person"), step: steps.person,
                         isDone: app.library.character(state.characterID) != nil || state.personPhoto != nil, isOptional: true) {
                person(state, model: model, steps: steps)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private func person(_ state: AdState, model: ImageModel?, steps: Steps) -> some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 8) {
            CharacterMenu(selection: $state.characterID, placeholder: L("Choose a saved character…"))
            if app.library.character(state.characterID) == nil {
                ImageWell(title: L("Person photo"), subtitle: personHint(state, steps: steps),
                          systemImage: "person.crop.square", data: $state.personPhoto, minHeight: 150, sources: [.library],
                          isInPanel: true)
                    .wellFrame(Self.wellHeight)
            }
            if let field = tool.text, field.role == .person {
                modelDescription(field, state: state, model: model)
            }
        }
    }

    private func personHint(_ state: AdState, steps: Steps) -> String {
        guard let condition = tool.personWhen, !state.isOn(condition, in: tool), let step = steps.style else {
            return tool.personHint
        }
        return L("Only needed if you pick %@ in step %ld", choiceNames(condition), step)
    }

    private func modelDescription(_ field: AdTextField, state: AdState, model: ImageModel?) -> some View {
        @Bindable var state = state
        return VStack(alignment: .leading, spacing: 4) {
            Text(field.title).groupTitleStyle()
            TextField(field.placeholder, text: $state.text, axis: .vertical)
                .lineLimit(1...3)
                .inputBox()
                .characterLimit($state.text, copyLimits(state, model: model).text, clampsWhenLimitDrops: false)
            Text(L("With a character or photo, this only fine-tunes the look."))
                .helperTextStyle()
        }
        .padding(.top, 4)
    }

    @ViewBuilder private func options(_ state: AdState, step: Int?, isDone: Bool) -> some View {
        if !tool.options.isEmpty {
            let main = tool.groupOrder.filter { !tool.foldedGroups.contains($0) }
            let folded = tool.groupOrder.filter { tool.foldedGroups.contains($0) && state.isOn(tool.options[$0].appliesWhen, in: tool) }
            PanelSection(title: L("How it looks"), step: step, isDone: isDone) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(main, id: \.self) { index in
                        optionGroup(index, state: state)
                    }
                    if !folded.isEmpty {
                        let changed = folded.filter { state.choice($0, in: tool) != (tool.example[$0] ?? tool.options[$0].values.first) }
                        OptionalSection(L("More style options"), systemImage: "slider.horizontal.3",
                                        summary: folded.map { tool.options[$0].shortLabel(state.choice($0, in: tool)) }.joined(separator: " · "),
                                        isFilled: !changed.isEmpty, storageKey: "ad.\(tool.id).more") {
                            ForEach(folded, id: \.self) { index in
                                optionGroup(index, state: state)
                            }
                        }
                    }
                }
                .animation(Motion.standard, value: tool.options.indices.map { state.choice($0, in: tool) + state.picks($0, in: tool).joined() })
            }
        }
    }

    @ViewBuilder private func optionGroup(_ index: Int, state: AdState) -> some View {
        let group = tool.options[index]
        if state.isOn(group.appliesWhen, in: tool) {
            shownGroup(index, state: state)
                .transition(Motion.transition(.opacity.combined(with: .move(edge: .top))))
        } else if let note = group.appliesWhen?.note {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.title).groupTitleStyle()
                Label(note, systemImage: "info.circle").helperTextStyle()
            }
            .transition(.opacity)
        }
    }

    static func pictures(_ tool: AdTool, group: AdOptionGroup) -> [String: OptionPicture]? {
        if let source = tool.picturesFrom {
            let title = group.pictureTitle ?? english(group.title)
            if let found = OptionImages.pictures(family: "ads/\(source)", values: group.values, key: { "\(title) \($0)" }) { return found }
        }
        return OptionImages.pictures(adTool: tool.id, group: group)
    }

    private func manyGroup(_ index: Int, state: AdState) -> some View {
        let group = tool.options[index]
        let picked = state.picks(index, in: tool)
        let toggle: (String) -> Void = { value in
            withAnimation(Motion.select) { state.toggle(value, in: index, of: tool) }
        }
        let pictures = Self.pictures(tool, group: group)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.title).groupTitleStyle()
                Text(L("Pick one or more")).fineTextStyle()
            }
            switch group.style {
            case .tiles:
                AdTileGrid(count: group.values.count) {
                    ForEach(group.values, id: \.self) { value in
                        OptionTile(title: group.label(value), systemImage: Self.pictureFallbackSymbol(value), picture: pictures?[value],
                                   isSelected: picked.contains(value), isMultiSelect: true) { toggle(value) }
                    }
                }
            default:
                ChoiceChips(values: group.values, label: group.label, symbol: Self.pictureFallbackSymbol, pictures: pictures,
                            isSelected: { picked.contains($0) }, onSelect: toggle)
            }
        }
    }

    @ViewBuilder private func shownGroup(_ index: Int, state: AdState) -> some View {
        if tool.options[index].allowsMany {
            manyGroup(index, state: state)
        } else {
            singleGroup(index, state: state)
        }
    }

    private func singleGroup(_ index: Int, state: AdState, showsTitle: Bool = true) -> some View {
        let group = tool.options[index]
        let selection = state.choice(index, in: tool)
        let select: (String) -> Void = { value in
            state.choices[index] = value
            state.pickedGroups.insert(index)
        }
        let pictures = Self.pictures(tool, group: group)
        return VStack(alignment: .leading, spacing: 8) {
            if showsTitle {
                subtitle(group.title, note: nil)
            }
            Group {
                switch group.style {
                case .tiles where pictures != nil:
                    AdTileGrid(count: group.values.count) {
                        ForEach(group.values, id: \.self) { value in
                            OptionTile(title: group.label(value), systemImage: Self.pictureFallbackSymbol(value), picture: pictures?[value],
                                       isSelected: selection == value) { select(value) }
                        }
                    }
                case .segmented where pictures != nil, .chips where pictures != nil:
                    ChoiceChips(values: group.values, label: group.label, symbol: Self.pictureFallbackSymbol, pictures: pictures,
                                isSelected: { $0 == selection }, onSelect: select)
                case .tiles:
                    AdTileGrid(count: group.values.count) {
                        ForEach(group.values, id: \.self) { value in
                            OptionTile(title: group.label(value), isSelected: selection == value) { select(value) }
                        }
                    }
                case .segmented:
                    HStack(spacing: 12) {
                        Picker(group.title, selection: Binding(get: { state.choice(index, in: tool) }, set: { select($0) })) {
                            ForEach(group.values, id: \.self) { value in
                                Text(group.shortLabel(value)).tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        if tool.isCarousel, index == 1 {
                            Text(L("%ld images, one per slide", Int(selection) ?? 5))
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                case .chips:
                    ChoiceChips(values: group.values, label: group.label, isSelected: { $0 == selection }, onSelect: select)
                }
            }
            if tool.makesFullSet(selection), index == 0 {
                Text(L("One image of each: main image, callouts, angles, a close-up and a lifestyle photo."))
                    .helperTextStyle()
            }
        }
    }

    private static func pictureFallbackSymbol(_ value: String) -> String? {
        switch value {
        case "None": "circle.slash"
        case AdTool.fullSetValue: "square.grid.3x2"
        case "9:16": "rectangle.portrait"
        case "4:5": "rectangle.portrait"
        case "1:1": "square"
        case "16:9": "rectangle"
        default: nil
        }
    }

    private func subtitle(_ title: String, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).groupTitleStyle()
            if let note {
                Label(note, systemImage: "info.circle").helperTextStyle()
            }
        }
    }

    private func note(_ condition: AdCondition) -> String {
        if let note = condition.note { return note }
        if condition.typingTurnsOn, let first = condition.values.first {
            return L("Typing here picks %@.", L("“%@”", tool.options[condition.group].shortLabel(first)))
        }
        let list = choiceNames(condition)
        return condition.excluding ? L("Not used with %@.", list) : L("Only used with %@.", list)
    }

    private func choiceNames(_ condition: AdCondition) -> String {
        let group = tool.options[condition.group]
        return condition.values.map { L("“%@”", group.shortLabel($0)) }.joined(separator: L(" or "))
    }

    private func copyLimits(_ state: AdState, model: ImageModel?) -> (text: Int, line: Int, text2: Int) {
        let overhead = app.adPromptOverhead(tool, state: state)
        let onePerLine = tool.text?.onePerLine == true
        let text = state.usedText(in: tool)
        let longestText = onePerLine
            ? AppModel.lines(text).map(\.utf16.count).max() ?? 0
            : text.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count
        let text2Length = state.usedText2(in: tool).trimmingCharacters(in: .whitespacesAndNewlines).utf16.count
        let line = PromptBudget.userLimit(model: model, overhead: overhead + text2Length)
        let text2 = min(PromptBudget.userLimit(model: model, overhead: overhead + longestText), 400)
        return (onePerLine ? min(line * 4, 1200) : line, line, text2)
    }

    private func copyIsTooLong(_ state: AdState, model: ImageModel?) -> Bool {
        let limits = copyLimits(state, model: model)
        let text = state.usedText(in: tool)
        if text.utf16.count > limits.text || state.usedText2(in: tool).utf16.count > limits.text2 { return true }
        return tool.text?.onePerLine == true && AppModel.lines(text).contains { $0.utf16.count > limits.line }
    }

    @ViewBuilder private func copy(_ state: AdState, model: ImageModel?, step: Int?) -> some View {
        @Bindable var state = state
        let limits = copyLimits(state, model: model)
        if let step {
            PanelSection(title: ["marketplace", "hook-frame"].contains(tool.id) ? L("Text in the image") : L("Text in the ad"),
                         trailing: AnyView(printedBadge), step: step, isDone: copyTyped(state), isOptional: !copyRequired(state)) {
                VStack(alignment: .leading, spacing: 16) {
                    if let field = tool.text, field.role == .copy {
                        copyField(field, text: $state.text, limit: limits.text, lineLimit: limits.line,
                                  lines: field.onePerLine ? 3...8 : 2...4, state: state)
                    }
                    if let field = tool.text2, field.role == .copy {
                        copyField(field, text: $state.text2, limit: limits.text2, lineLimit: limits.text2,
                                  lines: field.pipeSeparated ? 2...6 : 1...3, state: state)
                    }
                    Text(L("Written in the image exactly as you type it, in your language."))
                        .helperTextStyle()
                }
            }
            .frame(maxWidth: tool.isCarousel ? .infinity : Self.textWidth, alignment: .leading)
        }
    }

    private func copyFields(_ state: AdState) -> [(field: AdTextField, text: String)] {
        [(tool.text, state.usedText(in: tool)), (tool.text2, state.usedText2(in: tool))].compactMap { field, text in
            guard let field, field.role == .copy else { return nil }
            return (field, text)
        }
    }

    private func copyTyped(_ state: AdState) -> Bool {
        copyFields(state).contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func copyRequired(_ state: AdState) -> Bool {
        copyFields(state).contains { $0.field.requiredReason != nil }
    }

    private var printedBadge: AnyView {
        AnyView(
            Label(L("Written in the image"), systemImage: "textformat")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: .capsule)
                .fixedSize()
        )
    }

    @ViewBuilder private func copyField(_ field: AdTextField, text: Binding<String>, limit: Int, lineLimit: Int,
                                        lines: ClosedRange<Int>, state: AdState) -> some View {
        let condition = field.appliesWhen
        let isOn = state.isOn(condition, in: tool)
        if isOn || condition?.typingTurnsOn == true {
            shownCopyField(field, text: text, limit: limit, lineLimit: lineLimit, lines: lines, state: state, isOn: isOn)
                .transition(Motion.transition(.opacity.combined(with: .move(edge: .top))))
        }
    }

    private func shownCopyField(_ field: AdTextField, text: Binding<String>, limit: Int, lineLimit: Int,
                                lines: ClosedRange<Int>, state: AdState, isOn: Bool) -> some View {
        let condition = field.appliesWhen
        return VStack(alignment: .leading, spacing: 6) {
            if tool.kind == .headlines, field == tool.text {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        subtitle(field.title, note: isOn ? nil : condition.map(note))
                        Spacer(minLength: 0)
                        HeadlineWriter(tool: tool, state: state, text: text)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        subtitle(field.title, note: isOn ? nil : condition.map(note))
                        HeadlineWriter(tool: tool, state: state, text: text)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    subtitle(field.title, note: isOn ? nil : condition.map(note))
                    Spacer(minLength: 0)
                    if AppModel.suggestsCopy(tool, field: field) {
                        AdCopySuggestions(tool: tool, field: field, state: state, text: text)
                    }
                }
            }
            Group {
                if tool.isCarousel, field == tool.text {
                    slideCaptions(text: text, limit: limit, state: state)
                } else if !field.parts.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(field.parts.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(field.parts[index]).fineTextStyle()
                                pieceField(text: text, index: index, count: field.parts.count,
                                           placeholder: L("Empty: no label"), limit: limit)
                            }
                        }
                    }
                } else {
                    TextField(field.placeholders[state.choice(0, in: tool)] ?? field.placeholder, text: text, axis: .vertical)
                        .lineLimit(lines)
                        .inputBox()
                        .characterLimit(text, limit, clampsWhenLimitDrops: false)
                        .onChange(of: text.wrappedValue) { oldValue, newValue in
                            if field.onePerLine {
                                let capped = Self.capLines(newValue, to: lineLimit, keeping: oldValue)
                                if capped != newValue { text.wrappedValue = capped }
                            }
                            if let condition, condition.typingTurnsOn, !newValue.isEmpty,
                               !state.isOn(condition, in: tool), let value = condition.values.first {
                                state.choices[condition.group] = value
                            }
                        }
                }
            }
            if let caption = field.caption {
                Text(caption).helperTextStyle()
            }
        }
    }

    private func slideCaptions(text: Binding<String>, limit: Int, state: AdState) -> some View {
        let count = Int(state.choice(1, in: tool)) ?? 5
        let names = AppModel.carouselSlideNames(story: state.choice(0, in: tool), count: count)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(0..<count, id: \.self) { index in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "\(index + 1) · \(index < names.count ? names[index] : "")")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    pieceField(text: text, index: index, count: count, placeholder: L("No caption on this slide"), limit: limit)
                }
            }
        }
    }

    private func pieceField(text: Binding<String>, index: Int, count: Int, placeholder: String, limit: Int) -> some View {
        let piece = Binding(get: { Self.pieces(text.wrappedValue, count: count)[index] },
                            set: { text.wrappedValue = Self.replacingPiece(index, with: $0, in: text.wrappedValue, count: count) })
        let others = text.wrappedValue.utf16.count - piece.wrappedValue.utf16.count
        return TextField(placeholder, text: piece)
            .textFieldStyle(.roundedBorder)
            .characterLimit(piece, max(0, limit - others), clampsWhenLimitDrops: false)
    }

    static func pieces(_ text: String, count: Int) -> [String] {
        let parts = text.isEmpty ? [] : text.components(separatedBy: "|")
        var pieces = parts.indices.map { index in
            var piece = parts[index]
            if index > 0, piece.hasPrefix(" ") { piece.removeFirst() }
            if index < parts.count - 1, piece.hasSuffix(" ") { piece.removeLast() }
            return piece
        }
        while pieces.count < count { pieces.append("") }
        return pieces
    }

    static func replacingPiece(_ index: Int, with value: String, in text: String, count: Int) -> String {
        var pieces = Self.pieces(text, count: count)
        pieces[index] = value.replacingOccurrences(of: "|", with: "").replacingOccurrences(of: "\n", with: " ")
        if pieces.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { return "" }
        return pieces.joined(separator: " | ")
    }

    private static func capLines(_ text: String, to limit: Int, keeping old: String) -> String {
        let unchanged = Set(old.split(whereSeparator: \.isNewline))
        return text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { unchanged.contains($0) ? String($0) : CharacterLimit.clamp(String($0), to: limit) }
            .joined(separator: "\n")
    }

    @ViewBuilder private func extraInstruction(_ state: AdState, model: ImageModel?) -> some View {
        @Bindable var state = state
        let caption = L("It guides the image and is never written in it.")
        if let field = tool.directionField {
            if tool.text == field {
                ExtraInstructionField(text: $state.text, placeholder: field.placeholder, caption: caption,
                                      limit: copyLimits(state, model: model).text)
            } else {
                let limit = min(PromptBudget.userLimit(model: model, overhead: app.adPromptOverhead(tool, state: state)), 400)
                ExtraInstructionField(text: $state.text2, placeholder: field.placeholder, caption: caption, limit: limit)
            }
        } else {
            let overhead = app.adPromptOverhead(tool, state: state, includingExtra: false) + AppModel.adExtraLead.utf16.count
            ExtraInstructionField(text: $state.extra, placeholder: tool.extraHint, caption: caption,
                                  limit: min(PromptBudget.userLimit(model: model, overhead: overhead), 1000))
        }
    }

    private func actionBar(_ state: AdState, model: ImageModel?, proxy: ScrollViewProxy) -> some View {
        @Bindable var state = state
        let images = app.adImageCount(tool, state: state)
        let reason = disabledReason(state, model)
        let lines = tool.text?.onePerLine == true ? AppModel.lines(state.usedText(in: tool)).count : 0
        let showsCount = !tool.isCarousel && !(tool.isUnboxing && state.choice(2, in: tool) == "3-photo sequence")
            && !tool.makesFullSet(state.choice(0, in: tool)) && !tool.makesSeveral
        let cost = images == 0 ? nil : app.estimatedCost(model: model, count: images, resolution: .oneK).map { $0 + app.adHelperCost(tool, state: state) }
        return VStack(alignment: .trailing, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                FlowLayout(spacing: 8) {
                    if let model, !model.aspectRatios.isEmpty, tool.kind != .batch, tool.kind != .resize {
                        AspectRatioMenu(selection: $state.aspect, available: model.aspectRatios)
                    }
                    if showsCount {
                        CountMenu(count: $state.count, maximum: 4)
                    }
                    MoreOptionsChip(summary: model.map { modelSummary($0, state: state) }, help: modelHelp(model, state: state)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("AI model")).groupTitleStyle()
                            ModelPicker(selectionID: $state.modelID, current: model, requirement: requirement(state))
                            Text(L("Auto picks the model this tool's example was made with."))
                                .helperTextStyle()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 4) {
                    if tool.kind == .batch {
                        Text(batchSummary(state, images: images))
                            .fineTextStyle()
                            .fixedSize()
                    } else if tool.kind == .headlines {
                        let planned = lines > 0 ? images : state.headlineCount * state.count
                        Text(planned == 1 ? L("1 ad will be made") : L("%ld ads will be made", planned))
                            .fineTextStyle()
                            .fixedSize()
                    } else if lines > 1 {
                        Text(L("%ld lines × %ld = %ld images", lines, state.count, images))
                            .fineTextStyle()
                            .fixedSize()
                    }
                    GenerateButton(title: tool.kind == .batch && images > 1 ? L("Generate %ld ads", images)
                                       : images > 1 ? L("Generate %ld images", images) : L("Generate"),
                                   isEnabled: reason == nil && !state.isPreparing, disabledReason: reason,
                                   estimatedCost: cost, isWorking: state.isPreparing) {
                        generate(state, model: model, proxy: proxy)
                    }
                }
            }
            DisabledReasonLabel(reason: reason)
            if state.isPreparing {
                Label(L("Writing the text for each ad…"), systemImage: "wand.and.sparkles")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            } else if tool.kind == .batch, reason == nil, app.adWritesCopy(tool, state: state) {
                Text(L("Includes the AI text for each product. Check every claim before you publish."))
                    .fineTextStyle()
            }
            if reason == nil, let warning = warning(state) {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : Motion.standard, value: reason)
    }

    private func batchSummary(_ state: AdState, images: Int) -> String {
        let products = app.batchProducts(state).count
        let angles = state.picks(1, in: tool).count
        let sizes = state.picks(2, in: tool).count
        return [products == 1 ? L("1 product") : L("%ld products", products),
                angles == 1 ? L("1 angle") : L("%ld angles", angles),
                sizes == 1 ? L("1 size") : L("%ld sizes", sizes)].joined(separator: " · ")
            + " → " + (images == 1 ? L("1 ad") : L("%ld ads", images))
    }

    private func modelSummary(_ model: ImageModel, state: AdState) -> String {
        state.modelID == nil ? L("Auto") : app.catalog.choice(for: model).displayName
    }

    private func modelHelp(_ model: ImageModel?, state: AdState) -> String {
        guard let model, state.modelID == nil else { return L("AI model") }
        return L("Auto · %@", app.catalog.choice(for: model).displayName)
    }

    private func warning(_ state: AdState) -> String? {
        guard tool.id == "static-ad",
              state.usedText(in: tool).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              state.usedText2(in: tool).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return L("No text: the ad will come out without a headline.")
    }

    private func generate(_ state: AdState, model: ImageModel?, proxy: ScrollViewProxy) {
        guard let model else { return }
        let latest = app.engine.jobs.first?.id
        app.runAd(tool, state: state, model: model)
        guard app.engine.jobs.first?.id != latest else { return }
        Task { @MainActor in
            withAnimation(reduceMotion ? nil : Motion.emphasized) { proxy.scrollTo("results", anchor: .top) }
        }
    }

    private func swapUsesImage(_ state: AdState) -> Bool {
        state.choice(0, in: tool) != "Location" || state.swapPhoto != nil
    }

    private func neededImages(_ state: AdState) -> Int {
        switch tool.kind {
        case .resize, .translate: 1
        case .multiply: swapUsesImage(state) ? 2 : 1
        case .batch: 1
        case .single, .headlines: tool.needsReference ? 2 : 1
        }
    }

    private func requirement(_ state: AdState) -> ModelRequirement {
        var count: Int
        switch tool.kind {
        case .resize, .translate, .multiply: count = neededImages(state)
        case .batch: count = app.batchProducts(state).isEmpty ? 0 : 1
        case .single, .headlines:
            count = app.adHasProduct(state) ? 1 : 0
            if tool.needsReference { count += 1 }
        }
        let minimum = tool.kind == .single || tool.kind == .headlines ? (tool.needsReference ? 2 : 0) : neededImages(state)
        return ModelRequirement(images: max(1, count), minimumImages: tool.kind == .batch ? 0 : minimum,
                                promptLength: app.adPromptOverhead(tool, state: state))
    }

    private func resolvedModel(_ state: AdState) -> ImageModel? {
        let (featured, others) = app.choices(for: requirement(state))
        if let id = state.modelID, let match = (featured + others).first(where: { $0.model.id == id }) { return match.model }
        for lineupID in [tool.model] + Lineup.defaultModelIDs(for: .ad) {
            if let match = featured.first(where: { $0.lineup?.id == lineupID && !app.catalog.strained.contains($0.model.id) }) {
                return match.model
            }
        }
        return featured.first?.model
    }

    static let batchLimit = 20

    private func swapMissing(_ state: AdState) -> String {
        switch state.choice(0, in: tool) {
        case "Product": L("Choose a product")
        case "Person": L("Choose a character or add a person photo")
        case "Location": L("Add a location photo or describe the place")
        default: L("Add the outfit photo")
        }
    }

    private func disabledReason(_ state: AdState, _ model: ImageModel?) -> String? {
        if !app.hasAnyKey { return Self.nextStep(L("Add an API key in Settings")) }
        if tool.needsReference, state.reference == nil { return Self.nextStep(tool.referenceMissing) }
        switch tool.kind {
        case .batch:
            if app.batchProducts(state).isEmpty { return Self.nextStep(L("Choose at least one product")) }
        case .multiply:
            if !app.adSwapReady(tool, state: state) { return Self.nextStep(swapMissing(state)) }
        case .resize, .translate:
            break
        case .single, .headlines:
            if !app.adHasProduct(state) { return Self.nextStep(L("Choose a product")) }
        }
        for index in tool.options.indices where tool.options[index].allowsMany && state.picks(index, in: tool).isEmpty {
            return Self.nextStep(L("Pick at least one in “%@”", tool.options[index].title))
        }
        if tool.kind == .batch {
            let total = app.adImageCount(tool, state: state)
            if total > Self.batchLimit { return L("That's %ld ads. Pick fewer: one run makes up to %ld.", total, Self.batchLimit) }
            if app.adWritesCopy(tool, state: state), app.helperModel == nil { return L("No text model is available for the AI assistant.") }
        }
        if tool.kind == .headlines, AppModel.lines(state.usedText(in: tool)).count == 1 {
            return Self.nextStep(L("Add a second headline to compare"))
        }
        if let reason = tool.text?.requiredReason, state.usedText(in: tool).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Self.nextStep(reason)
        }
        if let reason = tool.text2?.requiredReason, state.usedText2(in: tool).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Self.nextStep(reason)
        }
        guard let model else { return L("No compatible model available") }
        if model.maxReferences < neededImages(state) {
            return tool.kind == .multiply ? L("This model can't take both the ad and what goes in")
                : L("This model can't take both the reference ad and the product")
        }
        if copyIsTooLong(state, model: model) { return Self.nextStep(L("Shorten the text to fit the selected model")) }
        return nil
    }

    private static func nextStep(_ reason: String) -> String {
        DisabledReasonLabel.nextStep(reason.prefix(1).lowercased() + reason.dropFirst())
    }
}

extension AdOptionGroup {
    func label(_ value: String) -> String { labels[value] ?? L(value) }

    func shortLabel(_ value: String) -> String {
        let name = label(value)
        guard name.hasSuffix(")"), let open = name.range(of: " (") else { return OptionTile.capitalized(name) }
        return OptionTile.capitalized(String(name[..<open.lowerBound]))
    }
}

struct AdProductPicker: View {
    @Bindable var state: AdState
    var tool: AdTool?
    var wellHeight: CGFloat = 190
    @Environment(AppModel.self) private var app
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 8) {
                ProductMenu(selection: $state.productID, placeholder: L("Choose a saved product…"))
                Button(L("Import from Link…"), systemImage: "link") { importing = true }
                    .buttonStyle(.glass)
                    .fixedSize()
            }
            if let product = app.library.product(state.productID) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(product.photoFileNames.prefix(4), id: \.self) { name in
                            ThumbnailImage(url: app.library.productPhotoURL(name), maxPixel: 300, contentMode: .fit)
                                .frame(width: 96, height: 96)
                                .background(.white.opacity(0.92), in: .rect(cornerRadius: Radius.tile))
                                .clipShape(.rect(cornerRadius: Radius.tile))
                        }
                    }
                }
                .scrollIndicators(.never)
                .fixedSize(horizontal: false, vertical: true)
                Text(L("Up to 3 photos are sent so its label and shape stay exact."))
                    .helperTextStyle()
            } else {
                ImageWell(title: L("Product photo"), subtitle: L("Drop a photo here"),
                          systemImage: "shippingbox", data: $state.productPhoto, minHeight: 150, sources: [.library],
                          isInPanel: true)
                    .wellFrame(wellHeight)
            }
        }
        .sheet(isPresented: $importing) {
            NewProductSheet { product in state.productID = product.id }
        }
        .onChange(of: state.productID, initial: true) { _, id in
            app.rememberProduct(id)
            if let tool { app.applyProductDefaults(tool, state: state) }
        }
    }
}

struct AdCopySuggestions: View {
    let tool: AdTool
    let field: AdTextField
    let state: AdState
    @Binding var text: String

    @Environment(AppModel.self) private var app
    @State private var isPresented = false
    @State private var isWorking = false
    @State private var options: [String] = []
    @State private var problem: String?

    var body: some View {
        Button {
            isPresented = true
            if options.isEmpty, !isWorking { suggest() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.sparkles")
                Text(L("Suggest with AI"))
                PricePill(text: GenerateButton.format(AppModel.helperEstimate))
            }
        }
        .buttonStyle(.glass)
        .fixedSize()
        .disabled(reason != nil)
        .help(reason ?? L("The AI writes a few options from your product's name and details; you pick one."))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) { popover }
    }

    private var reason: String? {
        if !app.hasAnyKey { return L("Add an API key in Settings") }
        if app.helperModel == nil { return L("No text model is available for the AI assistant.") }
        if !app.adHasProduct(state) { return L("Choose a product first.") }
        return nil
    }

    private var popover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Suggestions for “%@”", field.title.components(separatedBy: " (").first ?? field.title)).font(.headline)
            if isWorking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("Writing options…")).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            } else if let problem {
                Text(problem).font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(field.onePerLine ? L("Click one to add it as a line; each line makes its own ad.") : L("Click one to use it."))
                    .helperTextStyle()
                ForEach(options, id: \.self) { option in
                    Button { use(option) } label: {
                        Text(display(option))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: Radius.thumb))
                            .contentShape(.rect(cornerRadius: Radius.thumb))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            HStack {
                Text(L("Check that every claim is true before you publish."))
                    .helperTextStyle()
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button { suggest() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text(L("Other ideas"))
                        PricePill(text: GenerateButton.format(AppModel.helperEstimate))
                    }
                }
                .buttonStyle(.glass)
                .fixedSize()
                .disabled(isWorking || reason != nil)
            }
        }
        .padding(16)
        .frame(width: 420, alignment: .leading)
    }

    private func display(_ option: String) -> String {
        Self.pieces(option).joined(separator: " · ")
    }

    private static func pieces(_ option: String) -> [String] {
        option.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func suggest() {
        isWorking = true
        problem = nil
        Task {
            defer { isWorking = false }
            do {
                let found = try await app.suggestAdCopy(tool, field: field, state: state)
                withAnimation(Motion.standard) { options = found }
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    private func use(_ option: String) {
        if field.onePerLine {
            let lines = AppModel.lines(text)
            if !lines.contains(option) { text = (lines + [option]).joined(separator: "\n") }
        } else if tool.isCarousel {
            let count = Int(state.choice(1, in: tool)) ?? 5
            text = Array(Self.pieces(option).prefix(count)).joined(separator: " | ")
        } else if field.pipeSeparated {
            text = Self.pieces(option).joined(separator: "\n")
        } else {
            text = option
        }
        isPresented = false
    }
}

struct AdExample: View {
    let tool: AdTool
    let state: AdState
    var rowHeight: CGFloat = AdExample.tallest

    static let tallest: CGFloat = 232
    private static let shortest: CGFloat = 160
    private static let formRoom: CGFloat = 464

    static func rowHeight(visible: CGFloat) -> CGFloat {
        guard visible > 0 else { return tallest }
        return min(tallest, max(shortest, visible - formRoom))
    }

    var body: some View {
        if let example = Examples.ad(tool.id) {
            VStack(alignment: .leading, spacing: 10) {
                Label(L("Real example"), systemImage: "checkmark.seal")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    if let before = example.before {
                        AdExampleImage(url: before, title: tool.needsReference ? tool.referenceTitle : L("Product"))
                    }
                    if let extra = example.extra {
                        AdExampleImage(url: extra, title: L("Product"))
                    }
                    Image(systemName: "arrow.right").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(example.gallery.isEmpty ? [example.after] : example.gallery, id: \.self) { url in
                        AdExampleImage(url: url, title: L("Result"))
                    }
                }
                .frame(height: rowHeight, alignment: .leading)
                settings
                if [tool.text, tool.text2].contains(where: { $0?.isLiteral == true }) {
                    Text(L("The example's words are in English; yours are written exactly as you type them."))
                        .fineTextStyle()
                }
            }
        }
    }

    @ViewBuilder private var settings: some View {
        let names = (tool.displayOrder ?? Array(tool.options.indices)).compactMap { index -> String? in
            if let many = tool.manyExample[index] {
                return many.map { tool.options[index].shortLabel($0) }.joined(separator: " + ")
            }
            return tool.example[index].map { value in
                Int(value) != nil ? "\(value) \(tool.options[index].title.localizedLowercase)" : tool.options[index].shortLabel(value)
            }
        }
        let modelName = Lineup.entry(tool.model)?.name
        let summary = names.isEmpty ? modelName ?? "" : names.joined(separator: " · ")
        let matches = state.modelID == nil && tool.example.allSatisfy { state.choice($0.key, in: tool) == $0.value }
            && tool.manyExample.allSatisfy { Set(state.picks($0.key, in: tool)) == Set($0.value) }
        if !summary.isEmpty {
            HStack(spacing: 10) {
                Text(L("Made with: %@", summary))
                    .helperTextStyle()
                    .fixedSize(horizontal: false, vertical: true)
                    .help(modelName.map { L("Made with: %@", $0) } ?? "")
                if !matches {
                    Button(L("Use these settings"), systemImage: "arrow.uturn.backward") {
                        withAnimation(Motion.standard) {
                            for (index, value) in tool.example { state.choices[index] = value }
                            for (index, values) in tool.manyExample { state.many[index] = Set(values) }
                            state.modelID = nil
                        }
                    }
                    .buttonStyle(.glass)
                    .fixedSize()
                }
            }
        }
    }
}

private struct AdExampleImage: View {
    let url: URL
    let title: String

    var body: some View {
        VStack(spacing: 4) {
            ThumbnailImage(url: url, maxPixel: 900, contentMode: .fit, placeholderAspect: Thumbnails.aspect(of: url) ?? 0.8)
                .clipShape(.rect(cornerRadius: Radius.tile))
            Text(title).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
        }
    }
}

private struct AdTileGrid<Content: View>: View {
    let count: Int
    @ViewBuilder var content: () -> Content

    @State private var width: CGFloat = 0

    var body: some View {
        OptionGrid(columns: width > 0 ? AdTileColumns.count(tiles: count, width: width) : nil, minimum: AdTileColumns.minimum) {
            content()
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
    }
}

private enum AdTileColumns {
    static let minimum: CGFloat = 124
    static let maximum: CGFloat = 220
    static let spacing: CGFloat = 8

    static func count(tiles: Int, width: CGFloat) -> Int {
        guard tiles > 0 else { return 1 }
        let fit = OptionGrid.columnCount(width: width, columns: nil, minimum: minimum, spacing: spacing)
        let rows = (tiles + fit - 1) / fit
        let balanced = (tiles + rows - 1) / rows
        let capped = Int(((width + spacing) / (maximum + spacing)).rounded(.up))
        let columns = min(fit, max(balanced, capped))
        guard tiles > columns, tiles % columns == 1 else { return columns }
        let fewerRows = (tiles + columns - 1) / columns
        return (tiles + fewerRows - 1) / fewerRows
    }
}

private extension View {
    func wellFrame(_ height: CGFloat) -> some View {
        frame(minHeight: height, idealHeight: height, maxHeight: .infinity)
    }
}

struct AdBatchProducts: View {
    @Bindable var state: AdState

    @Environment(AppModel.self) private var app
    @State private var importing = false

    static let limit = 10

    var body: some View {
        let products = app.library.products
        let chosen = app.batchProducts(state)
        VStack(alignment: .leading, spacing: 10) {
            if products.isEmpty {
                Text(L("Save your products first: each one needs a name and a photo."))
                    .helperTextStyle()
            } else {
                OptionGrid(minimum: 128, spacing: 8) {
                    ForEach(products) { product in
                        OptionTile(title: product.name,
                                   picture: product.photoFileNames.first.map { OptionPicture(url: app.library.productPhotoURL($0), aspect: 1) },
                                   isSelected: state.productIDs.contains(product.id), isMultiSelect: true, compact: true) {
                            toggle(product)
                        }
                    }
                }
            }
            FlowLayout(spacing: 8) {
                Button(L("Import from Link…"), systemImage: "link") { importing = true }
                    .buttonStyle(.glass)
                    .fixedSize()
                if products.count > 1 {
                    Button(chosen.isEmpty ? L("Select All") : L("Clear"), systemImage: chosen.isEmpty ? "checkmark.circle" : "xmark.circle") {
                        withAnimation(Motion.select) {
                            state.productIDs = chosen.isEmpty ? Array(products.prefix(Self.limit).map(\.id)) : []
                        }
                    }
                    .buttonStyle(.glass)
                    .fixedSize()
                }
                if !products.isEmpty {
                    Text(L("%ld of up to %ld chosen", chosen.count, Self.limit))
                        .fineTextStyle()
                        .fixedSize()
                }
            }
            if !products.isEmpty, chosen.isEmpty {
                Label(L("Click the products to include"), systemImage: "hand.point.up.left")
                    .helperTextStyle()
                    .transition(.opacity)
            }
            Text(L("Every product gets one ad per selling angle and size."))
                .helperTextStyle()
        }
        .onChange(of: products.map(\.id), initial: true) { _, ids in
            if ids.count == 1, app.batchProducts(state).isEmpty { state.productIDs = ids }
        }
        .sheet(isPresented: $importing) {
            NewProductSheet { product in
                if state.productIDs.count < Self.limit { state.productIDs.append(product.id) }
            }
        }
    }

    private func toggle(_ product: Product) {
        withAnimation(Motion.select) {
            if let index = state.productIDs.firstIndex(of: product.id) {
                state.productIDs.remove(at: index)
            } else if app.batchProducts(state).count < Self.limit {
                state.productIDs.removeAll { app.library.product($0) == nil }
                state.productIDs.append(product.id)
            }
        }
    }
}

struct HeadlineWriter: View {
    let tool: AdTool
    @Bindable var state: AdState
    @Binding var text: String

    @Environment(AppModel.self) private var app
    @State private var isWorking = false

    var body: some View {
        HStack(spacing: 8) {
            Picker(L("How many the AI writes"), selection: $state.headlineCount) {
                ForEach([3, 5, 8, 10], id: \.self) { value in
                    Text(verbatim: "\(value)").tag(value)
                }
            }
            .fixedSize()
            Button(action: write) {
                HStack(spacing: 6) {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "wand.and.sparkles")
                    }
                    Text(L("Write with AI"))
                    PricePill(text: GenerateButton.format(AppModel.helperEstimate))
                }
            }
            .buttonStyle(.glass)
            .fixedSize()
            .disabled(reason != nil || isWorking)
            .help(reason ?? L("The AI writes different headlines from your product's name and details. Edit them before you generate."))
        }
    }

    private var reason: String? {
        if !app.hasAnyKey { return L("Add an API key in Settings") }
        if app.helperModel == nil { return L("No text model is available for the AI assistant.") }
        if !app.adHasProduct(state) { return L("Choose a product first.") }
        return nil
    }

    private func write() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let headlines = try await app.writeHeadlines(tool, state: state)
                withAnimation(Motion.standard) { text = headlines.joined(separator: "\n") }
            } catch {
                app.presentError(error)
            }
        }
    }
}
