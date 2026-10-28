import AppKit
import AVFoundation
import FreefieldCore
import SwiftUI
import UniformTypeIdentifiers

enum VideoFrameMode {
    static var explanation: String {
        L("Recreates the clip from its first image instead of sharing it by link; the result is a new clip.")
    }

    static var details: String {
        L("Recreates the clip from its first frame and a description of its motion. Nothing is shared through a link, but a copy of the clip (at most 15 seconds, 720p) is sent once to a video-understanding model on OpenRouter (Gemini) to describe it. The result is a new clip, not an edit of the original.")
    }

    static func runsOn(_ model: VideoModel, in app: AppModel) -> String {
        L("Frame-based mode makes it with %@; the price includes the edited frame and the motion description.",
          app.catalog.videoChoice(for: model).displayName)
    }
}

enum VideoPromptBudget {
    static func modelLimit(_ model: VideoModel?) -> Int {
        guard let model else { return 2_000 }
        let slug = model.id.lowercased()
        switch VideoFamily(slug: slug) {
        case .kling: return 2_500
        case .wan: return slug.contains("wan-2.6") ? 1_500 : 5_000
        case .hailuo: return slug.contains("hailuo-3") ? 7_000 : 2_000
        default: return 2_000
        }
    }

    static func userLimit(model: VideoModel?, overhead: Int, cap: Int = PromptBudget.interfaceCap) -> Int {
        max(PromptBudget.minimum, min(cap, modelLimit(model) - overhead - 40))
    }
}

enum VideoCostLabel {
    static func price(_ cost: Double) -> String {
        GenerateButton.format(cost).replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    static func summary(cost: Double?, seconds: Double?, resolution: String?) -> String {
        var parts: [String] = []
        if let cost { parts.append(GenerateButton.format(cost)) }
        if let seconds { parts.append(L("%ld s", Int(seconds.rounded()))) }
        if let resolution, !resolution.isEmpty { parts.append(resolution) }
        return parts.joined(separator: " · ")
    }
}

struct VideoModelPicker: View {
    @Binding var selectionID: String?
    let current: VideoModel?
    let featured: [VideoModelChoice]
    let others: [VideoModelChoice]
    var summary: (VideoModel) -> String? = { _ in nil }
    var showsEnhance = true

    @Environment(AppModel.self) private var app
    @State private var isPresented = false
    @State private var search = ""

    var body: some View {
        FlowLayout(spacing: 8) {
            Button {
                isPresented.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: current == nil && lockedReason != nil ? "lock" : "film")
                    Text(title).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.glass)
            .fixedSize()
            .help(L("Video model"))
            .popover(isPresented: $isPresented, arrowEdge: .top) { popover }
            if showsEnhance, improvesDescription {
                AutoEnhanceSwitch(style: .chip)
            }
        }
    }

    private var title: String {
        if let current { return app.catalog.videoChoice(for: current).displayName }
        if app.catalog.loadingVideoModels { return L("Loading…") }
        return lockedReason ?? L("Choose Model")
    }

    private var lockedReason: String? {
        guard !featured.contains(where: \.isSelectable), !others.contains(where: \.isSelectable) else { return nil }
        return featured.first { !$0.isSelectable }?.lockedReason
    }

    private var improvesDescription: Bool {
        guard case .video(let id) = app.selection, let tool = VideoCatalog.tool(id) else { return false }
        return AppModel.enhancesDescription(of: tool)
    }

    private var popover: some View {
        let matches: (VideoModelChoice) -> Bool = { choice in
            search.isEmpty || choice.displayName.localizedCaseInsensitiveContains(search)
                || choice.model.vendor.localizedCaseInsensitiveContains(search) || choice.model.id.localizedCaseInsensitiveContains(search)
        }
        let shownFeatured = featured.filter(matches)
        let shownOthers = others.filter(matches)
        return VStack(spacing: 0) {
            TextField(L("Search models"), text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(12)
            Divider()
            if featured.isEmpty && others.isEmpty {
                ContentUnavailableView {
                    Label(app.hasAnyKey ? L("No Models") : L("No API Key"), systemImage: "film")
                } description: {
                    Text(app.hasAnyKey ? (app.catalog.videoError ?? L("No video model can do this with the inputs you added."))
                         : GenerationEngine.videoKeyMessage)
                } actions: {
                    if !app.hasAnyKey { SettingsLink { Text(L("Open Settings")) } }
                }
                .frame(height: 240)
            } else {
                let curated = shownFeatured.sorted { Self.lineupOrder($0) < Self.lineupOrder($1) }
                List {
                    if !curated.isEmpty {
                        Section(L("Featured")) {
                            ForEach(curated) { choice in
                                if choice.isSelectable {
                                    row(choice)
                                } else {
                                    LockedModelRow(name: choice.displayName, tagline: choice.tagline, provider: choice.model.host)
                                }
                            }
                        }
                    }
                    if !shownOthers.isEmpty {
                        Section(L("More Models")) { ForEach(shownOthers) { row($0) } }
                    }
                    if featured.contains(where: { !$0.isSelectable }) {
                        SettingsLink {
                            Label(L("Add a key in Settings to use the dimmed models"), systemImage: "key")
                                .font(.callout)
                        }
                        .buttonStyle(.link)
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 460, height: 540)
    }

    private static func lineupOrder(_ choice: VideoModelChoice) -> Int {
        VideoLineup.models.firstIndex { $0.id == choice.model.id } ?? Int.max
    }

    private func row(_ choice: VideoModelChoice) -> some View {
        let model = choice.model
        let isSelected = current?.id == model.id
        return Button {
            selectionID = model.id
            isPresented = false
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.appAccent : .secondary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(choice.displayName).font(.body.weight(.semibold)).lineLimit(1).layoutPriority(1)
                        if model.isBusy == true || app.catalog.strained.contains(model.id) {
                            badge(L("Busy now"), color: .orange)
                        }
                        if let text = choice.badge { badge(text, color: .brand) }
                    }
                    Text(choice.tagline).helperTextStyle().lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    FlowLayout(spacing: 10) {
                        Text(model.host == .google ? Self.googleHost(vendor: model.vendor) : model.vendor)
                        if let first = model.durations.first, let last = model.durations.last {
                            Label(first == last ? L("%ld s", first) : L("%ld–%ld s", first, last), systemImage: "timer")
                        }
                        if let top = model.resolutions.max(by: { VideoModel.rank(of: $0) < VideoModel.rank(of: $1) }) {
                            Label(top, systemImage: "square.resize")
                        }
                        if VideoModelTraits(model).makesSound { Label(L("Sound"), systemImage: "speaker.wave.2") }
                        if model.supportsFirstFrame { Label(L("Frames"), systemImage: "photo") }
                        if model.acceptsVideoInput { Label(L("Video in"), systemImage: "film") }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let line = summary(model), !line.isEmpty {
                    Text(line)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize()
                        .help(L("Approximate cost of one clip with these settings"))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
            .fixedSize()
    }

    private static func googleHost(vendor: String) -> String {
        let host = Provider.google.displayName
        return vendor.isEmpty || host.localizedCaseInsensitiveContains(vendor) ? host : "\(vendor) · \(host)"
    }
}

struct DurationMenu: View {
    @Binding var selection: Int?
    let available: [Int]
    var sent: Double?

    var body: some View {
        let chosen = Self.snapped(selection, in: available)
        let actual = sent.map { Int($0.rounded()) }
        let forced = selection != nil && actual != nil && actual != chosen
        let value = actual ?? chosen
        ChipMenu(systemImage: "timer", title: value.map { L("%ld s", $0) } ?? L("Auto"),
                 help: forced ? L("This model makes %ld-second clips with these settings.", actual ?? 0) : L("Clip length")) {
            Picker(L("Length"), selection: Binding(get: { chosen ?? available.first ?? 5 }, set: { selection = $0 })) {
                ForEach(available, id: \.self) { seconds in
                    Text(L("%ld seconds", seconds)).tag(seconds)
                }
            }
            .pickerStyle(.inline)
        }
        .disabled(forced)
    }

    static func snapped(_ seconds: Int?, in available: [Int]) -> Int? {
        guard !available.isEmpty else { return seconds }
        guard let seconds else { return available.contains(5) ? 5 : available.first }
        return available.min { a, b in
            let da = abs(a - seconds), db = abs(b - seconds)
            return da == db ? a > b : da < db
        }
    }
}

struct VideoResolutionMenu: View {
    @Binding var selection: String?
    let options: [VideoSizeOption]
    let current: VideoModel
    var followsClip: String?
    var releasesModel: () -> Void = {}

    @Environment(AppModel.self) private var app
    private static let clip = "clip"

    var body: some View {
        let supported = current.resolutions.sorted { VideoModel.rank(of: $0) < VideoModel.rank(of: $1) }
        let value = selection.map { Self.effective($0, available: supported) } ?? (followsClip == nil ? supported.first ?? "" : Self.clip)
        let clipSize = followsClip ?? ""
        let title = value != Self.clip ? L("Size: %@", value) : clipSize.isEmpty ? L("Size: like the clip") : L("Size: %@ (like the clip)", clipSize)
        ChipMenu(systemImage: "square.resize", title: title, help: L("Video resolution (affects cost)")) {
            Picker(L("Resolution"), selection: Binding(get: { value }, set: { picked in
                if picked != Self.clip, let option = options.first(where: { $0.size == picked }), option.model.id != current.id {
                    releasesModel()
                }
                selection = picked == Self.clip ? nil : picked
            })) {
                if let followsClip {
                    Text(followsClip.isEmpty ? L("Like the clip") : L("Like the clip (%@)", followsClip)).tag(Self.clip)
                    Divider()
                }
                ForEach(options, id: \.size) { option in
                    Text(label(for: option)).tag(option.size)
                }
            }
            .pickerStyle(.inline)
        }
    }

    private func label(for option: VideoSizeOption) -> String {
        var parts = [option.size, Self.detail(option.size)]
        if let cost = option.cost { parts.append(GenerateButton.format(cost)) }
        if option.model.id != current.id {
            parts.append(L("with %@", app.catalog.videoChoice(for: option.model).displayName))
        }
        return parts.joined(separator: "  ·  ")
    }

    static func effective(_ selection: String?, available: [String]) -> String {
        selection.map { wanted in
            available.first { $0.caseInsensitiveCompare(wanted) == .orderedSame }
                ?? available.last { VideoModel.rank(of: $0) < VideoModel.rank(of: wanted) }
        }.flatMap { $0 } ?? available.first ?? ""
    }

    static func detail(_ resolution: String) -> String {
        switch VideoModel.rank(of: resolution) {
        case ..<720: L("Draft")
        case ..<1080: L("Standard")
        case ..<1440: L("Full HD")
        case ..<2160: L("Very sharp")
        default: L("Most detail")
        }
    }
}

struct VideoAspectMenu: View {
    @Binding var selection: String?
    let available: [String]
    var allowsAuto = true

    private static let auto = "auto"

    var body: some View {
        let value = selection.flatMap { Self.nearest($0, in: available) } ?? (allowsAuto ? Self.auto : available.first ?? Self.auto)
        ChipMenu(systemImage: "aspectratio", title: value == Self.auto ? L("Shape: auto") : L("Shape: %@", value), help: L("Video aspect ratio")) {
            Picker(L("Aspect Ratio"), selection: Binding(get: { value }, set: { selection = $0 == Self.auto ? nil : $0 })) {
                if allowsAuto {
                    Label { Text(L("Auto · follows the image or clip")) } icon: { Image(nsImage: VideoAspectGlyph.image(nil)) }
                        .tag(Self.auto)
                }
                ForEach(available, id: \.self) { ratio in
                    Label { Text(Self.uses[ratio].map { "\(ratio)  ·  \($0)" } ?? ratio) } icon: {
                        Image(nsImage: VideoAspectGlyph.image(VideoModel.ratioValue(ratio)))
                    }
                    .tag(ratio)
                }
            }
            .pickerStyle(.inline)
        }
    }

    static let uses: [String: String] = [
        "9:16": L("Vertical: TikTok, Reels, Shorts"), "1:1": L("Square: social posts"), "4:5": L("Portrait: Instagram posts"),
        "3:4": L("Vertical photo"), "4:3": L("Classic TV"), "16:9": L("Wide: YouTube, TV"), "21:9": L("Cinema"),
        "9:21": L("Tall banner"), "3:2": L("Classic photo"), "2:3": L("Poster"),
    ]
}

extension VideoAspectMenu {
    static func nearest(_ ratio: String, in available: [String]) -> String? {
        if available.contains(ratio) { return ratio }
        guard let wanted = VideoModel.ratioValue(ratio) else { return nil }
        return available.min { a, b in
            abs(log((VideoModel.ratioValue(a) ?? 1) / wanted)) < abs(log((VideoModel.ratioValue(b) ?? 1) / wanted))
        }
    }
}

enum VideoAspectGlyph {
    static func image(_ ratio: Double?) -> NSImage {
        let size: CGFloat = 16
        let value = CGFloat(ratio ?? 1)
        let width = value >= 1 ? size - 2 : (size - 2) * value
        let height = value >= 1 ? (size - 2) / value : size - 2
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let rect = NSRect(x: (size - width) / 2, y: (size - height) / 2, width: width, height: height)
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.7, dy: 0.7), xRadius: 2, yRadius: 2)
            path.lineWidth = 1.4
            if ratio == nil { path.setLineDash([2, 2], count: 2, phase: 0) }
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct AudioToggle: View {
    @Binding var isOn: Bool
    var isAvailable = true
    var isAlwaysOn = false

    var body: some View {
        if isAlwaysOn || !isAvailable {
            Label(isAlwaysOn ? L("With sound") : L("No sound"), systemImage: isAlwaysOn ? "speaker.wave.2.fill" : "speaker.slash")
                .labelStyle(.titleAndIcon)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .help(isAlwaysOn ? L("This model always makes sound") : L("This model makes silent clips"))
        } else {
            Button {
                isOn.toggle()
            } label: {
                Label(isOn ? L("Sound") : L("No sound"), systemImage: isOn ? "speaker.wave.2.fill" : "speaker.slash")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.glass)
            .fixedSize()
            .help(L("Make sound with the clip (dialogue, effects, ambience)"))
        }
    }
}

struct SpokenLanguageMenu: View {
    let tool: VideoTool
    let state: VideoState
    let inputs: VideoToolInputs
    var labeled = true

    var body: some View {
        if let group = tool.group("language") {
            let effective = tool.choice(group.id, in: inputs.choices)
            let shown = state.languageIsPicked ? L(effective) : L("Auto (%@)", L(effective))
            ChipMenu(systemImage: "globe", title: labeled ? "\(group.title): \(shown)" : shown,
                     help: L("The language the people in the clip speak. Auto follows the words you type.")) {
                Picker(group.title, selection: Binding(get: { state.languageIsPicked ? effective : "" }, set: { value in
                    if value.isEmpty {
                        state.languageIsPicked = false
                    } else {
                        state.choices[group.id] = value
                        state.languageIsPicked = true
                    }
                })) {
                    Text(L("Auto (from the words you type)")).tag("")
                    Divider()
                    ForEach(group.values, id: \.self) { Text(L($0)).tag($0) }
                }
                .pickerStyle(.inline)
            }
        }
    }
}

struct BatchMenu: View {
    @Binding var count: Int
    var maximum = 4

    var body: some View {
        ChipMenu(systemImage: "square.stack", title: count == 1 ? L("1 clip") : L("%ld clips", count), help: L("How many clips to make")) {
            Picker(L("Clips"), selection: $count) {
                ForEach(1...maximum, id: \.self) { value in
                    Text(value == 1 ? L("1 clip") : L("%ld clips", value)).tag(value)
                }
            }
            .pickerStyle(.inline)
        }
    }
}

struct FramePicker: View {
    @Binding var first: Data?
    var last: Binding<Data?>?
    var firstTitle = L("Start image")
    var firstHint = L("The clip starts exactly on this image")
    var lastTitle = L("End image")
    var lastHint = L("The clip ends exactly on this image")
    var height: CGFloat = 220
    var sources: WellSources?
    var maxWellWidth: CGFloat = 340

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            frameWell(title: firstTitle, hint: firstHint, data: $first, symbol: "photo")
            if let last {
                Image(systemName: "arrow.right").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.top, height / 2 - 10)
                frameWell(title: lastTitle, hint: lastHint, data: last, symbol: "photo.badge.checkmark")
            }
        }
    }

    private func frameWell(title: String, hint: String, data: Binding<Data?>, symbol: String) -> some View {
        AdaptiveImageWell(title: title, subtitle: hint, systemImage: symbol, data: data, minHeight: height - 30, sources: sources)
            .frame(height: height)
            .frame(maxWidth: maxWellWidth)
    }
}

struct AdaptiveImageWell: View {
    let title: String
    var subtitle = L("Drag, paste (⌘V), or click to choose")
    var systemImage = "photo.badge.plus"
    @Binding var data: Data?
    var minHeight: CGFloat = 180
    var sources: WellSources?

    var body: some View {
        ImageWell(title: title, subtitle: subtitle, systemImage: systemImage, data: $data, minHeight: minHeight,
                  sources: sources ?? [.library, .products, .characters])
    }
}

struct VideoCharacterSection: View {
    let title: String
    let symbol: String
    var step: Int?
    var isDone = false
    var isOptional = false
    let hint: String
    @Binding var characterID: UUID?
    @Binding var photo: Data?
    var isPhotoreal = false
    var height: CGFloat = 170

    @Environment(AppModel.self) private var app

    var body: some View {
        PanelSection(title: title, systemImage: symbol,
                     trailing: AnyView(CharacterMenu(selection: $characterID, placeholder: L("Characters"))),
                     step: step, isDone: isDone, isOptional: isOptional) {
            VStack(alignment: .leading, spacing: 8) {
                if let character = app.library.character(characterID) {
                    chosen(character)
                } else {
                    ImageWell(title: L("Or a photo of the person"), subtitle: hint, systemImage: "person.crop.square",
                              data: $photo, minHeight: height - 20, sources: [.library])
                        .frame(height: height)
                }
                if isPhotoreal {
                    Label(L("A real person: Freefield makes a still of them first on some models."), systemImage: "person.fill.viewfinder")
                        .helperTextStyle()
                        .fixedSize(horizontal: false, vertical: true)
                        .help(L("A real person: on Seedance, Freefield makes a still of them first."))
                }
            }
        }
    }

    private func chosen(_ character: Character) -> some View {
        let names = character.photoFileNames
        return ZStack {
            Color.primary.opacity(0.04)
            if !names.isEmpty {
                ThumbnailImage(url: app.library.characterPhotoURL(names[min(max(0, character.coverIndex), names.count - 1)]),
                               maxPixel: 600, contentMode: .fit)
            } else {
                Image(systemName: "person.crop.square").iconSymbol(IconScale.hero).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(.rect(cornerRadius: Radius.card))
        .overlay(alignment: .topTrailing) {
            Button {
                withAnimation(Motion.standard) { characterID = nil }
            } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold)).frame(width: 22, height: 22)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help(L("Use a photo instead"))
            .padding(8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(character.name)
    }
}

struct CompactImageWell: View {
    @Binding var data: Data?
    var title = L("Add image")

    @Environment(AppModel.self) private var app
    @State private var isTargeted = false
    @State private var dragEntries = 0
    @State private var isHovering = false
    @State private var showingLibrary = false

    var body: some View {
        ZStack {
            if let data {
                DataImage(data: data, maxPixel: 400, contentMode: .fill)
                    .clipShape(.rect(cornerRadius: Radius.tile))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            set(nil)
                        } label: {
                            Image(systemName: "xmark").font(.caption2.weight(.bold)).frame(width: 16, height: 16)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.small)
                        .help(L("Remove image"))
                        .padding(5)
                    }
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "photo.badge.plus")
                        .font(.title3)
                        .symbolEffect(.bounce, value: dragEntries)
                    Text(title).font(.subheadline.weight(.medium))
                }
                .foregroundStyle(isTargeted ? Color.appAccent : .secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: Radius.tile)
                        .fill(isTargeted ? Color.appAccent.opacity(0.10) : Color.primary.opacity(isHovering ? 0.05 : 0.03))
                    RoundedRectangle(cornerRadius: Radius.tile)
                        .strokeBorder(isTargeted ? Color.appAccent : Color.secondary.opacity(isHovering ? 0.6 : 0.35),
                                      style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: isTargeted ? [] : [5, 4]))
                }
                .animation(Motion.select, value: isHovering)
                .overlay(alignment: .bottomTrailing) {
                    Menu { sourceItems } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.button)
                        .menuIndicator(.hidden)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.small)
                        .fixedSize()
                        .help(L("More places to pick an image from"))
                        .padding(7)
                }
            }
        }
        .animation(Motion.standard, value: isTargeted)
        .contentShape(.rect(cornerRadius: Radius.tile))
        .onHover { isHovering = $0 }
        .onTapGesture { if data == nil { choose() } }
        .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { providers in
            Task {
                if let first = await ImageIntake.data(from: providers).first { set(first) }
            }
            return true
        }
        .onChange(of: isTargeted) { _, targeted in
            if targeted { dragEntries += 1 }
        }
        .onPasteCommand(of: [.fileURL, .image]) { providers in
            Task {
                if let first = await ImageIntake.data(from: providers).first { set(first) }
            }
        }
        .contextMenu {
            sourceItems
            if data != nil {
                Divider()
                Button(L("Remove"), systemImage: "trash", role: .destructive) { set(nil) }
            }
        }
        .sheet(isPresented: $showingLibrary) {
            LibraryPicker(multiple: false) { picked in set(picked.first) }
                .environment(app)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(data == nil ? title : L("Image"))
        .accessibilityAction(named: L("Choose File…"), choose)
    }

    @ViewBuilder private var sourceItems: some View {
        Button(L("Choose File…"), systemImage: "folder") { choose() }
        Button(L("Choose from Library…"), systemImage: "photo.on.rectangle") { showingLibrary = true }
        if !app.library.characters.isEmpty {
            Menu(L("Characters"), systemImage: "person.crop.square") {
                ForEach(app.library.characters) { character in
                    Button(character.name) {
                        if let photo = app.library.coverPhotoData(character) { set(photo) }
                    }
                }
            }
        }
        if !app.library.products.isEmpty {
            Menu(L("Products"), systemImage: "shippingbox") {
                ForEach(app.library.products) { product in
                    Button(product.name) {
                        if let hero = app.library.productPhotoData(product).first { set(hero) }
                    }
                }
            }
        }
        Button(L("Paste Image"), systemImage: "doc.on.clipboard") {
            if let first = ImageIntake.pasteboardImages().first { set(first) }
        }
    }

    private func choose() {
        if let first = ImageIntake.pick(multiple: false).first { set(first) }
    }

    private func set(_ image: Data?) {
        withAnimation(Motion.standard) { data = image }
    }
}

struct VideoSourceWell: View {
    @Binding var pick: VideoClipPick
    var title = L("Clip")
    var hint = L("A clip from your library or a file")
    var showsSharingNote = true
    var height: CGFloat = 210
    var showsRecents = true
    var showsTitle = true

    @Environment(AppModel.self) private var app
    @State private var choosing = false
    @State private var pasting = false
    @State private var importing = false
    @State private var isTargeted = false
    @State private var dragEntries = 0
    @State private var isHovering = false

    var body: some View {
        let asset = pick.assetID.flatMap(app.library.asset)
        let boxHeight = asset == nil && pick.trimmedLink.isEmpty ? min(height, Self.emptyHeight) : height
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let asset {
                    VideoTile(url: app.library.url(for: asset), posterURL: app.library.posterURL(for: asset),
                              duration: asset.duration, hasAudio: asset.hasAudio, maxPixel: 900, cornerRadius: Radius.tile)
                        .aspectRatio(asset.aspect > 0 ? asset.aspect : 16.0 / 9, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: height)
                        .overlay(alignment: .topTrailing) { removeButton }
                        .onTapGesture(count: 2) { app.quickLook(asset) }
                } else if !pick.trimmedLink.isEmpty {
                    linkCard
                } else {
                    placeholder
                }
                if importing {
                    ProgressView(L("Importing…")).padding(14).glassEffect(in: .rect(cornerRadius: Radius.tile))
                }
            }
            .frame(maxWidth: .infinity, minHeight: boxHeight, maxHeight: boxHeight)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                Task {
                    for provider in providers {
                        if let url = await ImageIntake.movieURL(from: provider) {
                            await importFile(url)
                            break
                        }
                    }
                }
                return true
            }
            .onChange(of: isTargeted) { _, targeted in
                if targeted { dragEntries += 1 }
            }
            .onHover { isHovering = $0 }
            .popover(isPresented: $pasting, arrowEdge: .bottom) {
                VideoLinkField(link: pick.link) { link in
                    withAnimation(Motion.standard) { pick.link = link }
                    if let asset = pick.assetID.flatMap(app.library.asset) { try? app.setPastedLink(link, for: asset) }
                    pasting = false
                }
            }
            if asset != nil || !pick.trimmedLink.isEmpty {
                HStack(spacing: 8) {
                    if let asset {
                        Text(details(asset)).fineTextStyle().lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Menu {
                        sourceItems
                    } label: {
                        Label(L("Replace…"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.glass)
                    .fixedSize()
                }
            }
            if showsRecents, asset == nil, pick.trimmedLink.isEmpty, !importing { recents }
            if showsSharingNote { sharingNote }
        }
        .sheet(isPresented: $choosing) {
            VideoLibraryPicker(multiple: false) { ids in
                if let id = ids.first { use(id) }
            }
            .environment(app)
        }
    }

    private func use(_ id: UUID) {
        withAnimation(Motion.standard) {
            pick.assetID = id
            pick.link = app.library.asset(id).flatMap(app.pastedLink(for:)) ?? ""
        }
    }

    @ViewBuilder private var recents: some View {
        let clips = Array(app.library.videos.prefix(4))
        if !clips.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    recentsLabel
                    recentThumbnails(clips)
                    Spacer(minLength: 0)
                    latestButton
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        recentsLabel
                        Spacer(minLength: 0)
                        latestButton
                    }
                    recentThumbnails(clips)
                }
            }
            .transition(.opacity)
        }
    }

    private var recentsLabel: some View {
        Text(L("Recent clips")).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).fixedSize()
    }

    @ViewBuilder private var latestButton: some View {
        if let latest = app.latestVideoResult {
            Button(L("Use the latest result"), systemImage: "clock.arrow.circlepath") { use(latest.id) }
                .buttonStyle(.glass)
                .fixedSize()
                .help(VideoResultDetail.title(of: latest))
        }
    }

    private func recentThumbnails(_ clips: [Asset]) -> some View {
        HStack(spacing: 6) {
            ForEach(clips) { clip in
                Button { use(clip.id) } label: {
                    VideoPoster(url: app.library.url(for: clip), posterURL: app.library.posterURL(for: clip), maxPixel: 200)
                        .frame(width: 60, height: 40)
                        .clipShape(.rect(cornerRadius: Radius.thumb))
                        .overlay(RoundedRectangle(cornerRadius: Radius.thumb).strokeBorder(.primary.opacity(0.1)))
                        .contentShape(.rect(cornerRadius: Radius.thumb))
                }
                .buttonStyle(PressableStyle())
                .help(details(clip).isEmpty ? L("Use this clip") : details(clip))
                .accessibilityLabel(L("Use this clip"))
            }
        }
    }

    @ViewBuilder private var sourceItems: some View {
        Button(L("Choose File…"), systemImage: "folder") { chooseFile() }
        Button(L("Library"), systemImage: "film.stack") { choosing = true }
        Button(L("Paste Link…"), systemImage: "link") { pasting = true }
    }

    static let emptyHeight: CGFloat = 140

    private var placeholder: some View {
        ViewThatFits(in: .vertical) {
            placeholderContent(symbol: true)
            placeholderContent(symbol: false)
            placeholderContent(symbol: false).controlSize(.small)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Radius.card)
                .fill(isTargeted ? Color.appAccent.opacity(0.10) : Color.primary.opacity(isHovering ? 0.05 : 0.03))
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(isTargeted ? Color.appAccent : Color.secondary.opacity(isHovering ? 0.6 : 0.35),
                              style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: isTargeted ? [] : [6, 5]))
        }
        .animation(Motion.standard, value: isTargeted)
        .animation(Motion.select, value: isHovering)
        .contentShape(.rect(cornerRadius: Radius.card))
        .onTapGesture { choosing = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func placeholderContent(symbol: Bool) -> some View {
        VStack(spacing: 8) {
            if symbol {
                Image(systemName: "film")
                    .iconSymbol(IconScale.hero)
                    .foregroundStyle(isTargeted ? Color.appAccent : .secondary)
                    .symbolEffect(.bounce, value: dragEntries)
            }
            if showsTitle { Text(title).font(.headline) }
            Text(hint).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 6, centered: true) {
                Button(L("File"), systemImage: "folder") { chooseFile() }
                    .help(L("Choose File…"))
                Button(L("Library"), systemImage: "film.stack") { choosing = true }
                    .help(L("Choose from Library…"))
                Button(L("Link"), systemImage: "link") { pasting = true }
                    .help(L("Paste Link…"))
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.glass)
        }
    }

    private var linkCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "link.circle").iconSymbol(IconScale.hero).foregroundStyle(.secondary)
            Text(L("Clip from a link")).font(.headline)
            Text(URL(string: pick.trimmedLink)?.host() ?? pick.trimmedLink)
                .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: Radius.card))
        .overlay(alignment: .topTrailing) { removeButton }
    }

    private var removeButton: some View {
        Button {
            withAnimation(Motion.standard) { pick = VideoClipPick() }
        } label: {
            Image(systemName: "xmark").font(.caption.weight(.bold)).frame(width: 22, height: 22)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .help(L("Remove clip"))
        .padding(8)
    }

    @ViewBuilder private var sharingNote: some View {
        if !pick.trimmedLink.isEmpty {
            Label(L("The provider downloads the clip from this link."), systemImage: "link")
                .helperTextStyle()
        } else if app.sharesClipsFromMac {
            Label(L("Private: shared only while it's being processed"), systemImage: "lock.shield")
                .helperTextStyle()
                .help(L("Shared from this Mac through a temporary link only while the video job reads it, then closed."))
        } else {
            Label(L("Sharing from this Mac is off: paste a link, or use frame-based mode."), systemImage: "lock.slash")
                .font(.callout).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .help(L("Sharing clips from this Mac is off: paste a link (https), or use frame-based mode, which sends a copy of the clip once to a describing model on OpenRouter."))
        }
    }

    private func details(_ asset: Asset) -> String {
        var parts: [String] = []
        if let duration = asset.duration { parts.append(VideoPlayback.durationLabel(duration)) }
        if asset.width > 0 { parts.append(asset.pixelSizeLabel) }
        if asset.hasAudio == true { parts.append(L("with sound")) }
        return parts.joined(separator: " · ")
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L("Choose a video")
        panel.prompt = L("Use")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await importFile(url) }
    }

    private func importFile(_ url: URL) async {
        importing = true
        defer { importing = false }
        if let asset = await app.library.importVideo(url: url) {
            withAnimation(Motion.standard) { pick = VideoClipPick(assetID: asset.id) }
        } else {
            app.presentError(VideoMediaError.unreadable)
        }
    }
}

struct VideoLinkField: View {
    @State var link: String
    let onUse: (String) -> Void
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Paste a link to the file (https)")).font(.headline)
            Text(L("The provider downloads it from there, so nothing is shared from this Mac."))
                .helperTextStyle()
            TextField("https://…", text: $link)
                .textFieldStyle(.roundedBorder)
                .onSubmit(use)
            if let problem {
                Text(problem).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if !link.isEmpty {
                    Button(L("Remove link"), role: .destructive) { onUse("") }
                }
                Spacer()
                Button(L("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Use"), action: use).keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 360)
    }

    private func use() {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onUse("")
            return
        }
        do {
            onUse(try InputLink.checked(trimmed))
        } catch {
            problem = error.localizedDescription
        }
    }
}

struct VideoLibraryPicker: View {
    let multiple: Bool
    let onPick: ([UUID]) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var selection: [UUID] = []

    var body: some View {
        NavigationStack {
            Group {
                if app.library.videos.isEmpty {
                    ContentUnavailableView(L("No videos yet"), systemImage: "film",
                                           description: Text(L("Videos you make or import will appear here.")))
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                            ForEach(app.library.videos) { asset in
                                VideoTile(url: app.library.url(for: asset), posterURL: app.library.posterURL(for: asset),
                                          duration: asset.duration, hasAudio: asset.hasAudio,
                                          isSelected: selection.contains(asset.id), maxPixel: 400)
                                    .frame(height: 110)
                                    .overlay(alignment: .topLeading) {
                                        if multiple, let index = selection.firstIndex(of: asset.id) {
                                            Text("\(index + 1)").font(.caption.weight(.bold)).frame(width: 20, height: 20)
                                                .background(Color.appAccent, in: .circle).foregroundStyle(.white).padding(6)
                                        }
                                    }
                                    .contentShape(.rect)
                                    .onTapGesture { toggle(asset.id) }
                                    .onTapGesture(count: 2) {
                                        if !selection.contains(asset.id) { toggle(asset.id) }
                                        confirm()
                                    }
                                    .accessibilityAddTraits(selection.contains(asset.id) ? [.isButton, .isSelected] : .isButton)
                                    .accessibilityAction { toggle(asset.id) }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(multiple ? L("Choose Videos") : L("Choose Video"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(multiple && selection.count > 1 ? L("Use %ld", selection.count) : L("Use"), action: confirm)
                        .disabled(selection.isEmpty)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 460)
    }

    private func toggle(_ id: UUID) {
        if multiple {
            if let index = selection.firstIndex(of: id) { selection.remove(at: index) } else { selection.append(id) }
        } else {
            selection = [id]
        }
    }

    private func confirm() {
        onPick(selection)
        dismiss()
    }
}

struct VideoClipsEditor: View {
    @Binding var clipIDs: [UUID]
    var minimum = 2
    var maximum = 20

    @Environment(AppModel.self) private var app
    @State private var choosing = false

    var body: some View {
        let clips = clipIDs.compactMap(app.library.asset)
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(clips.enumerated()), id: \.element.id) { index, asset in
                        VStack(spacing: 4) {
                            VideoTile(url: app.library.url(for: asset), posterURL: app.library.posterURL(for: asset),
                                      duration: asset.duration, hasAudio: asset.hasAudio, maxPixel: 320)
                                .frame(width: 150, height: 92)
                                .overlay(alignment: .topLeading) {
                                    Text("\(index + 1)").font(.caption.weight(.bold)).frame(width: 20, height: 20)
                                        .glassEffect(in: .circle).padding(5)
                                }
                            HStack(spacing: 2) {
                                Button { move(asset.id, by: -1) } label: { Image(systemName: "chevron.left") }
                                    .disabled(index == 0).help(L("Move earlier"))
                                Button { clipIDs.removeAll { $0 == asset.id } } label: { Image(systemName: "trash") }
                                    .help(L("Remove clip"))
                                Button { move(asset.id, by: 1) } label: { Image(systemName: "chevron.right") }
                                    .disabled(index == clips.count - 1).help(L("Move later"))
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }
                    }
                    if clips.count < maximum {
                        Button { choosing = true } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "plus").font(.title3)
                                Text(L("Add clips")).font(.subheadline)
                            }
                            .frame(width: 150, height: 92)
                            .background(RoundedRectangle(cornerRadius: Radius.tile).strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)
            if clips.count < minimum {
                Text(minimum == 1 ? L("Add a clip.") : L("Add at least %ld clips.", minimum)).helperTextStyle()
            }
        }
        .sheet(isPresented: $choosing) {
            VideoLibraryPicker(multiple: true) { ids in
                let room = max(0, maximum - clipIDs.count)
                clipIDs.append(contentsOf: ids.filter { !clipIDs.contains($0) }.prefix(room))
            }
            .environment(app)
        }
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = clipIDs.firstIndex(of: id) else { return }
        let target = index + offset
        guard clipIDs.indices.contains(target) else { return }
        clipIDs.swapAt(index, target)
    }
}

struct AudioWell: View {
    @Binding var file: URL?
    @Binding var duration: Double?
    @Binding var link: String
    var title = L("Audio")
    var hint = L("An m4a, mp3 or wav file")

    @Environment(AppModel.self) private var app
    @State private var pasting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: file != nil || !trimmedLink.isEmpty ? "waveform.circle.fill" : "waveform.circle")
                    .iconSymbol(IconScale.large)
                    .foregroundStyle(file != nil || !trimmedLink.isEmpty ? Color.brand : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    if let file {
                        Text(Self.displayName(file)).font(.headline).lineLimit(1).truncationMode(.middle)
                        if let duration { Text(VideoPlayback.durationLabel(duration)).fineTextStyle() }
                    } else if !trimmedLink.isEmpty {
                        Text(L("Sound from a link")).font(.headline)
                        Text(URL(string: trimmedLink)?.host() ?? trimmedLink).fineTextStyle().lineLimit(1)
                    } else {
                        Text(title).font(.headline)
                        Text(hint).helperTextStyle()
                    }
                }
                Spacer()
                if file != nil || !trimmedLink.isEmpty {
                    Button {
                        file = nil
                        duration = nil
                        link = ""
                    } label: {
                        Image(systemName: "xmark").font(.caption.weight(.bold)).frame(width: 20, height: 20)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .help(L("Remove sound"))
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: Radius.tile))
            HStack(spacing: 6) {
                Button(L("Choose File…"), systemImage: "folder") { choose() }
                Button(L("Paste Link…"), systemImage: "link") { pasting = true }
                    .popover(isPresented: $pasting, arrowEdge: .bottom) {
                        VideoLinkField(link: link) { value in
                            link = value
                            if !value.isEmpty {
                                file = nil
                                duration = nil
                            }
                            pasting = false
                        }
                    }
            }
            .buttonStyle(.glass)
        }
    }

    private var trimmedLink: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }

    static func displayName(_ url: URL) -> String {
        let name = url.lastPathComponent
        guard name.hasPrefix("audio-"), let underscore = name.firstIndex(of: "_") else { return name }
        return String(name[name.index(after: underscore)...])
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L("Choose a sound file")
        panel.prompt = L("Use")
        guard panel.runModal() == .OK, let source = panel.url else { return }
        Task {
            let copy: URL
            do {
                copy = try await VideoMedia.scratchCopy(of: source, prefix: "audio")
            } catch {
                app.presentError(error)
                return
            }
            file = copy
            link = ""
            duration = nil
            let seconds = try? await AVURLAsset(url: copy).load(.duration).seconds
            if file == copy { duration = seconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } }
        }
    }
}

struct CameraMoveChip: View {
    @Binding var selection: [String]
    @Binding var strength: String
    var limit = CameraMoves.maxMix
    var emptyTitle = L("Camera: automatic")

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label(title, systemImage: "video.badge.waveform").lineLimit(1)
        }
        .buttonStyle(.glass)
        .fixedSize()
        .help(L("Camera moves, played in order"))
        .sheet(isPresented: $isPresented) {
            CameraMovePicker(selection: $selection, strength: $strength, limit: limit)
        }
    }

    private var title: String {
        let names = selection.compactMap(CameraMoves.move).map(\.name)
        guard let first = names.first else { return emptyTitle }
        return names.count == 1 ? first : "\(first) +\(names.count - 1)"
    }
}

struct StyleChip: View {
    @Binding var presetID: String?
    @Binding var moodboardID: UUID?

    @Environment(AppModel.self) private var app
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label(title, systemImage: "paintpalette").lineLimit(1)
        }
        .buttonStyle(.glass)
        .fixedSize()
        .help(L("A look for the clip"))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            StylePicker(selection: $presetID, moodboard: $moodboardID) { isPresented = false }
        }
    }

    private var title: String {
        if let preset = presetID.flatMap(StylePresets.preset) { return preset.name }
        if let board = app.library.moodboard(moodboardID) { return board.name }
        return L("Style")
    }
}

struct VideoShotsEditor: View {
    @Binding var shots: [VideoShotDraft]
    var minimum = 0
    var maximum = 3
    var takesImages = false
    var emotions: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach($shots) { $shot in
                let index = shots.firstIndex { $0.id == shot.id } ?? 0
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)").font(.caption.weight(.bold).monospacedDigit()).frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.08), in: .circle).foregroundStyle(.secondary)
                    if takesImages {
                        CompactImageWell(data: $shot.image)
                            .frame(width: 150, height: 100)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        TextField(takesImages ? L("What happens in this image") : L("What happens in this shot"),
                                  text: $shot.action, axis: .vertical)
                            .lineLimit(1...3)
                            .inputBox()
                            .characterLimit($shot.action, 200)
                        FlowLayout(spacing: 6) {
                            ShotCameraMenu(selection: $shot.camera, followsGeneral: takesImages)
                            if !emotions.isEmpty {
                                ChipMenu(systemImage: "face.smiling", title: shot.emotion.map(L) ?? L("Emotion"), help: L("The shot's emotion")) {
                                    Picker(L("Emotion"), selection: $shot.emotion) {
                                        Text(L("Auto")).tag(String?.none)
                                        ForEach(emotions.filter { $0 != "Auto" }, id: \.self) { Text(L($0)).tag(String?.some($0)) }
                                    }
                                    .pickerStyle(.inline)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: VideoLayout.textWidth, alignment: .leading)
                    if shots.count > minimum {
                        Button {
                            withAnimation(Motion.standard) { shots.removeAll { $0.id == shot.id } }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(L("Remove shot"))
                    }
                }
            }
            if shots.count < maximum {
                Button(takesImages ? L("Add another image") : L("Add shot"), systemImage: "plus") {
                    withAnimation(Motion.standard) { shots.append(VideoShotDraft()) }
                }
                .buttonStyle(.glass)
            }
        }
    }
}

struct ShotCameraMenu: View {
    @Binding var selection: String?
    var followsGeneral = false

    var body: some View {
        ChipMenu(systemImage: "video", title: selection.flatMap(CameraMoves.move)?.name ?? (followsGeneral ? L("Camera: general") : L("Camera: automatic")),
                 help: L("The shot's camera move")) {
            Picker(L("Camera"), selection: $selection) {
                Text(followsGeneral ? L("General camera") : L("Auto")).tag(String?.none)
                ForEach(CameraMoveGroup.allCases) { group in
                    Section(group.title) {
                        ForEach(CameraMoves.moves(in: group)) { Text($0.name).tag(String?.some($0.id)) }
                    }
                }
            }
            .pickerStyle(.inline)
        }
    }
}
