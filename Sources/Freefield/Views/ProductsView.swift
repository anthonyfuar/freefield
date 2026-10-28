import FreefieldCore
import SwiftUI

struct ProductsView: View {
    @Environment(AppModel.self) private var app
    @State private var selectedID: UUID?
    @State private var confirmingDelete: Product?

    var body: some View {
        @Bindable var app = app
        let selected = app.library.products.first { $0.id == selectedID }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: L("Products"),
                           detail: L("Save a product once, from its photos or a link to your store, and use it in any tool, effect or ad with its label and shape intact."))
                if app.library.products.isEmpty {
                    FlowLayout(spacing: 10) {
                        Button { app.creatingProduct = true } label: {
                            Label(L("Add My First Product"), systemImage: "plus").prominentLabel()
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.brandFill)
                        Button(L("Import from Link…"), systemImage: "link") { app.creatingProduct = true }
                            .buttonStyle(.glass)
                            .help(L("Paste a link to the product page in your store"))
                    }
                    .controlSize(.large)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 16)], spacing: 16) {
                    Button {
                        app.creatingProduct = true
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: "plus")
                                .iconSymbol(IconScale.hero)
                            Text(L("New Product")).font(.headline)
                            Text(L("Store link or photos")).fineTextStyle()
                        }
                        .frame(maxWidth: .infinity, minHeight: 250)
                        .background(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.2, dash: [7, 6])))
                        .contentShape(.rect(cornerRadius: Radius.card))
                    }
                    .buttonStyle(CardButtonStyle())

                    ForEach(app.library.products) { product in
                        Button {
                            selectedID = product.id
                        } label: {
                            ProductCard(product: product, isSelected: selectedID == product.id)
                        }
                        .buttonStyle(CardButtonStyle(shadow: false))
                        .contextMenu {
                            Button(L("Place in a Scene"), systemImage: Tool.product.systemImage) { app.use(product, in: .product) }
                            Button(L("Create with This Product"), systemImage: Tool.create.systemImage) { app.use(product, in: .create) }
                            Button(L("Create a Video with This Product"), systemImage: "play.rectangle.on.rectangle") { app.makeVideoAd(with: product) }
                            Menu(L("Create an Ad"), systemImage: "megaphone") { AdToolItems(product: product) }
                            Button(L("Add Photos…"), systemImage: "photo.badge.plus") {
                                app.library.updateProduct(product, addingPhotos: ImageIntake.pick(multiple: true))
                            }
                            Divider()
                            Button(L("Delete"), systemImage: "trash", role: .destructive) { confirmingDelete = product }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 18) {
                    if let product = selected {
                        ProductDetail(product: product)
                            .transition(Motion.transition(.opacity.combined(with: .offset(y: 12))))
                    } else if !app.library.products.isEmpty {
                        Label(L("Click a product to see its photos and what you made with it."), systemImage: "hand.point.up.left")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    PanelSection(title: L("Tips for Better Results"), systemImage: "lightbulb") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("• Paste a product link from a Shopify store to bring in every photo, its name and description."))
                            Text(L("• The first photo is the hero: a clean, front view on a plain background works best."))
                            Text(L("• Add photos from other angles so the label and shape stay faithful from any viewpoint."))
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: PageLayout.textWidth, alignment: .leading)
                    }
                }
                .animation(Motion.standard, value: selected == nil)
            }
            .pageContainer()
        }
        .navigationTitle(L("Products"))
        .navigationSubtitle(app.library.products.isEmpty ? "" : app.library.products.count == 1 ? L("1 product") : L("%ld products", app.library.products.count))
        .toolbar {
            ToolbarItem {
                Button(L("New Product"), systemImage: "plus") { app.creatingProduct = true }
            }
        }
        .sheet(isPresented: $app.creatingProduct) {
            NewProductSheet()
        }
        .confirmationDialog(L("Delete %@?", confirmingDelete?.name ?? ""), isPresented: Binding(get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } })) {
            Button(L("Delete"), role: .destructive) {
                if let product = confirmingDelete { app.library.deleteProduct(product.id) }
                confirmingDelete = nil
            }
        } message: {
            Text(L("Its saved photos will be deleted. Images already generated are kept."))
        }
    }
}

struct ProductCard: View {
    let product: Product
    var isSelected = false
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Rectangle().fill(.white.opacity(0.92))
                if let cover = product.photoFileNames.first {
                    ThumbnailImage(url: app.library.productPhotoURL(cover), maxPixel: 500, contentMode: .fit)
                        .padding(8)
                }
            }
            .frame(height: 210)
            .clipShape(.rect(cornerRadius: Radius.card))
            .overlay(alignment: .bottomTrailing) {
                Text(product.photoFileNames.count == 1 ? L("1 photo") : L("%ld photos", product.photoFileNames.count))
                    .fineTextStyle()
                    .fontWeight(.semibold)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .glassEffect(in: .capsule)
                    .padding(8)
            }
            .overlay(alignment: .topTrailing) {
                PhotoCornerMenu {
                    ProductUseItems(product: product)
                    Divider()
                    Menu(L("Create an Ad"), systemImage: "megaphone") { AdToolItems(product: product) }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(isSelected ? Color.appAccent : .clear, lineWidth: 3)
                    .animation(Motion.select, value: isSelected)
            }
            Text(product.name).font(.body.weight(.semibold)).lineLimit(1)
            if !product.details.isEmpty {
                Text(product.details).helperTextStyle().lineLimit(2)
            }
        }
        .contentShape(.rect)
        .help(L("Click to see details"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ProductDetail: View {
    let product: Product
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    title
                    Spacer()
                    actions
                }
                VStack(alignment: .leading, spacing: 8) {
                    title
                    actions
                }
            }
            if !product.details.isEmpty {
                Text(product.details).font(.callout).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(product.photoFileNames, id: \.self) { name in
                        ThumbnailImage(url: app.library.productPhotoURL(name), maxPixel: 300, contentMode: .fit)
                            .frame(width: 130, height: 130)
                            .background(.white.opacity(0.92), in: .rect(cornerRadius: Radius.tile))
                            .clipShape(.rect(cornerRadius: Radius.tile))
                    }
                }
            }
            .scrollIndicators(.never)
            let made = app.library.assets.filter { $0.productID == product.id }
            if !made.isEmpty {
                Text(L("Created with %@", product.name)).font(.headline).padding(.top, 6)
                JustifiedAssetGrid(assets: Array(made.prefix(24)), targetHeight: 160, spacing: 8) { asset, _ in
                    AssetCard(asset: asset, maxPixel: 480)
                        .onTapGesture(count: 2) { app.quickLook(asset) }
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: Radius.card))
    }
}

extension ProductDetail {
    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(product.name).font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
            if let source = product.sourceURL, let url = URL(string: source) {
                Link(url.host ?? source, destination: url).font(.subheadline)
            }
        }
    }

    private var actions: some View {
        HStack {
            Button(L("Add Photos"), systemImage: "photo.badge.plus") {
                app.library.updateProduct(product, addingPhotos: ImageIntake.pick(multiple: true))
            }
            .buttonStyle(.glass)
            .fixedSize()
            Menu(L("Create an Ad"), systemImage: "megaphone") {
                AdToolItems(product: product)
                Divider()
                Button(L("Create a Video with This Product"), systemImage: "play.rectangle.on.rectangle") { app.makeVideoAd(with: product) }
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .fixedSize()
            Menu {
                ProductUseItems(product: product)
            } label: {
                Label(L("Use in…"), systemImage: "arrow.up.forward.app").prominentLabel()
            }
            .menuStyle(.button)
            .buttonStyle(.glassProminent)
            .tint(.brandFill)
            .fixedSize()
        }
    }
}

struct ProductUseItems: View {
    let product: Product
    @Environment(AppModel.self) private var app

    var body: some View {
        Button(L("Create Image"), systemImage: Tool.create.systemImage) { app.use(product, in: .create) }
        Button(L("Place in a Scene"), systemImage: Tool.product.systemImage) { app.use(product, in: .product) }
        Button(Tool.edit.title, systemImage: Tool.edit.systemImage) { app.use(product, in: .edit) }
        Divider()
        Button(L("Create a Video with This Product"), systemImage: "play.rectangle.on.rectangle") { app.makeVideoAd(with: product) }
    }
}

struct AdToolItems: View {
    let product: Product
    @Environment(AppModel.self) private var app

    var body: some View {
        ForEach(AdCatalog.all.filter { $0.takesProduct }) { tool in
            Button(tool.name, systemImage: tool.symbol) { app.makeAd(tool, with: product) }
        }
    }
}

struct NewProductSheet: View {
    var onSave: ((Product) -> Void)?
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var name = ""
    @State private var details = ""
    @State private var photos: [Data] = []
    @State private var sourceURL: String?
    @State private var isImporting = false
    @State private var importError: String?
    @State private var importTask: Task<Void, Never>?

    private var trimmedLink: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField(L("Product link"), text: $link, prompt: Text("https://store.com/products/…"))
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
                    Text(L("From a store link"))
                } footer: {
                    Text(L("Works with any Shopify product page: its name, description and photos are brought in. Other stores work when the page shares its product images."))
                }
                Section {
                    TextField(L("Name"), text: $name, prompt: Text(L("e.g. Glow Serum 30 ml")))
                        .characterLimit($name, 60)
                    TextField(L("Description (optional)"), text: $details, prompt: Text(L("e.g. amber glass dropper bottle with a white label")), axis: .vertical)
                        .lineLimit(2...4)
                        .characterLimit($details, 300)
                } header: {
                    Text(L("Product"))
                } footer: {
                    Text(L("The description helps keep the product faithful when the photos don't show everything."))
                }
                Section {
                    ReferenceStrip(images: $photos, limit: ProductImporter.maxPhotos, label: L("Photos"))
                    if photos.isEmpty {
                        Text(L("Drag 1 to 8 photos of the product here, or click +."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(L("Photos"))
                } footer: {
                    Text(L("Up to 3 are sent per generation, the first one as the hero. They're stored only on your Mac."))
                }
            }
            .formStyle(.grouped)
            .navigationTitle(L("New Product"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save")) {
                        let product = app.library.addProduct(name: name.trimmingCharacters(in: .whitespaces), details: details,
                                                             photos: photos, sourceURL: sourceURL)
                        onSave?(product)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || photos.isEmpty)
                }
            }
        }
        .frame(width: 560, height: 620)
        .onDisappear { importTask?.cancel() }
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
                let product = try await ProductImporter.fetch(text)
                try Task.checkCancellation()
                name = String(product.title.prefix(60))
                details = String(product.description.prefix(300))
                photos = product.photos
                sourceURL = product.sourceURL.absoluteString
            } catch {
                if !Task.isCancelled { importError = error.localizedDescription }
            }
        }
    }
}

extension AppModel {
    func use(_ product: Product, in tool: Tool) {
        let photos = library.productPhotoData(product)
        guard let hero = photos.first else { return }
        let state = composer(for: tool)
        switch tool {
        case .product:
            state.secondary = hero
        case .create:
            state.productID = product.id
        default:
            state.references = Array((state.references + photos.prefix(3)).prefix(14))
        }
        selection = .tool(tool)
    }

    func makeAd(_ tool: AdTool, with product: Product) {
        adState(for: tool).productID = product.id
        selection = .ad(tool.id)
    }
}
