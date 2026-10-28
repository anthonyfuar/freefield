import FreefieldCore
import QuickLook
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var app = app
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 260, ideal: 272, max: 340)
        } detail: {
            detail
                .frame(minWidth: PanelLayout.canvasMinWidth, minHeight: 480)
        }
        .sheet(isPresented: $app.showOnboarding) {
            OnboardingView()
        }
        .alert(L("Something went wrong"),
               isPresented: Binding(get: { app.presentedError != nil }, set: { if !$0 { app.presentedError = nil } }),
               presenting: app.presentedError) { _ in
            Button(L("OK")) {}
        } message: { message in
            Text(message)
        }
        .quickLookPreview($app.quickLookURL, in: app.library.assets.map { app.library.url(for: $0) })
        .task {
            #if DEBUG
            DebugHooks.install(app: app)
            DebugHooks.openSettings = { openSettings() }
            #endif
            await app.refreshModels()
        }
    }

    @ViewBuilder private var detail: some View {
        switch app.selection ?? .home {
        case .home:
            HomeView()
        case .tool(.create):
            CreateView()
        case .tool(.storyboard):
            StoryboardView()
        case .tool(.photoSession):
            PhotoSessionView()
        case .tool(.colorGrade):
            ColorGradeView()
        case .tool(.video):
            videoDetail("createVideo")
        case .video(let id):
            videoDetail(id)
        case .videoEffects:
            videoDetail("videoEffects")
        case .tool(let tool):
            ToolWorkspace(tool: tool)
                .id(tool)
        case .styles:
            StylesGallery()
        case .characters:
            if app.charactersPage == .builder {
                CharacterBuilderView()
            } else {
                CharactersView()
            }
        case .products:
            ProductsView()
        case .ad(let id):
            if let tool = AdCatalog.tool(id) {
                AdRunner(tool: tool).id(id)
            }
        case .apps:
            AppsGallery()
        case .productEffects:
            ProductEffectsView()
        case .library:
            LibraryView(filter: .all)
        case .favorites:
            LibraryView(filter: .favorites)
        case .usage:
            UsageView()
        case .settings:
            InlineSettingsView()
        }
    }

    @ViewBuilder private func videoDetail(_ id: String) -> some View {
        if let tool = VideoCatalog.tool(id) {
            Group {
                switch id {
                case "cinemaStudio": CinemaStudioView(tool: tool)
                case "storyboardVideo": StoryboardVideoView(tool: tool)
                case "talkingAvatar": TalkingAvatarView(tool: tool)
                case "videoEffects": VideoEffectsView()
                case "drawToVideo": DrawToVideoView(tool: tool)
                case "reframeVideo": ReframeView(tool: tool)
                case "joinClips": JoinTrimView(tool: tool)
                case "hookCheck": HookCheckView(tool: tool)
                default: VideoRunner(tool: tool)
                }
            }
            .id(id)
        } else {
            ContentUnavailableView(L("Tool not found"), systemImage: "film",
                                   description: Text(L("This video tool isn't available in this version of Freefield.")))
        }
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var openFamily: String?
    @State private var search = ""
    @State private var pickedHere: SidebarItem?

    var body: some View {
        let selection = Binding<SidebarItem?>(
            get: { NavCatalog.rowItem(for: app.selection) },
            set: { newValue in
                guard let newValue, newValue != NavCatalog.rowItem(for: app.selection) else { return }
                pickedHere = newValue
                app.selection = newValue
            }
        )
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let home = Self.filtered([SidebarGroup(id: "home", title: "", rows: [row(for: .home)])], query: query)
        let sections = Self.filtered(self.sections, query: query)
        let families = Self.filtered(self.families, query: query)
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                List(selection: selection) {
                    ForEach(home) { group in ForEach(group.rows) { row($0) } }
                    if !families.isEmpty {
                        Section(L("Tools")) {
                            ForEach(families) { family($0, searching: !query.isEmpty) }
                        }
                    }
                    ForEach(sections) { plainSection($0) }
                    if home.isEmpty, sections.isEmpty, families.isEmpty {
                        Text(L("No tool matches “%@”", query))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .selectionDisabled()
                    }
                }
                .listStyle(.sidebar)
                .environment(\.sidebarRowSize, .large)
                .scrollEdgeEffectStyle(.hard, for: .top)
                Divider().opacity(0.5)
                AccountFooter()
            }
            .searchable(text: $search, placement: .sidebar, prompt: L("Search tools"))
            .onAppear { show(app.selection, proxy: proxy) }
            .onChange(of: app.selection) { _, item in
                if let row = NavCatalog.rowItem(for: item), row == pickedHere {
                    reveal(item)
                } else {
                    show(item, proxy: proxy)
                }
            }
        }
    }

    private func show(_ item: SidebarItem?, proxy: ScrollViewProxy) {
        pickedHere = nil
        reveal(item)
        guard let row = NavCatalog.rowItem(for: item) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(reduceMotion ? nil : Motion.standard) { proxy.scrollTo(row) }
        }
    }

    private var sections: [SidebarGroup] {
        [
            SidebarGroup(id: "mine", title: L("My Stuff"), rows: [
                row(for: .library, count: app.library.assets.count, keywords: [L("Favorites")]),
                row(for: .characters, count: app.library.characters.count,
                    keywords: [L("Locations"), L("Objects"), L("Design a Character"), L("Character Builder")]),
                row(for: .products, count: app.library.products.count),
                row(for: .styles),
            ]),
        ]
    }

    private var families: [SidebarGroup] {
        NavCatalog.kinds.map { kind in
            SidebarGroup(id: kind.id, title: kind.title, symbol: NavCatalog.familySymbol(kind.id),
                         parts: kind.parts.map { SidebarPart(id: $0.id, title: $0.title, rows: $0.items.map { row(for: $0) }) })
        }
    }

    private func row(for item: SidebarItem, count: Int? = nil, keywords: [String] = []) -> SidebarRow {
        var keywords = keywords + (NavCatalog.formerNames[item] ?? [])
        switch item {
        case .tool(.faceSwap): keywords += NavCatalog.swapTools.map(\.title)
        case .productEffects: keywords += NavCatalog.productEffects.map(\.name)
        default: break
        }
        return SidebarRow(item: item, title: NavCatalog.title(item), symbol: NavCatalog.symbol(item), running: running(item),
                          count: count, keywords: keywords)
    }

    private func plainSection(_ group: SidebarGroup) -> some View {
        Section(group.title) {
            ForEach(group.rows) { row($0) }
        }
    }

    private func family(_ group: SidebarGroup, searching: Bool) -> some View {
        let isOpen = searching || openFamily == group.id
        return DisclosureGroup(isExpanded: Binding(get: { isOpen }, set: { open in
            if !searching, open != (openFamily == group.id) { toggle(group.id) }
        })) {
            ForEach(group.parts) { part in
                if !part.title.isEmpty {
                    Text(part.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.top, part.id == group.parts.first?.id ? 2 : 10)
                        .selectionDisabled()
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(part.rows) { row($0) }
            }
        } label: {
            HStack {
                Label {
                    Text(group.title)
                        .fontWeight(.medium)
                } icon: {
                    FamilyStyle.tile(symbol: group.symbol ?? "folder", family: group.id, side: 22)
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                if !isOpen {
                    ZStack(alignment: .trailing) {
                        if group.running > 0 {
                            RunningBadge(count: group.running)
                                .transition(.opacity)
                        } else {
                            Text("\(group.rows.count)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .transition(.opacity)
                        }
                    }
                    .animation(Motion.fade, value: group.running > 0)
                }
            }
            .contentShape(.rect)
            .onTapGesture { if !searching { toggle(group.id) } }
            .help(isOpen ? L("Hide these tools") : L("Show these tools"))
        }
    }

    private static func filtered(_ groups: [SidebarGroup], query: String) -> [SidebarGroup] {
        guard !query.isEmpty else { return groups }
        let matches = { (text: String) in text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        return groups.compactMap { group in
            if !group.title.isEmpty, matches(group.title) { return group }
            var group = group
            group.parts = group.parts.compactMap { part in
                if !part.title.isEmpty, matches(part.title) { return part }
                var part = part
                part.rows = part.rows.filter { matches($0.title) || $0.keywords.contains(where: matches) }
                return part.rows.isEmpty ? nil : part
            }
            return group.parts.isEmpty ? nil : group
        }
    }

    private func toggle(_ id: String) {
        withAnimation(reduceMotion ? nil : Motion.standard) {
            openFamily = openFamily == id ? nil : id
        }
    }

    private func reveal(_ item: SidebarItem?) {
        guard let item = NavCatalog.rowItem(for: item),
              let group = families.first(where: { $0.rows.contains { $0.item == item } }),
              openFamily != group.id else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { openFamily = group.id }
    }

    private func running(_ item: SidebarItem) -> Int {
        switch item {
        case .tool(.faceSwap): NavCatalog.swapTools.reduce(0) { $0 + running($1) }
        case .tool(let tool): running(tool)
        case .video(let id): runningVideo(id)
        case .ad(let id): runningAds(id)
        case .apps: running(.app)
        case .productEffects:
            app.engine.jobs.filter { job in
                job.tool == .app && job.isRunning && NavCatalog.productEffects.contains { $0.id == job.spec?.appID }
            }.count
        default: 0
        }
    }

    private func runningAds(_ id: String) -> Int {
        app.engine.jobs.filter { $0.tool == .ad && $0.spec?.appID == id && $0.isRunning }.count
    }

    private func runningVideo(_ id: String) -> Int {
        let jobs = app.engine.jobs.filter { job in
            job.isRunning && (job.videoSpec?.toolID == id || (job.videoSpec == nil && job.tool == .video && job.spec?.appID == id))
        }.count
        guard let state = app.videoStates[id] else { return jobs }
        let local = state.localWork.filter(\.isRunning).count
        return jobs + local + (state.isPreparing && jobs + local == 0 ? 1 : 0)
    }

    private func running(_ tool: Tool) -> Int {
        app.engine.jobs.filter { $0.tool == tool && $0.isRunning }.count
    }

    private func row(_ row: SidebarRow) -> some View {
        HStack {
            Label {
                Text(row.title)
            } icon: {
                ZStack {
                    if row.running > 0 {
                        RunningIcon(count: row.running)
                            .transition(.opacity)
                    } else {
                        SidebarSymbol(name: row.symbol)
                            .transition(.opacity)
                    }
                }
                .animation(Motion.fade, value: row.running > 0)
            }
            Spacer(minLength: 4)
            if let count = row.count, count > 0 {
                Text("\(count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(count)))
                    .animation(Motion.standard, value: count)
            }
        }
        .tag(row.item)
        .id(row.item)
    }
}

private struct SidebarSymbol: View {
    let name: String
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        let symbol = Image(systemName: name)
            .fontWeight(IconScale.weight)
            .symbolRenderingMode(.hierarchical)
        if prominence == .increased {
            symbol
        } else {
            symbol.foregroundStyle(.secondary)
        }
    }
}

private struct RunningIcon: View {
    let count: Int

    var body: some View {
        ProgressView()
            .controlSize(.small)
            .overlay(alignment: .bottomTrailing) {
                if count > 1 {
                    Text("\(count)")
                        .font(.system(size: 8, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.brand)
                        .padding(.horizontal, 2)
                        .background(.background, in: .capsule)
                        .offset(x: 5, y: 3)
                }
            }
            .help(count == 1 ? L("1 generation in progress") : L("%ld generations in progress", count))
            .accessibilityLabel(count == 1 ? L("1 generation in progress") : L("%ld generations in progress", count))
    }
}

struct RunningBadge: View {
    let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            ProgressView().controlSize(.mini)
            Text("\(count)").monospacedDigit()
                .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(count)))
                .animation(Motion.standard, value: count)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.brand)
        .help(count == 1 ? L("1 generation in progress") : L("%ld generations in progress", count))
    }
}

struct AccountFooter: View {
    @Environment(AppModel.self) private var app

    static let lowBalance = 2.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !app.hasAnyKey {
                Button {
                    app.showOnboarding = true
                } label: {
                    Label(L("Connect an API key"), systemImage: "key.fill")
                        .frame(maxWidth: .infinity)
                        .prominentLabel()
                }
                .buttonStyle(.glassProminent)
                .tint(.brandFill)
            } else {
                ForEach(app.keys.configuredProviders) { provider in
                    balance(provider)
                }
            }
            EqualWidthButtons(spacing: 6) {
                link(.usage, L("Usage & Limits"), "chart.bar.xaxis")
                link(.settings, L("Settings"), "gearshape")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func balance(_ provider: Provider) -> some View {
        let remaining = app.catalog.accounts[provider]?.remainingCredits
        let isLow = (remaining ?? .infinity) < Self.lowBalance
        return Button {
            app.selection = .usage
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(app.catalog.errors[provider] == nil ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(provider.displayName).font(.callout.weight(.medium))
                Spacer()
                if app.catalog.loading.contains(provider) {
                    ProgressView().controlSize(.mini)
                } else if let remaining {
                    Text(L("Balance %@", AppModel.money(remaining, decimals: 2)))
                        .font(.callout.monospacedDigit().weight(isLow ? .semibold : .regular))
                        .foregroundStyle(isLow ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(app.catalog.errors[provider]
              ?? (isLow ? L("Your balance on %@ is running low. Click to see your usage.", provider.displayName)
                        : L("Balance available on %@. Click to see your usage.", provider.displayName)))
    }

    @ViewBuilder
    private func link(_ item: SidebarItem, _ title: String, _ symbol: String) -> some View {
        let button = Button {
            app.selection = item
        } label: {
            Label(title, systemImage: symbol)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.regular)
        if app.selection == item {
            button.buttonStyle(.glassProminent)
                .tint(.brandFill)
        } else {
            button.buttonStyle(.glass)
        }
    }
}

private struct EqualWidthButtons: Layout {
    var spacing: CGFloat = 6

    private func arrangement(width: CGFloat?, subviews: Subviews) -> (sizes: [CGSize], inRow: Bool, width: CGFloat) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let count = CGFloat(max(1, sizes.count))
        let rowWidth = (sizes.map(\.width).max() ?? 0) * count + spacing * (count - 1)
        let width = width ?? rowWidth
        return (sizes, rowWidth <= width, width)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (sizes, inRow, width) = arrangement(width: proposal.width, subviews: subviews)
        let heights = sizes.map(\.height)
        let height = inRow ? heights.max() ?? 0 : heights.reduce(0, +) + spacing * CGFloat(max(0, heights.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (sizes, inRow, _) = arrangement(width: bounds.width, subviews: subviews)
        let count = CGFloat(max(1, sizes.count))
        let share = (bounds.width - spacing * (count - 1)) / count
        var origin = bounds.origin
        for (index, size) in sizes.enumerated() {
            let width = inRow ? share : bounds.width
            subviews[index].place(at: origin, proposal: ProposedViewSize(width: width, height: size.height))
            if inRow { origin.x += share + spacing } else { origin.y += size.height + spacing }
        }
    }
}
