import FreefieldCore
import SwiftUI

struct CreateView: View {
    static let columnWidth: CGFloat = 940

    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedAssetID: UUID?
    @State private var showInspector = false
    @AppStorage("feedCardHeight") private var cardHeight = 300.0

    private var composer: ComposerState { app.composer(for: .create) }

    var body: some View {
        let feed = FeedModel(app: app, tool: .create)
        ZStack {
            if feed.isEmpty {
                CreateEmptyState(composer: composer)
                    .transition(.opacity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 28) {
                            ForEach(feed.batches) { batch in
                                BatchRow(batch: batch, selectedAssetID: $selectedAssetID, cardHeight: cardHeight) { asset in
                                    selectedAssetID = asset.id
                                    showInspector = true
                                }
                                .id(batch.id)
                                .transition(Motion.transition(.opacity.combined(with: .offset(y: -8))))
                            }
                        }
                        .animation(Motion.emphasized, value: feed.batches.map(\.id))
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 20)
                    }
                    .scrollEdgeEffectStyle(.soft, for: .bottom)
                    .onChange(of: feed.batches.first?.id) { old, new in
                        guard let new, new != old, let job = feed.batches.first?.job,
                              job.createdAt.timeIntervalSinceNow > -5 else { return }
                        withAnimation(reduceMotion ? nil : Motion.emphasized) { proxy.scrollTo(new, anchor: .top) }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.fade, value: feed.isEmpty)
        .safeAreaBar(edge: .bottom) {
            Composer(state: composer)
                .frame(maxWidth: Self.columnWidth)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .navigationTitle(L("Create Image"))
        .navigationSubtitle(feed.subtitle)
        .inspector(isPresented: $showInspector) {
            Group {
                if let id = selectedAssetID, let asset = app.library.asset(id) {
                    AssetInspector(asset: asset)
                } else {
                    ContentUnavailableView(L("No Selection"), systemImage: "photo", description: Text(L("Choose an image to see its details.")))
                }
            }
            .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker(L("Card Size"), selection: $cardHeight) {
                        Text(L("Small")).tag(200.0)
                        Text(L("Medium")).tag(300.0)
                        Text(L("Large")).tag(420.0)
                        Text(L("Huge")).tag(560.0)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(L("View"), systemImage: "rectangle.grid.2x2")
                }
                .help(L("Feed card size"))
            }
            ToolbarItem {
                Button(L("Details"), systemImage: "sidebar.right") { showInspector.toggle() }
                    .help(L("Show or hide details (⌥⌘I)"))
                    .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
        .onAppear {
            if let data = app.takeHandoff(for: .create) { composer.references.append(data) }
        }
    }
}

struct CreateEmptyState: View {
    let composer: ComposerState
    @Environment(AppModel.self) private var app
    @State private var pulses = !Self.didPulse
    private static var didPulse = false
    @State private var stripEdges = StripEdges()

    private let ideas: [(String, String, String)] = [
        ("editorial-portrait", L("Editorial Portrait"), L("Editorial portrait of a young woman with freckles in a sage linen blazer, soft window light, shot on 85mm, shallow depth of field")),
        ("premium-product", L("Premium Product"), L("Minimal luxury perfume bottle on a travertine pedestal, warm morning sun shadows, beige backdrop, high-end product photography")),
        ("tokyo-street", L("Tokyo Street"), L("Street style photo of a skater crossing a rainy Tokyo alley at night, neon reflections, 35mm film grain")),
        ("cozy-interior", L("Cozy Interior"), L("Cozy Scandinavian reading nook with a wool armchair, plants and a big window overlooking snowy pines, golden hour")),
        ("epic-fantasy", L("Epic Fantasy"), L("A lone knight on a cliff facing a colossal dragon emerging from storm clouds, cinematic lighting, ultra detailed matte painting")),
        ("food", L("Food"), L("Overhead shot of a rustic Mexican breakfast: chilaquiles, café de olla and pan dulce on a wooden table, natural light")),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                VStack(spacing: 8) {
                    IconTile(symbol: Tool.create.systemImage, size: .large)
                        .symbolEffect(.pulse, options: .repeat(2), isActive: pulses)
                        .onAppear { Self.didPulse = true }
                    Text(L("What shall we create?"))
                        .displayTitleStyle()
                    Text(L("Describe an idea below, pick a style, or start with one of these examples."))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)

                VStack(spacing: 22) {
                    stylesStrip
                    examples
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    }

    private var stylesStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("Popular styles")).sectionTitleStyle()
                Spacer()
                Button(L("See All")) { app.selection = .styles }
                    .buttonStyle(.link)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(StylePresets.featured) { preset in
                        PresetCard(preset: preset, isSelected: composer.presetID == preset.id, size: 120) {
                            composer.presetID = composer.presetID == preset.id ? nil : preset.id
                        }
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, Self.liftMargin)
            }
            .scrollIndicators(.never)
            .onScrollGeometryChange(for: StripEdges.self) { geometry in
                StripEdges(atStart: geometry.contentOffset.x <= 1,
                           atEnd: geometry.contentOffset.x + geometry.containerSize.width >= geometry.contentSize.width - 1)
            } action: { _, edges in
                stripEdges = edges
            }
            .mask { StripFade(edges: stripEdges, margin: Self.liftMargin) }
            .padding(.horizontal, -Self.liftMargin)
        }
        .frame(maxWidth: CreateView.columnWidth)
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Start with an example")).sectionTitleStyle()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)], spacing: 12) {
                ForEach(ideas, id: \.0) { idea in
                    Button {
                        composer.prompt = idea.2
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            if let picture = Self.ideaPicture(idea.0) {
                                ThumbnailImage(url: picture, maxPixel: 320)
                                    .frame(width: 96, height: 72)
                                    .clipShape(.rect(cornerRadius: Radius.thumb))
                                    .accessibilityHidden(true)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(idea.1).font(.headline)
                                Text(idea.2).helperTextStyle()
                                    .lineLimit(3, reservesSpace: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: Radius.card))
                        .contentShape(.rect(cornerRadius: Radius.card))
                    }
                    .buttonStyle(CardButtonStyle())
                }
            }
        }
        .frame(maxWidth: CreateView.columnWidth, alignment: .leading)
    }

    private static let liftMargin: CGFloat = 4

    private static func ideaPicture(_ slug: String) -> URL? {
        Bundle.main.url(forResource: slug, withExtension: "heic", subdirectory: "Examples/create/ideas")
    }

    nonisolated struct StripEdges: Equatable {
        var atStart = true
        var atEnd = false
    }

    private struct StripFade: View {
        let edges: StripEdges
        let margin: CGFloat

        var body: some View {
            HStack(spacing: 0) {
                Rectangle().opacity(edges.atStart ? 1 : 0).frame(width: margin)
                LinearGradient(colors: [.black.opacity(edges.atStart ? 1 : 0), .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 28)
                Rectangle()
                LinearGradient(colors: [.black, .black.opacity(edges.atEnd ? 1 : 0)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 28)
                Rectangle().opacity(edges.atEnd ? 1 : 0).frame(width: margin)
            }
            .animation(Motion.fade, value: edges)
        }
    }
}

struct BatchRow: View {
    let batch: FeedBatch
    @Binding var selectedAssetID: UUID?
    var cardHeight: Double = 300
    var onSelect: (Asset) -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(batch.title)
                        .font(.callout)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    FlowLayout(spacing: 6) {
                        ForEach(batch.chips, id: \.self) { chip in
                            Text(chip)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(.quaternary.opacity(0.6), in: .capsule)
                        }
                        Text(batch.date, format: .relative(presentation: .named))
                            .fineTextStyle()
                            .fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Menu(L("More"), systemImage: "ellipsis") {
                    if let first = batch.assets.first {
                        Button(L("Reuse Prompt"), systemImage: "arrow.counterclockwise") { app.reuse(first) }
                    }
                    Button(L("Export All…"), systemImage: "square.and.arrow.down") { app.export(batch.assets) }
                    if let job = batch.job {
                        if job.isRunning {
                            Button(L("Cancel"), systemImage: "stop.circle") { app.engine.cancel(job) }
                        } else {
                            Button(L("Remove from Feed"), systemImage: "xmark") { app.engine.dismiss(job) }
                        }
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(batch.slots) { slot in
                        FeedSlotView(slot: slot, batch: batch, height: cardHeight) { asset in
                            AssetCard(asset: asset, isSelected: selectedAssetID == asset.id, maxPixel: Int(cardHeight * 3))
                                .onTapGesture { onSelect(asset) }
                                .onTapGesture(count: 2) { app.quickLook(asset) }
                        }
                        .frame(height: cardHeight)
                    }
                }
                .animation(Motion.emphasized, value: batch.slotKeys)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)
        }
    }
}

struct FeedBatch: Identifiable {
    let id: UUID
    var title: String
    var date: Date
    var assets: [Asset]
    var job: Job?
    var aspect: Double
    var chips: [String]

    var pending: Int { job?.pending ?? 0 }

    var failure: String? {
        guard let job else { return nil }
        if case .failed(let message) = job.status { return message }
        if !job.failures.isEmpty, !job.isRunning, job.received < job.requested {
            return L("%ld of %ld failed: %@", job.requested - job.received, job.requested, job.failures[0])
        }
        return nil
    }

    var slots: [FeedSlot] {
        guard let job else { return assets.map { FeedSlot(id: .asset($0.id), content: .asset($0)) } }
        var slots: [FeedSlot] = []
        for (place, id) in job.assetIDs.enumerated() {
            if let asset = assets.first(where: { $0.id == id }) { slots.append(FeedSlot(id: .arrival(place), content: .asset(asset))) }
        }
        var next = job.assetIDs.count
        for _ in 0..<pending {
            slots.append(FeedSlot(id: .arrival(next), content: .pending))
            next += 1
        }
        if let failure { slots.append(FeedSlot(id: .arrival(next), content: .failed(failure))) }
        for asset in assets where !job.assetIDs.contains(asset.id) {
            slots.append(FeedSlot(id: .asset(asset.id), content: .asset(asset)))
        }
        return slots
    }

    var slotKeys: [FeedSlot.Key] { slots.map { FeedSlot.Key(batch: id, slot: $0) } }
}

struct FeedSlot: Identifiable {
    enum Place: Hashable {
        case arrival(Int)
        case asset(UUID)
    }

    enum Content {
        case asset(Asset)
        case pending
        case failed(String)
    }

    let id: Place
    let content: Content

    struct Key: Hashable {
        let batch: UUID
        let place: Place
        let assetID: UUID?
        let isFailed: Bool

        init(batch: UUID, slot: FeedSlot) {
            self.batch = batch
            place = slot.id
            switch slot.content {
            case .asset(let asset): assetID = asset.id; isFailed = false
            case .pending: assetID = nil; isFailed = false
            case .failed: assetID = nil; isFailed = true
            }
        }
    }
}

struct FeedModel {
    let batches: [FeedBatch]
    let subtitle: String

    var isEmpty: Bool { batches.isEmpty }

    var slotKeys: [FeedSlot.Key] { batches.flatMap(\.slotKeys) }

    init(app: AppModel, tool: Tool, appID: String? = nil) {
        var assetsByBatch: [UUID: [Asset]] = [:]
        var order: [UUID] = []
        for asset in app.library.assets where asset.tool == tool && (appID == nil || asset.appID == appID) {
            if assetsByBatch[asset.batchID] == nil { order.append(asset.batchID) }
            assetsByBatch[asset.batchID, default: []].append(asset)
        }
        let jobs = app.engine.jobs.filter { $0.tool == tool && (appID == nil || $0.spec?.appID == appID) }
        var batches: [FeedBatch] = []
        var seen = Set<UUID>()
        for job in jobs {
            let assets = (assetsByBatch[job.id] ?? []).sorted { $0.createdAt < $1.createdAt }
            seen.insert(job.id)
            let ratio = job.aspectRatio == .auto ? 1 : job.aspectRatio.ratio
            batches.append(FeedBatch(id: job.id, title: job.title, date: job.createdAt, assets: assets, job: job,
                                     aspect: assets.first?.aspect ?? ratio, chips: Self.chips(for: assets.first, app: app)))
        }
        for batchID in order where !seen.contains(batchID) {
            let assets = (assetsByBatch[batchID] ?? []).sorted { $0.createdAt < $1.createdAt }
            guard let first = assets.first else { continue }
            batches.append(FeedBatch(id: batchID, title: first.prompt, date: first.createdAt, assets: assets, job: nil,
                                     aspect: first.aspect, chips: Self.chips(for: first, app: app)))
        }
        batches.sort { $0.date > $1.date }
        self.batches = batches
        let count = batches.reduce(0) { $0 + $1.assets.count }
        subtitle = count == 0 ? "" : count == 1 ? L("1 image") : L("%ld images", count)
    }

    static func chips(for asset: Asset?, app: AppModel) -> [String] {
        guard let asset else { return [] }
        var chips = [asset.modelDisplayName]
        if let preset = asset.presetID.flatMap(StylePresets.preset) { chips.append(preset.name) }
        if let character = app.library.character(asset.characterID) { chips.append(character.name) }
        if asset.aspectRatio != .auto { chips.append(asset.aspectRatio.label) }
        return chips
    }
}
