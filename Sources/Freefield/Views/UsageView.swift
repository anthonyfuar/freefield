import Charts
import FreefieldCore
import SwiftUI
import UniformTypeIdentifiers

struct UsageView: View {
    enum PeriodChoice: String, CaseIterable, Identifiable {
        case today, week, month, custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .today: L("Today")
            case .week: L("This week")
            case .month: L("This month")
            case .custom: L("Date range")
            }
        }
    }

    enum Grouping: String, CaseIterable, Identifiable {
        case tool, model
        var id: String { rawValue }
        var title: String { self == .tool ? L("By tool") : L("By AI model") }
    }

    @Environment(AppModel.self) private var app
    @State private var choice: PeriodChoice = .month
    @State private var rangeStart = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
    @State private var rangeEnd = Date.now
    @State private var grouping: Grouping = .tool
    @State private var expandedEntryID: UUID?

    private var period: UsagePeriod {
        switch choice {
        case .today: .today
        case .week: .week
        case .month: .month
        case .custom: .custom(start: rangeStart, end: rangeEnd)
        }
    }

    var body: some View {
        let interval = period.interval()
        let entries = app.library.usage(in: interval)
        let total = entries.reduce(0) { $0 + $1.cost }
        let images = entries.filter { $0.kind != .video }.reduce(0) { $0 + $1.imageCount }
        let paidImages = entries.filter { $0.kind == .image }.reduce(0) { $0 + $1.imageCount }
        let videoEntries = entries.filter { $0.kind == .video }
        let clips = videoEntries.reduce(0) { $0 + $1.imageCount }
        let videoSeconds = videoEntries.reduce(0) { $0 + ($1.seconds ?? 0) }
        let estimated = entries.contains(where: \.isEstimated)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: L("Usage & Limits"),
                           detail: L("Everything Freefield spent on your AI accounts: what, when and how much, with the images and videos it produced."))

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 12) {
                        periodPicker
                        if choice == .custom { dateRange }
                        Spacer(minLength: 12)
                        exportButton(entries)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        periodPicker
                        HStack(alignment: .center, spacing: 12) {
                            if choice == .custom { dateRange }
                            Spacer(minLength: 12)
                            exportButton(entries)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        periodPicker
                        if choice == .custom { dateRange }
                        exportButton(entries)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        periodMenu
                        if choice == .custom { dateRange }
                        exportButton(entries)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        StatTile(title: L("Spent"), value: AppModel.money(total),
                                 detail: estimated ? L("Includes estimates") : L("Real cost reported by the provider"), isLarge: true)
                        if let balance {
                            StatTile(title: L("Available balance"), value: AppModel.money(balance.amount),
                                     detail: L("Left in your %@ account", balance.provider.displayName), isLarge: true)
                        }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: videoEntries.isEmpty ? 3 : 4),
                              spacing: 12) {
                    StatTile(title: L("Images"), value: "\(images)", detail: L("%ld generated with AI", paidImages))
                    if !videoEntries.isEmpty {
                        StatTile(title: L("Videos"), value: "\(clips)",
                                 detail: L("%@ of video · %@", UsageRow.secondsLabel(videoSeconds),
                                           AppModel.money(videoEntries.reduce(0) { $0 + $1.cost })))
                    }
                    StatTile(title: L("Times you used AI"), value: "\(entries.count)", detail: L("Generations and AI assistant"))
                    StatTile(title: L("Average per image"), value: paidImages > 0 ? AppModel.money(entries.filter { $0.kind == .image }.reduce(0) { $0 + $1.cost } / Double(paidImages)) : "—",
                             detail: L("AI images only"))
                    }
                }

                LimitsSection()

                if entries.isEmpty {
                    ContentUnavailableView(L("No activity in this period"), systemImage: "chart.bar",
                                           description: Text(L("Generate something and it will appear here with its cost.")))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(L("Spending over time")).sectionTitleStyle()
                            Spacer()
                            Picker(L("Chart colors"), selection: $grouping) {
                                ForEach(Grouping.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                        }
                        UsageChart(entries: entries, interval: interval, hourly: choice == .today, grouping: grouping)
                            .frame(height: 240)
                    }

                    HStack(alignment: .top, spacing: 18) {
                        BreakdownTable(title: L("By tool"), rows: breakdown(entries) { toolName($0) }, total: total)
                        BreakdownTable(title: L("By AI model"), rows: breakdown(entries) { $0.modelName }, total: total)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Detail")).sectionTitleStyle()
                        ForEach(entries) { entry in
                            UsageRow(entry: entry, isExpanded: expandedEntryID == entry.id) {
                                withAnimation(Motion.standard) { expandedEntryID = expandedEntryID == entry.id ? nil : entry.id }
                            }
                            Divider()
                        }
                    }
                }
            }
            .pageContainer()
        }
        .navigationTitle(L("Usage & Limits"))
        .navigationSubtitle(AppModel.money(total))
    }

    private var periodPicker: some View {
        Picker(L("Period"), selection: $choice) {
            ForEach(PeriodChoice.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    private var periodMenu: some View {
        Picker(L("Period"), selection: $choice) {
            ForEach(PeriodChoice.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }

    private var dateRange: some View {
        HStack(spacing: 12) {
            DatePicker(L("From"), selection: $rangeStart, displayedComponents: .date)
            DatePicker(L("To"), selection: $rangeEnd, in: rangeStart..., displayedComponents: .date)
        }
        .fixedSize()
    }

    private func exportButton(_ entries: [UsageEntry]) -> some View {
        Button(L("Export to Spreadsheet…"), systemImage: "square.and.arrow.up") { export(entries) }
            .buttonStyle(.glass)
            .fixedSize()
            .disabled(entries.isEmpty)
    }

    private var balance: (provider: Provider, amount: Double)? {
        for provider in Provider.allCases {
            if let amount = app.catalog.accounts[provider]?.remainingCredits { return (provider, amount) }
        }
        return nil
    }

    private func toolName(_ entry: UsageEntry) -> String {
        UsageRow.toolName(entry, library: app.library)
    }

    private func breakdown(_ entries: [UsageEntry], key: (UsageEntry) -> String) -> [(name: String, count: Int, cost: Double)] {
        var groups: [String: (count: Int, cost: Double)] = [:]
        for entry in entries {
            let name = key(entry)
            let current = groups[name] ?? (0, 0)
            groups[name] = (current.count + max(entry.imageCount, entry.kind == .text ? 1 : 0), current.cost + entry.cost)
        }
        return groups.map { (name: $0.key, count: $0.value.count, cost: $0.value.cost) }.sorted { $0.cost > $1.cost }
    }

    private func export(_ entries: [UsageEntry]) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Freefield-usage.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let formatter = ISO8601DateFormatter()
        var lines = ["date,kind,tool,title,model,provider,images,cost_usd,estimated,video_seconds"]
        for entry in entries {
            let fields = [
                formatter.string(from: entry.date), entry.kind.rawValue, entry.tool?.rawValue ?? "", entry.title,
                entry.modelName, entry.provider?.displayName ?? "", "\(entry.imageCount)",
                String(format: "%.5f", entry.cost), entry.isEstimated ? "yes" : "no",
                entry.seconds.map { String(format: "%.1f", $0) } ?? "",
            ]
            lines.append(fields.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ","))
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let detail: String
    var isLarge = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: isLarge ? 6 : 4) {
            Text(title).font(isLarge ? .body.weight(.semibold) : .subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: isLarge ? 34 : 28, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(reduceMotion ? .opacity : .numericText())
                .animation(Motion.standard, value: value)
            Text(detail).helperTextStyle().lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: isLarge ? 120 : 92, alignment: .topLeading)
        .padding(isLarge ? 18 : 14)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: Radius.card))
    }
}

struct UsageChart: View {
    let entries: [UsageEntry]
    let interval: DateInterval
    let hourly: Bool
    let grouping: UsageView.Grouping

    @Environment(AppModel.self) private var app

    static let maxSeries = 6

    var body: some View {
        let series = series()
        let axis = axis()
        Chart(Array(zip(entries, series.names).enumerated()), id: \.offset) { _, pair in
            BarMark(
                x: .value(L("Date"), pair.0.date, unit: hourly ? .hour : .day),
                y: .value(L("Spent"), pair.0.cost)
            )
            .foregroundStyle(by: .value(grouping.title, pair.1))
        }
        .chartForegroundStyleScale(domain: series.domain)
        .chartXScale(domain: interval.start...interval.end)
        .chartYScale(domain: 0...(axis.ticks.last ?? 1))
        .chartYAxis {
            AxisMarks(values: axis.ticks) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) { Text(AppModel.money(amount, decimals: axis.decimals)) }
                }
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .font(.callout)
    }

    private func axis() -> (ticks: [Double], decimals: Int) {
        let calendar = Calendar.current
        var bars: [Date: Double] = [:]
        for entry in entries {
            let bar = hourly ? calendar.dateInterval(of: .hour, for: entry.date)?.start ?? entry.date : calendar.startOfDay(for: entry.date)
            bars[bar, default: 0] += entry.cost
        }
        let top = max(bars.values.max() ?? 0, 0.04)
        let rough = top / 4
        let magnitude = pow(10, (log10(rough)).rounded(.down))
        let step = [1.0, 2, 5, 10].map { $0 * magnitude }.first { $0 >= rough * 0.999 } ?? magnitude * 10
        let count = max(1, Int((top / step - 0.001).rounded(.up)))
        let places = max(0, Int(-(log10(step)).rounded(.down)))
        return ((0...count).map { Double($0) * step }, places == 1 ? 2 : min(places, 3))
    }

    private func series() -> (names: [String], domain: [String]) {
        let names = entries.map { grouping == .tool ? UsageRow.toolName($0, library: app.library) : $0.modelName }
        var spend: [String: Double] = [:]
        for (entry, name) in zip(entries, names) { spend[name, default: 0] += entry.cost }
        let ranked = spend.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
        guard ranked.count > Self.maxSeries else { return (names, ranked) }
        let shown = Array(ranked.prefix(Self.maxSeries))
        let other = L("Other")
        return (names.map { shown.contains($0) ? $0 : other }, shown + [other])
    }
}

struct BreakdownTable: View {
    let title: String
    let rows: [(name: String, count: Int, cost: Double)]
    let total: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.bold())
            ForEach(rows.prefix(8), id: \.name) { row in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(row.name).lineLimit(1)
                        Spacer()
                        Text("\(row.count)").foregroundStyle(.secondary).monospacedDigit()
                        Text(AppModel.money(row.cost)).monospacedDigit().frame(minWidth: 70, alignment: .trailing)
                    }
                    .font(.callout)
                    GeometryReader { proxy in
                        Capsule().fill(.quaternary)
                            .overlay(alignment: .leading) {
                                Capsule().fill(Color.brand)
                                    .frame(width: total > 0 ? proxy.size.width * row.cost / total : 0)
                            }
                    }
                    .frame(height: 5)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: Radius.card))
    }
}

struct UsageRow: View {
    let entry: UsageEntry
    let isExpanded: Bool
    let toggle: () -> Void

    @Environment(AppModel.self) private var app

    static func toolName(_ entry: UsageEntry, library: Library) -> String {
        guard let tool = entry.tool else { return L("AI assistant") }
        guard tool == .video else { return tool.title }
        return entry.appID.flatMap(VideoCatalog.tool)?.name
            ?? entry.assetIDs.lazy.compactMap({ library.asset($0)?.appID }).compactMap(VideoCatalog.tool).first?.name
            ?? L("Video tools")
    }

    static func secondsLabel(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return total < 60 ? L("%ld s", total) : L("%ld min %ld s", total / 60, total % 60)
    }

    private var placeholderSymbol: String {
        switch entry.kind {
        case .text: "text.bubble"
        case .video: "film"
        default: "photo"
        }
    }

    var body: some View {
        let assets = entry.assetIDs.compactMap { app.library.asset($0) }
        let toolName = Self.toolName(entry, library: app.library)
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggle) {
                HStack(spacing: 12) {
                    ZStack {
                        if let first = assets.first {
                            AssetThumbnail(asset: first, maxPixel: 120)
                        } else {
                            Image(systemName: placeholderSymbol)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(.rect(cornerRadius: Radius.thumb))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title.isEmpty ? toolName : RecordTitle.localized(entry.title))
                            .lineLimit(1)
                        Text("\(toolName) · \(entry.modelName)")
                            .fineTextStyle()
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        .fineTextStyle()
                    if entry.kind == .video {
                        Label(entry.seconds.map(Self.secondsLabel) ?? "\(entry.imageCount)", systemImage: "film")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .help(entry.imageCount == 1 ? L("1 clip") : L("%ld clips", entry.imageCount))
                    } else if entry.imageCount > 0 {
                        Label("\(entry.imageCount)", systemImage: "photo")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.kind == .local ? L("Free") : AppModel.money(entry.cost) + (entry.isEstimated ? " *" : ""))
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .frame(minWidth: 76, alignment: .trailing)
                        .help(entry.isEstimated ? L("Estimated: the provider did not report the price.") : L("Real cost reported by the provider."))
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if isExpanded {
                if assets.isEmpty {
                    Text(entry.kind == .text ? L("The AI assistant produces text, not images.")
                         : entry.kind == .video ? L("The clips of this operation were deleted.") : L("The images of this operation were deleted."))
                        .helperTextStyle()
                        .padding(.leading, 52)
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(assets) { asset in
                                AssetCard(asset: asset, maxPixel: 500)
                                    .frame(height: 150)
                                    .onTapGesture(count: 2) { app.quickLook(asset) }
                            }
                        }
                        .padding(.leading, 52)
                    }
                    .scrollIndicators(.never)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

enum RecordTitle {
    private static let renamed = [
        "Enhance prompt": "Improve description", "Translate prompt to English": "Translate description to English",
        "Angles": "Other Angles", "Color Grade": "Color Filters", "Edit Text": "Change Text", "Storyboard": "Photo Story",
        "Upscale Video": "Improve Video Quality", "Reframe Video": "Change Video Shape", "Motion Transfer": "Copy a Movement",
        "Hook Check": "Does My Video Hook?", "Draw to Video": "Draw the Movement", "Storyboard to Video": "Photos to Video",
        "Swap in Video": "Swap a Person in Video", "Relight": "Change the Light", "Expand": "Widen the Frame",
        "Draw to Edit": "Draw Instructions",
    ]

    private struct Format {
        let key: String
        let names: Bool
        let regex: NSRegularExpression
        let kinds: [String]
    }

    private static let formats: [Format] = [
        ("Upscale %@", false), ("Light: %@", true), ("Angle: %@", true), ("Expand to %@", false), ("Background: %@", false),
        ("Character: %@", false), ("Color Grade: %@", true), ("Orbit: %ld° · tilt %ld° · zoom %.1f×", false),
        ("Scene %ld: %@", false), ("Analyze moodboard: %@", false), ("%ld shots joined", false), ("%ld clips", false),
    ].compactMap { key, names in
        var pattern = "^", kinds: [String] = []
        var rest = Substring(key)
        while let range = rest.range(of: #"%(@|ld|\.1f)"#, options: .regularExpression) {
            pattern += NSRegularExpression.escapedPattern(for: String(rest[..<range.lowerBound]))
            switch rest[range] {
            case "%@": pattern += "(.+?)"; kinds.append("@")
            case "%ld": pattern += "(-?\\d+)"; kinds.append("d")
            default: pattern += "(-?\\d+(?:\\.\\d+)?)"; kinds.append("f")
            }
            rest = rest[range.upperBound...]
        }
        pattern += NSRegularExpression.escapedPattern(for: String(rest)) + "((?: · .*)?)$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else { return nil }
        return Format(key: key, names: names, regex: regex, kinds: kinds)
    }

    static func localized(_ title: String) -> String {
        let title = renamed[title] ?? title
        let exact = L(title)
        if exact != title { return exact }
        let first = title.components(separatedBy: " · ")[0]
        if L(first) == first, let match = formatted(title) { return match.shown + parts(match.rest) }
        return parts(title)
    }

    private static func parts(_ text: String) -> String {
        text.components(separatedBy: " · ").map(part).joined(separator: " · ")
    }

    private static func part(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let text = renamed[text] ?? text
        let exact = L(text)
        if exact != text { return exact }
        if let match = formatted(text), match.rest.isEmpty { return match.shown }
        if let colon = text.range(of: ": ") {
            let head = String(text[..<colon.lowerBound])
            let shown = L(head)
            if shown != head { return shown + text[colon.lowerBound...] }
        }
        return text
    }

    private static func formatted(_ text: String) -> (shown: String, rest: String)? {
        for format in formats {
            guard let match = format.regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { continue }
            func group(_ index: Int) -> String {
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
            let values = format.kinds.enumerated().map { index, kind -> CVarArg in
                let value = group(index + 1)
                switch kind {
                case "d": return Int(value) ?? 0
                case "f": return Double(value) ?? 0
                default: return format.names ? L(value) : value
                }
            }
            return (String(format: L(format.key), locale: .current, arguments: values), group(format.kinds.count + 1))
        }
        return nil
    }
}

struct LimitsSection: View {
    @Environment(AppModel.self) private var app
    @AppStorage(UsageLimits.dailyKey) private var daily = 0.0
    @AppStorage(UsageLimits.weeklyKey) private var weekly = 0.0
    @AppStorage(UsageLimits.monthlyKey) private var monthly = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Spending limits")).sectionTitleStyle()
            Text(L("When a limit is reached, Freefield refuses new generations until the period ends. Leave it off for no limit."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: PageLayout.textWidth, alignment: .leading)
            LimitRow(title: L("Limit per day"), period: .today, amount: $daily)
            LimitRow(title: L("Limit per week"), period: .week, amount: $weekly)
            LimitRow(title: L("Limit per month"), period: .month, amount: $monthly)
        }
        .padding(16)
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: Radius.card))
    }
}

struct LimitRow: View {
    let title: String
    let period: UsagePeriod
    @Binding var amount: Double

    @Environment(AppModel.self) private var app
    @State private var draft = ""
    @FocusState private var isEditing: Bool

    static func parse(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite, value > 0 else { return nil }
        return value
    }

    static func format(_ value: Double) -> String { String(format: "%.2f", value) }

    var body: some View {
        let spent = app.library.spent(in: period.interval())
        let isOn = amount > 0
        let progress = isOn ? min(spent / amount, 1) : 0
        HStack(spacing: 14) {
            Text(title)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)
            Toggle(title, isOn: Binding(get: { isOn }, set: { amount = $0 ? max(Self.parse(draft) ?? 5, 0.5) : 0 }))
                .toggleStyle(.switch)
                .labelsHidden()
            HStack(spacing: 2) {
                Text("$")
                TextField(L("Amount"), text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .focused($isEditing)
                    .onSubmit(showSaved)
            }
            .disabled(!isOn)
            if isOn {
                ProgressView(value: progress)
                    .tint(progress >= 1 ? .red : progress > 0.8 ? .orange : .brand)
                    .frame(maxWidth: 320)
                    .transition(.opacity)
            }
            Text(isOn ? L("%@ of %@", AppModel.money(spent), AppModel.money(amount)) : L("Spent %@", AppModel.money(spent)))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(progress >= 1 ? .red : .secondary)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 0)
        }
        .animation(Motion.standard, value: isOn)
        .onAppear { draft = amount > 0 ? Self.format(amount) : "5.00" }
        .onChange(of: draft) {
            guard amount > 0, let value = Self.parse(draft), value != amount else { return }
            amount = value
        }
        .onChange(of: isEditing) { _, editing in if !editing { showSaved() } }
        .onChange(of: amount) { _, value in
            if value > 0, !isEditing || Self.parse(draft) != value { draft = Self.format(value) }
        }
    }

    private func showSaved() {
        if amount > 0 { draft = Self.format(amount) }
    }
}
