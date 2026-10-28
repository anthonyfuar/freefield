import Foundation
import FreefieldCore

struct ScriptShotPlan {
    var scene: String?
    var shots: [VideoShotDraft] = []
    var choices: [String: String] = [:]
}

enum ScriptShots {
    static let estimate = 0.003
    static let scriptLimit = 2000
    static let panelGroups = ["genre", "era", "body", "lens", "aperture", "light", "pacing"]

    static func instructions(tool: VideoTool, maxShots: Int) -> String {
        let moves = CameraMoves.all.map { "\($0.id) (\(english($0.name)))" }.joined(separator: ", ")
        let emotions = (tool.group("emotion")?.values ?? []).filter { $0 != "Auto" }.joined(separator: ", ")
        let panel = panelGroups.compactMap { id -> String? in
            guard let group = tool.group(id) else { return nil }
            return "\(id): \(group.values.joined(separator: " | "))"
        }.joined(separator: "\n")
        return """
        You are a film director's assistant. Split the user's script or idea into at most \(maxShots) shots for one short video clip of about 5 to 10 seconds. Fewer shots are fine when the idea is simple.
        For each shot give: "action", one short sentence about what is seen on screen (who does what, where); "camera", exactly one id from this list of camera moves: \(moves); "emotion", one of \(emotions), or null.
        For the whole clip give "scene", one or two sentences describing the place, the characters and what happens, and pick one value for each of these director settings, copied exactly from its list (use Auto when nothing clearly fits):
        \(panel)
        Write "scene" and every "action" in the same language as the user's script. Keep any dialogue out of the actions. Reply with JSON only, in this shape: {"scene": "…", "genre": "Drama", "era": "Auto", "body": "35 mm film", "lens": "Anamorphic", "aperture": "f/1.4 wide open", "light": "Window light", "pacing": "Calm", "shots": [{"action": "…", "camera": "dolly-in", "emotion": "Joy"}]}
        """
    }

    static func plan(from reply: String, tool: VideoTool, maxShots: Int) -> ScriptShotPlan? {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
              let object = try? JSONSerialization.jsonObject(with: Data(reply[start...end].utf8)) as? [String: Any] else { return nil }
        var plan = ScriptShotPlan()
        if let scene = (object["scene"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !scene.isEmpty {
            plan.scene = String(scene.prefix(400))
        }
        for id in panelGroups {
            guard let group = tool.group(id), let raw = object[id] as? String else { continue }
            if let value = match(raw, in: group.values), value != "Auto" { plan.choices[id] = value }
        }
        let emotions = tool.group("emotion")?.values ?? []
        let moveIDs = Set(CameraMoves.all.map(\.id))
        for item in (object["shots"] as? [Any] ?? []).prefix(maxShots) {
            guard let shot = item as? [String: Any],
                  let action = (shot["action"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !action.isEmpty else { continue }
            var draft = VideoShotDraft()
            draft.action = String(action.prefix(200))
            if let camera = (shot["camera"] as? String)?.trimmingCharacters(in: .whitespaces).lowercased() {
                draft.camera = moveIDs.contains(camera) ? camera
                    : CameraMoves.all.first { english($0.name).lowercased() == camera }?.id
            }
            if let emotion = shot["emotion"] as? String, let value = match(emotion, in: emotions), value != "Auto" {
                draft.emotion = value
            }
            plan.shots.append(draft)
        }
        return plan.shots.isEmpty ? nil : plan
    }

    private static func match(_ raw: String, in values: [String]) -> String? {
        let wanted = raw.trimmingCharacters(in: .whitespaces).lowercased()
        return values.first { $0.lowercased() == wanted }
    }
}

extension AppModel {
    func writeShots(from script: String, tool: VideoTool, state: VideoState) async throws -> Int {
        let maxShots = tool.slot(.shots)?.maxCount ?? 3
        let reply = try await helperComplete(title: E("Write shots from a script"), tool: .video,
                                             system: ScriptShots.instructions(tool: tool, maxShots: maxShots),
                                             user: "Script or idea:\n" + script)
        try Task.checkCancellation()
        guard let plan = ScriptShots.plan(from: reply, tool: tool, maxShots: maxShots) else {
            throw FreefieldError.unsupported(L("The AI didn't return any shots. Try again, or write a little more."))
        }
        state.shots = plan.shots
        if let scene = plan.scene, state.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { state.prompt = scene }
        for (id, value) in plan.choices { state.pick(value, for: id) }
        return plan.shots.count
    }
}
