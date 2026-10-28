import Foundation

nonisolated func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

nonisolated func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), locale: .current, arguments: arguments)
}

nonisolated func E(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: key, locale: Locale(identifier: "en_US_POSIX"), arguments: arguments)
}

nonisolated func english(_ text: String) -> String {
    EnglishText.originals[text] ?? text
}

enum EnglishText {
    nonisolated static let originals: [String: String] = {
        guard let url = Bundle.main.url(forResource: "Localizable", withExtension: "strings"),
              let table = NSDictionary(contentsOf: url) as? [String: String] else { return [:] }
        var inverted: [String: String] = [:]
        for key in table.keys.sorted() {
            guard let value = table[key] else { continue }
            if let current = inverted[value], !prefers(key, over: current) { continue }
            inverted[value] = key
        }
        return inverted
    }()

    nonisolated static func prefers(_ key: String, over other: String) -> Bool {
        let keyIsTitle = isTitleCase(key), otherIsTitle = isTitleCase(other)
        if keyIsTitle != otherIsTitle { return keyIsTitle }
        if key.count != other.count { return key.count < other.count }
        return key < other
    }

    nonisolated static func isTitleCase(_ text: String) -> Bool {
        !text.split(separator: " ").contains { $0.first?.isLowercase == true }
    }
}
