import AppKit
import Foundation
import FreefieldCore
import os

@Observable
final class Library {
    private(set) var assets: [Asset] = []
    private(set) var characters: [Character] = []
    private(set) var products: [Product] = []
    private(set) var elements: [SceneElement] = []
    private(set) var moodboards: [Moodboard] = []
    private(set) var usage: [UsageEntry] = []

    let root: URL
    let imagesFolder: URL
    let videosFolder: URL
    let postersFolder: URL
    let inputsFolder: URL
    let charactersFolder: URL
    let productsFolder: URL
    let elementsFolder: URL

    private let logger = Logger(subsystem: "app.freefield.Freefield", category: "Library")
    private var saveTask: Task<Void, Never>?
    private let writeQueue = DispatchQueue(label: "app.freefield.Freefield.library-index", qos: .utility)

    init(root: URL? = nil) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Freefield", isDirectory: true)
        self.root = base
        imagesFolder = base.appendingPathComponent("Images", isDirectory: true)
        videosFolder = base.appendingPathComponent("Videos", isDirectory: true)
        postersFolder = base.appendingPathComponent("Posters", isDirectory: true)
        inputsFolder = base.appendingPathComponent("Inputs", isDirectory: true)
        charactersFolder = base.appendingPathComponent("Characters", isDirectory: true)
        productsFolder = base.appendingPathComponent("Products", isDirectory: true)
        elementsFolder = base.appendingPathComponent("Elements", isDirectory: true)
        for folder in [base, imagesFolder, videosFolder, postersFolder, inputsFolder, charactersFolder, productsFolder, elementsFolder] {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        load()
    }

    func url(for asset: Asset) -> URL {
        (asset.isVideo ? videosFolder : imagesFolder).appendingPathComponent(asset.fileName)
    }

    func thumbnailURL(for asset: Asset) -> URL? {
        asset.isVideo ? posterURL(for: asset) : url(for: asset)
    }

    func posterURL(for asset: Asset) -> URL? {
        guard asset.isVideo, let name = asset.posterFileName else { return nil }
        return postersFolder.appendingPathComponent(name)
    }

    func imageData(for asset: Asset) -> Data? {
        guard !asset.isVideo else { return nil }
        return try? Data(contentsOf: url(for: asset))
    }

    func inputURL(_ fileName: String) -> URL { inputsFolder.appendingPathComponent(fileName) }
    func characterPhotoURL(_ fileName: String) -> URL { charactersFolder.appendingPathComponent(fileName) }
    func productPhotoURL(_ fileName: String) -> URL { productsFolder.appendingPathComponent(fileName) }
    func elementPhotoURL(_ fileName: String) -> URL { elementsFolder.appendingPathComponent(fileName) }

    var pendingVideosURL: URL { root.appendingPathComponent("pending-videos.json") }

    func asset(_ id: UUID) -> Asset? { assets.first { $0.id == id } }
    func character(_ id: UUID?) -> Character? { id.flatMap { id in characters.first { $0.id == id } } }
    func product(_ id: UUID?) -> Product? { id.flatMap { id in products.first { $0.id == id } } }
    func element(_ id: UUID?) -> SceneElement? { id.flatMap { id in elements.first { $0.id == id } } }
    func elements(of kind: SceneElementKind) -> [SceneElement] { elements.filter { $0.kind == kind } }

    var favorites: [Asset] { assets.filter(\.isFavorite) }
    var images: [Asset] { assets.filter { !$0.isVideo } }
    var videos: [Asset] { assets.filter(\.isVideo) }

    func assets(for tool: Tool) -> [Asset] { assets.filter { $0.tool == tool } }

    func averageCost(modelID: String) -> Double? {
        var total = 0.0
        var count = 0
        for asset in assets where asset.modelID == modelID {
            guard let cost = asset.cost else { continue }
            total += cost
            count += 1
            if count == 20 { break }
        }
        return count == 0 ? nil : total / Double(count)
    }

    var totalSpent: Double { assets.compactMap(\.cost).reduce(0, +) }

    @discardableResult
    func add(_ image: GeneratedImage, template: Asset) -> Asset {
        let ext = ImageCoding.fileExtension(forMimeType: image.mimeType)
        var asset = template
        asset.fileName = "\(asset.id.uuidString).\(ext)"
        let size = ImageCoding.pixelSize(of: image.data) ?? .zero
        asset.width = Int(size.width)
        asset.height = Int(size.height)
        do {
            try image.data.write(to: url(for: asset), options: .atomic)
        } catch {
            logger.error("Could not write image: \(error.localizedDescription)")
        }
        assets.insert(asset, at: 0)
        scheduleSave()
        exportIfNeeded(asset)
        return asset
    }

    @discardableResult
    func importImage(data: Data, name: String) -> Asset? {
        guard let size = ImageCoding.pixelSize(of: data) else { return nil }
        let ext = (name as NSString).pathExtension.isEmpty ? "png" : (name as NSString).pathExtension.lowercased()
        let id = UUID()
        let asset = Asset(
            id: id, fileName: "\(id.uuidString).\(ext)", createdAt: .now, width: Int(size.width), height: Int(size.height),
            tool: .imported, prompt: (name as NSString).deletingPathExtension, finalPrompt: "", modelID: "", modelName: E("Imported"),
            provider: .openRouter, aspectRatio: .auto, resolution: .oneK, batchID: id, inputFileNames: [], isFavorite: false
        )
        do {
            try data.write(to: url(for: asset), options: .atomic)
        } catch {
            return nil
        }
        assets.insert(asset, at: 0)
        scheduleSave()
        return asset
    }

    func addVideo(file: URL, template: Asset) async -> Asset? {
        var asset = template
        asset.mediaKind = .video
        let ext = file.pathExtension.isEmpty ? "mp4" : file.pathExtension.lowercased()
        let fileManager = FileManager.default
        if self.asset(asset.id) != nil || fileManager.fileExists(atPath: videosFolder.appendingPathComponent("\(asset.id.uuidString).\(ext)").path) {
            asset.id = UUID()
        }
        asset.fileName = "\(asset.id.uuidString).\(ext)"
        let destination = url(for: asset)
        do {
            try fileManager.moveItem(at: file, to: destination)
        } catch {
            logger.error("Could not move video: \(error.localizedDescription)")
            return nil
        }
        guard let info = try? await VideoMedia.probe(destination) else {
            try? fileManager.removeItem(at: destination)
            return nil
        }
        asset.width = Int(info.size.width.rounded())
        asset.height = Int(info.size.height.rounded())
        asset.duration = info.duration
        asset.fps = info.fps > 0 ? info.fps : nil
        asset.hasAudio = info.hasAudio
        if let poster = try? await VideoMedia.poster(destination) {
            let name = "\(asset.id.uuidString).jpg"
            do {
                try poster.write(to: postersFolder.appendingPathComponent(name), options: .atomic)
                asset.posterFileName = name
            } catch {
                logger.error("Could not write poster: \(error.localizedDescription)")
            }
        }
        assets.insert(asset, at: 0)
        scheduleSave()
        exportIfNeeded(asset)
        return asset
    }

    @discardableResult
    func importVideo(url source: URL) async -> Asset? {
        let ext = source.pathExtension.isEmpty ? "mp4" : source.pathExtension.lowercased()
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("Freefield-import-\(UUID().uuidString).\(ext)")
        guard await Self.copy(source, to: copy, securityScoped: true) else { return nil }
        let id = UUID()
        let template = Asset(
            id: id, fileName: "", createdAt: .now, width: 0, height: 0, tool: .imported,
            prompt: source.deletingPathExtension().lastPathComponent, finalPrompt: "", modelID: "", modelName: E("Imported"),
            provider: .openRouter, aspectRatio: .auto, resolution: .oneK, batchID: id, inputFileNames: [], isFavorite: false,
            mediaKind: .video
        )
        guard let asset = await addVideo(file: copy, template: template) else {
            try? FileManager.default.removeItem(at: copy)
            return nil
        }
        return asset
    }

    func storeInput(_ image: InputImage) -> String {
        let name = "\(UUID().uuidString).\(ImageCoding.fileExtension(forMimeType: image.mimeType))"
        try? image.data.write(to: inputURL(name), options: .atomic)
        return name
    }

    func toggleFavorite(_ ids: Set<UUID>) {
        let makeFavorite = assets.contains { ids.contains($0.id) && !$0.isFavorite }
        for index in assets.indices where ids.contains(assets[index].id) {
            assets[index].isFavorite = makeFavorite
        }
        scheduleSave()
    }

    func delete(_ ids: Set<UUID>) {
        let removed = assets.filter { ids.contains($0.id) }
        assets.removeAll { ids.contains($0.id) }
        for asset in removed {
            try? FileManager.default.trashItem(at: url(for: asset), resultingItemURL: nil)
            if let poster = posterURL(for: asset) { try? FileManager.default.removeItem(at: poster) }
        }
        scheduleSave()
    }

    @discardableResult
    func addCharacter(name: String, details: String, photos: [Data], designChoices: [String: String]? = nil) -> Character {
        let id = UUID()
        var names: [String] = []
        for (index, data) in photos.enumerated() {
            guard let prepared = ImageCoding.prepareForUpload(data, maxPixel: 1536) else { continue }
            let fileName = "\(id.uuidString)-\(index).\(ImageCoding.fileExtension(forMimeType: prepared.mimeType))"
            try? prepared.data.write(to: characterPhotoURL(fileName), options: .atomic)
            names.append(fileName)
        }
        var character = Character(id: id, name: name, details: details, photoFileNames: names, createdAt: .now)
        character.designChoices = designChoices
        characters.insert(character, at: 0)
        scheduleSave()
        return character
    }

    func updateCharacter(_ character: Character, addingPhotos photos: [Data] = []) {
        guard let index = characters.firstIndex(where: { $0.id == character.id }) else { return }
        var updated = character
        for data in photos {
            guard let prepared = ImageCoding.prepareForUpload(data, maxPixel: 1536) else { continue }
            let fileName = "\(character.id.uuidString)-\(UUID().uuidString.prefix(8)).\(ImageCoding.fileExtension(forMimeType: prepared.mimeType))"
            try? prepared.data.write(to: characterPhotoURL(fileName), options: .atomic)
            updated.photoFileNames.append(fileName)
        }
        characters[index] = updated
        scheduleSave()
    }

    func deleteCharacter(_ id: UUID) {
        guard let character = characters.first(where: { $0.id == id }) else { return }
        for name in character.photoFileNames {
            try? FileManager.default.removeItem(at: characterPhotoURL(name))
        }
        characters.removeAll { $0.id == id }
        scheduleSave()
    }

    func referenceImages(for character: Character, limit: Int = 4) -> [InputImage] {
        character.photoFileNames.prefix(limit).compactMap { name in
            guard let data = try? Data(contentsOf: characterPhotoURL(name)) else { return nil }
            return InputImage(
                data: data,
                mimeType: ImageCoding.mimeType(forFileExtension: (name as NSString).pathExtension),
                role: "character"
            )
        }
    }

    @discardableResult
    func addProduct(name: String, details: String, photos: [Data], sourceURL: String? = nil) -> Product {
        let id = UUID()
        var names: [String] = []
        for (index, data) in photos.enumerated() {
            guard let prepared = ImageCoding.prepareForUpload(data, maxPixel: 1536) else { continue }
            let fileName = "\(id.uuidString)-\(index).\(ImageCoding.fileExtension(forMimeType: prepared.mimeType))"
            try? prepared.data.write(to: productPhotoURL(fileName), options: .atomic)
            names.append(fileName)
        }
        let product = Product(id: id, name: name, details: details, photoFileNames: names, sourceURL: sourceURL, createdAt: .now)
        products.insert(product, at: 0)
        scheduleSave()
        return product
    }

    func updateProduct(_ product: Product, addingPhotos photos: [Data] = []) {
        guard let index = products.firstIndex(where: { $0.id == product.id }) else { return }
        var updated = product
        for data in photos {
            guard let prepared = ImageCoding.prepareForUpload(data, maxPixel: 1536) else { continue }
            let fileName = "\(product.id.uuidString)-\(UUID().uuidString.prefix(8)).\(ImageCoding.fileExtension(forMimeType: prepared.mimeType))"
            try? prepared.data.write(to: productPhotoURL(fileName), options: .atomic)
            updated.photoFileNames.append(fileName)
        }
        products[index] = updated
        scheduleSave()
    }

    func deleteProduct(_ id: UUID) {
        guard let product = products.first(where: { $0.id == id }) else { return }
        for name in product.photoFileNames {
            try? FileManager.default.removeItem(at: productPhotoURL(name))
        }
        products.removeAll { $0.id == id }
        scheduleSave()
    }

    func productImages(for product: Product, limit: Int = 3) -> [InputImage] {
        product.photoFileNames.prefix(limit).compactMap { name in
            guard let data = try? Data(contentsOf: productPhotoURL(name)) else { return nil }
            return InputImage(data: data, mimeType: ImageCoding.mimeType(forFileExtension: (name as NSString).pathExtension), role: "product")
        }
    }

    func productPhotoData(_ product: Product) -> [Data] {
        product.photoFileNames.compactMap { try? Data(contentsOf: productPhotoURL($0)) }
    }

    @discardableResult
    func addElement(kind: SceneElementKind, name: String, details: String, photos: [Data]) -> SceneElement {
        let id = UUID()
        var names: [String] = []
        for (index, data) in photos.prefix(SceneElement.maxPhotos).enumerated() {
            guard let prepared = ImageCoding.prepareForUpload(data, maxPixel: 1536) else { continue }
            let fileName = "\(id.uuidString)-\(index).\(ImageCoding.fileExtension(forMimeType: prepared.mimeType))"
            try? prepared.data.write(to: elementPhotoURL(fileName), options: .atomic)
            names.append(fileName)
        }
        let element = SceneElement(id: id, kind: kind, name: name, details: details, photoFileNames: names, createdAt: .now)
        elements.insert(element, at: 0)
        scheduleSave()
        return element
    }

    func updateElement(_ element: SceneElement, addingPhotos photos: [Data] = []) {
        guard let index = elements.firstIndex(where: { $0.id == element.id }) else { return }
        var updated = element
        for data in photos.prefix(max(0, SceneElement.maxPhotos - updated.photoFileNames.count)) {
            guard let prepared = ImageCoding.prepareForUpload(data, maxPixel: 1536) else { continue }
            let fileName = "\(element.id.uuidString)-\(UUID().uuidString.prefix(8)).\(ImageCoding.fileExtension(forMimeType: prepared.mimeType))"
            try? prepared.data.write(to: elementPhotoURL(fileName), options: .atomic)
            updated.photoFileNames.append(fileName)
        }
        elements[index] = updated
        scheduleSave()
    }

    func deleteElement(_ id: UUID) {
        guard let element = element(id) else { return }
        for name in element.photoFileNames {
            try? FileManager.default.removeItem(at: elementPhotoURL(name))
        }
        elements.removeAll { $0.id == id }
        scheduleSave()
    }

    func elementImages(for element: SceneElement, limit: Int = 2) -> [InputImage] {
        element.photoFileNames.prefix(max(0, limit)).compactMap { name in
            guard let data = try? Data(contentsOf: elementPhotoURL(name)) else { return nil }
            return InputImage(data: data, mimeType: ImageCoding.mimeType(forFileExtension: (name as NSString).pathExtension),
                              role: element.kind.rawValue)
        }
    }

    func elementPhotoData(_ element: SceneElement) -> [Data] {
        element.photoFileNames.compactMap { try? Data(contentsOf: elementPhotoURL($0)) }
    }

    func coverPhotoData(_ character: Character) -> Data? {
        let names = character.photoFileNames
        guard !names.isEmpty else { return nil }
        return try? Data(contentsOf: characterPhotoURL(names[min(max(0, character.coverIndex), names.count - 1)]))
    }

    func record(_ entry: UsageEntry) {
        usage.insert(entry, at: 0)
        scheduleSave()
    }

    func addAssets(_ ids: [UUID], toUsage entryID: UUID, seconds: Double?) {
        guard !ids.isEmpty, let index = usage.firstIndex(where: { $0.id == entryID }) else { return }
        usage[index].assetIDs += ids
        usage[index].imageCount += ids.count
        if let seconds { usage[index].seconds = seconds }
        scheduleSave()
    }

    func usage(in interval: DateInterval) -> [UsageEntry] {
        usage.filter { interval.contains($0.date) }
    }

    func spent(in interval: DateInterval) -> Double {
        var total = 0.0
        for entry in usage where interval.contains(entry.date) { total += entry.cost }
        return total
    }

    func moodboard(_ id: UUID?) -> Moodboard? { id.flatMap { id in moodboards.first { $0.id == id } } }

    @discardableResult
    func addMoodboard(name: String, images: [Data]) -> Moodboard {
        let id = UUID()
        var names: [String] = []
        for (index, data) in images.enumerated() {
            guard let prepared = ImageCoding.prepareForUpload(data, maxPixel: 1024) else { continue }
            let fileName = "mood-\(id.uuidString)-\(index).\(ImageCoding.fileExtension(forMimeType: prepared.mimeType))"
            try? prepared.data.write(to: characterPhotoURL(fileName), options: .atomic)
            names.append(fileName)
        }
        let board = Moodboard(id: id, name: name, imageFileNames: names, styleDescription: "", createdAt: .now)
        moodboards.insert(board, at: 0)
        scheduleSave()
        return board
    }

    func setStyleDescription(_ text: String, for id: UUID) {
        guard let index = moodboards.firstIndex(where: { $0.id == id }) else { return }
        moodboards[index].styleDescription = text
        scheduleSave()
    }

    func deleteMoodboard(_ id: UUID) {
        guard let board = moodboard(id) else { return }
        for name in board.imageFileNames { try? FileManager.default.removeItem(at: characterPhotoURL(name)) }
        moodboards.removeAll { $0.id == id }
        scheduleSave()
    }

    func styleImages(for board: Moodboard, limit: Int = 3) -> [InputImage] {
        board.imageFileNames.prefix(limit).compactMap { name in
            guard let data = try? Data(contentsOf: characterPhotoURL(name)) else { return nil }
            return InputImage(data: data, mimeType: ImageCoding.mimeType(forFileExtension: (name as NSString).pathExtension), role: "style")
        }
    }

    private struct Snapshot: Codable {
        var assets: [Asset]
        var characters: [Character]
        var moodboards: [Moodboard]?
        var usage: [UsageEntry]?
        var products: [Product]?
        var elements: [SceneElement]?
    }

    private var indexURL: URL { root.appendingPathComponent("library.json") }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(Snapshot.self, from: data)
            assets = snapshot.assets
            characters = snapshot.characters
            moodboards = snapshot.moodboards ?? []
            products = snapshot.products ?? []
            elements = snapshot.elements ?? []
            usage = snapshot.usage ?? Self.migratedUsage(from: snapshot.assets)
        } catch {
            logger.error("Library index unreadable, keeping a backup: \(error.localizedDescription)")
            try? FileManager.default.copyItem(at: indexURL, to: root.appendingPathComponent("library-backup-\(Int(Date().timeIntervalSince1970)).json"))
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        guard let data = encodedSnapshot() else { return }
        let url = indexURL
        writeQueue.async {
            try? data.write(to: url, options: .atomic)
        }
    }

    func flush() {
        guard let pending = saveTask else { return }
        pending.cancel()
        saveTask = nil
        guard let data = encodedSnapshot() else { return }
        let url = indexURL
        writeQueue.sync {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func encodedSnapshot() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(Snapshot(assets: assets, characters: characters, moodboards: moodboards, usage: usage, products: products, elements: elements))
    }

    private func exportIfNeeded(_ asset: Asset) {
        guard UserDefaults.standard.bool(forKey: SettingsKey.autoExport) else { return }
        let folder = SettingsKey.exportFolderURL
        let source = url(for: asset), destination = folder.appendingPathComponent(asset.exportFileName)
        Task {
            await Self.createFolder(folder)
            await Self.copy(source, to: destination, securityScoped: false)
        }
    }

    @concurrent
    @discardableResult
    nonisolated private static func copy(_ source: URL, to destination: URL, securityScoped: Bool) async -> Bool {
        let accessing = securityScoped && source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            return true
        } catch {
            return false
        }
    }

    @concurrent
    nonisolated private static func createFolder(_ folder: URL) async {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
}

extension Asset {
    var exportFileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let slug = prompt
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined()
            .split(separator: " ").prefix(6).joined(separator: " ")
        let ext = (fileName as NSString).pathExtension
        let suffix = slug.isEmpty ? "" : " – \(slug)"
        return "Freefield \(formatter.string(from: createdAt))\(suffix) \(id.uuidString.prefix(4)).\(ext)"
    }
}
