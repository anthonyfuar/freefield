import CryptoKit
import Foundation
import FreefieldCore

enum AIChecks {
    nonisolated static let estimate = 0.001
    nonisolated static let subjectPathEstimate = 0.005
    nonisolated static let maxSubjectFrames = 24

    static weak var app: AppModel?

    static var textLines: [String: [String]] = [:]

    private static let storeKey = "aiCheckAnswers"
    private static var stored: [String: Int] = UserDefaults.standard.dictionary(forKey: storeKey) as? [String: Int] ?? [:]
    private static var running: [String: Task<Int?, Never>] = [:]

    static func answer(_ key: String, ask: @escaping @MainActor () async -> Int?) async -> Int? {
        if let known = stored[key] { return known }
        if let task = running[key] { return await task.value }
        let task = Task { await ask() }
        running[key] = task
        let value = await task.value
        running[key] = nil
        if let value {
            if stored.count >= 500 { stored.removeAll() }
            stored[key] = value
            UserDefaults.standard.set(stored, forKey: storeKey)
        }
        return value
    }

    @concurrent
    nonisolated static func fingerprint(_ data: Data) async -> String {
        SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    @concurrent
    nonisolated static func upload(_ data: Data, maxPixel: Int) async -> InputImage? {
        ImageCoding.prepareForUpload(data, maxPixel: maxPixel, role: "photo")
    }

    nonisolated static func json(in reply: String) -> Any? {
        let brackets: [(String.Element, String.Element)] = [("[", "]"), ("{", "}")]
        let spans: [(String.Index, String.Index)] = brackets.compactMap { open, close in
            guard let start = reply.firstIndex(of: open), let end = reply.lastIndex(of: close), start < end else { return nil }
            return (start, end)
        }
        for (start, end) in spans.sorted(by: { $0.0 < $1.0 }) {
            if let value = try? JSONSerialization.jsonObject(with: Data(reply[start...end].utf8)) { return value }
        }
        return nil
    }

    nonisolated static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    nonisolated static func flag(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = (value as? String)?.lowercased() { return ["true", "yes"].contains(value) ? true : ["false", "no"].contains(value) ? false : nil }
        return nil
    }

    nonisolated static let textInstructions = """
    You read the text in an image so it can be retyped. List every legible piece of text, one entry per line as it appears, top to bottom and left to right, exactly as written: the same spelling, capitalization, accents, punctuation and language. Don't translate, correct or describe anything. Include headlines, labels, signs, logos with words and small print you can read with confidence; skip what you can't. Reply with a JSON array of strings only, like ["SUMMER SALE", "50% off"], or [] when there is no text.
    """

    nonisolated static func lines(from reply: String) -> [String]? {
        let items: [Any]
        switch json(in: reply) {
        case let array as [Any]: items = array
        case let object as [String: Any]: items = (object["lines"] ?? object["text"]) as? [Any] ?? []
        default: return nil
        }
        return items
            .compactMap { ($0 as? String) ?? (($0 as? [String: Any])?["text"] as? String) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    nonisolated static let faceInstructions = """
    You check a portrait before it's turned into a talking video. Count the faces clearly visible in it (people or characters, photographed or drawn); ignore tiny faces far in the background, faces on posters or screens, and reflections. Then say whether the main face's mouth is visible: not covered by a hand, mask, microphone, hair or an object, and not turned away. Reply with JSON only, like {"faces": 1, "mouth_visible": true}.
    """

    nonisolated static let subjectInstructions = """
    You follow the main subject of a video clip so it can be reframed to another shape. The images are frames of one clip in time order. The main subject is what a viewer must keep in view: a person's face (between the face and the product when they show one), otherwise the most important object or action. Follow the same subject from frame to frame. For each frame give the subject's center as fractions of the frame: x from 0 (left edge) to 1 (right edge), y from 0 (top edge) to 1 (bottom edge); use null when a frame has no clear subject. Reply with JSON only: an array with one entry per frame, in order, like [{"frame": 1, "x": 0.42, "y": 0.35}, {"frame": 2, "x": null, "y": null}].
    """

    nonisolated static func centers(from reply: String, count: Int) -> [CGPoint?] {
        var centers = [CGPoint?](repeating: nil, count: count)
        let parsed = json(in: reply)
        var entries = parsed as? [Any] ?? []
        if let object = parsed as? [String: Any], let array = object.values.first(where: { $0 is [Any] }) as? [Any] { entries = array }
        for (position, entry) in entries.enumerated() {
            var index = position
            var x: Double?, y: Double?
            if let object = entry as? [String: Any] {
                if let frame = number(object["frame"]) { index = Int(frame) - 1 }
                x = number(object["x"])
                y = number(object["y"])
            } else if let pair = entry as? [Any], pair.count >= 2 {
                x = number(pair[0])
                y = number(pair[1])
            }
            guard centers.indices.contains(index), var x, var y, x >= 0, y >= 0, x <= 100, y <= 100 else { continue }
            if x > 1 || y > 1 {
                x /= 100
                y /= 100
            }
            centers[index] = CGPoint(x: min(1, x), y: min(1, y))
        }
        return centers
    }
}

struct FaceCount: Equatable, Sendable {
    var faces: Int
    var mouthVisible: Bool

    var code: Int { faces * 2 + (mouthVisible ? 1 : 0) }

    init(faces: Int, mouthVisible: Bool) {
        self.faces = faces
        self.mouthVisible = mouthVisible
    }

    init(code: Int) {
        self.init(faces: code / 2, mouthVisible: code % 2 == 1)
    }
}

extension AppModel {
    var canLookWithAI: Bool { helperModel != nil }

    func countFaces(in data: Data) async -> FaceCount? {
        guard canLookWithAI else { return nil }
        let fingerprint = await AIChecks.fingerprint(data)
        let code = await AIChecks.answer("faces:" + fingerprint) {
            guard let image = await AIChecks.upload(data, maxPixel: 768),
                  let reply = try? await self.helperComplete(title: E("Check face"), tool: .video, system: AIChecks.faceInstructions,
                                                             user: "Check this portrait.", images: [image]),
                  let object = AIChecks.json(in: reply) as? [String: Any],
                  let faces = AIChecks.number(object["faces"] ?? object["face_count"]) else { return nil }
            let mouth = AIChecks.flag(object["mouth_visible"] ?? object["mouth"]) ?? true
            return FaceCount(faces: max(0, Int(faces)), mouthVisible: mouth).code
        }
        return code.map(FaceCount.init(code:))
    }

    func subjectCenters(inFrames frames: [Data], times: [Double]) async -> [CGPoint?]? {
        guard canLookWithAI, !frames.isEmpty else { return nil }
        let images = frames.map { InputImage(data: $0, mimeType: "image/jpeg", role: "frame") }
        let stamps = times.enumerated().map { "Frame \($0.offset + 1): \(String(format: "%.1f", $0.element)) s" }
        guard let reply = try? await helperComplete(title: E("Follow the subject"), tool: .video, system: AIChecks.subjectInstructions,
                                                    user: "There are \(frames.count) frames.\n" + stamps.joined(separator: "\n"),
                                                    images: images) else { return nil }
        return AIChecks.centers(from: reply, count: frames.count)
    }
}
