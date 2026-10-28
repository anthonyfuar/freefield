import Foundation

struct OptionPicture: Hashable {
    var url: URL?
    var aspect: CGFloat = 4.0 / 3.0
}

enum OptionImages {
    static func slug(_ text: String) -> String {
        var slug = ""
        var pendingDash = false
        for character in text.lowercased() {
            if character == "'" || character == "\u{2019}" { continue }
            if character.isASCII, character.isLetter || character.isNumber {
                if pendingDash, !slug.isEmpty { slug.append("-") }
                pendingDash = false
                slug.append(character)
            } else {
                pendingDash = true
            }
        }
        return slug
    }

    static func url(family: String, key: String) -> URL? {
        index["\(family)/\(slug(key))"]
    }

    static func pictures(family: String, values: [String], key: (String) -> String = { $0 }) -> [String: OptionPicture]? {
        let urls = values.map { url(family: family, key: key($0)) }
        guard urls.contains(where: { $0 != nil }) else { return nil }
        let aspect: CGFloat = family.hasPrefix("video/") ? 16.0 / 9.0 : 4.0 / 3.0
        return Dictionary(zip(values, urls.map { OptionPicture(url: $0, aspect: aspect) }), uniquingKeysWith: { first, _ in first })
    }

    static func pictures(adTool toolID: String, group: AdOptionGroup) -> [String: OptionPicture]? {
        let title = english(group.title)
        return pictures(family: "ads/\(toolID)", values: group.values) { "\(title) \($0)" }
    }

    static func pictures(videoTool toolID: String, group: VideoOptionGroup) -> [String: OptionPicture]? {
        pictures(family: "video/\(toolID)-\(group.id)", values: group.values)
    }

    private static let index: [String: URL] = {
        guard let root = Bundle.main.resourceURL?.appending(path: "Examples/options", directoryHint: .isDirectory),
              let paths = try? FileManager.default.subpathsOfDirectory(atPath: root.path) else { return [:] }
        var index: [String: URL] = [:]
        for path in paths where path.hasSuffix(".heic") {
            index[String(path.dropLast(5))] = root.appending(path: path, directoryHint: .notDirectory)
        }
        return index
    }()
}
