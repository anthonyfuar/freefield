import FreefieldCore
import SwiftUI

struct ElementsSection: View {
    let kind: SceneElementKind
    @Environment(AppModel.self) private var app
    @State private var selectedID: UUID?
    @State private var confirmingDelete: SceneElement?

    var body: some View {
        let items = app.library.elements(of: kind)
        let selected = items.first { $0.id == selectedID }
        VStack(alignment: .leading, spacing: 18) {
            Text(kind == .location
                 ? L("Save a place once (a café, a beach, your shop) and use it as the setting of any image or video.")
                 : L("Save an object once (a guitar, a car, a lamp) and place it in any image or video, looking the same every time."))
                .helperTextStyle()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: PageLayout.textWidth, alignment: .leading)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 16)], spacing: 16) {
                Button {
                    app.creatingElement = kind
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "plus")
                            .iconSymbol(IconScale.hero)
                        Text(kind.newTitle).font(.headline)
                        Text(L("1 to 5 photos")).fineTextStyle()
                    }
                    .frame(maxWidth: .infinity, minHeight: 250)
                    .background(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.2, dash: [7, 6])))
                    .contentShape(.rect(cornerRadius: Radius.card))
                }
                .buttonStyle(CardButtonStyle())

                ForEach(items) { element in
                    Button {
                        selectedID = element.id
                    } label: {
                        ElementCard(element: element, isSelected: selectedID == element.id)
                    }
                    .buttonStyle(CardButtonStyle(shadow: false))
                    .contextMenu {
                        Menu(L("Use in…"), systemImage: "arrow.up.forward.app") { ElementUseItems(element: element) }
                        Button(L("Add Photos…"), systemImage: "photo.badge.plus") {
                            app.library.updateElement(element, addingPhotos: ImageIntake.pick(multiple: true))
                        }
                        .disabled(element.photoFileNames.count >= SceneElement.maxPhotos)
                        Divider()
                        Button(L("Delete"), systemImage: "trash", role: .destructive) { confirmingDelete = element }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 18) {
                if let element = selected {
                    ElementDetail(element: element)
                        .transition(Motion.transition(.opacity.combined(with: .offset(y: 12))))
                } else if !items.isEmpty {
                    Label(L("Click one to see its photos and what you made with it."), systemImage: "hand.point.up.left")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                PanelSection(title: L("Tips for Better Results"), systemImage: "lightbulb") {
                    VStack(alignment: .leading, spacing: 4) {
                        if kind == .location {
                            Text(L("• Use wide, sharp photos of the place, without people in front."))
                            Text(L("• Add 2–3 views from different sides so the AI understands the space."))
                        } else {
                            Text(L("• Photograph the object alone, on a plain background, well lit."))
                            Text(L("• Add photos from other sides so its shape stays faithful from any angle."))
                        }
                        Text(L("• In Create Image, type @ and its name in the description to add it quickly."))
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: PageLayout.textWidth, alignment: .leading)
                }
            }
            .animation(Motion.standard, value: selected == nil)
        }
        .confirmationDialog(L("Delete %@?", confirmingDelete?.name ?? ""), isPresented: Binding(get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } })) {
            Button(L("Delete"), role: .destructive) {
                if let element = confirmingDelete { app.library.deleteElement(element.id) }
                confirmingDelete = nil
            }
        } message: {
            Text(L("Its saved photos will be deleted. Images already generated are kept."))
        }
    }
}

struct ElementCard: View {
    let element: SceneElement
    var isSelected = false
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let cover = element.photoFileNames.first {
                    ThumbnailImage(url: app.library.elementPhotoURL(cover), maxPixel: 500,
                                   contentMode: element.kind == .prop ? .fit : .fill)
                        .padding(element.kind == .prop ? 8 : 0)
                } else {
                    Image(systemName: element.kind.systemImage).iconSymbol(IconScale.hero).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 210)
            .background(element.kind == .prop ? AnyShapeStyle(.white.opacity(0.92)) : AnyShapeStyle(.quaternary))
            .clipShape(.rect(cornerRadius: Radius.card))
            .overlay(alignment: .bottomTrailing) {
                Text(element.photoFileNames.count == 1 ? L("1 photo") : L("%ld photos", element.photoFileNames.count))
                    .fineTextStyle()
                    .fontWeight(.semibold)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .glassEffect(in: .capsule)
                    .padding(8)
            }
            .overlay(alignment: .topTrailing) {
                PhotoCornerMenu { ElementUseItems(element: element) }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(isSelected ? Color.appAccent : .clear, lineWidth: 3)
                    .animation(Motion.select, value: isSelected)
            }
            Text(element.name).font(.body.weight(.semibold)).lineLimit(1)
            if !element.details.isEmpty {
                Text(element.details).helperTextStyle().lineLimit(2)
            }
        }
        .contentShape(.rect)
        .help(L("Click to see details"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ElementDetail: View {
    let element: SceneElement
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
            if !element.details.isEmpty {
                Text(element.details).font(.callout).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(element.photoFileNames, id: \.self) { name in
                        ThumbnailImage(url: app.library.elementPhotoURL(name), maxPixel: 300,
                                       contentMode: element.kind == .prop ? .fit : .fill)
                            .frame(width: 150, height: 112)
                            .background(.white.opacity(element.kind == .prop ? 0.92 : 0), in: .rect(cornerRadius: Radius.tile))
                            .clipShape(.rect(cornerRadius: Radius.tile))
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: Radius.card))
    }

    private var title: some View {
        Label {
            Text(element.name).font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: element.kind.systemImage).foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack {
            Button(L("Add Photos"), systemImage: "photo.badge.plus") {
                app.library.updateElement(element, addingPhotos: ImageIntake.pick(multiple: true))
            }
            .buttonStyle(.glass)
            .fixedSize()
            .disabled(element.photoFileNames.count >= SceneElement.maxPhotos)
            Menu {
                ElementUseItems(element: element)
            } label: {
                Label(L("Use %@ in…", element.name), systemImage: "arrow.up.forward.app").prominentLabel()
            }
            .menuStyle(.button)
            .buttonStyle(.glassProminent)
            .tint(.brandFill)
            .fixedSize()
        }
    }
}

struct ElementUseItems: View {
    let element: SceneElement
    @Environment(AppModel.self) private var app

    var body: some View {
        Button(Tool.create.title, systemImage: Tool.create.systemImage) { app.use(element, in: .create) }
        Button(Tool.edit.title, systemImage: Tool.edit.systemImage) { app.use(element, in: .edit) }
        Divider()
        ForEach(AppModel.elementVideoTools, id: \.self) { id in
            if let tool = VideoCatalog.tool(id) {
                Button(tool.name, systemImage: tool.symbol) { app.use(element, inVideo: id) }
            }
        }
    }
}

struct ElementReferenceButton: View {
    @Binding var images: [Data]
    var limit: Int
    @Environment(AppModel.self) private var app

    var body: some View {
        if !app.library.elements.isEmpty {
            Menu {
                ForEach(SceneElementKind.allCases) { kind in
                    let items = app.library.elements(of: kind)
                    if !items.isEmpty {
                        Section(kind.title) {
                            ForEach(items) { element in
                                Button(element.name, systemImage: kind.systemImage) { add(element) }
                            }
                        }
                    }
                }
            } label: {
                Label(L("Add a Saved Location or Object"), systemImage: "mountain.2")
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .controlSize(.small)
            .fixedSize()
            .disabled(images.count >= limit)
            .help(L("Adds the photos of a location or object you saved in Characters"))
        }
    }

    private func add(_ element: SceneElement) {
        let photos = app.library.elementPhotoData(element).prefix(2)
        images = Array((images + photos).prefix(limit))
    }
}

struct NewElementSheet: View {
    let kind: SceneElementKind
    var onSave: ((SceneElement) -> Void)?
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var details = ""
    @State private var photos: [Data] = []

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ReferenceStrip(images: $photos, limit: SceneElement.maxPhotos, label: L("Photos"))
                    if photos.isEmpty {
                        Text(kind == .location ? L("Drag 1 to 5 photos of the place here, or click +.")
                                               : L("Drag 1 to 5 photos of the object here, or click +."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(L("Photos"))
                } footer: {
                    Text(L("Up to 2 are sent per generation. They're stored only on your Mac."))
                }
                Section {
                    TextField(L("Name"), text: $name,
                              prompt: Text(kind == .location ? L("e.g. Rooftop bar") : L("e.g. Red electric guitar")))
                        .characterLimit($name, 40)
                    TextField(L("Description (optional)"), text: $details,
                              prompt: Text(kind == .location ? L("e.g. rooftop terrace with string lights and a city view")
                                                             : L("e.g. cherry-red guitar with a white pickguard")),
                              axis: .vertical)
                        .lineLimit(2...3)
                        .characterLimit($details, 240)
                } footer: {
                    Text(L("Use the name in your descriptions, for example “dancing at the Rooftop bar”."))
                }
            }
            .formStyle(.grouped)
            .navigationTitle(kind.newTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save")) {
                        let element = app.library.addElement(kind: kind, name: trimmedName, details: details, photos: photos)
                        onSave?(element)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty || photos.isEmpty)
                }
            }
        }
        .frame(width: 520, height: 500)
    }
}
