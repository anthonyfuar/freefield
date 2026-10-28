import AppKit
import FreefieldCore
import SwiftUI
import UniformTypeIdentifiers

enum ImageIntake {
    static let types: [UTType] = [.png, .jpeg, .heic, .webP, .tiff, .gif, .bmp, .image]

    static func data(from providers: [NSItemProvider]) async -> [Data] {
        var results: [Data] = []
        for provider in providers {
            if let data = await loadData(provider) { results.append(data) }
        }
        return results
    }

    private static func loadData(_ provider: NSItemProvider) async -> Data? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let url = await loadURL(provider), !isAudiovisual(url), let data = try? Data(contentsOf: url),
               ImageCoding.pixelSize(of: data) != nil {
                return data
            }
        }
        for type in types where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            if let data = await loadRepresentation(provider, type: type) { return data }
        }
        return nil
    }

    static func movieURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier), let url = await loadURL(provider),
              contentType(of: url)?.conforms(to: .movie) == true else { return nil }
        return url
    }

    private static func contentType(of url: URL) -> UTType? {
        (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType ?? UTType(filenameExtension: url.pathExtension)
    }

    private static func isAudiovisual(_ url: URL) -> Bool {
        contentType(of: url)?.conforms(to: .audiovisualContent) == true
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    private static func loadRepresentation(_ provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    static func pasteboardImages() -> [Data] {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            let images = urls.compactMap { try? Data(contentsOf: $0) }.filter { ImageCoding.pixelSize(of: $0) != nil }
            if !images.isEmpty { return images }
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff, NSPasteboard.PasteboardType(UTType.jpeg.identifier)] {
            if let data = pasteboard.data(forType: type) { return [data] }
        }
        return []
    }

    static func pick(multiple: Bool) -> [Data] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = false
        panel.message = multiple ? L("Choose one or more images") : L("Choose an image")
        panel.prompt = L("Use")
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap { try? Data(contentsOf: $0) }
    }
}

struct WellSources: OptionSet {
    let rawValue: Int
    static let library = WellSources(rawValue: 1 << 0)
    static let products = WellSources(rawValue: 1 << 1)
    static let characters = WellSources(rawValue: 1 << 2)

    static let standard: WellSources = [.library, .products]
    static let person: WellSources = [.library, .characters]
}

struct ImageWell: View {
    let title: String
    var subtitle: String = L("Drag, paste (⌘V), or click to choose")
    var systemImage: String = "photo.badge.plus"
    @Binding var data: Data?
    var minHeight: CGFloat = 180
    var sources: WellSources = .standard
    var onPickProduct: ((Product) -> Void)?
    var isInPanel = false

    @Environment(AppModel.self) private var app
    @State private var isTargeted = false
    @State private var dragEntries = 0
    @State private var isHovering = false
    @State private var showingLibrary = false

    var body: some View {
        ZStack {
            if let data {
                DataImage(data: data, maxPixel: 1600)
                    .clipShape(.rect(cornerRadius: Radius.card))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            set(nil)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.bold))
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .help(L("Remove image"))
                        .padding(8)
                    }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { providers in
            Task {
                if let first = await ImageIntake.data(from: providers).first { set(first) }
            }
            return true
        }
        .onChange(of: isTargeted) { _, targeted in
            if targeted { dragEntries += 1 }
        }
        .contextMenu {
            Button(L("Choose File…"), systemImage: "folder") { choose() }
            if sources.contains(.library) {
                Button(L("Choose from Library…"), systemImage: "photo.on.rectangle") { showingLibrary = true }
            }
            productsMenu
            charactersMenu
            Button(L("Paste Image"), systemImage: "doc.on.clipboard") { paste() }
            if data != nil {
                Divider()
                Button(L("Remove"), systemImage: "trash", role: .destructive) { set(nil) }
            }
        }
        .onPasteCommand(of: [.fileURL, .image]) { providers in
            Task {
                if let first = await ImageIntake.data(from: providers).first { set(first) }
            }
        }
        .sheet(isPresented: $showingLibrary) {
            LibraryPicker(multiple: false) { picked in
                set(picked.first)
            }
            .environment(app)
        }
    }

    private func set(_ image: Data?) {
        withAnimation(Motion.standard) { data = image }
    }

    private var placeholder: some View {
        ViewThatFits(in: .vertical) {
            placeholderContent(symbol: true, subtitle: true, latestLink: true)
            placeholderContent(symbol: false, subtitle: true, latestLink: true)
            placeholderContent(symbol: false, subtitle: true, latestLink: false)
            placeholderContent(symbol: false, subtitle: false, latestLink: false)
            placeholderContent(symbol: false, subtitle: false, latestLink: false, recents: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Radius.card)
                .fill(isTargeted ? Color.appAccent.opacity(0.10) : Color.primary.opacity(isHovering ? 0.05 : 0.03))
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(isTargeted ? Color.appAccent : Color.secondary.opacity(isHovering ? 0.6 : 0.45),
                              style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: isTargeted ? [] : [6, 5]))
        }
        .animation(Motion.standard, value: isTargeted)
        .animation(Motion.select, value: isHovering)
        .contentShape(.rect(cornerRadius: Radius.card))
        .onTapGesture(perform: choose)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(title)
        .accessibilityAction(named: L("Choose File…"), choose)
    }

    private func placeholderContent(symbol: Bool, subtitle showsSubtitle: Bool, latestLink: Bool, recents showsRecents: Bool = true) -> some View {
        VStack(spacing: 10) {
            if symbol {
                Image(systemName: systemImage)
                    .iconSymbol(IconScale.hero)
                    .foregroundStyle(isTargeted ? Color.appAccent : .secondary)
                    .symbolEffect(.bounce, value: dragEntries)
            }
            VStack(spacing: 3) {
                Text(title).font(.title3.weight(.semibold))
                if showsSubtitle {
                    Text(subtitle).helperTextStyle()
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            sourceButtons
            if showsRecents { recents(latestLink: latestLink) }
        }
    }

    private var sourceButtons: some View {
        FlowLayout(spacing: 6, centered: true) {
            Button(L("File"), systemImage: "folder") { choose() }
                .help(L("Choose File…"))
            if sources.contains(.library) {
                Button(L("Library"), systemImage: "photo.on.rectangle") { showingLibrary = true }
                    .help(L("Choose from Library…"))
            }
            if hasMoreSources {
                Menu(L("More"), systemImage: "ellipsis.circle") {
                    if sources.contains(.products), !app.library.products.isEmpty {
                        Section(L("Products")) { productButtons }
                    }
                    if sources.contains(.characters), !app.library.characters.isEmpty {
                        Section(L("Characters")) { characterButtons }
                    }
                }
                .menuStyle(.button)
                .modifier(WellButtonStyle(isInPanel: isInPanel))
                .fixedSize()
                .help(L("Use a saved product or character"))
            }
        }
        .labelStyle(.titleAndIcon)
        .controlSize(.regular)
        .modifier(WellButtonStyle(isInPanel: isInPanel))
    }

    private var recentImages: [Asset] {
        guard sources.contains(.library) else { return [] }
        return Array(app.library.assets.lazy.filter { !$0.isVideo }.prefix(4))
    }

    @ViewBuilder private func recents(latestLink: Bool) -> some View {
        let recent = recentImages
        if !recent.isEmpty {
            VStack(spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        Text(L("Recent")).fineTextStyle()
                        thumbnails(recent)
                    }
                    VStack(spacing: 4) {
                        Text(L("Recent")).fineTextStyle()
                        thumbnails(recent)
                    }
                }
                if latestLink, let latest = app.library.assets.first(where: { !$0.isVideo && $0.tool != .imported }) {
                    Button(L("Use the latest result")) { use(latest) }
                        .buttonStyle(.link)
                        .font(.subheadline)
                }
            }
        }
    }

    private func thumbnails(_ assets: [Asset]) -> some View {
        HStack(spacing: 6) {
            ForEach(assets) { asset in
                Button {
                    use(asset)
                } label: {
                    ThumbnailImage(url: app.library.url(for: asset), maxPixel: 120)
                        .frame(width: 36, height: 36)
                        .clipShape(.rect(cornerRadius: Radius.thumb))
                        .overlay(RoundedRectangle(cornerRadius: Radius.thumb).strokeBorder(.primary.opacity(0.12)))
                        .contentShape(.rect(cornerRadius: Radius.thumb))
                }
                .buttonStyle(PressableStyle())
                .help(L("Use this image"))
                .accessibilityLabel(L("Use this image"))
            }
        }
    }

    private func use(_ asset: Asset) {
        if let image = app.library.imageData(for: asset) { set(image) }
    }

    private func choose() {
        if let first = ImageIntake.pick(multiple: false).first { set(first) }
    }

    private var hasMoreSources: Bool {
        (sources.contains(.products) && !app.library.products.isEmpty)
            || (sources.contains(.characters) && !app.library.characters.isEmpty)
    }

    @ViewBuilder private var productButtons: some View {
        ForEach(app.library.products) { product in
            Button(product.name, systemImage: "shippingbox") {
                if let onPickProduct {
                    onPickProduct(product)
                } else if let hero = app.library.productPhotoData(product).first {
                    set(hero)
                }
            }
        }
    }

    @ViewBuilder private var characterButtons: some View {
        ForEach(app.library.characters) { character in
            Button(character.name, systemImage: "person.crop.square") {
                if let photo = app.library.coverPhotoData(character) { set(photo) }
            }
        }
    }

    @ViewBuilder private var productsMenu: some View {
        if sources.contains(.products), !app.library.products.isEmpty {
            Menu(L("Products"), systemImage: "shippingbox") { productButtons }
        }
    }

    @ViewBuilder private var charactersMenu: some View {
        if sources.contains(.characters), !app.library.characters.isEmpty {
            Menu(L("Characters"), systemImage: "person.crop.square") { characterButtons }
        }
    }

    private func paste() {
        if let first = ImageIntake.pasteboardImages().first { set(first) }
    }
}

private struct WellButtonStyle: ViewModifier {
    let isInPanel: Bool

    func body(content: Content) -> some View {
        if isInPanel {
            content.buttonStyle(.bordered)
        } else {
            content.buttonStyle(.glass)
        }
    }
}

struct ReferenceStrip: View {
    @Binding var images: [Data]
    var limit: Int
    var label = L("References")

    @Environment(AppModel.self) private var app
    @State private var isTargeted = false
    @State private var showingLibrary = false
    @State private var identity = ReferenceIdentity()

    var body: some View {
        let ids = identity.ids(for: images)
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(zip(ids, images)), id: \.0) { id, data in
                    DataImage(data: data, maxPixel: 200, contentMode: .fill)
                        .frame(width: 52, height: 52)
                        .clipShape(.rect(cornerRadius: Radius.thumb))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                remove(id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .offset(x: 5, y: -5)
                            .help(L("Remove reference"))
                        }
                        .transition(Motion.transition(.scale(scale: 0.9).combined(with: .opacity)))
                }
                if images.count < limit {
                    Menu {
                        Button(L("Choose Files…"), systemImage: "folder") { add(ImageIntake.pick(multiple: true)) }
                        Button(L("From Library…"), systemImage: "photo.on.rectangle") { showingLibrary = true }
                        if !app.library.products.isEmpty {
                            Menu(L("From Products"), systemImage: "shippingbox") {
                                ForEach(app.library.products) { product in
                                    Button(product.name) { add(Array(app.library.productPhotoData(product).prefix(3))) }
                                }
                            }
                        }
                        Button(L("Paste"), systemImage: "doc.on.clipboard") { add(ImageIntake.pasteboardImages()) }
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.medium))
                            .frame(width: 52, height: 52)
                            .background(RoundedRectangle(cornerRadius: Radius.thumb).strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .help(L("%@: up to %ld", label, limit))
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.never)
        .background(isTargeted ? Color.appAccent.opacity(0.08) : .clear, in: .rect(cornerRadius: Radius.tile))
        .animation(Motion.fade, value: isTargeted)
        .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { providers in
            Task { add(await ImageIntake.data(from: providers)) }
            return true
        }
        .sheet(isPresented: $showingLibrary) {
            LibraryPicker(multiple: true) { add($0) }
                .environment(app)
        }
    }

    private func add(_ new: [Data]) {
        withAnimation(Motion.standard) {
            images.append(contentsOf: new.prefix(max(0, limit - images.count)))
        }
    }

    private func remove(_ id: UUID) {
        guard let index = identity.ids(for: images).firstIndex(of: id) else { return }
        withAnimation(Motion.standard) { _ = images.remove(at: index) }
    }
}

private final class ReferenceIdentity {
    private var entries: [(id: UUID, data: Data)] = []

    func ids(for images: [Data]) -> [UUID] {
        var unused = entries
        let next = images.map { data in
            if let match = unused.firstIndex(where: { $0.data == data }) {
                return unused.remove(at: match)
            }
            return (id: UUID(), data: data)
        }
        entries = next
        return next.map(\.id)
    }
}
