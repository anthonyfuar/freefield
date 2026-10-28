import AppKit
import FreefieldCore
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    enum Filter { case all, favorites }

    enum MediaFilter: Hashable { case all, images, videos, favorites }

    @Environment(AppModel.self) private var app
    @State private var mediaFilter: MediaFilter
    @State private var search = ""
    @State private var toolFilter: Tool?
    @State private var modelFilter: String?
    @State private var selection: Set<UUID> = []
    @State private var lastSelected: UUID?
    @State private var showInspector = true
    @State private var confirmDelete = false
    @State private var isDropTargeted = false
    @AppStorage("libraryThumbnailSize") private var thumbnailSize = 190.0

    init(filter: Filter = .all) {
        _mediaFilter = State(initialValue: filter == .favorites ? .favorites : .all)
    }

    private static let thumbnailSizes: [(title: String, height: Double)] = [
        (L("Small"), 130), (L("Medium"), 190), (L("Large"), 260), (L("Huge"), 360),
    ]

    private var effectiveMediaFilter: MediaFilter {
        switch mediaFilter {
        case .images, .videos: app.library.assets.contains(where: \.isVideo) ? mediaFilter : .all
        default: mediaFilter
        }
    }

    private var showsFavorites: Bool { effectiveMediaFilter == .favorites }

    private var items: [Asset] {
        var assets = app.library.assets
        switch effectiveMediaFilter {
        case .all: break
        case .images: assets = assets.filter { !$0.isVideo }
        case .videos: assets = assets.filter(\.isVideo)
        case .favorites: assets = assets.filter(\.isFavorite)
        }
        if let toolFilter { assets = assets.filter { $0.tool == toolFilter } }
        if let modelFilter { assets = assets.filter { $0.modelName == modelFilter } }
        if !search.isEmpty {
            assets = assets.filter {
                $0.prompt.localizedCaseInsensitiveContains(search)
                    || $0.modelName.localizedCaseInsensitiveContains(search)
                    || $0.tool.title.localizedCaseInsensitiveContains(search)
                    || ($0.appID.flatMap(VideoCatalog.tool)?.name.localizedCaseInsensitiveContains(search) ?? false)
            }
        }
        return assets
    }

    var body: some View {
        let items = items
        Group {
            if app.library.assets.isEmpty {
                ContentUnavailableView {
                    Label(showsFavorites ? L("No Favorites") : L("Your library is empty"),
                          systemImage: showsFavorites ? "heart" : "photo.on.rectangle.angled")
                } description: {
                    Text(showsFavorites ? L("Your favorites are empty. Make something first, then click ♡ on it to save it here.")
                         : L("Everything you generate is saved here. You can also drag in photos and videos."))
                        .helperTextStyle()
                } actions: {
                    HStack(spacing: 10) {
                        Button { app.selection = .tool(.create) } label: {
                            Text(L("Create My First Image")).prominentLabel()
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.brandFill)
                        .controlSize(.large)
                        Button(L("Import Photos or Videos…"), systemImage: "square.and.arrow.down") { LibraryImport.run(app) }
                            .buttonStyle(.glass)
                            .controlSize(.large)
                    }
                    .fixedSize()
                }
            } else {
                grid(items)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(Color.appAccent, lineWidth: 2)
                .padding(8)
                .opacity(isDropTargeted ? 1 : 0)
                .animation(Motion.fade, value: isDropTargeted)
                .allowsHitTesting(false)
        }
        .navigationTitle(showsFavorites ? L("Favorites") : L("Library"))
        .navigationSubtitle(countLabel(items))
        .safeAreaBar(edge: .top) {
            if toolFilter != nil || modelFilter != nil {
                filterChips
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: L("Search library"))
        .toolbar { toolbar(items) }
        .inspector(isPresented: Binding(get: { showInspector && !selection.isEmpty }, set: { showInspector = $0 })) {
            Group {
                if selection.count == 1, let id = selection.first, let asset = app.library.asset(id) {
                    AssetInspector(asset: asset)
                } else if selection.count > 1 {
                    MultiSelectionSummary(assets: app.library.assets.filter { selection.contains($0.id) })
                } else {
                    ContentUnavailableView(L("No Selection"), systemImage: "photo",
                                           description: Text(app.library.videos.isEmpty ? L("Choose an image to see its details.")
                                                             : L("Choose an image or video to see its details.")))
                }
            }
            .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            Task {
                var images: [NSItemProvider] = []
                var failed = 0
                for provider in providers {
                    if let movie = await ImageIntake.movieURL(from: provider) {
                        if await app.library.importVideo(url: movie) == nil { failed += 1 }
                    } else {
                        images.append(provider)
                    }
                }
                for data in await ImageIntake.data(from: images) {
                    app.library.importImage(data: data, name: L("Imported") + ".png")
                }
                if failed > 0 { app.presentError(LibraryImport.unreadableVideos(failed)) }
            }
            return true
        }
        .confirmationDialog(deleteTitle, isPresented: $confirmDelete) {
            Button(L("Move to Trash"), role: .destructive) {
                withAnimation(Motion.standard) { app.library.delete(selection) }
                selection.removeAll()
            }
        } message: {
            Text(L("You can recover them from the macOS Trash."))
        }
    }

    private var deleteTitle: String {
        let selected = app.library.assets.filter { selection.contains($0.id) }
        let videos = selected.count(where: \.isVideo)
        if videos == 0 { return selected.count == 1 ? L("Move the image to the Trash?") : L("Move %ld images to the Trash?", selected.count) }
        if videos == selected.count { return videos == 1 ? L("Move the video to the Trash?") : L("Move %ld videos to the Trash?", videos) }
        return L("Move %ld items to the Trash?", selected.count)
    }

    private func grid(_ items: [Asset]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: showsFavorites ? L("Favorites") : L("Library"),
                           detail: showsFavorites ? L("Everything you marked with ♡. Click ♡ on an image or video to add it here.")
                               : L("Everything you make is saved here. Search by description, tool or model, or drag in photos and videos to add them."))
                if items.isEmpty {
                    ContentUnavailableView(showsFavorites && search.isEmpty ? L("No Favorites") : L("No Results"),
                                           systemImage: showsFavorites ? "heart" : "magnifyingglass",
                                           description: Text(showsFavorites && search.isEmpty ? L("Click ♡ on an image to save it here.") : L("Try a different search or filter.")))
                        .padding(.top, 40)
                } else {
                    JustifiedAssetGrid(assets: items, targetHeight: thumbnailSize, spacing: 6) { asset, size in
                        AssetCard(asset: asset, isSelected: selection.contains(asset.id), maxPixel: Int(max(size.width, size.height) * 2))
                            .onTapGesture(count: 2) { app.quickLook(asset) }
                            .simultaneousGesture(TapGesture().onEnded { select(asset, in: items) })
                            .contextMenu {
                                let targets = selection.contains(asset.id) ? app.library.assets.filter { selection.contains($0.id) } : [asset]
                                AssetMenu(assets: targets)
                            }
                    }
                }
            }
            .pageContainer()
        }
        .background {
            Color.clear
                .contentShape(.rect)
                .onTapGesture { selection.removeAll() }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            guard let id = selection.first, let asset = app.library.asset(id) else { return .ignored }
            app.quickLook(asset)
            return .handled
        }
        .onDeleteCommand { if !selection.isEmpty { confirmDelete = true } }
        .onCommand(#selector(NSResponder.selectAll(_:))) { selection = Set(items.map(\.id)) }
    }

    private var filterChips: some View {
        FlowLayout(spacing: 6) {
            Text(L("Filtered by:"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize()
            if let toolFilter {
                filterChip(toolFilter.title, systemImage: toolFilter.systemImage) { self.toolFilter = nil }
            }
            if let modelFilter {
                filterChip(L(modelFilter), systemImage: "cpu") { self.modelFilter = nil }
            }
            if toolFilter != nil, modelFilter != nil {
                Button(L("Clear Filters")) {
                    toolFilter = nil
                    modelFilter = nil
                }
                .buttonStyle(.link)
                .font(.callout)
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private func filterChip(_ title: String, systemImage: String, remove: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(Motion.standard) { remove() } }) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                Text(title).lineLimit(1)
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .glassEffect(in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(L("Remove this filter"))
    }

    private func countLabel(_ items: [Asset]) -> String {
        let videos = items.count(where: \.isVideo)
        if videos == 0 { return items.count == 1 ? L("1 image") : L("%ld images", items.count) }
        if videos == items.count { return videos == 1 ? L("1 video") : L("%ld videos", videos) }
        return L("%ld items", items.count)
    }

    private func select(_ asset: Asset, in items: [Asset]) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) {
            if selection.contains(asset.id) { selection.remove(asset.id) } else { selection.insert(asset.id) }
        } else if modifiers.contains(.shift), let anchor = lastSelected,
                  let from = items.firstIndex(where: { $0.id == anchor }), let to = items.firstIndex(where: { $0.id == asset.id }) {
            selection.formUnion(items[min(from, to)...max(from, to)].map(\.id))
        } else {
            selection = [asset.id]
        }
        lastSelected = asset.id
    }

    private var thumbnailChoice: Binding<Double> {
        Binding(
            get: { Self.thumbnailSizes.min { abs($0.height - thumbnailSize) < abs($1.height - thumbnailSize) }?.height ?? 190 },
            set: { thumbnailSize = $0 }
        )
    }

    @ToolbarContentBuilder
    private func toolbar(_ items: [Asset]) -> some ToolbarContent {
        if !app.library.assets.isEmpty {
            let hasVideos = app.library.assets.contains(where: \.isVideo)
            ToolbarItem {
                Picker(L("Show"), selection: Binding(get: { effectiveMediaFilter }, set: { mediaFilter = $0 })) {
                    Text(L("All")).tag(MediaFilter.all)
                    if hasVideos {
                        Text(L("Images")).tag(MediaFilter.images)
                        Text(L("Videos")).tag(MediaFilter.videos)
                    }
                    Text("♡ " + L("Favorites")).tag(MediaFilter.favorites)
                }
                .pickerStyle(.segmented)
                .help(hasVideos ? L("Show images, videos, both, or only your favorites") : L("Show everything, or only your favorites"))
            }
            ToolbarItem {
                Menu {
                    Picker(L("Tool"), selection: $toolFilter) {
                        Text(L("All Tools")).tag(Tool?.none)
                        ForEach(Tool.allCases.filter { tool in app.library.assets.contains { $0.tool == tool } }) { tool in
                            Label(tool.title, systemImage: tool.systemImage).tag(Tool?.some(tool))
                        }
                    }
                    Picker(L("AI model"), selection: $modelFilter) {
                        Text(L("All AI Models")).tag(String?.none)
                        ForEach(Array(Set(app.library.assets.map(\.modelName))).sorted(), id: \.self) { name in
                            Text(L(name)).tag(String?.some(name))
                        }
                    }
                } label: {
                    Label(L("Filter"), systemImage: toolFilter == nil && modelFilter == nil
                          ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .help(L("Filter by tool or AI model"))
            }
            ToolbarItem {
                Menu {
                    Picker(L("Thumbnail size"), selection: thumbnailChoice) {
                        ForEach(Self.thumbnailSizes, id: \.height) { size in
                            Text(size.title).tag(size.height)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(L("View"), systemImage: "rectangle.grid.2x2")
                }
                .help(L("Thumbnail size"))
            }
        }
        ToolbarItem {
            Button(L("Import"), systemImage: "square.and.arrow.down") { LibraryImport.run(app) }
                .help(L("Import images and videos"))
        }
        if !app.library.assets.isEmpty {
            ToolbarItem {
                Button(L("Export"), systemImage: "square.and.arrow.up") {
                    app.export(app.library.assets.filter { selection.contains($0.id) })
                }
                .disabled(selection.isEmpty)
                .help(L("Export the selection"))
            }
            ToolbarItem {
                Button(L("Details"), systemImage: "sidebar.right") { showInspector.toggle() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .disabled(selection.isEmpty)
                    .help(selection.isEmpty ? L("Select an image or video to see its details") : L("Show or hide details (⌥⌘I)"))
            }
        }
    }
}

struct MultiSelectionSummary: View {
    let assets: [Asset]
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                ForEach(Array(assets.prefix(4).enumerated()), id: \.element.id) { index, asset in
                    AssetThumbnail(asset: asset, maxPixel: 300)
                        .frame(width: 140, height: 140)
                        .clipShape(.rect(cornerRadius: Radius.tile))
                        .rotationEffect(.degrees(Double(index) * 5 - 6))
                        .shadow(radius: 4)
                }
            }
            .frame(height: 180)
            Text(assets.contains(where: \.isVideo)
                 ? (assets.allSatisfy(\.isVideo) ? L("%ld videos selected", assets.count) : L("%ld items selected", assets.count))
                 : L("%ld images selected", assets.count))
                .font(.headline)
            let cost = assets.compactMap(\.cost).reduce(0, +)
            if cost > 0 {
                Text(L("Total cost: %@", AppModel.money(cost))).font(.callout).foregroundStyle(.secondary)
            }
            VStack(spacing: 8) {
                Button(L("Export…"), systemImage: "square.and.arrow.down") { app.export(assets) }
                Button(L("Favorites"), systemImage: "heart") { app.library.toggleFavorite(Set(assets.map(\.id))) }
            }
            .buttonStyle(.glass)
            Spacer()
        }
        .padding(20)
    }
}

enum LibraryImport {
    static func run(_ app: AppModel, videosOnly: Bool = false) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = videosOnly ? [.movie] : [.image, .movie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = videosOnly ? L("Choose one or more videos") : L("Choose images or videos")
        panel.prompt = L("Import")
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        app.selection = .library
        Task {
            var failed = 0
            for url in urls {
                let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType ?? UTType(filenameExtension: url.pathExtension)
                if type?.conforms(to: .movie) == true {
                    if await app.library.importVideo(url: url) == nil { failed += 1 }
                } else if let data = try? Data(contentsOf: url) {
                    app.library.importImage(data: data, name: url.lastPathComponent)
                }
            }
            if failed > 0 { app.presentError(unreadableVideos(failed)) }
        }
    }

    static func unreadableVideos(_ count: Int) -> FreefieldError {
        .unsupported(count == 1 ? L("Couldn't import the video: the file isn't a readable movie.")
                     : L("Couldn't import %ld videos: the files aren't readable movies.", count))
    }
}
