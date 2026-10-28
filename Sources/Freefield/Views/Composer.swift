import AppKit
import FreefieldCore
import ImageIO
import SwiftUI

struct Composer: View {
    @Bindable var state: ComposerState
    @Environment(AppModel.self) private var app
    @State private var showStyles = false
    @State private var isDropTargeted = false
    @State private var attachmentsWidth: CGFloat = 0
    @State private var showMentions = false
    @State private var focusToken = 0

    private var character: Character? { app.library.character(state.characterID) }
    private var castPeople: [Character] { app.castCharacters(for: state) }
    private var elements: [SceneElement] { app.sceneElements(for: state) }
    private var product: Product? { app.library.product(state.productID) }
    private var preset: StylePreset? { state.presetID.flatMap(StylePresets.preset) }
    private var moodboard: Moodboard? { app.library.moodboard(state.moodboardID) }
    private var requirement: ModelRequirement {
        ModelRequirement(images: state.references.count + (character == nil ? 0 : 1) + castPeople.count + elements.count
                         + (product == nil ? 0 : 1))
    }
    private var hasSceneItems: Bool { !castPeople.isEmpty || !elements.isEmpty }
    private var attachmentSignature: [String?] {
        [preset?.id, moodboard?.id.uuidString, character?.id.uuidString, product?.id.uuidString, String(state.references.count),
         castPeople.map(\.id.uuidString).joined(), elements.map(\.id.uuidString).joined()]
    }

    var body: some View {
        let model = app.resolvedModel(for: state, requirement: requirement)
        VStack(alignment: .leading, spacing: 10) {
            if preset != nil || moodboard != nil || character != nil || product != nil || hasSceneItems || !state.references.isEmpty {
                attachments(model: model)
                    .transition(.opacity)
            }
            if state.references.count == 1, preset == nil, moodboard == nil, character == nil, product == nil, !hasSceneItems {
                RelatedToolHint(prompt: L("Want to change this photo?"), links: [editLink])
            }

            ComposerPromptField(text: $state.prompt, placeholder: L("Describe the image you have in mind…"),
                                limit: app.promptLimit(for: .create, state: state, model: model),
                                focusToken: focusToken,
                                onSubmit: { generate(model) }) {
                improveButton
            }
            .popover(isPresented: $showMentions, arrowEdge: .bottom) {
                MentionPicker { mention in
                    insert(mention, model: model)
                }
            }
            .onChange(of: state.prompt) { old, new in
                if new.hasSuffix("@"), new.count == old.count + 1, hasMentionables { showMentions = true }
                attachMentions(in: new, previous: old, model: model)
            }

            GlassEffectContainer(spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    VStack(alignment: .trailing, spacing: 10) {
                        HStack(spacing: 12) {
                            HStack(spacing: 2) { addItems(model) }
                            Spacer(minLength: 12)
                            HStack(spacing: 8) { settingsItems(model) }
                        }
                        generateColumn(model)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 2) { addItems(model) }
                        HStack(alignment: .bottom, spacing: 8) {
                            HStack(spacing: 8) { settingsItems(model) }
                            Spacer(minLength: 8)
                            generateColumn(model)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        FlowLayout(spacing: 2, lineSpacing: 4) { addItems(model) }
                        FlowLayout(spacing: 8) { settingsItems(model) }
                        generateColumn(model)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.panel))
        .animation(Motion.standard, value: attachmentSignature)
        .overlay {
            RoundedRectangle(cornerRadius: Radius.panel)
                .strokeBorder(Color.appAccent, lineWidth: 2)
                .opacity(isDropTargeted ? 1 : 0)
                .animation(Motion.fade, value: isDropTargeted)
                .allowsHitTesting(false)
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            Task {
                let images = await ImageIntake.data(from: providers)
                state.references.append(contentsOf: images.prefix(max(0, 14 - state.references.count)))
            }
            return true
        }
    }

    private var improveButton: some View {
        Button {
            Task { await app.enhancePrompt(in: state) }
        } label: {
            HStack(spacing: 5) {
                if state.isEnhancing {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "wand.and.sparkles")
                }
                Text(L("Improve Description"))
            }
            .lineLimit(1)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .fixedSize()
        .disabled(state.trimmedPrompt.isEmpty || state.isEnhancing || !app.hasAnyKey)
        .help(L("Improve Description: rewrites it with more detail (⌘E)"))
        .keyboardShortcut("e", modifiers: .command)
    }

    @ViewBuilder
    private func addItems(_ model: ImageModel?) -> some View {
        Text(L("Add:"))
            .fineTextStyle()
            .fixedSize()
            .frame(minHeight: 28)
            .padding(.trailing, 2)
        Button {
            showStyles = true
        } label: {
            AddOnLabel(title: preset?.name ?? moodboard?.name ?? L("Style")) {
                Image(systemName: "paintpalette")
            }
        }
        .buttonStyle(PressableStyle())
        .fixedSize()
        .help(L("Styles and moodboards"))
        .popover(isPresented: $showStyles, arrowEdge: .top) {
            StylePicker(selection: $state.presetID, moodboard: $state.moodboardID) { showStyles = false }
        }
        CastMenu(state: state, limit: app.maxPeople(for: model))
        SceneElementMenu(state: state, kind: .location)
        SceneElementMenu(state: state, kind: .prop)
        ProductMenu(selection: $state.productID, isAddOn: true)
        if model?.acceptsImageInput ?? true {
            Button {
                let picked = ImageIntake.pick(multiple: true)
                state.references.append(contentsOf: picked.prefix(max(0, (model?.maxReferences ?? 4) - state.references.count)))
            } label: {
                AddOnLabel(title: L("Reference Photo")) {
                    Image(systemName: "photo.badge.plus")
                }
            }
            .buttonStyle(PressableStyle())
            .fixedSize()
            .help(L("Add reference images (you can also drag them here)"))
        }
    }

    @ViewBuilder
    private func settingsItems(_ model: ImageModel?) -> some View {
        AspectRatioMenu(selection: $state.aspectRatio, available: model?.aspectRatios.isEmpty == false ? model!.aspectRatios : AspectRatio.standard)
        CountMenu(count: $state.count, maximum: 4)
        MoreOptionsChip(summary: moreSummary(model), help: moreHelp(model)) {
            CreateMoreOptions(state: state, model: model, requirement: requirement)
        }
    }

    private func moreHelp(_ model: ImageModel?) -> String {
        let base = L("Camera, color, size, quality and AI model")
        guard let model else { return base }
        let name = app.catalog.choice(for: model).displayName
        return base + "\n" + (state.modelID == nil ? L("Auto · %@", name) : name)
    }

    private func generateColumn(_ model: ImageModel?) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            if !app.hasAnyKey || model == nil {
                DisabledReasonLabel(reason: disabledReason(model))
            }
            GenerateButton(
                title: state.count > 1 ? L("Generate %ld images", state.count) : L("Generate"),
                isEnabled: canGenerate(model),
                disabledReason: disabledReason(model),
                estimatedCost: app.estimatedCost(model: model, count: state.count, resolution: state.resolution),
                isWorking: state.isEnhancing,
                size: .extraLarge
            ) {
                generate(model)
            }
        }
    }

    private var chipTransition: AnyTransition {
        Motion.transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
    }

    private var attachmentCap: CGFloat { attachmentsWidth > 0 ? attachmentsWidth : .infinity }

    @ViewBuilder
    private func attachments(model: ImageModel?) -> some View {
        let sceneSlots = 2 * (castPeople.count + elements.count)
        let referenceLimit = max(1, (model?.maxReferences ?? 4) - (character == nil ? 0 : hasSceneItems ? 2 : 4) - sceneSlots
                                    - (product == nil ? 0 : 3))
        FlowLayout(spacing: 8) {
            if let preset {
                AttachmentChip(title: preset.name, systemImage: "paintpalette", thumbnail: preset.thumbnailURL) {
                    state.presetID = nil
                }
                .frame(maxWidth: attachmentCap, alignment: .leading)
                .transition(chipTransition)
            }
            if let moodboard {
                AttachmentChip(title: moodboard.name, systemImage: "square.grid.2x2",
                               thumbnail: moodboard.imageFileNames.first.map(app.library.characterPhotoURL)) {
                    state.moodboardID = nil
                }
                .frame(maxWidth: attachmentCap, alignment: .leading)
                .transition(chipTransition)
            }
            if let character {
                AttachmentChip(title: character.name, systemImage: "person.crop.square",
                               thumbnail: character.photoFileNames.first.map(app.library.characterPhotoURL)) {
                    app.removeFromCast(character.id, in: state)
                }
                .frame(maxWidth: attachmentCap, alignment: .leading)
                .transition(chipTransition)
            }
            ForEach(castPeople) { person in
                AttachmentChip(title: person.name, systemImage: "person.crop.square",
                               thumbnail: person.photoFileNames.first.map(app.library.characterPhotoURL)) {
                    app.removeFromCast(person.id, in: state)
                }
                .frame(maxWidth: attachmentCap, alignment: .leading)
                .transition(chipTransition)
            }
            ForEach(elements) { element in
                AttachmentChip(title: element.name, systemImage: element.kind.systemImage,
                               thumbnail: element.photoFileNames.first.map(app.library.elementPhotoURL)) {
                    state.elementIDs.removeAll { $0 == element.id }
                }
                .frame(maxWidth: attachmentCap, alignment: .leading)
                .transition(chipTransition)
            }
            if let product {
                AttachmentChip(title: product.name, systemImage: "shippingbox",
                               thumbnail: product.photoFileNames.first.map(app.library.productPhotoURL)) {
                    state.productID = nil
                }
                .frame(maxWidth: attachmentCap, alignment: .leading)
                .transition(chipTransition)
            }
            if !state.references.isEmpty {
                let tiles = state.references.count + (state.references.count < referenceLimit ? 1 : 0)
                ReferenceStrip(images: $state.references, limit: referenceLimit)
                    .frame(minWidth: min(120, attachmentCap), idealWidth: CGFloat(tiles) * 60 - 4, maxWidth: attachmentCap,
                           alignment: .leading)
                    .transition(chipTransition)
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { attachmentsWidth = $0 }
    }

    private func moreSummary(_ model: ImageModel?) -> String {
        var parts: [String] = []
        if CameraMenu.isSet(state) { parts.append(CameraMenu.title(for: state)) }
        if let palette = state.palette { parts.append(palette.name) }
        if let model, model.resolutions.count > 1, state.resolution != .oneK { parts.append(state.resolution.rawValue) }
        if let model, !model.qualities.isEmpty, state.quality != "auto" { parts.append(QualityMenu.label(state.quality)) }
        if state.modelID != nil, let model { parts.append(app.catalog.choice(for: model).displayName) }
        if parts.isEmpty { return L("Auto") }
        return parts.count > 2 ? parts.prefix(2).joined(separator: " · ") + " · +\(parts.count - 2)" : parts.joined(separator: " · ")
    }

    private var editLink: RelatedToolHint.Link {
        let image = state.references.first
        let typed = state.prompt
        return RelatedToolHint.Link(title: Tool.edit.title) { [app] in
            let edit = app.composer(for: .edit)
            if edit.trimmedPrompt.isEmpty { edit.prompt = typed }
            app.openRelated(.tool(.edit), image: image)
        }
    }

    private func canGenerate(_ model: ImageModel?) -> Bool {
        disabledReason(model) == nil && !state.isEnhancing
    }

    private func disabledReason(_ model: ImageModel?) -> String? {
        if !app.hasAnyKey { return L("Add an API key in Settings") }
        if model == nil { return app.catalog.isLoading ? L("Loading models…") : L("No model available") }
        if state.trimmedPrompt.isEmpty && preset == nil && moodboard == nil && product == nil { return L("Write a description") }
        return nil
    }

    private func generate(_ model: ImageModel?) {
        guard let model, canGenerate(model) else { return }
        app.runCreate(state, model: model)
    }

    private var hasMentionables: Bool {
        !app.library.characters.isEmpty || !app.library.elements.isEmpty || !app.library.products.isEmpty
    }

    private func insert(_ mention: Mention, model: ImageModel?) {
        showMentions = false
        if state.prompt.hasSuffix("@") { state.prompt.removeLast() }
        state.prompt += "@\(mention.name) "
        attach(mention, model: model)
        focusToken += 1
    }

    private func attach(_ mention: Mention, model: ImageModel?) {
        switch mention {
        case .character(let character): app.addToCast(character, in: state, limit: app.maxPeople(for: model))
        case .element(let element): app.attach(element, to: state)
        case .product(let product): state.productID = product.id
        }
    }

    private func attachMentions(in text: String, previous: String, model: ImageModel?) {
        guard text.contains("@") else { return }
        for mention in Mention.all(in: app.library)
        where Mention.isMentioned(mention.name, in: text) && !Mention.isMentioned(mention.name, in: previous) {
            switch mention {
            case .character(let character):
                if state.characterID != character.id, !state.castIDs.contains(character.id) { attach(mention, model: model) }
            case .element(let element):
                if !state.elementIDs.contains(element.id) { attach(mention, model: model) }
            case .product(let product):
                if state.productID == nil { state.productID = product.id }
            }
        }
    }
}

enum Mention: Identifiable {
    case character(Character)
    case element(SceneElement)
    case product(Product)

    var id: UUID {
        switch self {
        case .character(let character): character.id
        case .element(let element): element.id
        case .product(let product): product.id
        }
    }

    var name: String {
        switch self {
        case .character(let character): character.name
        case .element(let element): element.name
        case .product(let product): product.name
        }
    }

    static func all(in library: Library) -> [Mention] {
        library.characters.map(Mention.character) + library.elements.map(Mention.element) + library.products.map(Mention.product)
    }

    static func isMentioned(_ name: String, in text: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let range = text.range(of: "@" + name, options: [.caseInsensitive, .diacriticInsensitive]) else { return false }
        guard range.upperBound < text.endIndex else { return true }
        let next = text[range.upperBound]
        return !(next.isLetter || next.isNumber)
    }
}

private struct MentionPicker: View {
    let onPick: (Mention) -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Add something you saved")).font(.headline)
                section(L("Characters"), symbol: "person.crop.square", app.library.characters.map(Mention.character))
                section(L("Locations"), symbol: SceneElementKind.location.systemImage,
                        app.library.elements(of: .location).map(Mention.element))
                section(L("Objects"), symbol: SceneElementKind.prop.systemImage, app.library.elements(of: .prop).map(Mention.element))
                section(L("Products"), symbol: "shippingbox", app.library.products.map(Mention.product))
            }
            .padding(14)
        }
        .frame(width: 280)
        .frame(maxHeight: 380)
    }

    @ViewBuilder
    private func section(_ title: String, symbol: String, _ items: [Mention]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fineTextStyle()
                ForEach(items) { item in
                    Button {
                        onPick(item)
                    } label: {
                        Label(item.name, systemImage: symbol)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct CastMenu: View {
    @Bindable var state: ComposerState
    var limit: Int
    @Environment(AppModel.self) private var app
    @AppStorage("lastCharacterID") private var lastCharacterID = ""

    var body: some View {
        let primary = app.library.character(state.characterID)
        let extras = app.castCharacters(for: state)
        let title = primary.map { extras.isEmpty ? $0.name : L("%@ + %ld", $0.name, extras.count) } ?? L("Character")
        Menu {
            if app.library.characters.isEmpty {
                Text(L("You don't have any characters yet"))
            } else {
                Section(limit > 1 ? L("Up to %ld people with this AI model", limit) : L("1 person with this AI model")) {
                    ForEach(app.library.characters) { character in
                        Toggle(isOn: Binding(get: { isIn(character) }, set: { set(character, on: $0) })) {
                            Label {
                                Text(character.name)
                            } icon: {
                                if let face = CharacterFace.image(for: character, in: app.library) { Image(nsImage: face) }
                            }
                        }
                        .disabled(!isIn(character) && primary != nil && (limit <= 1 ? false : extras.count + 1 >= limit))
                    }
                }
            }
            Divider()
            Button(L("New character…"), systemImage: "plus") {
                app.charactersPage = .people
                app.selection = .characters
                app.creatingCharacter = true
            }
            Button(L("Design a character…"), systemImage: "wand.and.sparkles") {
                app.charactersPage = .builder
                app.selection = .characters
            }
        } label: {
            AddOnLabel(title: title, showsMenuIndicator: true) {
                if let primary, let face = CharacterFace.image(for: primary, in: app.library) {
                    Image(nsImage: face).resizable().scaledToFill().frame(width: 18, height: 18).clipShape(.circle)
                } else {
                    Image(systemName: extras.isEmpty ? "person.crop.square" : "person.2")
                }
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("Characters with a consistent face; choose several to put them in the same image"))
    }

    private func isIn(_ character: Character) -> Bool {
        state.characterID == character.id || state.castIDs.contains(character.id)
    }

    private func set(_ character: Character, on: Bool) {
        if on {
            if limit <= 1 {
                state.characterID = character.id
                state.castIDs = []
            } else {
                app.addToCast(character, in: state, limit: limit)
            }
            lastCharacterID = character.id.uuidString
        } else {
            app.removeFromCast(character.id, in: state)
        }
    }
}

struct SceneElementMenu: View {
    @Bindable var state: ComposerState
    let kind: SceneElementKind
    @Environment(AppModel.self) private var app

    var body: some View {
        let items = app.library.elements(of: kind)
        let picked = app.sceneElements(for: state).filter { $0.kind == kind }
        let title = picked.first.map { picked.count > 1 ? L("%@ + %ld", $0.name, picked.count - 1) : $0.name } ?? kind.singular
        Menu {
            if items.isEmpty {
                Text(kind == .location ? L("You don't have any locations yet") : L("You don't have any objects yet"))
            } else {
                Section(kind == .location ? L("One place per image") : L("Choose any")) {
                    ForEach(items) { element in
                        Toggle(element.name, isOn: Binding(get: { state.elementIDs.contains(element.id) }, set: { on in
                            if on { app.attach(element, to: state) } else { state.elementIDs.removeAll { $0 == element.id } }
                        }))
                    }
                }
            }
            Divider()
            Button(kind == .location ? L("New location…") : L("New object…"), systemImage: "plus") {
                app.charactersPage = kind.page
                app.selection = .characters
                app.creatingElement = kind
            }
        } label: {
            AddOnLabel(title: title, showsMenuIndicator: true) {
                Image(systemName: kind.systemImage)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(kind == .location ? L("A saved place, used as the setting of the image") : L("A saved object, shown just as it is"))
    }
}

struct ComposerPromptField<Accessory: View>: View {
    @Binding var text: String
    var placeholder: String
    var limit: Int
    var focusToken = 0
    var onSubmit: () -> Void = {}
    @ViewBuilder var accessory: () -> Accessory

    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineLimit(2...7)
                .focused($focused)
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    onSubmit()
                    return .handled
                }
                .characterLimit($text, limit)
                .frame(maxWidth: .infinity, alignment: .leading)
            accessory()
        }
        .onAppear { focused = true }
        .onChange(of: focusToken) { focused = true }
        .boxedField(isFocused: focused) { focused = true }
    }
}

struct AddOnLabel<Icon: View>: View {
    let title: String
    var showsMenuIndicator = false
    @ViewBuilder var icon: () -> Icon

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 5) {
            icon()
                .foregroundStyle(Color.appAccent)
            Text(title)
                .foregroundStyle(.primary)
            if showsMenuIndicator {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .background(Color.primary.opacity(isHovered ? 0.07 : 0), in: .capsule)
        .contentShape(.capsule)
        .onHover { isHovered = $0 }
        .animation(Motion.fade, value: isHovered)
    }
}

struct AttachmentChip: View {
    let title: String
    let systemImage: String
    var thumbnail: URL?
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if let thumbnail {
                ThumbnailImage(url: thumbnail, maxPixel: 120)
                    .frame(width: 26, height: 26)
                    .clipShape(.rect(cornerRadius: Radius.thumb))
            } else {
                Image(systemName: systemImage)
            }
            Text(title).font(.callout.weight(.medium)).lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L("Remove"))
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.6), in: .capsule)
    }
}

struct ProductMenu: View {
    @Binding var selection: UUID?
    var placeholder = L("Product")
    var isAddOn = false
    @Environment(AppModel.self) private var app
    @AppStorage("lastProductID") private var lastProductID = ""

    var body: some View {
        if isAddOn {
            menu {
                AddOnLabel(title: app.library.product(selection)?.name ?? placeholder, showsMenuIndicator: true) {
                    Image(systemName: "shippingbox")
                }
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L("A saved product, kept faithful in the image"))
        } else {
            menu {
                Label(app.library.product(selection)?.name ?? placeholder, systemImage: "shippingbox")
                    .lineLimit(1)
            }
            .buttonStyle(.glass)
            .fixedSize()
            .help(L("A saved product, kept faithful in the image"))
        }
    }

    private func menu<MenuLabel: View>(@ViewBuilder label: () -> MenuLabel) -> some View {
        Menu {
            if app.library.products.isEmpty {
                Text(L("You don't have any products yet"))
            }
            Picker(L("Product"), selection: Binding(get: { selection }, set: { picked in
                selection = picked
                if let picked { lastProductID = picked.uuidString }
            })) {
                Text(L("None")).tag(UUID?.none)
                ForEach(app.library.products) { product in
                    Text(product.name).tag(UUID?.some(product.id))
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button(L("New product…"), systemImage: "plus") {
                app.selection = .products
                app.creatingProduct = true
            }
        } label: {
            label()
        }
        .menuStyle(.button)
    }
}

@MainActor enum CharacterFace {
    private static var cache: [String: NSImage] = [:]

    static func image(for character: Character, in library: Library) -> NSImage? {
        let names = character.photoFileNames
        guard !names.isEmpty else { return nil }
        let name = names[min(max(0, character.coverIndex), names.count - 1)]
        if let cached = cache[name] { return cached }
        guard let source = CGImageSourceCreateWithURL(library.characterPhotoURL(name) as CFURL, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                         kCGImageSourceCreateThumbnailWithTransform: true,
                                                                         kCGImageSourceThumbnailMaxPixelSize: 64] as CFDictionary)
        else { return nil }
        let side = CGFloat(min(thumb.width, thumb.height))
        let crop = thumb.cropping(to: CGRect(x: (CGFloat(thumb.width) - side) / 2, y: (CGFloat(thumb.height) - side) / 2, width: side, height: side)) ?? thumb
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSBezierPath(ovalIn: rect).addClip()
            NSGraphicsContext.current?.cgContext.draw(crop, in: rect)
            return true
        }
        cache[name] = image
        return image
    }
}

struct CharacterMenu: View {
    @Binding var selection: UUID?
    var placeholder = L("Character")
    var fillsWidth = false
    var isAddOn = false
    @Environment(AppModel.self) private var app
    @AppStorage("lastCharacterID") private var lastCharacterID = ""

    var body: some View {
        if isAddOn {
            menu {
                AddOnLabel(title: app.library.character(selection)?.name ?? placeholder, showsMenuIndicator: true) {
                    if let character = app.library.character(selection), let face = CharacterFace.image(for: character, in: app.library) {
                        Image(nsImage: face).resizable().scaledToFill().frame(width: 18, height: 18).clipShape(.circle)
                    } else {
                        Image(systemName: "person.crop.square")
                    }
                }
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L("Character with a consistent face"))
        } else if fillsWidth {
            menu {
                HStack(spacing: 6) {
                    label
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .glassEffect(.regular.interactive(), in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .frame(maxWidth: .infinity)
            .help(L("Character with a consistent face"))
        } else {
            menu { label }
                .buttonStyle(.glass)
                .fixedSize()
                .help(L("Character with a consistent face"))
        }
    }

    private func menu<MenuLabel: View>(@ViewBuilder label: () -> MenuLabel) -> some View {
        Menu {
            if app.library.characters.isEmpty {
                Text(L("You don't have any characters yet"))
            }
            Picker(L("Character"), selection: Binding(get: { selection }, set: { picked in
                selection = picked
                if let picked { lastCharacterID = picked.uuidString }
            })) {
                Text(L("None")).tag(UUID?.none)
                ForEach(app.library.characters) { character in
                    Label {
                        Text(character.name)
                    } icon: {
                        if let face = CharacterFace.image(for: character, in: app.library) { Image(nsImage: face) }
                    }
                    .tag(UUID?.some(character.id))
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button(L("New character…"), systemImage: "plus") {
                app.selection = .characters
                app.creatingCharacter = true
            }
        } label: {
            label()
        }
        .menuStyle(.button)
    }

    @ViewBuilder private var label: some View {
        if let character = app.library.character(selection), let face = CharacterFace.image(for: character, in: app.library) {
            Label {
                Text(character.name).lineLimit(1)
            } icon: {
                Image(nsImage: face).resizable().scaledToFill().frame(width: 18, height: 18).clipShape(.circle)
            }
        } else {
            Label(app.library.character(selection)?.name ?? placeholder, systemImage: "person.crop.square")
                .lineLimit(1)
        }
    }
}

struct CreateMoreOptions: View {
    @Bindable var state: ComposerState
    let model: ImageModel?
    let requirement: ModelRequirement

    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PanelSection(title: L("Camera and color"), systemImage: "camera") {
                FlowLayout(spacing: 8) {
                    CameraMenu(state: state)
                    PaletteMenu(state: state)
                }
            }
            if let model, model.resolutions.count > 1 || !model.qualities.isEmpty {
                PanelSection(title: L("Size and quality"), systemImage: "square.resize") {
                    FlowLayout(spacing: 8) {
                        if model.resolutions.count > 1 { ResolutionMenu(selection: $state.resolution, available: model.resolutions) }
                        if !model.qualities.isEmpty { QualityMenu(selection: $state.quality, available: model.qualities) }
                    }
                }
            }
            PanelSection(title: L("AI model"), systemImage: "cpu") {
                ModelPicker(selectionID: $state.modelID, current: model, requirement: requirement)
                if let model {
                    Text(app.catalog.choice(for: model).tagline)
                        .helperTextStyle()
                        .fixedSize(horizontal: false, vertical: true)
                }
                AutoEnhanceSwitch(style: .panel)
                    .padding(.top, 4)
            }
            if model?.supportsTransparency == true || model?.supportsSeed == true || model?.provider == .google {
                PanelSection(title: L("Extras"), systemImage: "plus.circle") {
                    if model?.supportsTransparency == true {
                        Toggle(L("Transparent background"), isOn: $state.transparentBackground)
                    }
                    if model?.supportsSeed == true || model?.provider == .google {
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                seedToggle
                                Spacer(minLength: 8)
                                newSeedButton
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                seedToggle
                                newSeedButton
                            }
                        }
                    }
                }
            }
        }
    }

    private var seedToggle: some View {
        Toggle(L("Fixed seed (%ld)", state.seed), isOn: $state.useSeed)
    }

    private var newSeedButton: some View {
        Button(L("New Random Seed"), systemImage: "dice") { state.seed = Int.random(in: 1...999_999) }
            .buttonStyle(.glass)
            .fixedSize()
    }
}

struct CameraMenu: View {
    @Bindable var state: ComposerState

    typealias Choice = (id: String, name: String, prompt: String)

    private static let namedBodies: Set<String> = ["red-v-raptor", "sony-venice", "arri-alexa-35", "panavision-dxl2"]
    private static let namedLenses: Set<String> = [
        "petzval", "jdc-xtal-xpress", "cooke-s4", "panavision-c-series", "lensbaby", "zeiss-ultra-prime", "helios",
        "arri-signature-prime", "canon-k35", "laowa-macro", "hawk-v-lite",
    ]

    static func isSet(_ state: ComposerState) -> Bool {
        [state.cameraBody, state.cameraLens, state.cameraFocalLength, state.cameraAperture].contains { $0 != "auto" }
    }

    static func title(for state: ComposerState) -> String {
        func name(_ choices: [Choice], _ id: String, short: Bool = false) -> String? {
            guard id != "auto", let name = choices.first(where: { $0.id == id })?.name else { return nil }
            return short ? name.components(separatedBy: " (")[0] : name
        }
        let parts = [name(CinemaCamera.bodies, state.cameraBody), name(CinemaCamera.lenses, state.cameraLens),
                     name(CinemaCamera.focalLengths, state.cameraFocalLength, short: true),
                     name(CinemaCamera.apertures, state.cameraAperture, short: true)].compactMap(\.self)
        if parts.isEmpty { return L("Camera") }
        return parts.count > 2 ? parts.prefix(2).joined(separator: " · ") + " · +\(parts.count - 2)" : parts.joined(separator: " · ")
    }

    var body: some View {
        ChipMenu(systemImage: "camera", title: Self.title(for: state), help: L("Cinema camera, lens, focal length and aperture")) {
            Picker(L("Camera"), selection: $state.cameraBody) {
                grouped(CinemaCamera.bodies, named: Self.namedBodies, looks: L("Film and digital looks"), models: L("Real camera models"))
            }
            .pickerStyle(.menu)
            Picker(L("Lens"), selection: $state.cameraLens) {
                grouped(CinemaCamera.lenses, named: Self.namedLenses, looks: L("Lens looks"), models: L("Real lens models"))
            }
            .pickerStyle(.menu)
            Picker(L("Focal length"), selection: $state.cameraFocalLength) {
                ForEach(CinemaCamera.focalLengths, id: \.id) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.menu)
            Picker(L("Aperture"), selection: $state.cameraAperture) {
                ForEach(CinemaCamera.apertures, id: \.id) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.menu)
            if Self.isSet(state) {
                Divider()
                Button(L("Reset Camera"), systemImage: "arrow.counterclockwise") {
                    state.cameraBody = "auto"
                    state.cameraLens = "auto"
                    state.cameraFocalLength = "auto"
                    state.cameraAperture = "auto"
                }
            }
        }
    }

    @ViewBuilder
    private func grouped(_ choices: [Choice], named: Set<String>, looks: String, models: String) -> some View {
        ForEach(choices.filter { $0.id == "auto" }, id: \.id) { Text($0.name).tag($0.id) }
        Section(looks) {
            ForEach(choices.filter { $0.id != "auto" && !named.contains($0.id) }, id: \.id) { Text($0.name).tag($0.id) }
        }
        Section(models) {
            ForEach(choices.filter { named.contains($0.id) }, id: \.id) { Text($0.name).tag($0.id) }
        }
    }
}

struct PaletteMenu: View {
    @Bindable var state: ComposerState

    var body: some View {
        Menu {
            Picker(L("Palette"), selection: $state.paletteID) {
                Text(L("No palette")).tag(String?.none)
                ForEach(ColorPalette.builtIn) { palette in
                    Label { Text(palette.name) } icon: { Image(nsImage: PaletteSwatch.image(palette.hexes)) }
                        .tag(String?.some(palette.id))
                }
                if !state.customPalette.isEmpty {
                    Label { Text(L("From your image")) } icon: { Image(nsImage: PaletteSwatch.image(state.customPalette)) }
                        .tag(String?.some("custom"))
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button(L("Extract from an image…"), systemImage: "eyedropper") {
                guard let data = ImageIntake.pick(multiple: false).first else { return }
                Task {
                    let hexes = await AppModel.extractPalette(data)
                    guard !hexes.isEmpty else { return }
                    state.customPalette = hexes
                    state.paletteID = "custom"
                }
            }
        } label: {
            HStack(spacing: 5) {
                if let palette = state.palette {
                    HStack(spacing: 0) {
                        ForEach(Array(palette.colors.enumerated()), id: \.offset) { _, color in
                            Rectangle().fill(color).frame(width: 6, height: 14)
                        }
                    }
                    .clipShape(.rect(cornerRadius: Radius.small))
                } else {
                    Image(systemName: "swatchpalette")
                }
                Text(state.palette?.name ?? L("Color")).lineLimit(1)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .fixedSize()
        .help(L("Color palette"))
    }
}

enum PaletteSwatch {
    static func image(_ hexes: [String]) -> NSImage {
        let width: CGFloat = 30, height: CGFloat = 12
        return NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let step = width / CGFloat(max(hexes.count, 1))
            for (index, hex) in hexes.enumerated() {
                NSColor(Color(hex: hex)).setFill()
                NSRect(x: CGFloat(index) * step, y: 0, width: step + 0.5, height: rect.height).fill()
            }
            return true
        }
    }
}
