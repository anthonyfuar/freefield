import AppKit
import FreefieldCore
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedGoal: String?
    @State private var width: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                PageHeader(title: L("What do you want to do?"),
                           detail: L("Start with a photo or a video, go back to a tool, or pick what you want to make."), isLanding: true)
                quickStart
                HomeStartArea()
                recents
                goals
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
            .pageContainer()
        }
        .navigationTitle(L("Home"))
    }

    private func columns(minimum: CGFloat, spacing: CGFloat) -> Int {
        width > 0 ? min(3, OptionGrid.columnCount(width: width, columns: nil, minimum: minimum, spacing: spacing)) : 3
    }

    private var quickStart: some View {
        OptionGrid(columns: columns(minimum: 200, spacing: 14), minimum: 200, spacing: 14, stretchesLastRow: true) {
            ForEach(QuickStart.all) { entry in
                QuickStartCard(entry: entry)
            }
        }
    }

    private var recentItems: [SidebarItem] {
        var seen: Set<SidebarItem> = []
        return Array(app.recentTools.filter { seen.insert(NavCatalog.rowItem(for: $0) ?? $0).inserted }.prefix(3))
    }

    @ViewBuilder private var recents: some View {
        let items = recentItems
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Continue with…")).sectionTitleStyle()
                OptionGrid(columns: columns(minimum: 260, spacing: 12), minimum: 260, spacing: 12) {
                    ForEach(items, id: \.self) { item in
                        RecentToolCard(item: item)
                    }
                }
            }
        }
    }

    private var goals: some View {
        let goals = HomeGoal.all
        let count = columns(minimum: 280, spacing: Spacing.l)
        let rows = stride(from: 0, to: goals.count, by: count).map { Array(goals[$0..<min($0 + count, goals.count)]) }
        return VStack(alignment: .leading, spacing: 10) {
            Text(L("Tools by Goal")).sectionTitleStyle()
            Grid(alignment: .topLeading, horizontalSpacing: Spacing.l, verticalSpacing: Spacing.l) {
                ForEach(rows, id: \.first?.id) { row in
                    GridRow {
                        ForEach(row) { goal in
                            GoalCard(goal: goal, showsAll: expandedGoal == goal.id) {
                                withAnimation(reduceMotion ? nil : Motion.standard) {
                                    expandedGoal = expandedGoal == goal.id ? nil : goal.id
                                }
                            }
                        }
                        ForEach(row.count..<count, id: \.self) { _ in Color.clear.gridCellUnsizedAxes(.vertical) }
                    }
                }
            }
        }
    }
}

struct QuickStart: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let family: String
    let item: SidebarItem

    static var all: [QuickStart] {
        [
            QuickStart(id: "create", title: L("Create an image from words"), detail: L("Describe what you imagine and get a picture."),
                       symbol: Tool.create.systemImage, family: "create", item: .tool(.create)),
            QuickStart(id: "edit", title: L("Fix or change a photo"), detail: L("Say in words what to change in your photo."),
                       symbol: Tool.edit.systemImage, family: "photo", item: .tool(.edit)),
            QuickStart(id: "video", title: L("Make a video"), detail: L("Describe a scene or bring a photo to life."),
                       symbol: NavCatalog.symbol(.video("createVideo")), family: "video", item: .video("createVideo")),
        ]
    }
}

private struct QuickStartCard: View {
    let entry: QuickStart
    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            app.selection = entry.item
        } label: {
            HStack(alignment: .center, spacing: 14) {
                FamilyStyle.tile(symbol: entry.symbol, family: entry.family, side: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(entry.detail)
                        .helperTextStyle()
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 96, maxHeight: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(.primary.opacity(0.07)))
            .contentShape(.rect(cornerRadius: Radius.card))
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityElement(children: .combine)
    }
}

struct HomeGoal: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let tools: [SidebarItem]
    var top = 3

    static var all: [HomeGoal] {
        let create = HomeGoal(id: "create", title: L("Create an Image or Video"), detail: L("Describe an idea, or add a photo and pick an effect."),
                              symbol: NavCatalog.familySymbol("create"), tools: NavCatalog.create, top: 4)
        return [create] + NavCatalog.families.map { family in
            HomeGoal(id: family.id, title: family.title, detail: detail(family.id), symbol: NavCatalog.familySymbol(family.id),
                     tools: family.items, top: ["photo", "ads"].contains(family.id) ? 4 : 3)
        }
    }

    private static func detail(_ id: String) -> String {
        switch id {
        case "photo": L("Background, quality, light and touch-ups in words.")
        case "people": L("Photo sessions, swaps and stories with the same face.")
        case "video": L("Animate a photo, make an avatar talk or film a scene.")
        case "videoEdit": L("Change, lengthen, trim or reshape a clip.")
        case "productPhotos": L("Studio, model and store photos of your product.")
        case "ads": L("Ads and videos that sell, ready to post.")
        default: ""
        }
    }

    static func family(of item: SidebarItem) -> String {
        let row = NavCatalog.rowItem(for: item) ?? item
        return NavCatalog.families.first { $0.items.contains(row) }?.id ?? "create"
    }
}

private struct GoalCard: View {
    let goal: HomeGoal
    let showsAll: Bool
    let toggle: () -> Void

    var body: some View {
        let hasMore = goal.tools.count > goal.top
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                FamilyStyle.tile(symbol: goal.symbol, family: goal.id, side: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(goal.detail)
                        .helperTextStyle()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(showsAll || !hasMore ? goal.tools : Array(goal.tools.prefix(goal.top)), id: \.self) { item in
                    HomeToolLink(item: item)
                        .transition(Motion.transition(.opacity.combined(with: .offset(y: -4))))
                }
            }
            if hasMore {
                Button(action: toggle) {
                    Label(showsAll ? L("Show fewer") : L("See all tools (%ld)", goal.tools.count),
                          systemImage: showsAll ? "chevron.up" : "chevron.down")
                        .font(.callout)
                }
                .buttonStyle(.link)
                .padding(.leading, 8)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: .rect(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(.primary.opacity(0.07)))
    }
}

private struct HomeToolLink: View {
    let item: SidebarItem
    @Environment(AppModel.self) private var app
    @State private var isHovering = false

    var body: some View {
        Button {
            app.selection = item
        } label: {
            HStack(spacing: 8) {
                Image(systemName: NavCatalog.symbol(item))
                    .fontWeight(IconScale.weight)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(NavCatalog.title(item))
                        .font(.body)
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .fineTextStyle()
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .opacity(isHovering ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(minHeight: 32)
            .background(Color.primary.opacity(isHovering ? 0.06 : 0), in: .rect(cornerRadius: Radius.thumb))
            .contentShape(.rect(cornerRadius: Radius.thumb))
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering in withAnimation(Motion.fade) { isHovering = hovering } }
        .help(subtitle)
    }

    private var subtitle: String { HomeToolText.subtitle(item) }
}

private struct RecentToolCard: View {
    let item: SidebarItem
    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            app.selection = item
        } label: {
            HStack(spacing: 12) {
                FamilyStyle.tile(symbol: NavCatalog.symbol(item), family: HomeGoal.family(of: item), side: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(HomeToolText.title(item))
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(HomeToolText.subtitle(item))
                        .helperTextStyle()
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(.primary.opacity(0.07)))
            .contentShape(.rect(cornerRadius: Radius.card))
        }
        .buttonStyle(CardButtonStyle(isCompact: true))
    }
}

enum HomeToolText {
    static func title(_ item: SidebarItem) -> String {
        if case .tool(let tool) = item, NavCatalog.swapTools.contains(tool) { return tool.title }
        return NavCatalog.title(item)
    }

    static func subtitle(_ item: SidebarItem) -> String {
        switch item {
        case .tool(.video): VideoCatalog.tool("createVideo")?.subtitle ?? ""
        case .tool(let tool): tool.subtitle
        case .video(let id): VideoCatalog.tool(id)?.subtitle ?? ""
        case .videoEffects: VideoCatalog.tool("videoEffects")?.subtitle ?? ""
        case .ad(let id): AdCatalog.tool(id)?.subtitle ?? ""
        case .apps: Tool.app.subtitle
        case .productEffects: L("One-click photos of your product.")
        default: ""
        }
    }
}

private struct HomeStartArea: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pickedID: UUID?
    @State private var wasImported = false
    @State private var isImporting = false
    @State private var isTargeted = false
    @State private var isHovering = false
    @State private var dragEntries = 0

    private static let recentCount = 5

    var body: some View {
        Group {
            if let asset = pickedID.flatMap(app.library.asset) {
                picked(asset)
                    .transition(Motion.transition(.opacity.combined(with: .scale(scale: 0.98))))
            } else {
                empty
                    .transition(.opacity)
            }
        }
        .overlay {
            if isImporting {
                RoundedRectangle(cornerRadius: Radius.card)
                    .fill(.background.opacity(0.7))
                    .overlay {
                        VStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(L("Importing…")).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .transition(.opacity)
            }
        }
        .animation(Motion.fade, value: isImporting)
        .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { providers in
            Task { await importDropped(providers) }
            return true
        }
        .onChange(of: isTargeted) { _, targeted in
            if targeted { dragEntries += 1 }
        }
        .onPasteCommand(of: [.fileURL, .image]) { providers in
            Task { await importDropped(providers) }
        }
    }

    private var empty: some View {
        let latest = Array(app.library.assets.prefix(Self.recentCount))
        return VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .iconSymbol(IconScale.hero)
                .foregroundStyle(isTargeted ? Color.appAccent : .secondary)
                .symbolEffect(.bounce, value: reduceMotion ? 0 : dragEntries)
            VStack(spacing: 4) {
                Text(L("Start with a photo or a video")).font(.title3.weight(.semibold))
                Text(L("Drop it here, paste it (⌘V) or choose it, and pick what to do with it."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(L("Choose File…"), systemImage: "folder", action: choose)
                .buttonStyle(.glass)
            if !latest.isEmpty {
                VStack(spacing: 8) {
                    Text(L("Or use one of your latest:"))
                        .helperTextStyle()
                    HStack(spacing: 8) {
                        ForEach(latest) { asset in
                            latestButton(asset)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, latest.isEmpty ? 16 : 20)
        .frame(maxWidth: .infinity, minHeight: 150)
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
        .onHover { isHovering = $0 }
        .onTapGesture(perform: choose)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Start with a photo or a video"))
        .accessibilityAction(named: L("Choose File…"), choose)
    }

    private func latestButton(_ asset: Asset) -> some View {
        Button {
            pick(asset, imported: false)
        } label: {
            AssetThumbnail(asset: asset, maxPixel: 160)
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: Radius.thumb))
                .overlay(alignment: .bottomLeading) {
                    if asset.isVideo {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .shadow(radius: 2)
                    }
                }
                .contentShape(.rect(cornerRadius: Radius.thumb))
        }
        .buttonStyle(CardButtonStyle(isCompact: true))
        .help(asset.isVideo ? L("Use this video") : L("Use this photo"))
        .accessibilityLabel(asset.isVideo ? L("Use this video") : L("Use this photo"))
    }

    private func picked(_ asset: Asset) -> some View {
        HStack(alignment: .top, spacing: 18) {
            AssetThumbnail(asset: asset, maxPixel: 400)
                .frame(width: 150, height: 150)
                .clipShape(.rect(cornerRadius: Radius.tile))
                .overlay(alignment: .bottomLeading) {
                    if asset.isVideo, let duration = asset.duration {
                        Label(VideoPlayback.durationLabel(duration), systemImage: "play.fill")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .glassEffect(in: .capsule)
                            .padding(6)
                    }
                }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(asset.isVideo ? L("What should we do with this video?") : L("What should we do with this photo?"))
                            .font(.title3.weight(.semibold))
                        if wasImported {
                            Label(L("Saved to your Library"), systemImage: "checkmark.circle")
                                .fineTextStyle()
                        }
                    }
                    Spacer(minLength: 8)
                    Button(L("Use Another"), systemImage: "arrow.uturn.backward") {
                        withAnimation(reduceMotion ? nil : Motion.standard) { pickedID = nil }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.regular)
                }
                FlowLayout(spacing: 8) {
                    if asset.isVideo { videoActions(asset) } else { photoActions(asset) }
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03), in: .rect(cornerRadius: Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(isTargeted ? Color.appAccent : Color.primary.opacity(0.08), lineWidth: isTargeted ? 2 : 1)
                .animation(Motion.standard, value: isTargeted)
        }
    }

    @ViewBuilder private func photoActions(_ asset: Asset) -> some View {
        ForEach([Tool.background, .upscale, .edit]) { tool in
            Button(tool.title, systemImage: tool.systemImage) { app.open(tool, with: asset) }
        }
        ForEach(["animateImage", "videoEffects"], id: \.self) { id in
            if let tool = VideoCatalog.tool(id) {
                Button(tool.name, systemImage: tool.symbol) { app.makeVideo(from: asset, in: id) }
            }
        }
        Menu(L("More"), systemImage: "ellipsis") {
            Section(L("Open In")) {
                ForEach(Tool.editingTools) { tool in
                    Button(tool.title, systemImage: tool.systemImage) { app.open(tool, with: asset) }
                }
            }
            Section(L("Make a Video")) {
                MakeVideoItems(asset: asset)
            }
            Button(L("Use as Reference"), systemImage: "photo.badge.plus") { app.useAsReference(asset) }
        }
        .menuStyle(.button)
        .fixedSize()
    }

    @ViewBuilder private func videoActions(_ asset: Asset) -> some View {
        ForEach(["editVideo", "extendVideo", "reframeVideo", "hookCheck"], id: \.self) { id in
            if let tool = VideoCatalog.tool(id) {
                Button(tool.name, systemImage: tool.symbol) { app.openVideoTool(id, with: asset) }
            }
        }
        Menu(L("More"), systemImage: "ellipsis") {
            ForEach(VideoFollowUp.tools) { tool in
                Button(tool.name, systemImage: tool.symbol) { app.openVideoTool(tool.id, with: asset) }
            }
        }
        .menuStyle(.button)
        .fixedSize()
    }

    private func pick(_ asset: Asset, imported: Bool) {
        withAnimation(reduceMotion ? nil : Motion.standard) {
            pickedID = asset.id
            wasImported = imported
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L("Choose a photo or a video")
        panel.prompt = L("Use")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await importFile(url) }
    }

    private func importFile(_ url: URL) async {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType ?? UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .movie) == true {
            await importMovie(url)
        } else if let data = try? Data(contentsOf: url), let asset = app.library.importImage(data: data, name: url.lastPathComponent) {
            pick(asset, imported: true)
        }
    }

    private func importDropped(_ providers: [NSItemProvider]) async {
        for provider in providers {
            if let movie = await ImageIntake.movieURL(from: provider) {
                await importMovie(movie)
                return
            }
        }
        if let data = await ImageIntake.data(from: providers).first,
           let asset = app.library.importImage(data: data, name: E("Imported") + ".png") {
            pick(asset, imported: true)
        }
    }

    private func importMovie(_ url: URL) async {
        isImporting = true
        defer { isImporting = false }
        if let asset = await app.library.importVideo(url: url) {
            pick(asset, imported: true)
        } else {
            app.presentError(LibraryImport.unreadableVideos(1))
        }
    }
}

struct ProductEffectsView: View {
    @Environment(AppModel.self) private var app
    @State private var path: [String] = []

    var body: some View {
        let items = NavCatalog.productEffects
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    PageHeader(title: L("Product Effects"),
                               detail: L("One-click photos of your product: pick an effect, add the product and generate. No text to write."))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                        ForEach(items) { item in
                            AppCard(item: item) { path.append(item.id) }
                        }
                    }
                    Button(L("See All Photo Effects"), systemImage: Tool.app.systemImage) { app.selection = .apps }
                        .buttonStyle(.glass)
                }
                .pageContainer()
            }
            .navigationTitle(L("Product Effects"))
            .navigationSubtitle(L("%ld effects", items.count))
            .navigationDestination(for: String.self) { id in
                if let item = AppCatalog.item(id) {
                    AppRunner(item: item)
                }
            }
        }
    }
}
