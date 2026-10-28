import FreefieldCore
import SwiftUI

struct AppsGallery: View {
    @Environment(AppModel.self) private var app
    @State private var path: [String] = []
    @State private var search = ""
    @State private var category = AppCatalog.allCategory

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PageHeader(title: L("Photo Effects"),
                               detail: L("One-click styles and extras: upload a photo, pick a variant and generate. No prompts to write."))
                    CategoryChips(categories: AppCatalog.categoryNames, selection: $category)

                    let items = AppCatalog.filtered(category: category, search: search)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                        ForEach(items) { item in
                            AppCard(item: item) { path.append(item.id) }
                        }
                    }
                    if items.isEmpty { ContentUnavailableView.search(text: search) }
                }
                .pageContainer()
            }
            .searchable(text: $search, placement: .toolbar, prompt: L("Search photo effects"))
            .navigationTitle(L("Photo Effects"))
            .navigationSubtitle(L("%ld effects", AppCatalog.all.count))
            .navigationDestination(for: String.self) { id in
                if let item = AppCatalog.item(id) {
                    AppRunner(item: item)
                }
            }
        }
        .onAppear(perform: openPending)
        .onChange(of: app.pendingQuickStyle) { openPending() }
    }

    private func openPending() {
        guard let id = app.pendingQuickStyle else { return }
        app.pendingQuickStyle = nil
        if AppCatalog.item(id) != nil { path = [id] }
    }
}

struct AppCard: View {
    let item: AppItem
    let action: () -> Void
    @Environment(AppModel.self) private var app

    private static let focus = UnitPoint(x: 0.5, y: 0.3)

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay {
                        ZStack {
                            Color.primary.opacity(0.04)
                            if let latest = app.library.assets.first(where: { $0.appID == item.id }) {
                                ThumbnailImage(url: app.library.url(for: latest), maxPixel: 500, focus: Self.focus)
                            } else if let example = Examples.appResult(item.id) {
                                ThumbnailImage(url: example, maxPixel: 500, focus: Self.focus)
                            } else {
                                IconTile(symbol: item.symbol, size: .large)
                            }
                        }
                    }
                    .clipped()
                .overlay(alignment: .bottomLeading) {
                    if app.library.assets.first(where: { $0.appID == item.id }) == nil,
                       let input = Examples.appInput(item.id) {
                        ThumbnailImage(url: input, maxPixel: 160)
                            .frame(width: 38, height: 38)
                            .clipShape(.rect(cornerRadius: Radius.thumb))
                            .overlay(RoundedRectangle(cornerRadius: Radius.thumb).strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                            .shadow(radius: 3)
                            .padding(8)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.name).font(.headline).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        if let badge = item.badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.brand.opacity(0.18), in: .capsule)
                                .foregroundStyle(Color.brand)
                                .fixedSize()
                        }
                    }
                    Text(item.subtitle).helperTextStyle().lineLimit(3, reservesSpace: true)
                    Label(item.slots.count == 1 ? L("1 image · one click") : L("%ld images · one click", item.slots.count),
                          systemImage: "hand.tap")
                        .fineTextStyle()
                        .lineLimit(1)
                }
                .padding(12)
            }
            .background(.background.secondary)
            .clipShape(.rect(cornerRadius: Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(.primary.opacity(0.07)))
            .contentShape(.rect(cornerRadius: Radius.card))
        }
        .buttonStyle(CardButtonStyle())
        .help(item.subtitle)
    }
}

struct AppRunner: View {
    let item: AppItem

    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inputs: [Data?] = []
    @State private var option: String?
    @State private var text = ""
    @State private var extra = ""
    @State private var count = 1
    @State private var modelID: String?
    @State private var aspect: AspectRatio = .auto
    @State private var selectedResultID: UUID?

    private var requirement: ModelRequirement {
        ModelRequirement(images: item.slots.count, minimumImages: item.slots.count > 1 ? item.slots.count : 0)
    }

    var body: some View {
        let state = app.composer(for: .app)
        let model = resolvedModel(state)
        let hasResults = !FeedModel(app: app, tool: .app, appID: item.id).isEmpty
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 14) {
                        IconTile(symbol: item.symbol, size: .large)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).toolTitleStyle()
                            Text(item.subtitle).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    CollapsibleExample(id: "app.\(item.id)", hasResults: hasResults) {
                        QuickStyleExample(item: item)
                    }

                    HStack(alignment: .top, spacing: 14) {
                        ForEach(Array(item.slots.enumerated()), id: \.offset) { index, slot in
                            PanelSection(title: slot.label, systemImage: slot.symbol) {
                                ImageWell(title: slot.label, subtitle: slot.hint, systemImage: slot.symbol,
                                          data: binding(for: index), minHeight: 200, isInPanel: true)
                                    .frame(height: 230)
                            }
                            .frame(maxWidth: 360)
                        }
                    }
                    if let related = item.related {
                        RelatedToolHint(prompt: related.prompt, links: related.tools.map { app.relatedLink($0, image: inputs.first ?? nil) })
                    }

                    textInputs(model)

                    if !item.options.isEmpty {
                        PanelSection(title: item.optionTitle ?? L("Variant"), systemImage: "square.grid.3x3") {
                            ChoiceChips(values: item.options,
                                        pictures: OptionImages.pictures(family: "apps/\(item.id)", values: item.options),
                                        isSelected: { (option ?? item.options.first) == $0 }) { value in
                                option = value
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 20) {
                        if item.splitsIntoCells {
                            ContactSheetPicker(item: item, selectedID: $selectedResultID)
                        }
                        ResultsGrid(appID: item.id, selectedID: $selectedResultID)
                    }
                    .id("results")
                }
                .padding(24)
                .frame(maxWidth: 980, alignment: .leading)
            }
            .pinnedActionBar(maxWidth: 980) {
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(alignment: .bottom, spacing: 8) {
                        FlowLayout(spacing: 8) {
                            if let model, !model.aspectRatios.isEmpty {
                                AspectRatioMenu(selection: $aspect, available: model.aspectRatios)
                            }
                            CountMenu(count: $count, maximum: 4)
                            MoreOptionsChip(summary: modelSummary(model), help: L("AI model")) {
                                PanelSection(title: L("AI model"), systemImage: "cpu") {
                                    ModelPicker(selectionID: $modelID, current: model, requirement: requirement)
                                    if let model {
                                        Text(app.catalog.choice(for: model).tagline)
                                            .helperTextStyle()
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        GenerateButton(title: count > 1 ? L("Generate %ld images", count) : L("Generate"),
                                       isEnabled: disabledReason(model) == nil, disabledReason: disabledReason(model),
                                       estimatedCost: app.estimatedCost(model: model, count: count, resolution: item.resolution)) {
                            run(model, proxy: proxy)
                        }
                    }
                    DisabledReasonLabel(reason: disabledReason(model))
                }
                .animation(reduceMotion ? nil : Motion.standard, value: disabledReason(model))
            }
        }
        .navigationTitle(item.name)
        .onAppear {
            if inputs.count != item.slots.count { inputs = Array(repeating: nil, count: item.slots.count) }
            if let handoff = app.takeHandoff(for: .app), !inputs.isEmpty { inputs[0] = handoff }
            aspect = item.aspect
        }
    }

    @ViewBuilder private func textInputs(_ model: ImageModel?) -> some View {
        if let placeholder = item.textPlaceholder {
            PanelSection(title: item.textTitle ?? L("Details (optional)"), systemImage: "text.cursor") {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(2...4)
                    .inputBox()
                    .characterLimit($text, item.textLimit(model: model))
            }
            if item.takesExtraInstructions {
                ExtraInstructionField(text: $extra, placeholder: extraPlaceholder, limit: item.extraLimit(model: model))
            }
        } else {
            ExtraInstructionField(text: $text, placeholder: L("E.g. keep my glasses, navy blue background"),
                                  limit: item.textLimit(model: model))
        }
    }

    private var extraPlaceholder: String {
        switch item.id {
        case "poster": L("E.g. pastel colors and a lot of empty space")
        case "meme": L("E.g. a reaction-meme look with the text at the bottom")
        default: L("E.g. walking toward the camera, sleeves rolled up")
        }
    }

    private func binding(for index: Int) -> Binding<Data?> {
        Binding(
            get: { index < inputs.count ? inputs[index] : nil },
            set: { value in
                if inputs.count != item.slots.count { inputs = Array(repeating: nil, count: item.slots.count) }
                inputs[index] = value
            }
        )
    }

    private func resolvedModel(_ state: ComposerState) -> ImageModel? {
        let (featured, others) = app.choices(for: requirement)
        if let modelID, let match = (featured + others).first(where: { $0.model.id == modelID }) { return match.model }
        for lineupID in (item.model.map { [$0] } ?? []) + Lineup.defaultModelIDs(for: .app) {
            if let match = featured.first(where: { $0.lineup?.id == lineupID }) { return match.model }
        }
        return featured.first?.model
    }

    private func modelSummary(_ model: ImageModel?) -> String {
        guard modelID != nil, let model else { return L("Auto") }
        return app.catalog.choice(for: model).displayName
    }

    private func disabledReason(_ model: ImageModel?) -> String? {
        if !app.hasAnyKey { return L("Add an API key in Settings") }
        if inputs.count < item.slots.count || inputs.contains(where: { $0 == nil }) {
            return L("Add: %@", item.slots.map(\.label).joined(separator: L(" and ")).lowercased())
        }
        if model == nil { return app.catalog.isLoading ? L("Loading models…") : L("No compatible model available") }
        return nil
    }

    private func run(_ model: ImageModel?, proxy: ScrollViewProxy) {
        guard let model, disabledReason(model) == nil else { return }
        app.runApp(item, inputs: inputs.compactMap { $0 }, option: option ?? item.options.first, text: text, extra: extra,
                   model: model, aspect: aspect, count: count)
        Task {
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(reduceMotion ? nil : Motion.emphasized) { proxy.scrollTo("results", anchor: .top) }
        }
    }
}

struct ResultsGrid: View {
    var tool: Tool = .app
    let appID: String
    @Binding var selectedID: UUID?
    @Environment(AppModel.self) private var app

    var body: some View {
        let feed = FeedModel(app: app, tool: tool, appID: appID)
        if !feed.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(L("Results")).groupTitleStyle()
                        .fixedSize()
                    Label(L("Saved to your Library automatically"), systemImage: "checkmark.circle")
                        .fineTextStyle()
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(L("Saved to your Library automatically"))
                    Text(feed.subtitle).fineTextStyle()
                        .fixedSize()
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                    ForEach(feed.batches) { batch in
                        ForEach(batch.slots) { slot in
                            FeedSlotView(slot: slot, batch: batch, failedAspect: 1, height: 240, keepsShape: false) { asset in
                                VStack(spacing: 6) {
                                    AssetCard(asset: asset, isSelected: selectedID == asset.id, maxPixel: 600)
                                        .frame(height: 240)
                                        .onTapGesture { selectedID = asset.id }
                                        .onTapGesture(count: 2) { app.quickLook(asset) }
                                    videoFollowUp(asset)
                                }
                            }
                        }
                    }
                }
                .animation(Motion.emphasized, value: feed.slotKeys)
            }
        }
    }

    @ViewBuilder private func videoFollowUp(_ asset: Asset) -> some View {
        Group {
            if let effect = app.pairedEffect(for: asset) {
                ViewThatFits(in: .horizontal) {
                    Button(L("Animate with %@", effect.name), systemImage: effect.symbol) { app.animate(asset, with: effect) }
                        .help(L("Opens Video Effects with this image as the finished start frame, so the style isn't made again"))
                    Button(L("Animate"), systemImage: effect.symbol) { app.animate(asset, with: effect) }
                        .help(L("Animate with %@: opens Video Effects with this image as the finished start frame, so the style isn't made again",
                                effect.name))
                }
            } else if tool == .ad, !asset.isVideo, let videoAd = VideoCatalog.tool("videoAd") {
                Button(L("Animate as Ad"), systemImage: videoAd.symbol) { app.animateAsAd(asset) }
                    .help(L("Opens Video Ad as a hook video with this image as the start frame"))
            }
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .lineLimit(1)
    }
}

extension AppItem {
    var related: (prompt: String, tools: [RelatedTool])? {
        switch id {
        case "ai-stylist", "style-snap": (L("Have a photo of the garment?"), [.tool(.outfitSwap)])
        case "headshot": (L("Want many photos of you?"), [.tool(.photoSession)])
        case "shots", "zooms": (L("Want each angle as its own photo?"), [.tool(.angles)])
        default: category == L("Ads & Products") ? (L("Making an ad?"), [.ad("product-shoot"), .ad("static-ad")]) : nil
        }
    }
}
