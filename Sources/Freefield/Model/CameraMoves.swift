import Foundation

enum CameraMoveGroup: String, CaseIterable, Identifiable {
    case basic, epic, dynamic, timelapse, cinema

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic: L("Basic")
        case .epic: L("Epic")
        case .dynamic: L("Dynamic")
        case .timelapse: L("Timelapse")
        case .cinema: L("Cinema")
        }
    }

    var symbol: String {
        switch self {
        case .basic: "video"
        case .epic: "mountain.2"
        case .dynamic: "bolt"
        case .timelapse: "clock.arrow.circlepath"
        case .cinema: "film"
        }
    }
}

nonisolated enum CameraStrength: String, CaseIterable, Identifiable, Codable, Sendable {
    case subtle, normal, strong

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subtle: L("Subtle")
        case .normal: L("Normal")
        case .strong: L("Strong")
        }
    }

    var adverb: String {
        switch self {
        case .subtle: "slowly and subtly"
        case .normal: "smoothly, at medium speed"
        case .strong: "fast and dramatically"
        }
    }

    var sentence: String {
        switch self {
        case .subtle: "Slow and subtle."
        case .normal: "Smooth, medium speed."
        case .strong: "Fast and dramatic."
        }
    }
}

struct CameraMove: Identifiable, Hashable {
    let id: String
    let name: String
    let group: CameraMoveGroup
    let prompt: String
    var wanPrompt: String?
    var isBig = false

    func text(for family: VideoFamily) -> String {
        family == .wan ? wanPrompt ?? prompt : prompt
    }

    var statesSpeed: Bool {
        let words = prompt.lowercased()
        return ["slow", "fast", "quick", "rapid", "sudden", "speed", "does not move", "accelerates"].contains { words.contains($0) }
    }
}

enum CameraMoves {
    static let maxMix = 3

    static func move(_ id: String) -> CameraMove? { all.first { $0.id == id } }

    static func moves(in group: CameraMoveGroup) -> [CameraMove] { all.filter { $0.group == group } }

    static func search(_ text: String) -> [CameraMove] {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(query) || english($0.name).localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    static func maxMoves(forDuration seconds: Int?, allowsThird: Bool = false) -> Int {
        guard let seconds else { return 2 }
        return seconds < 5 ? 1 : seconds < 10 || !allowsThird ? 2 : maxMix
    }

    static func combined(_ ids: [String], strength: CameraStrength? = nil, family: VideoFamily = .other,
                         limit: Int = maxMix) -> String? {
        var seen = Set<String>()
        let moves = ids.filter { seen.insert($0).inserted }.compactMap(move).prefix(max(1, min(limit, maxMix)))
        guard !moves.isEmpty else { return nil }
        let parts = moves.enumerated().map { index, move in
            let sentence = clause(move.text(for: family))
            return index == 0 ? sentence : lowercasingFirst(sentence)
        }
        let line = parts.joined(separator: ", then ") + "."
        guard let strength, strength != .normal, !moves.contains(where: \.statesSpeed) else { return line }
        return line + " " + strength.sentence
    }

    static func clause(_ sentence: String) -> String {
        var text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix(".") { text.removeLast() }
        return text
    }

    static func lowercasingFirst(_ text: String) -> String {
        guard let first = text.first, first.isUppercase else { return text }
        let second = text.dropFirst().first
        if let second, second.isUppercase { return text }
        return first.lowercased() + text.dropFirst()
    }

    private static func m(_ id: String, _ name: String, _ group: CameraMoveGroup, _ prompt: String,
                          wan: String? = nil, big: Bool = false) -> CameraMove {
        CameraMove(id: id, name: name, group: group, prompt: prompt, wanPrompt: wan, isBig: big)
    }

    static let all: [CameraMove] = [
        m("static", L("Static"), .basic, "Locked-off camera on a tripod; the frame does not move at all, only the subject moves."),
        m("general", L("General"), .basic, "Gentle, natural camera movement that suits the scene: a slow, subtle drift with a little handheld life."),
        m("zoom-in", L("Zoom In"), .basic, "Slow optical zoom in toward the subject; the camera stays in place while the lens tightens the framing."),
        m("zoom-out", L("Zoom Out"), .basic, "Slow optical zoom out from the subject; the camera stays in place while the framing widens to reveal the surroundings."),
        m("dolly-in", L("Dolly In"), .basic, "The camera physically moves forward toward the subject on a smooth dolly at steady speed, with visible background parallax."),
        m("dolly-out", L("Dolly Out"), .basic, "The camera physically moves backward away from the subject on a smooth dolly, revealing more of the scene."),
        m("dolly-left", L("Dolly Left"), .basic, "The camera tracks sideways to the left on a smooth dolly, parallel to the subject, with foreground parallax."),
        m("dolly-right", L("Dolly Right"), .basic, "The camera tracks sideways to the right on a smooth dolly, parallel to the subject, with foreground parallax."),
        m("pan-left", L("Pan Left"), .basic, "From a fixed position, the camera pans smoothly to the left, rotating on its vertical axis."),
        m("pan-right", L("Pan Right"), .basic, "From a fixed position, the camera pans smoothly to the right, rotating on its vertical axis."),
        m("tilt-up", L("Tilt Up"), .basic, "From a fixed position, the camera tilts up smoothly, from the subject's feet to above their head."),
        m("tilt-down", L("Tilt Down"), .basic, "From a fixed position, the camera tilts down smoothly, from above the subject's head to their feet."),
        m("pedestal-up", L("Pedestal Up"), .basic, "The camera rises straight up on a pedestal, staying level and keeping the subject in frame."),
        m("pedestal-down", L("Pedestal Down"), .basic, "The camera lowers straight down on a pedestal, staying level and keeping the subject in frame."),
        m("arc-left", L("Arc Left"), .basic, "The camera arcs around the subject to the left, about 45 degrees, at constant distance, keeping them centered."),
        m("arc-right", L("Arc Right"), .basic, "The camera arcs around the subject to the right, about 45 degrees, at constant distance, keeping them centered."),
        m("handheld", L("Handheld"), .basic, "Handheld camera with natural slight shake and small reframing, as if held by an operator walking gently."),
        m("overhead", L("Overhead"), .basic, "Top-down overhead view, the camera pointing straight down and drifting slowly across the scene."),
        m("tracking", L("Tracking Shot"), .basic, "The camera follows the subject from behind as they walk, at exactly their speed."),
        m("side-tracking", L("Side Tracking"), .basic, "The camera moves alongside the walking subject in profile, matching their pace."),

        m("crane-up", L("Crane Up"), .epic, "The camera rises vertically on a crane and ends in a high angle looking down on the subject."),
        m("crane-down", L("Crane Down"), .epic, "The camera descends vertically on a crane from a high angle down to the subject's eye level."),
        m("crane-over-the-head", L("Crane Over The Head"), .epic, "The camera rises on a crane and passes directly over the subject's head, ending looking straight down at them."),
        m("jib-up", L("Jib Up"), .epic, "A short jib arm lifts the camera upward in a gentle arc while keeping the subject centered."),
        m("jib-down", L("Jib Down"), .epic, "A short jib arm lowers the camera downward in a gentle arc while keeping the subject centered."),
        m("360-orbit", L("360 Orbit"), .epic, "The camera orbits a full 360 degrees around the subject at constant speed and height, keeping them centered and sharp.",
          wan: "The camera arcs about 45 degrees around the subject at constant speed and height, keeping them centered and sharp.", big: true),
        m("drone-orbit", L("Drone Orbit"), .epic, "A drone slowly orbits the subject from above at a 45-degree downward angle.",
          wan: "A drone arcs slowly about 45 degrees around the subject from above, looking down at a 45-degree angle."),
        m("aerial-pullback", L("Aerial Pullback"), .epic, "Starting close on the subject, the camera pulls back and rises in one long continuous aerial move that reveals the whole landscape.", big: true),
        m("helicopter-shot", L("Helicopter Shot"), .epic, "A high aerial helicopter shot circling slowly above the location.",
          wan: "A high aerial helicopter shot arcing slowly, about 45 degrees, above the location.", big: true),
        m("fpv-drone", L("FPV Drone"), .epic, "FPV drone shot: fast, agile flight swooping toward and around the subject with banking turns, smooth and continuous.", big: true),
        m("hero-cam", L("Hero Cam"), .epic, "Low-angle hero shot: the camera starts low and slowly rises and pushes in as the subject stands tall and powerful."),
        m("super-dolly-in", L("Super Dolly In"), .epic, "A long, fast, dramatic dolly in from a wide shot to an extreme close-up of the subject's eyes in one move.", big: true),
        m("super-dolly-out", L("Super Dolly Out"), .epic, "A long, fast, dramatic dolly out from an extreme close-up of the subject's eyes to a wide shot of the scene in one move.", big: true),
        m("through-object-in", L("Through Object In"), .epic, "The camera flies through a gap in a foreground object, such as a window, leaves or a doorway, into the scene toward the subject."),
        m("through-object-out", L("Through Object Out"), .epic, "The camera pulls back from the subject and out through a gap in a foreground object, such as a window, leaves or a doorway."),

        m("crash-zoom-in", L("Crash Zoom In"), .dynamic, "A sudden, very fast crash zoom in onto the subject's face, snapping into a tight close-up.", big: true),
        m("crash-zoom-out", L("Crash Zoom Out"), .dynamic, "A sudden, very fast crash zoom out from a close-up to a wide shot of the whole scene.", big: true),
        m("rapid-zoom-in", L("Rapid Zoom In"), .dynamic, "A quick, punchy zoom in on the subject in under a second, then hold."),
        m("rapid-zoom-out", L("Rapid Zoom Out"), .dynamic, "A quick, punchy zoom out from the subject in under a second, then hold on the wide frame."),
        m("whip-pan", L("Whip Pan"), .dynamic, "A very fast whip pan to the side with heavy motion blur, landing on the subject."),
        m("yoyo-zoom", L("YoYo Zoom"), .dynamic, "Yo-yo zoom: a quick zoom in, then out, then in again on the subject, rhythmic and playful."),
        m("wiggle", L("Wiggle"), .dynamic, "A playful, quick side-to-side wiggle of the camera, a few small rapid shakes, then it settles on the subject."),
        m("robo-arm", L("Robo Arm"), .dynamic, "A motion-control robot-arm move: a fast, precise sweep that whips around the subject and stops perfectly, like a high-end commercial.",
          wan: "A motion-control robot-arm move: a fast, precise sweep of about 45 degrees around the subject that stops perfectly, like a high-end commercial.", big: true),
        m("flying-cam-transition", L("Flying Cam Transition"), .dynamic, "The camera flies fast past the subject and through the scene in one seamless whoosh, as if traveling to the next location.", big: true),
        m("bullet-time", L("Bullet Time"), .dynamic, "Bullet time: the action freezes in mid-motion while the camera sweeps 180 degrees around the subject, then the motion resumes.",
          wan: "Bullet time: the action freezes in mid-motion while the camera sweeps about 45 degrees around the subject, then the motion resumes.", big: true),
        m("3d-rotation", L("3D Rotation"), .dynamic, "The subject rotates on its own vertical axis like on a turntable while the camera stays still, showing every side."),
        m("lazy-susan", L("Lazy Susan"), .dynamic, "The subject sits on a slowly rotating platform; the camera stays still while it turns half a circle."),
        m("eating-zoom", L("Eating Zoom"), .dynamic, "The camera pushes into an extreme close-up of the mouth as the person takes a bite, then pulls back."),
        m("mouth-in", L("Mouth In"), .dynamic, "The camera dives toward the person's open mouth and flies inside in one continuous, surreal move."),
        m("eyes-in", L("Eyes In"), .dynamic, "The camera pushes rapidly toward the person's eye until the iris fills the frame."),
        m("buckle-up", L("Buckle Up"), .dynamic, "Inside a car: the camera is mounted on the dashboard facing the driver as the car accelerates hard, with slight vibration."),
        m("car-chasing", L("Car Chasing"), .dynamic, "The camera chases a moving car from behind at speed, low to the road, with motion blur on the asphalt."),
        m("car-grip", L("Car Grip"), .dynamic, "The camera is mounted on the side of a moving car, looking along the car body at the passing street, steady with road vibration."),
        m("road-rush", L("Road Rush"), .dynamic, "A low camera rushes forward along the road surface at high speed, lane lines streaking past."),
        m("fisheye", L("Fisheye"), .dynamic, "Ultra-wide fisheye lens with strong barrel distortion; the camera is close to the subject and moves slightly with them."),
        m("low-shutter", L("Low Shutter"), .dynamic, "Low-shutter-speed look: streaky motion-blur trails on everything that moves while the camera drifts slowly."),

        m("hyperlapse", L("Hyperlapse"), .timelapse, "Hyperlapse: the camera travels steadily forward through the scene while time speeds up, people and clouds streaking past."),
        m("timelapse-landscape", L("Timelapse Landscape"), .timelapse, "Locked-off timelapse of the landscape: clouds race, and light and shadows sweep across as hours pass."),
        m("timelapse-human", L("Timelapse Human"), .timelapse, "Timelapse: the subject stays still while the people around them move as fast, blurred streams."),
        m("timelapse-glam", L("Timelapse Glam"), .timelapse, "Glam timelapse: the person holds a pose while the light, background and styling change rapidly around them."),

        m("dolly-zoom-in", L("Dolly Zoom In"), .cinema, "Dolly zoom: the camera moves toward the subject while zooming out, so the subject stays the same size while the background stretches away (vertigo effect)."),
        m("dolly-zoom-out", L("Dolly Zoom Out"), .cinema, "Dolly zoom: the camera moves away from the subject while zooming in, so the subject stays the same size while the background looms closer."),
        m("double-dolly", L("Double Dolly"), .cinema, "Double dolly: the subject and the camera move forward together at the same speed, so the subject stays the same size while the background glides past."),
        m("dutch-angle", L("Dutch Angle"), .cinema, "The camera rolls into a tilted Dutch angle of about 20 degrees while drifting slowly, creating tension."),
        m("incline", L("Incline"), .cinema, "The camera moves forward while slowly rising from a low angle to eye level, giving a gradual sense of ascent."),
        m("focus-change", L("Focus Change"), .cinema, "Rack focus: the foreground starts sharp with the subject blurred, then focus shifts smoothly onto the subject."),
        m("snorricam", L("Snorricam"), .cinema, "Snorricam: the camera is rigged to the subject's body facing them, so their face stays fixed in frame while the background sways and moves."),
        m("head-tracking", L("Head Tracking"), .cinema, "The camera tracks the subject's head closely from the front as they move, keeping the face centered in frame."),
        m("object-pov", L("Object POV"), .cinema, "The point of view of an object close to the subject, such as a cup, phone or bag, looking up at them as they interact with it."),
        m("pov", L("POV"), .cinema, "First-person point of view through the subject's eyes, hands visible, walking forward."),
        m("bts", L("BTS"), .cinema, "Behind-the-scenes look: a handheld camera slightly off-axis, as if a crew member is filming the shoot from the side."),
        m("glam", L("Glam"), .cinema, "Glamour beauty shot: a slow push-in with a soft breeze in the hair, gentle light flicker and a slight slow-motion feel."),
    ]
}
