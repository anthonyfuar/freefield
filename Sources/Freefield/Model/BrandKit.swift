import AppKit
import Foundation
import FreefieldCore

struct BrandKit: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var website: String
    var logoFileName: String?
    var colors: [String]
    var fonts: [String]
    var tone: String
    var about: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String = "", website: String = "", logoFileName: String? = nil, colors: [String] = [],
         fonts: [String] = [], tone: String = "", about: String = "", createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.website = website
        self.logoFileName = logoFileName
        self.colors = colors
        self.fonts = fonts
        self.tone = tone
        self.about = about
        self.createdAt = createdAt
    }

    var trimmedTone: String { tone.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedAbout: String { about.trimmingCharacters(in: .whitespacesAndNewlines) }
    var cleanFonts: [String] { fonts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    var cleanColors: [String] { colors.compactMap(BrandColor.normalized) }
}

@Observable
final class BrandStore {
    static let shared = BrandStore()

    private(set) var brands: [BrandKit] = []
    let folder: URL

    private var indexURL: URL { folder.appendingPathComponent("brands.json") }

    init(folder: URL? = nil) {
        self.folder = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Freefield", isDirectory: true)
            .appendingPathComponent("Brands", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
        load()
    }

    func brand(_ id: UUID?) -> BrandKit? { id.flatMap { id in brands.first { $0.id == id } } }

    func logoURL(_ brand: BrandKit) -> URL? {
        brand.logoFileName.map { folder.appendingPathComponent($0) }
    }

    func logoData(_ brand: BrandKit) -> Data? {
        logoURL(brand).flatMap { try? Data(contentsOf: $0) }
    }

    @discardableResult
    func save(_ brand: BrandKit, logo: Data?) -> BrandKit {
        var saved = brand
        let previous = self.brand(brand.id)
        let oldLogo = previous.flatMap(logoData)
        if logo != oldLogo {
            if let name = previous?.logoFileName { try? FileManager.default.removeItem(at: folder.appendingPathComponent(name)) }
            saved.logoFileName = nil
            if let logo, let prepared = ImageCoding.prepareForUpload(logo, maxPixel: 1024) {
                let name = "\(brand.id.uuidString)-\(UUID().uuidString.prefix(8)).\(ImageCoding.fileExtension(forMimeType: prepared.mimeType))"
                if (try? prepared.data.write(to: folder.appendingPathComponent(name), options: .atomic)) != nil {
                    saved.logoFileName = name
                }
            }
        } else {
            saved.logoFileName = previous?.logoFileName
        }
        saved.colors = saved.cleanColors
        saved.fonts = saved.cleanFonts
        if let index = brands.firstIndex(where: { $0.id == brand.id }) {
            brands[index] = saved
        } else {
            brands.insert(saved, at: 0)
        }
        persist()
        return saved
    }

    func delete(_ id: UUID) {
        guard let brand = brand(id) else { return }
        if let url = logoURL(brand) { try? FileManager.default.removeItem(at: url) }
        brands.removeAll { $0.id == id }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([BrandKit].self, from: data) else { return }
        brands = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(brands) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}

nonisolated enum BrandColor {
    static func normalized(_ text: String) -> String? {
        var hex = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.allSatisfy(\.isHexDigit) else { return nil }
        if hex.count == 3 || hex.count == 4 { hex = String(hex.prefix(3).flatMap { [$0, $0] }) }
        if hex.count == 8 { hex = String(hex.prefix(6)) }
        guard hex.count == 6 else { return nil }
        return "#" + hex
    }

    static func components(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        guard let hex = normalized(hex), let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    static func hex(r: Double, g: Double, b: Double) -> String {
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    static func hex(_ color: NSColor) -> String? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        return hex(r: Double(srgb.redComponent), g: Double(srgb.greenComponent), b: Double(srgb.blueComponent))
    }

    static func isNeutral(_ hex: String) -> Bool {
        guard let (r, g, b) = components(hex) else { return true }
        let high = max(r, g, b), low = min(r, g, b)
        return high - low < 0.1 || high < 0.08 || low > 0.95
    }

    static func distance(_ a: String, _ b: String) -> Double {
        guard let x = components(a), let y = components(b) else { return 1 }
        return ((x.r - y.r) * (x.r - y.r) + (x.g - y.g) * (x.g - y.g) + (x.b - y.b) * (x.b - y.b)).squareRoot()
    }

    static func palette(_ weighted: [(String, Double)], limit: Int = 5) -> [String] {
        var totals: [String: Double] = [:]
        var order: [String] = []
        for (raw, weight) in weighted {
            guard let hex = normalized(raw) else { continue }
            if totals[hex] == nil { order.append(hex) }
            totals[hex, default: 0] += weight
        }
        let ranked = order.sorted { (totals[$0] ?? 0) > (totals[$1] ?? 0) }
        var picked: [String] = []
        for hex in ranked.filter({ !isNeutral($0) }) + ranked.filter(isNeutral) where picked.count < limit {
            if picked.contains(where: { distance($0, hex) < 0.12 }) { continue }
            if isNeutral(hex), picked.count >= 3 { continue }
            picked.append(hex)
        }
        return picked
    }
}

struct ImportedBrand: Sendable {
    var name: String
    var website: String
    var logo: Data?
    var colors: [String]
    var fonts: [String]
    var about: String
    var pageText: String
}

nonisolated enum BrandImporter {
    static let maxPageBytes = 2 << 20
    static let maxStyleBytes = 1 << 20
    static let maxImageBytes = 8 << 20
    static let maxStylesheets = 3

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    @concurrent
    static func fetch(_ link: String) async throws -> ImportedBrand {
        guard let url = normalized(link) else { throw FreefieldError.unsupported(L("That doesn't look like a website link.")) }
        let page: Data
        do {
            page = try await load(url, limit: maxPageBytes, truncating: true) { response in
                guard (200..<300).contains(response.statusCode) else {
                    throw FreefieldError.unsupported(L("Couldn't open that page (the site may block automatic access)."))
                }
            }
        } catch let error as FreefieldError {
            throw error
        } catch {
            throw FreefieldError.unsupported(L("Couldn't open that page (the site may block automatic access)."))
        }
        try Task.checkCancellation()
        let html = String(decoding: page, as: UTF8.self)
        let scan = HTMLScan(html)

        var styles = scan.styleBlocks.joined(separator: "\n") + "\n" + scan.styleAttributes.map { "x{\($0)}" }.joined(separator: "\n")
        for sheet in scan.stylesheets.compactMap({ absolute($0, base: url) }).filter({ $0.host == url.host }).prefix(maxStylesheets) {
            try Task.checkCancellation()
            if let data = try? await load(sheet, limit: maxStyleBytes, truncating: true, accept: { response in
                guard response.statusCode == 200 else { throw FreefieldError.decoding("no stylesheet") }
            }) {
                styles += "\n" + String(decoding: data, as: UTF8.self)
            }
        }
        let css = CSSScan(styles)

        var weightedColors = scan.themeColors.map { ($0, 20.0) }
        weightedColors += css.colors
        let colors = BrandColor.palette(weightedColors)

        var fontCounts: [String: Int] = [:]
        var fontOrder: [String] = []
        for font in scan.googleFonts.flatMap({ [$0, $0, $0] }) + css.fonts {
            let key = font.lowercased()
            guard !genericFonts.contains(key), !iconFontWords.contains(where: key.contains) else { continue }
            if fontCounts[key] == nil { fontOrder.append(font) }
            fontCounts[key, default: 0] += 1
        }
        let fonts = Array(fontOrder.sorted { (fontCounts[$0.lowercased()] ?? 0) > (fontCounts[$1.lowercased()] ?? 0) }.prefix(3))

        var logo: Data?
        for candidate in scan.logoCandidates.compactMap({ absolute($0, base: url) }).prefix(8) {
            try Task.checkCancellation()
            if let data = await image(at: candidate) { logo = data; break }
        }

        let about = String(collapsed(scan.description).prefix(300))
        let text = ([scan.description] + scan.headings + scan.paragraphs).map(collapsed).filter { !$0.isEmpty }
        return ImportedBrand(name: brandName(scan, url: url), website: url.absoluteString, logo: logo, colors: colors, fonts: fonts,
                             about: about, pageText: String(text.joined(separator: "\n").prefix(1500)))
    }

    static func normalized(_ link: String) -> URL? {
        var text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = text.lowercased()
        if lowercased.hasPrefix("//") {
            text = "https:" + text
        } else if !lowercased.hasPrefix("http://"), !lowercased.hasPrefix("https://") {
            text = "https://" + text
        }
        guard let url = URL(string: text), isWeb(url), let host = url.host, host.contains(".") else { return nil }
        return url
    }

    private static func brandName(_ scan: HTMLScan, url: URL) -> String {
        if let name = scan.siteName.map(collapsed), !name.isEmpty { return String(name.prefix(60)) }
        if let title = scan.title.map(collapsed), !title.isEmpty {
            let parts = title.components(separatedBy: CharacterSet(charactersIn: "|–—:·")).flatMap { $0.components(separatedBy: " - ") }
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if let short = parts.min(by: { $0.count < $1.count }), short.count <= 40 { return short }
            return String(title.prefix(60))
        }
        var host = url.host ?? ""
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let label = host.split(separator: ".").first.map(String.init) ?? host
        return label.prefix(1).uppercased() + label.dropFirst()
    }

    private static let genericFonts: Set<String> = [
        "serif", "sans-serif", "monospace", "cursive", "fantasy", "system-ui", "ui-sans-serif", "ui-serif", "ui-monospace",
        "ui-rounded", "-apple-system", "blinkmacsystemfont", "segoe ui", "helvetica", "helvetica neue", "arial", "inherit",
        "initial", "unset", "revert", "apple color emoji", "segoe ui emoji", "segoe ui symbol", "noto color emoji", "times",
        "times new roman", "courier", "courier new", "sf pro text", "sf pro display", "math", "emoji", "fangsong", "none",
    ]

    private static let iconFontWords = ["icon", "awesome", "slick", "swiper", "glyph", "dashicons", "eicons", "fontello", "var("]

    private static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("text/html, text/css;q=0.9, image/*;q=0.8, */*;q=0.5", forHTTPHeaderField: "Accept")
        return request
    }

    private static func load(_ url: URL, limit: Int, truncating: Bool = false,
                             accept: (HTTPURLResponse) throws -> Void) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: request(url))
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse else { throw FreefieldError.decoding("no HTTP response") }
        try accept(http)
        if !truncating, http.expectedContentLength > Int64(limit) { throw FreefieldError.decoding("response too large") }
        var body: [UInt8] = []
        body.reserveCapacity(Int(min(max(http.expectedContentLength, 0), Int64(limit))))
        for try await byte in bytes {
            guard body.count < limit else {
                if truncating { break }
                throw FreefieldError.decoding("response too large")
            }
            body.append(byte)
            if body.count & 0xFFFF == 0 { try Task.checkCancellation() }
        }
        return Data(body)
    }

    private static func image(at url: URL) async -> Data? {
        guard let data = try? await load(url, limit: maxImageBytes, accept: { response in
            guard response.statusCode == 200 else { throw FreefieldError.decoding("not an image") }
        }) else { return nil }
        if let size = ImageCoding.pixelSize(of: data) {
            return min(size.width, size.height) >= 32 ? data : nil
        }
        return rasterizedSVG(data)
    }

    private static func rasterizedSVG(_ data: Data) -> Data? {
        guard String(decoding: data.prefix(2048), as: UTF8.self).lowercased().contains("<svg"),
              let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = 768 / max(image.size.width, image.size.height)
        let width = Int((image.size.width * scale).rounded()), height = Int((image.size.height * scale).rounded())
        guard width > 0, height > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func absolute(_ source: String, base: URL) -> URL? {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !source.lowercased().hasPrefix("data:") else { return nil }
        let text = source.hasPrefix("//") ? "https:" + source : source
        guard let url = URL(string: text, relativeTo: base)?.absoluteURL, isWeb(url) else { return nil }
        return url
    }

    private static func isWeb(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }

    static func collapsed(_ text: String) -> String {
        decodeEntities(text).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        for (entity, character) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"),
                                    ("&nbsp;", " "), ("&#x27;", "'"), ("&ndash;", "–"), ("&mdash;", "—"), ("&rsquo;", "’")] {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }
}

nonisolated struct HTMLScan {
    var title: String?
    var siteName: String?
    var description = ""
    var themeColors: [String] = []
    var stylesheets: [String] = []
    var googleFonts: [String] = []
    var logoCandidates: [String] = []
    var styleBlocks: [String] = []
    var styleAttributes: [String] = []
    var headings: [String] = []
    var paragraphs: [String] = []

    init(_ html: String) {
        styleBlocks = Self.blocks("style", in: html)
        let scripts = Self.blocks("script", in: html, attribute: "ld+json")
        let body = Self.removingBlocks(["script", "style", "noscript", "svg"], from: html)
        title = Self.blocks("title", in: body).first.map(Self.plain)

        var icons: [(String, Int)] = []
        var imageLogos: [String] = []
        var ogImage: String?
        for tag in Self.tags(in: body) {
            let values = tag.attributes
            if let style = values["style"], style.contains(":") { styleAttributes.append(style) }
            switch tag.name {
            case "meta":
                let key = (values["property"] ?? values["name"] ?? "").lowercased()
                let content = values["content"] ?? ""
                switch key {
                case "og:site_name", "application-name", "apple-mobile-web-app-title": if siteName == nil, !content.isEmpty { siteName = content }
                case "description", "og:description": if description.isEmpty { description = content }
                case "theme-color", "msapplication-tilecolor": themeColors.append(content)
                case "og:image", "og:image:url": if ogImage == nil { ogImage = content }
                case "og:logo": imageLogos.insert(content, at: 0)
                default: break
                }
            case "link":
                let rel = (values["rel"] ?? "").lowercased()
                guard let href = values["href"] else { break }
                if rel.contains("stylesheet") { stylesheets.append(href) }
                if href.contains("fonts.googleapis.com") || href.contains("fonts.bunny.net") { googleFonts += Self.fontFamilies(in: href) }
                if rel.contains("icon") {
                    let size = (values["sizes"] ?? "").split(separator: "x").first.flatMap { Int($0) } ?? (rel.contains("apple") ? 180 : 32)
                    icons.append((href, size))
                }
            case "img":
                let marker = [values["alt"], values["class"], values["id"], values["src"]].compactMap { $0?.lowercased() }.joined(separator: " ")
                if marker.contains("logo"), let source = values["src"] ?? values["data-src"] { imageLogos.append(source) }
            default:
                break
            }
        }
        var structured: [String] = []
        for block in scripts {
            guard let data = block.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) else { continue }
            Self.collect(object, logos: &structured, name: &siteName)
        }
        logoCandidates = structured + imageLogos + icons.filter { $0.1 >= 96 }.sorted { $0.1 > $1.1 }.map(\.0)
            + icons.filter { $0.1 < 96 }.sorted { $0.1 > $1.1 }.map(\.0) + [ogImage].compactMap { $0 }
        headings = ["h1", "h2"].flatMap { Self.blocks($0, in: body) }.map(Self.plain).filter { !$0.isEmpty }.prefix(6).map { $0 }
        paragraphs = Self.blocks("p", in: body).map(Self.plain).filter { $0.count > 30 }.prefix(6).map { $0 }
    }

    private static func collect(_ value: Any, logos: inout [String], name: inout String?) {
        if let object = value as? [String: Any] {
            let type = "\(object["@type"] ?? "")".lowercased()
            if let logo = object["logo"] {
                if let text = logo as? String { logos.append(text) }
                if let nested = logo as? [String: Any], let url = (nested["url"] ?? nested["contentUrl"]) as? String { logos.append(url) }
            }
            if name == nil, type.contains("organization") || type.contains("brand") || type.contains("website"),
               let text = object["name"] as? String, !text.isEmpty {
                name = text
            }
            for nested in object.values { collect(nested, logos: &logos, name: &name) }
        } else if let list = value as? [Any] {
            for nested in list { collect(nested, logos: &logos, name: &name) }
        }
    }

    private static func fontFamilies(in href: String) -> [String] {
        guard let components = URLComponents(string: href.hasPrefix("//") ? "https:" + href : href) else { return [] }
        return (components.queryItems ?? []).filter { $0.name == "family" }.flatMap { item in
            (item.value ?? "").components(separatedBy: "|").map { family in
                (family.components(separatedBy: ":").first ?? family).replacingOccurrences(of: "+", with: " ")
                    .trimmingCharacters(in: .whitespaces)
            }
        }.filter { !$0.isEmpty }
    }

    struct Tag {
        var name: String
        var attributes: [String: String]
    }

    private static let tagPattern = try? NSRegularExpression(pattern: #"<(meta|link|img)\b([^>]{0,4000})>"#, options: [.caseInsensitive])
    private static let attributePattern = try? NSRegularExpression(
        pattern: #"([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#)

    static func tags(in html: String) -> [Tag] {
        guard let tagPattern, let attributePattern else { return [] }
        let text = html as NSString
        return tagPattern.matches(in: html, range: NSRange(location: 0, length: text.length)).prefix(3000).map { match in
            let name = text.substring(with: match.range(at: 1)).lowercased()
            let body = text.substring(with: match.range(at: 2))
            let inner = body as NSString
            var attributes: [String: String] = [:]
            for attribute in attributePattern.matches(in: body, range: NSRange(location: 0, length: inner.length)) {
                let key = inner.substring(with: attribute.range(at: 1)).lowercased()
                let value = (2...4).map { attribute.range(at: $0) }.first { $0.location != NSNotFound }.map(inner.substring(with:)) ?? ""
                if attributes[key] == nil { attributes[key] = BrandImporter.decodeEntities(value) }
            }
            return Tag(name: name, attributes: attributes)
        }
    }

    static func blocks(_ name: String, in html: String, attribute: String? = nil) -> [String] {
        let pattern = #"<"# + name + #"\b([^>]*)>(.*?)</"# + name + #"\s*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let text = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: text.length)).prefix(400).compactMap { match in
            if let attribute, !text.substring(with: match.range(at: 1)).lowercased().contains(attribute) { return nil }
            return text.substring(with: match.range(at: 2))
        }
    }

    static func removingBlocks(_ names: [String], from html: String) -> String {
        var result = html
        for name in names {
            let pattern = #"<"# + name + #"\b[^>]*>.*?</"# + name + #"\s*>"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { continue }
            result = regex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: (result as NSString).length), withTemplate: " ")
        }
        return result
    }

    static func plain(_ html: String) -> String {
        let stripped = html.replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: .regularExpression)
        return BrandImporter.collapsed(stripped)
    }
}

nonisolated struct CSSScan {
    var colors: [(String, Double)] = []
    var fonts: [String] = []

    private static let hexPattern = try? NSRegularExpression(pattern: #"#([0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3,4})(?![0-9a-zA-Z_-])"#)
    private static let rgbPattern = try? NSRegularExpression(
        pattern: #"rgba?\(\s*(\d{1,3})[\s,]+(\d{1,3})[\s,]+(\d{1,3})\s*(?:[,/]\s*([0-9.]+%?))?\s*\)"#)

    init(_ css: String) {
        var buffer = ""
        var inComment = false
        var previous: Swift.Character = " "
        var declarations: [String] = []
        for character in css {
            if inComment {
                if previous == "*", character == "/" { inComment = false }
                previous = character
                continue
            }
            if previous == "/", character == "*" {
                inComment = true
                if !buffer.isEmpty { buffer.removeLast() }
                previous = character
                continue
            }
            switch character {
            case "{": buffer = ""
            case ";", "}":
                if buffer.contains(":") { declarations.append(buffer) }
                buffer = ""
            default:
                if buffer.count < 2000 { buffer.append(character) }
            }
            previous = character
            if declarations.count > 40000 { break }
        }
        for declaration in declarations {
            guard let colon = declaration.firstIndex(of: ":") else { continue }
            let property = declaration[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = String(declaration[declaration.index(after: colon)...])
            if property == "font-family" || property == "font" || (property.hasPrefix("--") && property.contains("font")) {
                if let font = Self.firstFamily(property == "font" ? Self.familyPart(of: value) : value) { fonts.append(font) }
            }
            let weight: Double = if property.hasPrefix("--"), ["primary", "brand", "accent", "secondary", "button", "main"].contains(where: property.contains) {
                5
            } else if property.contains("background") || property.contains("button") || property.hasPrefix("--") {
                2
            } else if property.contains("color") || property == "fill" || property.contains("border") {
                1
            } else {
                0
            }
            guard weight > 0 else { continue }
            for hex in Self.hexes(in: value) { colors.append((hex, weight)) }
        }
    }

    private static func hexes(in value: String) -> [String] {
        let text = value as NSString
        let range = NSRange(location: 0, length: text.length)
        var found: [String] = []
        for match in hexPattern?.matches(in: value, range: range) ?? [] {
            let digits = text.substring(with: match.range(at: 1))
            if digits.count == 8 || digits.count == 4 {
                let alpha = digits.count == 8 ? String(digits.suffix(2)) : String(repeating: String(digits.suffix(1)), count: 2)
                if (UInt8(alpha, radix: 16) ?? 255) < 200 { continue }
            }
            if let hex = BrandColor.normalized(digits) { found.append(hex) }
        }
        for match in rgbPattern?.matches(in: value, range: range) ?? [] {
            if match.range(at: 4).location != NSNotFound {
                let alpha = text.substring(with: match.range(at: 4))
                let amount = alpha.hasSuffix("%") ? (Double(alpha.dropLast()) ?? 100) / 100 : Double(alpha) ?? 1
                if amount < 0.8 { continue }
            }
            let parts = (1...3).compactMap { Double(text.substring(with: match.range(at: $0))) }
            guard parts.count == 3 else { continue }
            found.append(BrandColor.hex(r: parts[0] / 255, g: parts[1] / 255, b: parts[2] / 255))
        }
        return found
    }

    private static func familyPart(of shorthand: String) -> String {
        guard let size = shorthand.range(of: #"\d[\d.]*(px|pt|em|rem|%)(\s*/\s*[\d.]+[a-z%]*)?\s+"#, options: .regularExpression) else { return "" }
        return String(shorthand[size.upperBound...])
    }

    private static func firstFamily(_ value: String) -> String? {
        let first = value.split(separator: ",").first.map(String.init) ?? value
        let name = first.replacingOccurrences(of: "!important", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"' ").union(.whitespacesAndNewlines))
        guard !name.isEmpty, name.count <= 40, !name.contains("("), !name.hasPrefix("--"), !name.hasPrefix("$") else { return nil }
        return name
    }
}
