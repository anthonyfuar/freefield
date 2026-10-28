import FreefieldCore
import SwiftUI

struct CharacterBuilderView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showControls = true
    @State private var canvasWidth: CGFloat = 0

    private var design: CharacterDesign { CharacterDesign.shared }

    var body: some View {
        CharacterSheetCanvas(design: design)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { canvasWidth = $0 }
            .navigationTitle(L("Design a Character"))
            .canvasSubtitle(L("An original person, no photos needed"), canvasWidth: canvasWidth)
            .inspector(isPresented: $showControls) {
                controls
                    .toolPanelWidth()
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(L("Characters"), systemImage: "chevron.backward") { app.charactersPage = .people }
                        .help(L("Back to your characters"))
                }
                ToolbarItem {
                    Button(L("Controls"), systemImage: "sidebar.right") { showControls.toggle() }
                        .help(L("Show or hide controls (⌥⌘I)"))
                        .keyboardShortcut("i", modifiers: [.command, .option])
                }
            }
    }

    private var controls: some View {
        @Bindable var design = design
        let model = app.characterSheetModel(selection: design.modelID)
        let reason = disabledReason(model)
        let cost = app.characterSheetCost(model)
        let create = {
            guard let model, reason == nil else { return }
            app.runCharacterSheet(design, model: model)
        }

        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 28) {
                        VStack(alignment: .leading, spacing: 12) {
                            PanelSection(title: L("The basics"), step: 1, isDone: true) {
                                Text(L("Click to choose. Click again to clear a choice; anything left empty, the AI decides."))
                                    .helperTextStyle()
                                    .fixedSize(horizontal: false, vertical: true)
                                groups(.basics)
                            }
                            ExtraInstructionField(text: $design.extra,
                                                  placeholder: L("E.g. a friendly baker from Lisbon with a warm laugh and flour on her apron"),
                                                  limit: 400)
                        }
                        PanelSection(title: L("Face and hair"), step: 2, isDone: true) {
                            groups(.face)
                        }
                    }
                    ExtrasHeader()
                    VStack(alignment: .leading, spacing: 16) {
                        OptionalSection(L("Clothes"), systemImage: "tshirt", summary: design.summary(of: .clothes),
                                        isFilled: design.isFilled(.clothes), storageKey: "builder.clothes") {
                            groups(.clothes)
                        }
                        OptionalSection(L("Details"), systemImage: "eyeglasses", summary: design.summary(of: .details),
                                        isFilled: design.isFilled(.details), storageKey: "builder.details") {
                            groups(.details)
                        }
                        OptionalSection(L("Personality"), systemImage: "face.smiling", summary: design.summary(of: .personality),
                                        isFilled: design.isFilled(.personality), storageKey: "builder.personality") {
                            groups(.personality)
                        }
                        OptionalSection(L("More options"), systemImage: "slider.horizontal.3",
                                        summary: design.modelID == nil ? L("Auto") : model.map { app.catalog.choice(for: $0).displayName },
                                        storageKey: "builder.moreOptions") {
                            ModelPicker(selectionID: $design.modelID, current: model)
                            if let model {
                                Text(app.catalog.choice(for: model).tagline)
                                    .helperTextStyle()
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(20)
            }
            Divider()
            VStack(spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        surpriseButton
                        GenerateButton(title: L("Create Character Sheet"), isEnabled: reason == nil, disabledReason: reason,
                                       estimatedCost: cost, size: .extraLarge, action: create)
                    }
                    VStack(spacing: 8) {
                        GenerateButton(title: L("Create Character Sheet"), isEnabled: reason == nil, disabledReason: reason,
                                       estimatedCost: cost, action: create)
                        surpriseButton
                    }
                }
                .frame(maxWidth: .infinity)
                DisabledReasonLabel(reason: reason)
                Text(L("Makes one image with 4 views: front, three-quarter, profile and full body."))
                    .fineTextStyle()
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .animation(reduceMotion ? nil : Motion.standard, value: reason)
            .padding(16)
        }
    }

    private var surpriseButton: some View {
        Button(L("Surprise Me"), systemImage: "dice") {
            withAnimation(reduceMotion ? nil : Motion.standard) { design.surprise() }
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .fixedSize()
        .help(L("Picks random choices for you to start from"))
    }

    private func groups(_ step: DesignGroup.Step) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(DesignCatalog.groups(in: step)) { group in
                if group.id != "facialHair" || design.choices["who"] != "Woman" {
                    DesignGroupPicker(group: group, design: design)
                }
            }
        }
    }

    private func disabledReason(_ model: ImageModel?) -> String? {
        if !app.hasAnyKey { return L("Add an API key") }
        if model == nil { return app.catalog.isLoading ? L("Loading models…") : L("No model available") }
        if !app.characterSheetJobs.isEmpty { return L("Wait for the current sheet to finish") }
        return nil
    }
}

private struct DesignGroupPicker: View {
    let group: DesignGroup
    let design: CharacterDesign

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(group.title).font(.callout.weight(.semibold))
                if group.isMultiple {
                    Text(L("Choose any")).fineTextStyle()
                }
            }
            if !group.swatches.isEmpty {
                SwatchPicker(group: group, design: design)
            } else {
                ChoiceChips(values: group.values, pictures: group.pictures,
                            isSelected: { design.isSelected($0, in: group) },
                            onSelect: { value in withAnimation(Motion.select) { design.toggle(value, in: group) } })
            }
        }
    }
}

private struct SwatchPicker: View {
    let group: DesignGroup
    let design: CharacterDesign

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(group.values, id: \.self) { value in
                let selected = design.isSelected(value, in: group)
                Button {
                    withAnimation(Motion.select) { design.toggle(value, in: group) }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: group.swatches[value] ?? "999999"))
                            .overlay { Circle().strokeBorder(.primary.opacity(0.2), lineWidth: 1) }
                            .frame(width: 18, height: 18)
                        Text(L(value)).font(.callout.weight(.medium)).lineLimit(1)
                        if selected { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                    }
                    .padding(.leading, 6)
                    .padding(.trailing, 12)
                    .frame(minHeight: 34)
                    .background(selected ? Color.appAccent.opacity(0.16) : Color.primary.opacity(0.05), in: .capsule)
                    .overlay {
                        Capsule().strokeBorder(selected ? Color.appAccent : .primary.opacity(0.08), lineWidth: selected ? 1.5 : 1)
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

private struct CharacterSheetCanvas: View {
    @Bindable var design: CharacterDesign
    @Environment(AppModel.self) private var app
    @State private var panels: [Data] = []
    @State private var panelsFor: UUID?

    private var sheet: Asset? {
        app.library.asset(design.sheetID ?? UUID()) ?? app.characterSheets.first
    }

    private static let viewNames = [L("Front"), L("Three-quarter"), L("Profile"), L("Full body")]

    var body: some View {
        let running = app.characterSheetJobs
        let failure = app.engine.jobs.first { $0.spec?.appID == CharacterSheet.appID }.flatMap { job -> String? in
            if case .failed(let message) = job.status { return message }
            return nil
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !running.isEmpty {
                    working
                }
                if let failure, running.isEmpty {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let sheet {
                    result(sheet)
                } else if running.isEmpty {
                    emptyState
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task(id: sheet?.id) { await loadPanels() }
    }

    private var working: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.regular)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Creating your character…")).font(.headline)
                Text(L("It usually takes 20 to 60 seconds."))
                    .helperTextStyle()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: Radius.card))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Your character will appear here")).font(.title2.bold())
                Text(L("Choose how they look on the right, or click Surprise Me. Freefield makes a sheet with 4 views of the same person, and you save it as a character to use in any tool."))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: PageLayout.textWidth, alignment: .leading)
            }
            HStack(spacing: 12) {
                ForEach(Array(zip(Self.viewNames, ["person.crop.circle", "person.crop.circle.badge.clock", "person.crop.square", "figure.stand"])), id: \.0) { name, symbol in
                    VStack(spacing: 8) {
                        Image(systemName: symbol)
                            .iconSymbol(IconScale.hero)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 110)
                            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: Radius.tile))
                        Text(name).fineTextStyle().lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: 560)
        }
    }

    @ViewBuilder
    private func result(_ sheet: Asset) -> some View {
        let saved = app.library.character(design.savedCharacterID)
        VStack(alignment: .leading, spacing: 16) {
            ThumbnailImage(url: app.library.url(for: sheet), maxPixel: 1400, contentMode: .fit)
                .frame(maxWidth: 560, maxHeight: 560)
                .clipShape(.rect(cornerRadius: Radius.card))
                .onTapGesture(count: 2) { app.quickLook(sheet) }
                .help(L("Double-click to see it bigger"))

            if panels.count == 4 {
                HStack(spacing: 10) {
                    ForEach(Array(panels.enumerated()), id: \.offset) { index, data in
                        VStack(spacing: 4) {
                            if let image = NSImage(data: data) {
                                Image(nsImage: image).resizable().scaledToFill()
                                    .frame(width: 96, height: 96)
                                    .clipShape(.rect(cornerRadius: Radius.tile))
                            }
                            Text(Self.viewNames[index]).fineTextStyle().lineLimit(1)
                        }
                    }
                }
            }

            if let saved {
                savedBanner(saved)
            } else {
                saveBox(sheet)
            }

            changeBox(sheet)

            if app.characterSheets.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Earlier sheets")).groupTitleStyle()
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(app.characterSheets.prefix(12)) { asset in
                                Button {
                                    design.sheetID = asset.id
                                    design.savedCharacterID = nil
                                } label: {
                                    ThumbnailImage(url: app.library.url(for: asset), maxPixel: 240)
                                        .frame(width: 76, height: 76)
                                        .clipShape(.rect(cornerRadius: Radius.tile))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: Radius.tile)
                                                .strokeBorder(asset.id == sheet.id ? Color.appAccent : .clear, lineWidth: 2.5)
                                        }
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
        }
    }

    private func saveBox(_ sheet: Asset) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Like it? Give them a name and save them")).font(.headline)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    nameField
                    saveButton(sheet)
                }
                VStack(alignment: .leading, spacing: 8) {
                    nameField
                    saveButton(sheet)
                }
            }
            Text(L("The 4 views become their reference photos, so every tool keeps the same face."))
                .helperTextStyle()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: 640, alignment: .leading)
        .background(Color.brand.opacity(0.08), in: .rect(cornerRadius: Radius.card))
    }

    private var nameField: some View {
        TextField(L("Name"), text: $design.name, prompt: Text(L("e.g. Lucía")))
            .textFieldStyle(.roundedBorder)
            .characterLimit($design.name, 40)
            .frame(maxWidth: 280)
    }

    private func saveButton(_ sheet: Asset) -> some View {
        Button {
            if let character = app.saveCharacter(from: sheet, design: design, panels: panels) {
                design.savedCharacterID = character.id
            }
        } label: {
            Label(L("Save as Character"), systemImage: "person.crop.square.badge.plus").prominentLabel()
        }
        .buttonStyle(.glassProminent)
        .tint(.brandFill)
        .controlSize(.large)
        .fixedSize()
        .disabled(panels.count != 4)
    }

    private func savedBanner(_ character: Character) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { savedLabel(character); Spacer(minLength: 8); useMenu(character) }
            VStack(alignment: .leading, spacing: 10) { savedLabel(character); useMenu(character) }
        }
        .padding(16)
        .frame(maxWidth: 640, alignment: .leading)
        .background(Color.green.opacity(0.1), in: .rect(cornerRadius: Radius.card))
    }

    private func savedLabel(_ character: Character) -> some View {
        Label(L("%@ is saved in Characters.", character.name), systemImage: "checkmark.circle.fill")
            .font(.headline)
            .symbolRenderingMode(.multicolor)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func useMenu(_ character: Character) -> some View {
        Menu {
            CharacterUseItems(character: character)
        } label: {
            Label(L("Use %@ in…", character.name), systemImage: "arrow.up.forward.app").prominentLabel()
        }
        .menuStyle(.button)
        .buttonStyle(.glassProminent)
        .tint(.brandFill)
        .fixedSize()
    }

    private func changeBox(_ sheet: Asset) -> some View {
        let model = app.characterSheetModel(selection: design.modelID, needsImage: true)
        let busy = !app.characterSheetJobs.isEmpty
        let ready = model != nil && app.hasAnyKey && !busy && !design.change.trimmingCharacters(in: .whitespaces).isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            Text(L("Not quite right? Describe a change")).font(.headline)
            PromptField(text: $design.change, placeholder: L("E.g. make the hair shorter and add round glasses"),
                        minLines: 1, maxLines: 3, focusOnAppear: false)
                .characterLimit($design.change, 300)
                .frame(maxWidth: 640)
            HStack(spacing: 10) {
                GenerateButton(title: L("Change It"), isEnabled: ready,
                               disabledReason: busy ? L("Wait for the current sheet to finish") : L("Write the change"),
                               estimatedCost: app.characterSheetCost(model)) {
                    guard let model, ready else { return }
                    app.changeCharacterSheet(sheet, design: design, model: model)
                }
                Text(L("Or change the choices on the right and create a new sheet."))
                    .helperTextStyle()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loadPanels() async {
        guard let sheet, panelsFor != sheet.id || panels.count != 4 else { return }
        guard let data = app.library.imageData(for: sheet) else {
            panels = []
            return
        }
        let result = await CharacterSheet.panelsInBackground(from: data)
        panels = result
        panelsFor = sheet.id
    }
}

extension CharacterDesign {
    func edit(_ character: Character) {
        if let stored = character.designChoices { load(stored) }
        name = character.name
        sheetID = nil
        savedCharacterID = nil
        change = ""
    }
}
