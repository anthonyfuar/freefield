import Foundation

func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .main, comment: "")
}

func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(key, bundle: .main, comment: ""), locale: .current, arguments: arguments)
}
