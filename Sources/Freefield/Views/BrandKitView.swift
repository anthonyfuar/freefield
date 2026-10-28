import AppKit
import FreefieldCore
import SwiftUI

struct BrandEditorTarget: Identifiable {
    let id = UUID()
    var brandID: UUID?
}

struct AdBrandSection: View {
    @Bindable var state: AdState
    let tool: AdTool

    @State private var editing: BrandEditorTarget?

    private var store: BrandStore { BrandStore.shared }

    var body: some View {
        let brand = store.brand(state.brandID)
        OptionalSection(L("Your brand"), systemImage: "seal", summary: brand?.name ?? L("None"), isFilled: brand != nil,
                        storageKey: "ad.brand") {
            VStack(alignment: .leading, spacing: 10) {
                FlowLayout(spacing: 8) {
                    Menu {
                        Button(L("No brand")) { state.brandID = nil }
                        if !store.brands.isEmpty {
                            Divider()
                            ForEach(store.brands) { item in
                                Button(item.name) { state.brandID = item.id }
                            }
                        }
                        Divider()
                        Button(L("New Brand…"), systemImage: "plus") { editing = BrandEditorTarget() }
                    } label: {
                        Label(brand?.name ?? L("Choose a brand…"), systemImage: "seal")
                            .lineLimit(1)
                    }
                    .buttonStyle(.glass)
                    .fixedSize()
                    if let brand {
                        Button(L("Edit Brand…"), systemImage: "pencil") { editing = BrandEditorTarget(brandID: brand.id) }
                            .buttonStyle(.glass)
                            .fixedSize()
                    } else if store.brands.isEmpty {
                        Button(L("New Brand…"), systemImage: "plus") { editing = BrandEditorTarget() }
                            .buttonStyle(.glass)
                            .fixedSize()
                    }
                }
                if let brand {
                    BrandSummary(brand: brand)
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(L("Use the brand colors"), isOn: $state.usesBrandColors)
                            .disabled(brand.cleanColors.isEmpty)
                        if tool.placesLogo, brand.logoFileName != nil {
                            Toggle(L("Add the logo (small, in a corner)"), isOn: $state.addsLogo)
                        }
                    }
                    Text(L("Its colors, type and feel guide the design. Your text is still written exactly as you type it."))
                        .helperTextStyle()
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L("Save your logo, colors, fonts and tone once, from your website or by hand, and your ads follow them."))
                        .helperTextStyle()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: VideoLayout.textWidth, alignment: .leading)
        .sheet(item: $editing) { target in
            BrandEditorSheet(brandID: target.brandID) { saved in state.brandID = saved?.id }
        }
    }
}

struct BrandSummary: View {
    let brand: BrandKit

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let url = BrandStore.shared.logoURL(brand) {
                ThumbnailImage(url: url, maxPixel: 200, contentMode: .fit)
                    .padding(4)
                    .frame(width: 52, height: 52)
                    .background(.white.opacity(0.92), in: .rect(cornerRadius: Radius.thumb))
                    .clipShape(.rect(cornerRadius: Radius.thumb))
            }
            VStack(alignment: .leading, spacing: 6) {
                if !brand.cleanColors.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(brand.cleanColors, id: \.self) { hex in
                            Circle().fill(Color(hex: hex))
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))
                                .frame(width: 18, height: 18)
                                .help(hex)
                        }
                    }
                }
                let details = [brand.cleanFonts.joined(separator: ", "), brand.trimmedTone].filter { !$0.isEmpty }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .fineTextStyle()
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct BrandEditorSheet: View {
    var brandID: UUID?
    var onSave: ((BrandKit?) -> Void)?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var brand = BrandKit()
    @State private var logo: Data?
    @State private var link = ""
    @State private var fontsText = ""
    @State private var pageText = ""
    @State private var isImporting = false
    @State private var importError: String?
    @State private var importTask: Task<Void, Never>?
    @State private var isWriting = false
    @State private var writeError: String?
    @State private var confirmingDelete = false
    @State private var loaded = false

    private static let maxColors = 6
    private var trimmedLink: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isEditing: Bool { brandID.flatMap(BrandStore.shared.brand) != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField(L("Website link"), text: $link, prompt: Text(verbatim: "https://yourbrand.com"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(importLink)
                        Button(action: importLink) {
                            if isImporting { ProgressView().controlSize(.small) } else { Text(L("Import")) }
                        }
                        .fixedSize()
                        .disabled(trimmedLink.isEmpty || isImporting)
                    }
                    if let importError {
                        Label(importError, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text(L("From your website"))
                } footer: {
                    Text(L("Brings in the name, logo, colors and fonts the page uses. Only that page, its own style files and its logo are opened. Check everything below."))
                }
                Section {
                    TextField(L("Name"), text: $brand.name, prompt: Text(L("e.g. Glow Lab")))
                        .characterLimit($brand.name, 60)
                    LabeledContent(L("Logo")) {
                        ImageWell(title: L("Logo"), subtitle: L("Drop the logo here"), systemImage: "seal", data: $logo,
                                  minHeight: 96, sources: [.library], isInPanel: true)
                            .frame(width: 220, height: 110)
                    }
                    LabeledContent(L("Colors")) {
                        colors
                    }
                    TextField(L("Fonts"), text: $fontsText, prompt: Text(L("e.g. Inter, Playfair Display")))
                        .characterLimit($fontsText, 120)
                } header: {
                    Text(L("Brand"))
                } footer: {
                    Text(L("Font names are only used as a style guide; the AI picks the closest look."))
                }
                Section {
                    HStack(alignment: .top) {
                        TextField(L("Tone of voice"), text: $brand.tone, prompt: Text(L("e.g. warm, playful and confident, with short lines")),
                                  axis: .vertical)
                            .lineLimit(2...3)
                            .characterLimit($brand.tone, 160)
                        Button(action: writeVoice) {
                            HStack(spacing: 6) {
                                if isWriting { ProgressView().controlSize(.small) } else { Image(systemName: "wand.and.sparkles") }
                                Text(L("Write with AI"))
                                PricePill(text: GenerateButton.format(AppModel.helperEstimate))
                            }
                        }
                        .fixedSize()
                        .disabled(writeReason != nil || isWriting)
                        .help(writeReason ?? L("The AI reads the website text and describes the tone and what the brand sells."))
                    }
                    TextField(L("What the brand sells (optional)"), text: $brand.about, prompt: Text(L("e.g. vegan skincare for sensitive skin")),
                              axis: .vertical)
                        .lineLimit(2...3)
                        .characterLimit($brand.about, 300)
                    if let writeError {
                        Label(writeError, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text(L("Voice"))
                } footer: {
                    Text(L("Guides the look of the ads and any text the AI writes for you."))
                }
                if isEditing {
                    Section {
                        Button(L("Delete Brand…"), role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? L("Edit Brand") : L("New Brand"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save"), action: save)
                        .disabled(brand.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog(L("Delete this brand?"), isPresented: $confirmingDelete) {
                Button(L("Delete"), role: .destructive) {
                    BrandStore.shared.delete(brand.id)
                    onSave?(nil)
                    dismiss()
                }
            } message: {
                Text(L("Its saved logo, colors and tone are removed from this Mac. Ads you already made stay in your library."))
            }
        }
        .frame(width: 600, height: 680)
        .onAppear(perform: load)
        .onDisappear { importTask?.cancel() }
    }

    private var colors: some View {
        FlowLayout(spacing: 8) {
            ForEach(brand.colors.indices, id: \.self) { index in
                HStack(spacing: 4) {
                    ColorPicker(L("Color"), selection: colorBinding(index), supportsOpacity: false)
                        .labelsHidden()
                    Text(verbatim: brand.colors[index]).font(.subheadline.monospaced()).foregroundStyle(.secondary)
                    Button {
                        brand.colors.remove(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L("Remove this color"))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.05), in: .capsule)
            }
            if brand.colors.count < Self.maxColors {
                Button(L("Add Color"), systemImage: "plus") { brand.colors.append(brand.colors.last ?? "#3366FF") }
                    .fixedSize()
            }
        }
    }

    private func colorBinding(_ index: Int) -> Binding<Color> {
        Binding(get: { index < brand.colors.count ? Color(hex: brand.colors[index]) : .clear },
                set: { color in
                    guard index < brand.colors.count, let hex = BrandColor.hex(NSColor(color)) else { return }
                    brand.colors[index] = hex
                })
    }

    private var writeReason: String? {
        if !app.hasAnyKey { return L("Add an API key in Settings") }
        if app.helperModel == nil { return L("No text model is available for the AI assistant.") }
        if brand.name.trimmingCharacters(in: .whitespaces).isEmpty && pageText.isEmpty { return L("Import a website or write the brand name first.") }
        return nil
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let id = brandID, let saved = BrandStore.shared.brand(id) else { return }
        brand = saved
        logo = BrandStore.shared.logoData(saved)
        link = saved.website
        fontsText = saved.cleanFonts.joined(separator: ", ")
    }

    private func importLink() {
        let text = trimmedLink
        guard !isImporting, !text.isEmpty else { return }
        importTask?.cancel()
        isImporting = true
        importError = nil
        importTask = Task {
            defer { isImporting = false }
            do {
                let found = try await BrandImporter.fetch(text)
                try Task.checkCancellation()
                if brand.name.trimmingCharacters(in: .whitespaces).isEmpty || !isEditing { brand.name = String(found.name.prefix(60)) }
                brand.website = found.website
                if let image = found.logo { logo = image }
                if !found.colors.isEmpty { brand.colors = Array(found.colors.prefix(Self.maxColors)) }
                if !found.fonts.isEmpty { fontsText = found.fonts.joined(separator: ", ") }
                if brand.trimmedAbout.isEmpty { brand.about = found.about }
                pageText = found.pageText
                var missing: [String] = []
                if found.logo == nil { missing.append(L("logo")) }
                if found.colors.isEmpty { missing.append(L("colors")) }
                if found.fonts.isEmpty { missing.append(L("fonts")) }
                if !missing.isEmpty {
                    importError = L("Not found on that page: %@. Add them by hand.", missing.joined(separator: ", "))
                }
            } catch {
                if !Task.isCancelled { importError = error.localizedDescription }
            }
        }
    }

    private func writeVoice() {
        isWriting = true
        writeError = nil
        Task {
            defer { isWriting = false }
            do {
                let voice = try await app.writeBrandVoice(name: brand.name, pageText: pageText, about: brand.about)
                if !voice.tone.isEmpty { brand.tone = String(voice.tone.prefix(160)) }
                if !voice.about.isEmpty { brand.about = String(voice.about.prefix(300)) }
            } catch {
                writeError = error.localizedDescription
            }
        }
    }

    private func save() {
        var updated = brand
        updated.name = updated.name.trimmingCharacters(in: .whitespaces)
        if updated.website.isEmpty, let url = BrandImporter.normalized(trimmedLink) { updated.website = url.absoluteString }
        updated.fonts = fontsText.components(separatedBy: CharacterSet(charactersIn: ",;\n"))
        let saved = BrandStore.shared.save(updated, logo: logo)
        onSave?(saved)
        dismiss()
    }
}

extension AppModel {
    func writeBrandVoice(name: String, pageText: String, about: String) async throws -> (tone: String, about: String) {
        var user = "Brand: \(name)"
        if !about.isEmpty { user += "\nWhat it sells: \(about)" }
        if !pageText.isEmpty { user += "\nText from its website:\n\(pageText)" }
        let text = try await helperComplete(
            title: E("Describe brand voice"), tool: .ad,
            system: "You are a brand strategist. From the brand information, write exactly two lines. Line 1 starts with \"Tone:\" and describes the brand's tone of voice in 5 to 14 words, as a list of adjectives with a short note on sentence style. Line 2 starts with \"About:\" and says in under 20 words what the brand sells and to whom. Write in \(VideoCatalog.interfaceLanguage). Describe only what the text supports; never invent awards, numbers or claims.",
            user: user
        )
        var tone = "", summary = ""
        for line in text.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }) {
            let lower = line.lowercased()
            if let colon = line.firstIndex(of: ":"), lower.hasPrefix("tone") || lower.hasPrefix("tono") {
                tone = line[line.index(after: colon)...].trimmingCharacters(in: CharacterSet(charactersIn: "\"“” *").union(.whitespaces))
            } else if let colon = line.firstIndex(of: ":"), lower.hasPrefix("about") || lower.hasPrefix("acerca") || lower.hasPrefix("sobre") {
                summary = line[line.index(after: colon)...].trimmingCharacters(in: CharacterSet(charactersIn: "\"“” *").union(.whitespaces))
            }
        }
        guard !tone.isEmpty || !summary.isEmpty else { throw FreefieldError.unsupported(L("The AI returned no suggestions.")) }
        return (tone, summary)
    }
}
