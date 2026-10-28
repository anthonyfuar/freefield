import FreefieldCore
import SwiftUI

struct PresetCard: View {
    let preset: StylePreset
    var isSelected = false
    var size: CGFloat = 150
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                let url = preset.thumbnailURL
                if let url {
                    ThumbnailImage(url: url, maxPixel: Int(size * 2.4))
                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                } else {
                    IconPlaceholder(symbol: preset.symbol, size: size < 120 ? .medium : .large)
                }
                Text(preset.name)
                    .font(Self.captionFont(size))
                    .foregroundStyle(url == nil ? Color.primary : .white)
                    .lineLimit(3)
                    .padding(8)
            }
            .frame(width: size, height: size * 1.25)
            .clipShape(.rect(cornerRadius: Radius.tile))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.tile)
                    .strokeBorder(isSelected ? Color.appAccent : .white.opacity(0.08), lineWidth: isSelected ? 3 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.appAccent)
                        .font(.title3)
                        .padding(6)
                }
            }
        }
        .buttonStyle(CardButtonStyle(isCompact: size <= 160))
        .help(preset.summary)
    }

    static func captionFont(_ size: CGFloat) -> Font {
        size < 150 ? .callout.weight(.semibold) : .system(size: max(13, size * 0.085), weight: .semibold)
    }
}

struct StylesGallery: View {
    @Environment(AppModel.self) private var app
    @State private var category: String = StylePresets.allCategory
    @State private var search = ""
    @State private var creatingMoodboard = false
    @State private var previewingID: String?

    var body: some View {
        let presets = StylePresets.filtered(category: category, search: search)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: L("Styles"),
                           detail: L("Curated presets: apply a complete look — lighting, camera, color, and mood — in one click."))
                MoodboardRow(creating: $creatingMoodboard)

                Text(L("Presets")).sectionTitleStyle().padding(.top, 4)
                CategoryChips(categories: StylePresets.categoryNames, selection: $category)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14, alignment: .leading)], spacing: 14) {
                    ForEach(presets) { preset in
                        PresetCard(preset: preset, isSelected: app.composer(for: .create).presetID == preset.id, size: 160) {
                            previewingID = preset.id
                        }
                        .popover(isPresented: Binding(get: { previewingID == preset.id }, set: { if !$0 { previewingID = nil } }),
                                 arrowEdge: .trailing) {
                            PresetPreview(preset: preset) { tool in
                                previewingID = nil
                                use(preset, in: tool)
                            }
                        }
                    }
                }
                if presets.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .pageContainer()
        }
        .searchable(text: $search, placement: .toolbar, prompt: L("Search styles"))
        .navigationTitle(L("Styles"))
        .navigationSubtitle(L("%ld styles", StylePresets.all.count))
        .sheet(isPresented: $creatingMoodboard) { NewMoodboardSheet() }
    }

    private func use(_ preset: StylePreset, in tool: Tool) {
        let state = app.composer(for: tool)
        state.presetID = preset.id
        state.moodboardID = nil
        app.selection = .tool(tool)
    }
}

struct PresetPreview: View {
    let preset: StylePreset
    let onUse: (Tool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                if let url = preset.thumbnailURL {
                    ThumbnailImage(url: url, maxPixel: 800)
                } else {
                    IconPlaceholder(symbol: preset.symbol)
                }
            }
            .frame(width: 268, height: 335)
            .clipShape(.rect(cornerRadius: Radius.tile))

            VStack(alignment: .leading, spacing: 3) {
                Text(preset.name).font(.title3.bold())
                Text(preset.category).fineTextStyle()
            }
            Text(preset.summary)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                Button { onUse(.create) } label: {
                    Label(L("Use in Create Image"), systemImage: Tool.create.systemImage).frame(maxWidth: .infinity)
                        .prominentLabel()
                }
                .buttonStyle(.glassProminent)
                .tint(.brandFill)
                .keyboardShortcut(.defaultAction)
                Button { onUse(.storyboard) } label: {
                    Label(L("Use in Photo Story"), systemImage: Tool.storyboard.systemImage).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
        }
        .padding(16)
        .frame(width: 300)
    }
}

struct StylePicker: View {
    @Binding var selection: String?
    var moodboard: Binding<UUID?>? = nil
    var onDone: () -> Void

    @Environment(AppModel.self) private var app

    @State private var category: String = StylePresets.allCategory
    @State private var search = ""

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                TextField(L("Search styles"), text: $search)
                    .textFieldStyle(.roundedBorder)
                if selection != nil || moodboard?.wrappedValue != nil {
                    Button(L("No style")) {
                        selection = nil
                        moodboard?.wrappedValue = nil
                        onDone()
                    }
                }
            }
            if let moodboard, !app.library.moodboards.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(app.library.moodboards) { board in
                            MoodboardCard(board: board, isSelected: moodboard.wrappedValue == board.id, size: 86) {
                                moodboard.wrappedValue = board.id
                                selection = nil
                                onDone()
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.never)
                .padding(.vertical, -8)
            }
            CategoryChips(categories: StylePresets.categoryNames, selection: $category, compact: true)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 10)], spacing: 10) {
                    ForEach(StylePresets.filtered(category: category, search: search)) { preset in
                        PresetCard(preset: preset, isSelected: selection == preset.id, size: 112) {
                            selection = preset.id
                            moodboard?.wrappedValue = nil
                            onDone()
                        }
                    }
                }
                .padding(8)
            }
            .padding(-6)
        }
        .padding(14)
        .frame(width: 520, height: 520)
    }
}

struct CategoryChips: View {
    let categories: [String]
    @Binding var selection: String
    var compact = false

    @State private var isAtEnd = false

    var body: some View {
        if compact {
            ScrollView(.horizontal) {
                HStack(spacing: 6) { chips }
                    .padding(.vertical, 2)
            }
            .scrollIndicators(.never)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.x + geometry.containerSize.width >= geometry.contentSize.width - 1
            } action: { _, atEnd in
                isAtEnd = atEnd
            }
            .mask {
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .black.opacity(isAtEnd ? 1 : 0)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 28)
                }
            }
        } else {
            FlowLayout(spacing: 6) { chips }
        }
    }

    @ViewBuilder private var chips: some View {
        ForEach(categories, id: \.self) { name in
            Button {
                withAnimation(Motion.standard) { selection = name }
            } label: {
                Text(L(name))
                    .font(compact ? .subheadline.weight(.medium) : .callout.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, compact ? 10 : 12)
                    .padding(.vertical, compact ? 5 : 6)
                    .frame(minHeight: compact ? 26 : 30)
                    .foregroundStyle(selection == name ? Color.white : Color.primary)
                    .background(selection == name ? Color.appAccent : Color.primary.opacity(0.07), in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selection == name ? .isSelected : [])
        }
    }
}

struct MoodboardRow: View {
    @Binding var creating: Bool
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("My moodboards")).sectionTitleStyle()
                Text(L("Your own style, built from your images")).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    Button {
                        creating = true
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "plus").iconSymbol(IconScale.hero)
                            Text(L("Create moodboard")).font(.callout.weight(.medium))
                            Text(L("3 to 12 images, no faces")).fineTextStyle()
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 10)
                        }
                        .frame(width: 160, height: 200)
                        .background(RoundedRectangle(cornerRadius: Radius.tile).strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.2, dash: [7, 6])))
                        .contentShape(.rect(cornerRadius: Radius.tile))
                    }
                    .buttonStyle(CardButtonStyle(isCompact: true))
                    ForEach(app.library.moodboards) { board in
                        MoodboardCard(board: board, isSelected: app.composer(for: .create).moodboardID == board.id, size: 160) {
                            app.composer(for: .create).moodboardID = board.id
                            app.composer(for: .create).presetID = nil
                            app.selection = .tool(.create)
                        }
                        .contextMenu {
                            Button(L("Delete"), systemImage: "trash", role: .destructive) { app.library.deleteMoodboard(board.id) }
                        }
                    }
                }
                .padding(.vertical, 10)
            }
            .scrollIndicators(.never)
            .padding(.vertical, -8)
        }
    }
}

struct MoodboardCard: View {
    let board: Moodboard
    var isSelected = false
    var size: CGFloat = 150
    let action: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                mosaic(Array(board.imageFileNames.prefix(4)))
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Text(board.name).font(PresetCard.captionFont(size)).foregroundStyle(.white)
                    if board.styleDescription.isEmpty {
                        Text(L("Analyzing style…")).font(.subheadline).foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(8)
            }
            .frame(width: size, height: size * 1.25)
            .clipShape(.rect(cornerRadius: Radius.tile))
            .overlay(RoundedRectangle(cornerRadius: Radius.tile).strokeBorder(isSelected ? Color.appAccent : .clear, lineWidth: 3))
        }
        .buttonStyle(CardButtonStyle(isCompact: size <= 160))
        .help(board.styleDescription)
    }

    @ViewBuilder private func mosaic(_ names: [String]) -> some View {
        let width = size, height = size * 1.25
        switch names.count {
        case 0:
            Rectangle().fill(.quaternary).frame(width: width, height: height)
        case 1, 2:
            HStack(spacing: 2) {
                ForEach(names, id: \.self) { tile($0, width: (width - CGFloat(names.count - 1) * 2) / CGFloat(names.count), height: height) }
            }
        case 3:
            VStack(spacing: 2) {
                tile(names[0], width: width, height: height / 2 - 1)
                HStack(spacing: 2) {
                    tile(names[1], width: width / 2 - 1, height: height / 2 - 1)
                    tile(names[2], width: width / 2 - 1, height: height / 2 - 1)
                }
            }
        default:
            VStack(spacing: 2) {
                ForEach([0, 2], id: \.self) { row in
                    HStack(spacing: 2) {
                        tile(names[row], width: width / 2 - 1, height: height / 2 - 1)
                        tile(names[row + 1], width: width / 2 - 1, height: height / 2 - 1)
                    }
                }
            }
        }
    }

    private func tile(_ name: String, width: CGFloat, height: CGFloat) -> some View {
        ThumbnailImage(url: app.library.characterPhotoURL(name), maxPixel: 300)
            .frame(width: width, height: height)
            .clipped()
    }
}

struct NewMoodboardSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var images: [Data] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("Name"), text: $name, prompt: Text(L("E.g. Analog summer")))
                        .characterLimit($name, 40)
                }
                Section {
                    ReferenceStrip(images: $images, limit: 12, label: L("Images"))
                    if images.count < 3 {
                        Text(L("Add at least 3 images with a consistent look. Avoid faces: the moodboard defines the style, not the people."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                } header: {
                    Text(L("Reference images"))
                } footer: {
                    Text(L("Freefield analyzes the style once (color, lighting, texture, mood) and applies it to your generations along with 3 of these images."))
                }
            }
            .formStyle(.grouped)
            .navigationTitle(L("New moodboard"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Create")) {
                        let board = app.library.addMoodboard(name: name.trimmingCharacters(in: .whitespaces), images: images)
                        Task { await app.describeMoodboard(board) }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || images.count < 3)
                }
            }
        }
        .frame(width: 540, height: 440)
    }
}
