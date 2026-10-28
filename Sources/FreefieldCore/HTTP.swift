import Foundation

enum HTTP {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 900
        configuration.waitsForConnectivity = true
        configuration.httpMaximumConnectionsPerHost = 8
        return URLSession(configuration: configuration)
    }()

    static func jsonBody(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
    }

    static func send(_ request: URLRequest, provider: Provider) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FreefieldError.decoding(L("no HTTP response"))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw error(status: http.statusCode, body: data, provider: provider)
        }
        return data
    }

    static func error(status: Int, body: Data, provider: Provider) -> FreefieldError {
        let message = errorMessage(in: body) ?? HTTPURLResponse.localizedString(forStatusCode: status)
        if message.localizedCaseInsensitiveContains("moderation") || message.localizedCaseInsensitiveContains("safety")
            || message.localizedCaseInsensitiveContains("blocked") {
            return .unsupported(L("The provider blocked this request with its content filter. Rephrase the text or try another model. (%@)", String(message.prefix(120))))
        }
        switch status {
        case 401, 403:
            if provider == .google, message.localizedCaseInsensitiveContains("api key") {
                return .invalidKey(provider)
            }
            return status == 401 ? .invalidKey(provider) : .http(status: status, message: message)
        case 400 where message.localizedCaseInsensitiveContains("API key not valid")
            || message.localizedCaseInsensitiveContains("API_KEY_INVALID"):
            return .invalidKey(provider)
        case 402:
            return .insufficientCredits(message)
        case 429:
            return .rateLimited(message)
        default:
            return .http(status: status, message: message)
        }
    }

    static func errorMessage(in body: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            let text = String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return text?.isEmpty == false ? String(text!.prefix(400)) : nil
        }
        if let error = object["error"] as? [String: Any] {
            var message = error["message"] as? String ?? L("Unknown error")
            if let metadata = error["metadata"] as? [String: Any], let raw = metadata["raw"] as? String,
               !raw.isEmpty, raw != message {
                message += " — \(raw.prefix(300))"
            }
            return message
        }
        if let error = object["error"] as? String { return error }
        return nil
    }

    static func imageData(fromURLString string: String) async throws -> GeneratedImage {
        if string.hasPrefix("data:") {
            guard let comma = string.firstIndex(of: ",") else { throw FreefieldError.decoding(L("invalid data URL")) }
            let header = string[string.index(string.startIndex, offsetBy: 5)..<comma]
            let mime = header.split(separator: ";").first.map(String.init) ?? "image/png"
            let payload = string[string.index(after: comma)...]
            guard let data = Data(base64Encoded: String(payload), options: .ignoreUnknownCharacters) else {
                throw FreefieldError.decoding(L("invalid base64"))
            }
            return GeneratedImage(data: data, mimeType: mime)
        }
        guard let url = URL(string: string) else { throw FreefieldError.decoding(L("invalid image URL")) }
        let (data, response) = try await session.data(from: url)
        let mime = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "image/png"
        return GeneratedImage(data: data, mimeType: mime)
    }
}
