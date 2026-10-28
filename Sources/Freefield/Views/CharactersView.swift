import FreefieldCore
import SwiftUI

struct CharactersView: View {
    @Environment(AppModel.self) private var app
    @State private var selectedID: UUID?
    @State private var confirmingDelete: Character?

    var body: some View {
        @Bindable var app = app
        let selected = app.library.characters.first { $0.id == selectedID }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: L("Characters"),
                           detail: L("Save the people, places and objects you use again and again, and add them to any image or video with one click."))
                Picker(L("Show"), selection: $app.charactersPage) {
                    ForEach(CharactersPage.tabs) { page in
                        Label(page.title, systemImage: page.systemImage).tag(page)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 460)
                .fixedSize(horizontal: false, vertical: true)
                if let kind = app.charactersPage.kind {
                    ElementsSection(kind: kind)
                } else {
                    people(selected: selected)
                }
            }
            .pageContainer()
        }
        .navigationTitle(L("Characters"))
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem {
                if let kind = app.charactersPage.kind {
                    Button(kind.newTitle, systemImage: "plus") { app.creatingElement = kind }
                } else {
                    Button(L("New Character"), systemImage: "plus") { app.creatingCharacter = true }
                }
            }
        }
        .sheet(isPresented: $app.creatingCharacter) {
            NewCharacterSheet()
        }
        .sheet(item: $app.creatingElement) { kind in
            NewElementSheet(kind: kind)
        }
        .confirmationDialog(L("Delete %@?", confirmingDelete?.name ?? ""), isPresented: Binding(get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } })) {
            Button(L("Delete"), role: .destructive) {
                if let character = confirmingDelete { app.library.deleteCharacter(character.id) }
                confirmingDelete = nil
            }
        } message: {
            Text(L("Their reference photos will be deleted. Images already generated are kept."))
        }
    }

    private var subtitle: String {
        if let kind = app.charactersPage.kind {
            let count = app.library.elements(of: kind).count
            return count == 0 ? "" : count == 1 ? L("1 saved") : L("%ld saved", count)
        }
        let count = app.library.characters.count
        return count == 0 ? "" : count == 1 ? L("1 character") : L("%ld characters", count)
    }

    @ViewBuilder
    private func people(selected: Character?) -> some View {
        Text(L("Upload several photos of a person and use them in any image, style or scene with a consistent face, with no training or waiting."))
            .helperTextStyle()
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: PageLayout.textWidth, alignment: .leading)
        if app.library.characters.isEmpty {
            Button { app.creatingCharacter = true } label: {
                Label(L("Create My First Character"), systemImage: "plus").prominentLabel()
            }
            .buttonStyle(.glassProminent)
            .tint(.brandFill)
            .controlSize(.large)
            .fixedSize()
        }

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 16)], spacing: 16) {
            Button {
                app.creatingCharacter = true
            } label: {
                VStack(spacing: 10) {
                    Image(systemName: "plus")
                        .iconSymbol(IconScale.hero)
                    Text(L("New Character")).font(.headline)
                    Text(L("1 to 10 photos")).fineTextStyle()
                }
                .frame(maxWidth: .infinity, minHeight: 250)
                .background(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.2, dash: [7, 6])))
                .contentShape(.rect(cornerRadius: Radius.card))
            }
            .buttonStyle(CardButtonStyle())

            Button {
                app.charactersPage = .builder
            } label: {
                VStack(spacing: 10) {
                    Image(systemName: "wand.and.sparkles")
                        .iconSymbol(IconScale.hero)
                        .foregroundStyle(Color.brand)
                    Text(L("Design a Character")).font(.headline)
                    Text(L("No photos needed")).fineTextStyle()
                }
                .frame(maxWidth: .infinity, minHeight: 250)
                .background(Color.brand.opacity(0.08), in: .rect(cornerRadius: Radius.card))
                .background(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Color.brand.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [7, 6])))
                .contentShape(.rect(cornerRadius: Radius.card))
            }
            .buttonStyle(CardButtonStyle())
            .help(L("Create an original person from simple choices, like age, hair and style"))

            ForEach(app.library.characters) { character in
                Button {
                    selectedID = character.id
                } label: {
                    CharacterCard(character: character, isSelected: selectedID == character.id)
                }
                .buttonStyle(CardButtonStyle(shadow: false))
                .contextMenu {
                    Menu(L("Use in…"), systemImage: "arrow.up.forward.app") { CharacterUseItems(character: character) }
                    Button(L("Add Photos…"), systemImage: "photo.badge.plus") {
                        app.library.updateCharacter(character, addingPhotos: ImageIntake.pick(multiple: true))
                    }
                    Divider()
                    Button(L("Delete"), systemImage: "trash", role: .destructive) { confirmingDelete = character }
                }
            }
        }

        VStack(alignment: .leading, spacing: 18) {
            if let character = selected {
                CharacterDetail(character: character)
                    .transition(Motion.transition(.opacity.combined(with: .offset(y: 12))))
            } else if !app.library.characters.isEmpty {
                Label(L("Click a character to see their photos and what you made with them."), systemImage: "hand.point.up.left")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            PanelSection(title: L("Tips for Better Results"), systemImage: "lightbulb") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("• Use sharp photos with the face well lit, from the front and in profile."))
                    Text(L("• Vary expressions and backgrounds; avoid sunglasses and filters."))
                    Text(L("• If the face doesn't look like them, try another AI model: some keep a face better than others."))
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: PageLayout.textWidth, alignment: .leading)
            }
        }
        .animation(Motion.standard, value: selected == nil)
    }
}

struct CharacterUseItems: View {
    let character: Character
    @Environment(AppModel.self) private var app

    var body: some View {
        ForEach(CharacterDestination.allCases) { destination in
            if destination.startsVideo { Divider() }
            Button(destination.title, systemImage: destination.systemImage) { app.use(character, in: destination) }
        }
    }
}

struct CharacterCard: View {
    let character: Character
    var isSelected = false
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let cover = character.photoFileNames.first {
                    ThumbnailImage(url: app.library.characterPhotoURL(cover), maxPixel: 500)
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(height: 210)
            .clipShape(.rect(cornerRadius: Radius.card))
            .overlay(alignment: .bottomTrailing) {
                Text(character.photoFileNames.count == 1 ? L("1 photo") : L("%ld photos", character.photoFileNames.count))
                    .fineTextStyle()
                    .fontWeight(.semibold)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .glassEffect(in: .capsule)
                    .padding(8)
            }
            .overlay(alignment: .topTrailing) {
                PhotoCornerMenu { CharacterUseItems(character: character) }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(isSelected ? Color.appAccent : .clear, lineWidth: 3)
                    .animation(Motion.select, value: isSelected)
            }
            Text(character.name).font(.body.weight(.semibold))
            if !character.details.isEmpty {
                Text(character.details).helperTextStyle().lineLimit(2)
            }
        }
        .contentShape(.rect)
        .help(L("Click to see details"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct PhotoCornerMenu<Items: View>: View {
    @ViewBuilder var items: () -> Items

    var body: some View {
        Menu {
            items()
        } label: {
            Label(L("Use in…"), systemImage: "arrow.up.forward.app")
                .labelStyle(.iconOnly)
                .foregroundStyle(.white)
        }
        .menuStyle(.button)
        .menuIndicator(.visible)
        .buttonStyle(.glass)
        .controlSize(.small)
        .fixedSize()
        .background(.black.opacity(0.45), in: .capsule)
        .help(L("Use in…"))
        .accessibilityLabel(L("Use in…"))
        .padding(8)
    }
}

struct CharacterDetail: View {
    let character: Character
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    title
                    Spacer()
                    actions
                }
                VStack(alignment: .leading, spacing: 8) {
                    title
                    actions
                }
            }
            if character.photoFileNames.count == 1 {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.rectangle.badge.plus")
                        .font(.title3.weight(IconScale.weight))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.brand)
                    Text(L("Add 2–3 more photos (other angles and expressions) for a closer likeness."))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button(L("Add Photos"), action: addPhotos)
                        .controlSize(.regular)
                        .fixedSize()
                }
                .padding(10)
                .background(Color.brand.opacity(0.1), in: .rect(cornerRadius: Radius.tile))
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(character.photoFileNames, id: \.self) { name in
                        ThumbnailImage(url: app.library.characterPhotoURL(name), maxPixel: 300)
                            .frame(width: 110, height: 140)
                            .clipShape(.rect(cornerRadius: Radius.tile))
                    }
                }
            }
            .scrollIndicators(.never)
            let made = app.library.assets.filter { $0.characterID == character.id }
            if !made.isEmpty {
                Text(L("Created with %@", character.name)).font(.headline).padding(.top, 6)
                JustifiedAssetGrid(assets: Array(made.prefix(24)), targetHeight: 160, spacing: 8) { asset, _ in
                    AssetCard(asset: asset, maxPixel: 480)
                        .onTapGesture(count: 2) { app.quickLook(asset) }
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: Radius.card))
    }

    private var title: some View {
        Text(character.name).font(.title2.bold())
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actions: some View {
        HStack {
            if character.designChoices != nil {
                Button(L("Change the Design"), systemImage: "wand.and.sparkles") {
                    CharacterDesign.shared.edit(character)
                    app.charactersPage = .builder
                }
                .buttonStyle(.glass)
                .fixedSize()
                .help(L("Opens the character designer with these choices, to make a new version"))
            } else {
                Button(L("Add Photos"), systemImage: "photo.badge.plus", action: addPhotos)
                    .buttonStyle(.glass)
                    .fixedSize()
            }
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
    }

    private func addPhotos() {
        app.library.updateCharacter(character, addingPhotos: ImageIntake.pick(multiple: true))
    }
}

struct NewCharacterSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var details = ""
    @State private var photos: [Data] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("Name"), text: $name, prompt: Text(L("e.g. Sophie")))
                        .characterLimit($name, 40)
                    TextField(L("Description (optional)"), text: $details, prompt: Text(L("e.g. 28-year-old woman, curly brown hair, freckles")), axis: .vertical)
                        .lineLimit(2...3)
                        .characterLimit($details, 240)
                } footer: {
                    Text(L("The description reinforces the identity when the model is unsure."))
                }
                Section {
                    ReferenceStrip(images: $photos, limit: 10, label: L("Photos"))
                    if photos.isEmpty {
                        Text(L("Drag 1 to 10 photos of the person here, or click +."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(L("Reference Photos"))
                } footer: {
                    Text(L("Up to 4 are used per generation. They're stored only on your Mac."))
                }
            }
            .formStyle(.grouped)
            .navigationTitle(L("New Character"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Create")) {
                        app.library.addCharacter(name: name.trimmingCharacters(in: .whitespaces), details: details, photos: photos)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || photos.isEmpty)
                }
            }
        }
        .frame(width: 520, height: 460)
    }
}
