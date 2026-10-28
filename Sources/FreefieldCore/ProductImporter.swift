import Foundation

public struct ImportedProduct: Sendable {
    public var title: String
    public var description: String
    public var vendor: String?
    public var sourceURL: URL
    public var photos: [Data]
}

public enum ProductImporter {
    public static let maxPhotos = 8
    static let maxPageBytes = 2 << 20
    static let maxJSONBytes = 5 << 20
    static let maxImageBytes = 25 << 20
    static let maxTagBytes = 16 << 10
    static let maxJSONDepth = 64
    static let deadline = Duration.seconds(120)

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: configuration)
    }()

    @concurrent
    public static func fetch(_ link: String) async throws -> ImportedProduct {
        guard let url = normalized(link) else {
            throw FreefieldError.unsupported(L("That doesn't look like a product link."))
        }
        return try await withThrowingTaskGroup(of: ImportedProduct.self) { group in
            group.addTask {
                if let product = try? await shopify(url) { return product }
                try Task.checkCancellation()
                return try await openGraph(url)
            }
            group.addTask {
                try await Task.sleep(for: deadline)
                throw FreefieldError.unsupported(L("The store took too long to respond. Try again later."))
            }
            defer { group.cancelAll() }
            guard let product = try await group.next() else { throw CancellationError() }
            return product
        }
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

    static func shopifyJSONURL(_ url: URL) -> URL? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(of: "products"), index + 1 < parts.count,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var handle = parts[index + 1]
        if handle.hasSuffix(".json") || handle.hasSuffix(".js") { handle = (handle as NSString).deletingPathExtension }
        components.path = "/products/\(handle).json"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func shopify(_ url: URL) async throws -> ImportedProduct {
        guard let jsonURL = shopifyJSONURL(url) else { throw FreefieldError.decoding("not a product path") }
        let data = try await load(jsonURL, limit: maxJSONBytes) { response in
            guard response.statusCode == 200 else { throw FreefieldError.decoding("not Shopify JSON") }
        }
        guard isShallowJSON(data), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let product = object["product"] as? [String: Any],
              let title = product["title"] as? String else { throw FreefieldError.decoding("not Shopify JSON") }
        let sources = (product["images"] as? [[String: Any]] ?? []).compactMap { $0["src"] as? String }
        let photos = await download(sources.compactMap { absolute($0, base: url) })
        try Task.checkCancellation()
        guard !photos.isEmpty else { throw FreefieldError.unsupported(L("The product has no photos.")) }
        return ImportedProduct(title: title, description: plainText(product["body_html"] as? String ?? ""),
                               vendor: product["vendor"] as? String, sourceURL: url, photos: photos)
    }

    private static func openGraph(_ url: URL) async throws -> ImportedProduct {
        let data = try await load(url, limit: maxPageBytes, truncating: true) { response in
            guard (200..<300).contains(response.statusCode) else {
                throw FreefieldError.unsupported(L("Couldn't open that page (the store may block automatic access)."))
            }
        }
        try Task.checkCancellation()
        let page = Page(scanning: [UInt8](data))
        try Task.checkCancellation()
        var sources = page.meta(["og:image", "og:image:url", "og:image:secure_url", "twitter:image", "twitter:image:src"])
        sources += page.jsonLD.flatMap(jsonLDImages)
        try Task.checkCancellation()
        let photos = await download(unique(sources).compactMap { absolute($0, base: url) })
        try Task.checkCancellation()
        guard !photos.isEmpty else { throw FreefieldError.unsupported(L("No product photos were found on that page.")) }
        let title = (page.meta(["og:title", "twitter:title"]) + [page.title ?? ""]).map(collapsed).first { !$0.isEmpty }
            ?? url.host ?? ""
        let description = page.meta(["og:description", "description"]).map { collapsed(strippingTags($0)) }.first { !$0.isEmpty } ?? ""
        return ImportedProduct(title: title, description: String(description.prefix(400)), vendor: nil, sourceURL: url, photos: photos)
    }

    private static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/html;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")
        return request
    }

    private static func load(_ url: URL, limit: Int, truncating: Bool = false,
                             accept: (HTTPURLResponse) throws -> Void) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: request(url))
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse else { throw FreefieldError.decoding("no HTTP response") }
        try accept(http)
        let tooLarge = FreefieldError.decoding("response too large")
        if !truncating, http.expectedContentLength > Int64(limit) { throw tooLarge }
        var body: [UInt8] = []
        body.reserveCapacity(Int(min(max(http.expectedContentLength, 0), Int64(limit))))
        for try await byte in bytes {
            guard body.count < limit else {
                if truncating { break }
                throw tooLarge
            }
            body.append(byte)
            if body.count & 0xFFFF == 0 { try Task.checkCancellation() }
        }
        return Data(body)
    }

    private static func download(_ urls: [URL]) async -> [Data] {
        let candidates = unique(urls.map(\.absoluteString)).compactMap(URL.init(string:)).prefix(maxPhotos * 2)
        return await withTaskGroup(of: (Int, Data?).self) { group in
            var pending = Array(candidates.enumerated())[...]
            var results: [(Int, Data)] = []
            var running = 0
            while true {
                while running < 6, results.count < maxPhotos, !Task.isCancelled, let item = pending.popFirst() {
                    group.addTask { (item.offset, await photo(at: item.element)) }
                    running += 1
                }
                guard let finished = await group.next() else { break }
                running -= 1
                if case (let index, let data?) = finished { results.append((index, data)) }
            }
            return results.sorted { $0.0 < $1.0 }.prefix(maxPhotos).map(\.1)
        }
    }

    private static func photo(at url: URL) async -> Data? {
        let data = try? await load(url, limit: maxImageBytes) { response in
            let type = response.mimeType?.lowercased() ?? "application/octet-stream"
            guard response.statusCode == 200, type.hasPrefix("image/") || type.hasSuffix("octet-stream") else {
                throw FreefieldError.decoding("not an image")
            }
        }
        guard let data, let size = ImageCoding.pixelSize(of: data), min(size.width, size.height) >= 300 else { return nil }
        return data
    }

    private static func absolute(_ source: String, base: URL) -> URL? {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = source.hasPrefix("//") ? "https:" + source : source
        guard let url = URL(string: text, relativeTo: base)?.absoluteURL, isWeb(url) else { return nil }
        return url
    }

    private static func isWeb(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }

    private static func jsonLDImages(_ block: Data) -> [String] {
        guard isShallowJSON(block), let object = try? JSONSerialization.jsonObject(with: block) else { return [] }
        var images: [String] = []
        collectImages(object, into: &images)
        return images
    }

    private static func collectImages(_ value: Any, into images: inout [String]) {
        if let dictionary = value as? [String: Any] {
            if let image = dictionary["image"] {
                if let text = image as? String { images.append(text) }
                if let list = image as? [Any] { images += list.compactMap { ($0 as? String) ?? imageURL(in: $0) } }
                if let text = imageURL(in: image) { images.append(text) }
            }
            for nested in dictionary.values { collectImages(nested, into: &images) }
        } else if let list = value as? [Any] {
            for nested in list { collectImages(nested, into: &images) }
        }
    }

    static func isShallowJSON(_ data: Data) -> Bool {
        let quote = UInt8(ascii: "\""), backslash = UInt8(ascii: "\\")
        var depth = 0, inString = false, escaped = false
        for byte in data {
            if inString {
                if escaped { escaped = false } else if byte == backslash { escaped = true } else if byte == quote { inString = false }
                continue
            }
            switch byte {
            case quote: inString = true
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
                if depth > maxJSONDepth { return false }
            case UInt8(ascii: "}"), UInt8(ascii: "]"): depth = max(0, depth - 1)
            default: break
            }
        }
        return true
    }

    private static func imageURL(in value: Any) -> String? {
        guard let object = value as? [String: Any] else { return nil }
        return (object["url"] ?? object["contentUrl"]) as? String
    }

    static func plainText(_ html: String) -> String {
        String(collapsed(decodeEntities(strippingTags(html))).prefix(400))
    }

    private static func strippingTags(_ html: String) -> String {
        guard html.contains("<") else { return html }
        var text = ""
        var tagStart: String.Index?
        for index in html.indices {
            let character = html[index]
            if tagStart != nil {
                if character == ">" { tagStart = nil; text.append(" ") }
            } else if character == "<" {
                tagStart = index
            } else {
                text.append(character)
            }
        }
        if let tagStart { text += html[tagStart...] }
        return text
    }

    private static func collapsed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var rest = text[...]
        while let ampersand = rest.firstIndex(of: "&") {
            result += rest[..<ampersand]
            let after = rest[rest.index(after: ampersand)...]
            if let semicolon = after.prefix(10).firstIndex(of: ";"), let character = entity(after[..<semicolon]) {
                result.append(character)
                rest = after[after.index(after: semicolon)...]
            } else {
                result.append("&")
                rest = after
            }
        }
        return result + rest
    }

    private static func entity(_ name: Substring) -> Character? {
        guard name.first == "#" else { return namedEntities[String(name)] }
        let digits = name.dropFirst()
        let isHex = digits.first == "x" || digits.first == "X"
        guard let value = UInt32(isHex ? digits.dropFirst() : digits, radix: isHex ? 16 : 10) else { return nil }
        if let character = windows1252[value] { return character }
        guard value != 0, let scalar = Unicode.Scalar(value) else { return "\u{FFFD}" }
        return Character(scalar)
    }

    private static let windows1252: [UInt32: Character] = [
        128: "€", 130: "‚", 131: "ƒ", 132: "„", 133: "…", 134: "†", 135: "‡", 136: "ˆ", 137: "‰", 138: "Š", 139: "‹",
        140: "Œ", 142: "Ž", 145: "‘", 146: "’", 147: "“", 148: "”", 149: "•", 150: "–", 151: "—", 152: "˜", 153: "™",
        154: "š", 155: "›", 156: "œ", 158: "ž", 159: "Ÿ",
    ]

    private static let namedEntities: [String: Character] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}", "shy": "\u{00AD}",
        "ndash": "–", "mdash": "—", "hellip": "…", "bull": "•", "middot": "·", "prime": "′", "Prime": "″",
        "lsquo": "‘", "rsquo": "’", "sbquo": "‚", "ldquo": "“", "rdquo": "”", "bdquo": "„",
        "laquo": "«", "raquo": "»", "lsaquo": "‹", "rsaquo": "›", "iexcl": "¡", "iquest": "¿",
        "trade": "™", "reg": "®", "copy": "©", "deg": "°", "euro": "€", "pound": "£", "yen": "¥", "cent": "¢",
        "times": "×", "divide": "÷", "plusmn": "±", "frac12": "½", "frac14": "¼", "frac34": "¾",
        "sup1": "¹", "sup2": "²", "sup3": "³", "micro": "µ", "para": "¶", "sect": "§", "ordf": "ª", "ordm": "º",
        "dagger": "†", "Dagger": "‡", "hearts": "♥", "starf": "★",
        "aacute": "á", "eacute": "é", "iacute": "í", "oacute": "ó", "uacute": "ú", "yacute": "ý",
        "Aacute": "Á", "Eacute": "É", "Iacute": "Í", "Oacute": "Ó", "Uacute": "Ú", "Yacute": "Ý",
        "agrave": "à", "egrave": "è", "igrave": "ì", "ograve": "ò", "ugrave": "ù",
        "Agrave": "À", "Egrave": "È", "Igrave": "Ì", "Ograve": "Ò", "Ugrave": "Ù",
        "acirc": "â", "ecirc": "ê", "icirc": "î", "ocirc": "ô", "ucirc": "û",
        "Acirc": "Â", "Ecirc": "Ê", "Icirc": "Î", "Ocirc": "Ô", "Ucirc": "Û",
        "auml": "ä", "euml": "ë", "iuml": "ï", "ouml": "ö", "uuml": "ü", "yuml": "ÿ",
        "Auml": "Ä", "Euml": "Ë", "Iuml": "Ï", "Ouml": "Ö", "Uuml": "Ü",
        "atilde": "ã", "otilde": "õ", "ntilde": "ñ", "Atilde": "Ã", "Otilde": "Õ", "Ntilde": "Ñ",
        "ccedil": "ç", "Ccedil": "Ç", "aring": "å", "Aring": "Å", "aelig": "æ", "AElig": "Æ",
        "oslash": "ø", "Oslash": "Ø", "oelig": "œ", "OElig": "Œ", "szlig": "ß",
    ]

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

extension ProductImporter {
    struct Page {
        var metas: [(key: String, value: String)] = []
        var jsonLD: [Data] = []
        var title: String?

        init(scanning html: [UInt8]) {
            var index = 0
            while !Task.isCancelled, let open = html[index...].firstIndex(of: UInt8(ascii: "<")), open + 1 < html.count {
                index = open + 1
                if html[index] == UInt8(ascii: "!") {
                    if Self.matches("!--", in: html, at: index) { index = Self.commentEnd(in: html, from: index + 3) }
                    continue
                }
                guard let name = Self.tagName(in: html, at: index) else { continue }
                guard let tag = Self.attributes(in: html, from: index + name.utf8.count) else {
                    index = min(html.count, index + maxTagBytes)
                    continue
                }
                index = tag.end
                switch name {
                case "meta":
                    guard let content = tag.values["content"] else { break }
                    for attribute in ["property", "name"] {
                        if let key = tag.values[attribute] { metas.append((key.lowercased(), content)) }
                    }
                case "title":
                    guard title == nil else { break }
                    let end = Self.find("</title", in: html, from: index) ?? html[index...].firstIndex(of: UInt8(ascii: "<")) ?? html.count
                    title = decodeEntities(String(decoding: html[index..<min(end, index + 2048)], as: UTF8.self))
                    index = end
                default:
                    let end = Self.find("</" + name, in: html, from: index) ?? html.count
                    if name == "script", tag.values["type"]?.lowercased().contains("ld+json") == true {
                        jsonLD.append(Data(html[index..<end]))
                    }
                    index = end
                }
            }
        }

        func meta(_ keys: [String]) -> [String] {
            keys.flatMap { key in metas.filter { $0.key == key }.map(\.value) }
        }

        private static func commentEnd(in html: [UInt8], from start: Int) -> Int {
            if matches(">", in: html, at: start) { return start + 1 }
            if matches("->", in: html, at: start) { return start + 2 }
            var index = start
            while let dashes = find("--", in: html, from: index) {
                if matches("-->", in: html, at: dashes) { return dashes + 3 }
                if matches("--!>", in: html, at: dashes) { return dashes + 4 }
                index = dashes + 1
            }
            return html.count
        }

        private static func tagName(in html: [UInt8], at index: Int) -> String? {
            let first = lowercased(html[index])
            for (name, bytes) in tagNames where bytes[0] == first && matches(bytes, in: html, at: index) {
                let next = index + bytes.count
                if next == html.count || isSpace(html[next]) || html[next] == UInt8(ascii: "/") || html[next] == UInt8(ascii: ">") {
                    return name
                }
            }
            return nil
        }

        private static func attributes(in html: [UInt8], from start: Int) -> (values: [String: String], end: Int)? {
            let limit = min(html.count, start + maxTagBytes)
            let equals = UInt8(ascii: "="), slash = UInt8(ascii: "/"), close = UInt8(ascii: ">")
            var values: [String: String] = [:]
            var index = start
            while index < limit {
                let byte = html[index]
                if byte == close { return (values, index + 1) }
                if isSpace(byte) || byte == slash { index += 1; continue }
                let nameStart = index
                index += 1
                while index < limit, !isSpace(html[index]), html[index] != equals, html[index] != slash, html[index] != close { index += 1 }
                let name = String(decoding: html[nameStart..<index], as: UTF8.self).lowercased()
                while index < limit, isSpace(html[index]) { index += 1 }
                var value = ""
                if index < limit, html[index] == equals {
                    index += 1
                    while index < limit, isSpace(html[index]) { index += 1 }
                    guard index < limit else { return nil }
                    let quote = html[index]
                    if quote == UInt8(ascii: "\"") || quote == UInt8(ascii: "'") {
                        guard let end = html[(index + 1)..<limit].firstIndex(of: quote) else { return nil }
                        value = String(decoding: html[(index + 1)..<end], as: UTF8.self)
                        index = end + 1
                    } else {
                        let valueStart = index
                        while index < limit, !isSpace(html[index]), html[index] != close { index += 1 }
                        value = String(decoding: html[valueStart..<index], as: UTF8.self)
                    }
                }
                if values[name] == nil { values[name] = decodeEntities(value) }
            }
            return nil
        }

        private static let tagNames = ["meta", "title", "script", "style"].map { ($0, Array($0.utf8)) }

        private static func find(_ word: String, in html: [UInt8], from start: Int) -> Int? {
            let word = Array(word.utf8)
            guard let first = word.first else { return nil }
            var index = start
            while let candidate = html[index...].firstIndex(where: { lowercased($0) == first }) {
                if matches(word, in: html, at: candidate) { return candidate }
                index = candidate + 1
            }
            return nil
        }

        private static func matches(_ word: String, in html: [UInt8], at index: Int) -> Bool {
            matches(Array(word.utf8), in: html, at: index)
        }

        private static func matches(_ word: [UInt8], in html: [UInt8], at index: Int) -> Bool {
            guard index + word.count <= html.count else { return false }
            for offset in word.indices where lowercased(html[index + offset]) != word[offset] { return false }
            return true
        }

        private static func lowercased(_ byte: UInt8) -> UInt8 {
            (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte + 32 : byte
        }

        private static func isSpace(_ byte: UInt8) -> Bool {
            byte == 0x20 || (0x09...0x0D).contains(byte)
        }
    }
}
