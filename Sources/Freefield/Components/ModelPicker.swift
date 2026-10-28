import FreefieldCore
import SwiftUI

struct ModelRequirement {
    var images = 0
    var minimumImages = 0
    var promptLength = 0

    func allows(_ model: ImageModel) -> Bool {
        if promptLength > 0, PromptBudget.modelLimit(model) < promptLength + PromptBudget.minimum { return false }
        if minimumImages > 0, model.maxReferences < minimumImages { return false }
        if images > 0 { return model.maxReferences >= min(images, 1) }
        return !model.requiresImageInput
    }
}

extension AppModel {
    func choices(for requirement: ModelRequirement) -> (featured: [ModelChoice], others: [ModelChoice]) {
        let featured = catalog.featuredChoices(preferring: preferredProvider).filter { requirement.allows($0.model) }
        let others = UserDefaults.standard.bool(forKey: SettingsKey.showAllModels)
            ? catalog.otherChoices(preferring: preferredProvider).filter { requirement.allows($0.model) }
            : []
        return (featured, others)
    }

    func resolvedModel(for state: ComposerState, requirement: ModelRequirement) -> ImageModel? {
        let (featured, others) = choices(for: requirement)
        let all = featured + others
        if let id = state.modelID, let match = all.first(where: { $0.model.id == id }) { return match.model }
        let defaults = Lineup.defaultModelIDs(for: state.tool)
        for lineupID in defaults {
            if let match = featured.first(where: { $0.lineup?.id == lineupID && !catalog.strained.contains($0.model.id) }) {
                return match.model
            }
        }
        return featured.first { !catalog.strained.contains($0.model.id) }?.model ?? featured.first?.model ?? others.first?.model
    }

    func estimatedCost(model: ImageModel?, count: Int, resolution: Resolution) -> Double? {
        guard let model else { return nil }
        guard let perImage = library.averageCost(modelID: model.id) ?? model.estimatedCostPerImage else { return nil }
        let factor: Double = switch model.bestResolution(for: resolution) {
        case .fourK: model.provider == .google || model.vendor == "Google" ? 1.8 : 2.5
        case .twoK: model.provider == .google || model.vendor == "Google" ? 1.0 : 1.6
        default: 1
        }
        return perImage * factor * Double(count)
    }
}

struct ModelPicker: View {
    @Binding var selectionID: String?
    let current: ImageModel?
    var requirement = ModelRequirement()

    @Environment(AppModel.self) private var app
    @State private var isPresented = false
    @State private var search = ""

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                Text(label)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.glass)
        .fixedSize()
        .help(selectionID == nil ? L("AI model, chosen automatically for this tool") : L("AI model"))
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            popover
        }
    }

    private var label: String {
        guard let current else { return app.catalog.isLoading ? L("Loading…") : L("Choose Model") }
        let name = app.catalog.choice(for: current).displayName
        return selectionID == nil ? L("Auto · %@", name) : name
    }

    private enum LineupRow: Identifiable {
        case available(ModelChoice)
        case locked(LineupModel, Provider)

        var id: String {
            switch self {
            case .available(let choice): choice.id
            case .locked(let entry, _): "locked:\(entry.id)"
            }
        }

        var isFeatured: Bool {
            switch self {
            case .available(let choice): choice.lineup?.isFeatured == true
            case .locked(let entry, _): entry.isFeatured
            }
        }

        var order: Int {
            let id = switch self {
            case .available(let choice): choice.lineup?.id
            case .locked(let entry, _): entry.id
            }
            return Lineup.models.firstIndex { $0.id == id } ?? Int.max
        }
    }

    private var popover: some View {
        let (featured, others) = app.choices(for: requirement)
        let filter: (ModelChoice) -> Bool = { choice in
            search.isEmpty
                || choice.displayName.localizedCaseInsensitiveContains(search)
                || choice.model.vendor.localizedCaseInsensitiveContains(search)
                || choice.model.modelID.localizedCaseInsensitiveContains(search)
        }
        let locked = app.catalog.lockedEntries(configured: app.keys.configuredProviders)
            .filter { search.isEmpty || $0.entry.name.localizedCaseInsensitiveContains(search) }
            .map { LineupRow.locked($0.entry, $0.provider) }
        return VStack(spacing: 0) {
            TextField(L("Search models"), text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(12)
            Divider()
            if featured.isEmpty && others.isEmpty {
                ContentUnavailableView {
                    Label(app.hasAnyKey ? L("No Models") : L("No API Key"), systemImage: "cpu")
                } description: {
                    Text(app.hasAnyKey ? L("Check your connection or your keys in Settings.") : L("Add an OpenRouter or Google API key in Settings."))
                } actions: {
                    SettingsLink { Text(L("Open Settings")) }
                }
                .frame(height: 240)
            } else {
                List {
                    if search.isEmpty {
                        Button {
                            selectionID = nil
                            isPresented = false
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: selectionID == nil ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectionID == nil ? Color.appAccent : .secondary)
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(L("Automatic (recommended)")).font(.body.weight(.semibold))
                                    Text(L("Freefield picks the best model for this tool and skips busy ones."))
                                        .helperTextStyle()
                                }
                                Spacer()
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 3)
                    }
                    let lineupRows = (featured.filter(filter).map(LineupRow.available) + locked).sorted { $0.order < $1.order }
                    let highlighted = lineupRows.filter(\.isFeatured)
                    let rest = lineupRows.filter { !$0.isFeatured }
                    if !highlighted.isEmpty {
                        Section(L("Featured")) {
                            ForEach(highlighted) { lineupRow($0) }
                        }
                    }
                    if !rest.isEmpty {
                        Section(L("All Models")) {
                            ForEach(rest) { lineupRow($0) }
                        }
                    }
                    let shownOthers = others.filter(filter)
                    if !shownOthers.isEmpty {
                        Section(L("More Models")) {
                            ForEach(shownOthers) { row($0) }
                        }
                    }
                    if !locked.isEmpty {
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
        .frame(width: 440, height: 520)
    }

    @ViewBuilder private func lineupRow(_ row: LineupRow) -> some View {
        switch row {
        case .available(let choice): self.row(choice)
        case .locked(let entry, let provider): LockedModelRow(name: entry.name, tagline: entry.tagline, provider: provider)
        }
    }

    private func row(_ choice: ModelChoice) -> some View {
        let model = choice.model
        let isSelected = selectionID != nil && current?.id == model.id
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
                        Text(choice.displayName).font(.body.weight(.semibold))
                            .lineLimit(1)
                            .layoutPriority(1)
                        if app.catalog.strained.contains(model.id) { badge(L("Busy now"), color: .orange) }
                        if let text = choice.badge { badge(text, color: .brand) }
                    }
                    Text(choice.tagline)
                        .helperTextStyle()
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    FlowLayout(spacing: 8) {
                        Text("\(model.vendor) · \(model.provider.displayName)")
                        if model.acceptsImageInput { Label(L("Edits"), systemImage: "photo.badge.plus") }
                        if let top = model.resolutions.last { Label(top.rawValue, systemImage: "square.resize") }
                        if model.maxImagesPerRequest > 1 { Label("×\(model.maxImagesPerRequest)", systemImage: "square.grid.2x2") }
                        if model.outputsVector { Label("SVG", systemImage: "scribble") }
                    }
                    .fineTextStyle()
                    .labelStyle(.titleAndIcon)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let cost = app.library.averageCost(modelID: model.id) ?? model.estimatedCostPerImage {
                    Text(AppModel.money(cost, decimals: 3))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .help(L("Approximate cost per image at 1K"))
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
            .lineLimit(1)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
            .fixedSize()
    }
}

struct LockedModelRow: View {
    let name: String
    let tagline: String
    let provider: Provider

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Group {
                    Text(name).font(.body.weight(.semibold))
                    Text(tagline).font(.callout).lineLimit(2)
                }
                .opacity(0.45)
                Label(provider.missingKeyReason, systemImage: "key")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 3)
        .contentShape(.rect)
        .help(L("Add a %@ key in Settings to use this model.", provider.displayName))
        .accessibilityElement(children: .combine)
    }
}

struct AutoEnhanceSwitch: View {
    enum Style {
        case panel
        case chip
    }

    var style: Style = .panel

    @Environment(AppModel.self) private var app
    @AppStorage(SettingsKey.autoEnhance) private var isOn = false
    @AppStorage(SettingsKey.helperModelID) private var helperModelID = ""

    static var title: String { L("Enhance prompts automatically when generating") }
    static var explanation: String {
        L("Before sending, an AI rewrites what you wrote as a detailed description in English. It can change details.")
    }
    static var price: String { L("≈ $0.001 each time") }

    var body: some View {
        switch style {
        case .panel: panel
        case .chip: chip
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $isOn) {
                Label(Self.title, systemImage: "wand.and.sparkles")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            Text(Self.explanation)
                .helperTextStyle()
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 4) {
                Text(Self.price + " ·").fixedSize()
                HelperModelMenu(selection: $helperModelID)
            }
            .fineTextStyle()
        }
    }

    private var chip: some View {
        Menu {
            Toggle(Self.title, isOn: $isOn)
            Section {
                Text(L("Before sending, an AI rewrites what you wrote in detailed English."))
                Text(L("It can change details · %@", Self.price))
            }
            Picker(L("Model that rewrites it"), selection: $helperModelID) {
                HelperModelMenu.options(app)
            }
        } label: {
            Label(isOn ? L("Auto-improve: on") : L("Auto-improve: off"), systemImage: "wand.and.sparkles")
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .fixedSize()
        .help(Self.explanation)
    }
}

struct HelperModelMenu: View {
    @Binding var selection: String
    @Environment(AppModel.self) private var app

    var body: some View {
        Menu {
            Picker(L("Model that rewrites it"), selection: $selection) {
                Self.options(app)
            }
            .pickerStyle(.inline)
        } label: {
            Text(L("with %@", app.helperModel?.name ?? L("the automatic model")))
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .fixedSize()
        .help(L("The text model that rewrites the description"))
    }

    @ViewBuilder static func options(_ app: AppModel) -> some View {
        Text(app.automaticHelperModel.map { L("Automatic (%@)", $0.name) } ?? L("Automatic (fast)")).tag("")
        ForEach(app.helperModelChoices) { model in
            Text("\(model.name) · \(model.provider.displayName)").tag(model.id)
        }
    }
}
