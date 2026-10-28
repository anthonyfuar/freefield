import SwiftUI

enum VideoEffectInput: String {
    case photo
    case product
    case image

    var title: String {
        switch self {
        case .photo: L("Your photo")
        case .product: L("Your product")
        case .image: L("Image")
        }
    }

    var symbol: String {
        switch self {
        case .photo: "person.crop.square"
        case .product: "shippingbox"
        case .image: "photo"
        }
    }

    var identityLine: String? {
        switch self {
        case .photo: "The person keeps the same face, hair and clothing throughout."
        case .product: "The product's shape, label, logo and colors stay exact."
        case .image: nil
        }
    }
}

enum VideoEffectCategory: String, CaseIterable, Identifiable {
    case viral, visualFX, transform, transitions, ugc, product, action, dance, horror, apps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .viral: L("Viral")
        case .visualFX: L("Visual Effects")
        case .transform: L("Transformations")
        case .transitions: L("Transitions")
        case .ugc: L("UGC & Lifestyle")
        case .product: L("Product")
        case .action: L("Sports & Action")
        case .dance: L("Dance & Gestures")
        case .horror: L("Horror")
        case .apps: L("With Photo Effect")
        }
    }

    var tint: Color {
        switch self {
        case .viral: .pink
        case .visualFX: .purple
        case .transform: .teal
        case .transitions: .indigo
        case .ugc: .orange
        case .product: .blue
        case .action: .green
        case .dance: .mint
        case .horror: .red
        case .apps: .brand
        }
    }
}

struct VideoEffect: Identifiable, Hashable {
    let id: String
    let name: String
    let hint: String
    let summary: String
    let category: VideoEffectCategory
    let input: VideoEffectInput
    let symbol: String
    let model: String
    var duration = 5
    var resolution = "720p"
    var audio = false
    var aspect: String?
    var quickStyleID: String?
    var identityLine: String?
    var textTitle: String?
    var textPlaceholder: String?
    let template: String

    var takesText: Bool { template.contains("{text}") }

    var previewStill: URL? {
        Bundle.main.url(forResource: id, withExtension: "heic", subdirectory: "Examples/video/effects")
    }
}

enum VideoEffects {
    static let textFieldID = "effect"

    static func effect(_ id: String) -> VideoEffect? { all.first { $0.id == id } }

    static func filtered(category: VideoEffectCategory?, search: String) -> [VideoEffect] {
        var list = category.map { category in all.filter { $0.category == category } } ?? all
        let query = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            list = list.filter { effect in
                [effect.name, effect.summary, effect.hint, effect.category.title].contains { $0.localizedCaseInsensitiveContains(query) }
            }
        }
        return list
    }

    static func paired(withQuickStyle id: String) -> VideoEffect? { all.first { $0.quickStyleID == id } }

    private static let kling = "kwaivgi/kling-v3.0-std"
    private static let veoLite = "google/veo-3.1-lite"
    private static let seedanceFast = "bytedance/seedance-2.0-fast"
    private static let grokLite = "x-ai/grok-imagine-video-1.5-lite"

    static let all: [VideoEffect] = [
        VideoEffect(id: "earth-zoom-out", name: L("Earth Zoom Out"), hint: L("A photo of a person outdoors"), summary: L("The camera flies up from you all the way to space."), category: .viral,
                    input: .photo, symbol: "globe.americas", model: kling, aspect: "9:16",
                    template: "Starting exactly on the first frame, the camera pulls straight up and away in one continuous, accelerating move: the person, the street, the neighborhood, the city, the coastline, and finally the whole curved Earth seen from orbit against black space, with a thin blue atmosphere and the sun on the horizon. Realistic satellite-photo detail at every height, no cuts; as the camera rises the city shrinks into a tiny gray speck on the coast, and from orbit the Earth shows only natural continents, oceans and clouds, with no city texture on it. The person keeps the same face, clothes and pose at the start."),
        VideoEffect(id: "eyes-in", name: L("Eyes In"), hint: L("A close portrait of a person"), summary: L("The camera dives into an eye and on into the stars."), category: .viral,
                    input: .photo, symbol: "eye", model: kling, aspect: "9:16",
                    template: "The camera pushes in fast and continuously toward the person's left eye until the iris fills the frame, then flies through the pupil into a glowing tunnel of stars and nebula colors. One continuous move, sharp focus, a clean and detailed iris texture, no cuts. The face stays exactly as in the first frame until the camera enters the eye."),
        VideoEffect(id: "turning-metal", name: L("Turning Metal"), hint: L("A photo of a person, waist up"), summary: L("You slowly turn into liquid chrome."), category: .viral,
                    input: .photo, symbol: "circle.hexagongrid", model: kling, aspect: "9:16", identityLine: "",
                    template: "Starting at the fingertips and spreading up the arms, over the clothes and finally the face, the person's skin and clothing turn into polished liquid chrome within four seconds; reflections of the surroundings slide across the new metal surface. The person keeps the same pose and blinks once before the face finishes turning to metal. Locked-off camera, realistic reflections."),
        VideoEffect(id: "melting", name: L("Melting"), hint: L("A photo of a person or an object"), summary: L("The subject melts away like warm wax."), category: .viral,
                    input: .image, symbol: "drop", model: kling, aspect: "9:16",
                    template: "The subject slowly melts like warm wax from the top down: its colors stay intact, thick glossy drips slide down and pool on the ground, and the shape sags gradually while the background stays still. Locked-off camera, realistic viscous liquid physics, no smoke."),
        VideoEffect(id: "building-explosion", name: L("Building Explosion"), hint: L("A person in front of a building or street"), summary: L("A building explodes as you walk away calmly."), category: .viral,
                    input: .photo, symbol: "flame", model: veoLite, duration: 6, audio: true, aspect: "9:16",
                    template: "Behind the person, the building erupts in a huge cinematic explosion: a rolling fireball, a shockwave and flying debris. The person stays calm and walks slowly toward the camera without looking back, hair and clothes pushed forward by the blast wind, orange firelight on their back. Handheld action-movie camera. SFX: a deep boom, then debris raining down. No music, no subtitles."),
        VideoEffect(id: "angel-wings", name: L("Angel Wings"), hint: L("A photo of a person"), summary: L("White wings unfold from your back."), category: .viral,
                    input: .photo, symbol: "bird", model: veoLite, duration: 6, audio: true, aspect: "9:16",
                    template: "Large white feathered wings unfold from the person's back and spread wide with a soft rustle; a few feathers drift down through warm backlight as the person slowly looks up into golden light rays from above. Slow push-in, photorealistic feathers. Ambient noise: soft wind and a gentle choir hum. No subtitles."),
        VideoEffect(id: "disintegration", name: L("Disintegration"), hint: L("A photo of a person"), summary: L("You crumble into dust on the wind."), category: .viral,
                    input: .photo, symbol: "aqi.medium", model: kling, aspect: "9:16",
                    template: "The person begins to turn into fine dust from the edges inward: tiny particles break away from the fingertips, hair and shoulders and drift off to the right on the wind, until the figure is gone and only the empty background remains. Static camera, realistic particle physics; the face stays recognizable until it dissolves."),
        VideoEffect(id: "thunder-god", name: L("Thunder God"), hint: L("A photo of a person"), summary: L("Lightning crackles around your hands."), category: .viral,
                    input: .photo, symbol: "cloud.bolt", model: veoLite, duration: 6, audio: true, aspect: "9:16",
                    template: "Dark storm clouds gather overhead and lightning cracks across the sky; bright electric arcs crackle around the person's body and along their arms while their arms and hands stay solid and clearly visible, their eyes glow faint blue and their hair lifts with static. Locked-off camera that keeps the photo's own framing, with the person and anything they hold in frame, flickering lightning light on the face. SFX: crackling electricity and rolling thunder. No subtitles."),
        VideoEffect(id: "money-rain", name: L("Money Rain"), hint: L("A photo of a person"), summary: L("Banknotes rain down all around you."), category: .viral,
                    input: .photo, symbol: "banknote", model: grokLite, aspect: "9:16",
                    template: "Green paper banknotes with no readable text start raining down from above, fluttering and spinning around the person, who looks up, laughs and opens their arms as the bills pile up at their feet. Slight slow motion, gentle camera arc, celebratory mood. The person keeps the same face, hair and clothing throughout."),
        VideoEffect(id: "outfit-switch", name: L("Outfit Switch"), hint: L("A full-body photo of a person"), summary: L("You spin and end up in a new outfit."), category: .viral,
                    input: .photo, symbol: "tshirt", model: kling, aspect: "9:16",
                    textTitle: L("New outfit"), textPlaceholder: L("e.g. a red silk evening dress"),
                    template: "The person spins once on the spot; mid-spin there is a quick blur of motion, and when they face the camera again they are wearing {text}. Same face, hair, body and setting; the camera stays still at eye level; they finish with a confident pose."),
        VideoEffect(id: "raven-transition", name: L("Raven Transition"), hint: L("A photo of a person"), summary: L("A flock of ravens sweeps across and you vanish."), category: .viral,
                    input: .photo, symbol: "bird.fill", model: kling, aspect: "9:16",
                    identityLine: "The person keeps the same face, hair and clothing until they vanish.",
                    template: "A flock of black ravens bursts across the frame from behind the person, their wings filling the screen for a moment; as the birds scatter away, the person has vanished, leaving the empty scene and a few black feathers falling. Moody light, steady camera."),
        VideoEffect(id: "levitation", name: L("Levitation"), hint: L("A full-body photo of a person"), summary: L("You rise off the ground and float."), category: .viral,
                    input: .photo, symbol: "figure.mind.and.body", model: veoLite, duration: 6, aspect: "9:16",
                    template: "The person slowly rises off the ground and floats half a meter in the air, clothes and hair drifting as if underwater, while small dust particles and droplets lift around them. They stay calm and look into the camera. Locked-off full-body camera: their feet clearly leave the ground and their shadow stays on the ground below them. Soft natural light. The person keeps the same face, hair and clothing throughout."),
        VideoEffect(id: "portal", name: L("Portal"), hint: L("A photo of a person"), summary: L("A glowing portal opens and you step through."), category: .viral,
                    input: .photo, symbol: "circle.dashed", model: kling, aspect: "9:16",
                    identityLine: "The person keeps the same face, hair and clothing until they step through.",
                    template: "A glowing circle of swirling blue energy opens in the air beside the person, throwing moving light across them; they glance at it and step through, and the portal snaps shut behind them in a burst of sparks, leaving the scene empty."),
        VideoEffect(id: "werewolf", name: L("Werewolf"), hint: L("A photo of a person"), summary: L("You turn into a werewolf under the moon."), category: .viral,
                    input: .photo, symbol: "moon.stars", model: kling, aspect: "9:16", identityLine: "",
                    template: "Under cold moonlight the person hunches forward as coarse fur spreads across their face and arms, their ears lengthen, their jaw stretches into a wolf's muzzle and yellow eyes open; they end as a werewolf still fully dressed in the same clothes, intact and covering the body, with fur pushing out only at the cuffs and collar, and let out a silent howl. No bare skin. Static camera, realistic practical-effects look."),
        VideoEffect(id: "cyborg", name: L("Cyborg"), hint: L("A photo of a person"), summary: L("Panels open to show machinery under your skin."), category: .viral,
                    input: .photo, symbol: "cpu", model: kling, aspect: "9:16",
                    template: "Thin seams of light appear on the person's skin; panels slide open along the jaw, neck and forearm to reveal intricate chrome machinery and glowing blue circuits underneath, and their eyes light up softly. The person stays calm and turns their head slightly. Slow push-in, realistic metal and skin."),
        VideoEffect(id: "water-bending", name: L("Water Bending"), hint: L("A photo of a person"), summary: L("A ribbon of water spirals around you."), category: .viral,
                    input: .photo, symbol: "water.waves", model: kling, aspect: "9:16",
                    template: "The person raises their hands and a ribbon of clear water rises from the ground, spiraling around their body in a graceful arc, hanging in midair for a moment, then splashing down. Realistic water physics with droplets catching the light; the camera arcs slowly."),
        VideoEffect(id: "painting-alive", name: L("Painting Comes Alive"), hint: L("A painting or artwork, not a photo of a real person"), summary: L("The painted figure blinks, breathes and smiles."), category: .viral,
                    input: .image, symbol: "paintpalette", model: seedanceFast, audio: true,
                    template: "The painted figure blinks, breathes, turns their head slightly toward the viewer and smiles; loose strands of hair and fabric move gently, while the brushstrokes, canvas texture and palette stay exactly the same. Slow push-in. （quiet classical music）"),

        VideoEffect(id: "splash", name: L("Splash"), hint: L("A product photo"), summary: L("A wave of water crashes around the product."), category: .visualFX,
                    input: .product, symbol: "drop.triangle", model: seedanceFast, audio: true,
                    template: "A wave of clear water crashes in from the left and splashes around the single product in slow motion, droplets frozen in the light, then falls away and leaves it glistening and wet; there is only one product, the water never passes through it, and its shape and cap never change. Locked-off camera, high-speed-camera look. < water splash > The product's shape, label and colors stay exact."),
        VideoEffect(id: "flame-reveal", name: L("Flame Reveal"), hint: L("A product photo or a scene"), summary: L("Flames sweep up and reveal the product."), category: .visualFX,
                    input: .product, symbol: "flame.fill", model: seedanceFast, audio: true,
                    template: "Flames sweep up across the frame from the bottom edge, briefly engulfing the view in orange fire, and burn away to reveal the same product glowing in warm firelight with embers floating around it. Steady camera. < roaring fire > The product stays exactly as in the first frame."),
        VideoEffect(id: "diamond", name: L("Diamond"), hint: L("A product or object photo"), summary: L("The object turns into sparkling diamond."), category: .visualFX,
                    input: .image, symbol: "diamond", model: seedanceFast,
                    template: "Starting from the center, the object's surface turns into faceted clear diamond; light refracts into rainbow sparkles as the camera slowly orbits about 30 degrees. The shape and proportions stay exactly the same."),
        VideoEffect(id: "x-ray-scan", name: L("X-Ray Scan"), hint: L("A product or object photo"), summary: L("A scan line shows the inside as an X-ray."), category: .visualFX,
                    input: .image, symbol: "rays", model: seedanceFast, audio: true,
                    template: "A thin band of blue scanning light sweeps across the frame from left to right; wherever it passes, the object appears as a glowing blue X-ray showing its internal parts, and once the band has passed it returns to normal. Locked-off camera. < soft electronic scan beep >"),
        VideoEffect(id: "wireframe", name: L("Wireframe"), hint: L("A product photo or a scene"), summary: L("The scene turns into a 3D wireframe and back."), category: .visualFX,
                    input: .image, symbol: "cube.transparent", model: seedanceFast,
                    template: "From top to bottom the scene dissolves into a glowing green 3D wireframe mesh and holds for a beat while the camera drifts slightly, then rebuilds into the real photo from bottom to top. Clean, precise CG look."),
        VideoEffect(id: "ice-freeze", name: L("Ice Freeze"), hint: L("A product photo or a scene"), summary: L("Frost grows until the product is locked in ice."), category: .visualFX,
                    input: .product, symbol: "snowflake", model: seedanceFast, audio: true,
                    template: "Frost spreads across the surface from the bottom edge, ice crystals growing over the product until it is encased in clear ice, with cold mist rolling off. Static camera. < ice crackling > The product's shape and label stay visible through the ice."),
        VideoEffect(id: "zero-gravity", name: L("Zero Gravity"), hint: L("A product photo"), summary: L("The product floats up and turns slowly."), category: .visualFX,
                    input: .product, symbol: "balloon", model: seedanceFast,
                    template: "The product lifts gently off the surface and floats, slowly rotating, while small props and droplets around it drift weightlessly; soft studio light glints across the label as it turns. Slow push-in. The product's shape, label and colors stay exact."),
        VideoEffect(id: "glitch", name: L("Glitch"), hint: L("Any image"), summary: L("Bursts of digital glitch flicker over the image."), category: .visualFX,
                    input: .image, symbol: "tv", model: grokLite,
                    template: "Short bursts of digital glitch flicker across the image in rhythm: RGB channel splits, horizontal tearing, pixel blocks and scan lines, while the scene underneath stays the same; the clip ends clean. No on-screen text."),

        VideoEffect(id: "behind-the-scenes", name: L("Behind the Scenes"), hint: L("Any image: a photo or a Photo Effects result"), summary: L("The camera pulls back to reveal a film set."), category: .apps,
                    input: .image, symbol: "video.badge.ellipsis", model: grokLite,
                    template: "The camera pulls back and to the side to reveal that the scene is a film set: crew members, lights on stands, a boom microphone and a camera rig surround it, and someone with a clapperboard walks past. Handheld documentary camera, warm set lighting. The original scene stays unchanged in the middle of the set, and the person keeps exactly the same clothes, colors and hair the whole time."),
        VideoEffect(id: "3d-rotation", name: L("3D Rotation"), hint: L("A product photo"), summary: L("The product turns a full circle."), category: .apps,
                    input: .product, symbol: "rotate.3d", model: seedanceFast,
                    template: "The product turns a full 360 degrees on its vertical axis at a constant slow speed on a seamless background, perfectly centered, with consistent soft studio light and a faint reflection below. Locked-off camera. The shape, label, logo and colors stay exact from every side."),
        VideoEffect(id: "packshot-reveal", name: L("Packshot Reveal"), hint: L("A product photo; the effect's image is made first"), summary: L("A slow, premium move around a studio packshot."), category: .apps,
                    input: .product, symbol: "camera.aperture", model: seedanceFast, audio: true, quickStyleID: "packshot",
                    template: "Premium packshot: a slow dolly in with a slight arc around the product while a soft light sweep glides across the label from left to right; tiny dust particles float in the light; the move ends on a centered hero frame. （minimal elegant music） The product stays exact."),
        VideoEffect(id: "billboard-pullback", name: L("Billboard Pullback"), hint: L("A product photo; the effect's image is made first"), summary: L("From your billboard back to the busy street."), category: .apps,
                    input: .product, symbol: "rectangle.on.rectangle", model: seedanceFast, audio: true, quickStyleID: "billboard",
                    template: "The camera starts tight on the billboard and pulls back smoothly to reveal the busy street at dusk below it: cars passing with light trails, people crossing, city lights coming on. The billboard image stays sharp and unchanged. < city traffic ambience >"),
        VideoEffect(id: "sketch-to-real", name: L("Sketch to Real"), hint: L("A pencil sketch or drawing"), summary: L("A sketch fills with color and becomes real."), category: .apps,
                    input: .image, symbol: "pencil.and.scribble", model: seedanceFast,
                    template: "Color and real materials flow across the pencil sketch from left to right, turning every line into a photorealistic version of the same scene with real light and shadows; once complete, the camera pushes in slightly. The composition stays identical to the sketch."),
        VideoEffect(id: "comic-book-motion", name: L("Comic Book Motion"), hint: L("A photo; the effect's image is made first"), summary: L("Your comic panel comes to life."), category: .apps,
                    input: .photo, symbol: "book.pages", model: seedanceFast, audio: true, quickStyleID: "comic-book",
                    template: "The comic panel comes to life: the character moves through their action with bold speed lines, halftone dots pulse, ink outlines stay thick and flat colors stay unchanged; a short camera shake lands on impact. 2D comic style throughout, never photorealistic. < punchy whoosh >"),
        VideoEffect(id: "roller-coaster", name: L("Roller Coaster"), hint: L("A photo of a person; the effect's image is made first"), summary: L("The coaster plunges down the big drop."), category: .apps,
                    input: .photo, symbol: "point.topleft.down.to.point.bottomright.curvepath", model: veoLite,
                    duration: 6, audio: true, aspect: "16:9", quickStyleID: "roller-coaster",
                    template: "The roller coaster car tips over the top and plunges down the steep drop; wind blasts the person's hair and face as they scream with joy, while the track and sky rush past with slight camera shake. SFX: rattling track, rushing wind, screams of joy. No music, no subtitles."),
        VideoEffect(id: "giallo-horror", name: L("Giallo Horror"), hint: L("A photo of a person; the effect's image is made first"), summary: L("A tense scene from a '70s horror film."), category: .apps,
                    input: .photo, symbol: "theatermasks", model: veoLite,
                    duration: 6, audio: true, aspect: "16:9", quickStyleID: "giallo",
                    template: "A 1970s Italian horror film: the person slowly turns toward the camera in saturated red and green light, eyes widening, as a gloved hand enters the edge of the frame; slow zoom in with film grain. Ambient noise: a tense synth drone and distant thunder. No subtitles."),
        VideoEffect(id: "sand-worm", name: L("Sandworm"), hint: L("A photo of a person; the effect's image is made first"), summary: L("A giant worm bursts out of the dunes behind you."), category: .apps,
                    input: .photo, symbol: "sun.dust", model: kling, quickStyleID: "sand-worm",
                    template: "A colossal desert worm bursts out of the dunes behind the person, sand pouring off its ringed body as it rises high into the sky; the person flinches and turns to look up at it as sand blasts past them; the worm keeps one clear head with an open mouth the whole time. Epic wide shot with the person's full body in frame, slight shake, golden haze."),
        VideoEffect(id: "storm-creature", name: L("Storm Creature"), hint: L("A photo of a person; the effect's image is made first"), summary: L("A storm giant rises behind you."), category: .apps,
                    input: .photo, symbol: "cloud.bolt.rain", model: kling, quickStyleID: "storm-creature",
                    template: "A gigantic creature made of storm clouds and lightning rises over the horizon behind the person, lightning flashing inside its body as it slowly turns its head; wind whips the person's clothes. Epic slow push-in."),
        VideoEffect(id: "asmr", name: L("ASMR"), hint: L("A product photo"), summary: L("Close-up hands tap and unwrap the product."), category: .apps,
                    input: .product, symbol: "ear", model: veoLite, duration: 6, audio: true, aspect: "9:16",
                    template: "Extreme close-up ASMR: two hands slowly tap and gently squeeze the product with a steady grip, every texture crisp and detailed, shallow depth of field; the cap and every part of the product stay on and unchanged. SFX: soft tapping, crinkling, close-up rustle, a very quiet room tone. No music, no speech, no subtitles. The product's label and colors stay exact."),
        VideoEffect(id: "magic-button", name: L("Magic Button"), hint: L("A product photo; the effect's image is made first"), summary: L("A button press makes the product appear."), category: .apps,
                    input: .product, symbol: "button.programmable", model: seedanceFast, audio: true, quickStyleID: "magic-button",
                    template: "A finger presses the glowing button; with a soft pop and a burst of sparkles the product appears and grows to full size on the surface, then the light settles. < soft click, magical chime > The product's shape, label and colors stay exact."),
        VideoEffect(id: "life-sim", name: L("Simlife"), hint: L("A photo of a person; the effect's image is made first"), summary: L("You walk around as a life-sim character."), category: .apps,
                    input: .photo, symbol: "gamecontroller", model: grokLite, quickStyleID: "simlife",
                    identityLine: "The character keeps the same look throughout.",
                    template: "Life-simulation gameplay: the character walks across the room, sits on the sofa and waves, the small glowing blue ring above their head pulsing while the needs bars tick; the high isometric game camera drifts slightly. Stylized 3D game look throughout, not a photograph."),

        VideoEffect(id: "face-punch", name: L("Face Punch"), hint: L("A close portrait of a person"), summary: L("A padded glove lands a slow-motion punch."), category: .viral,
                    input: .photo, symbol: "figure.boxing", model: kling, aspect: "9:16",
                    template: "A padded red boxing glove swings in from the right edge of the frame and lands softly on the person's cheek in extreme slow motion: the cheek ripples like a wave, hair and a few drops of sweat fly sideways and the head turns with the hit. Then the person blinks, shakes it off and grins at the camera. Comic, harmless tone, no injury. Locked-off close-up, high-speed-camera look."),
        VideoEffect(id: "lens-crack", name: L("Lens Crack"), hint: L("A photo of a person, waist up"), summary: L("You tap the lens and the glass cracks."), category: .viral,
                    input: .photo, symbol: "burst", model: kling, aspect: "9:16",
                    template: "The person leans toward the camera and taps the lens hard with one knuckle; a spiderweb crack spreads across the glass from the point of impact and catches the light, while the person leans back and smirks through it. The crack stays on the lens in front of the scene and the person behind it stays sharp. Handheld camera."),
        VideoEffect(id: "invisible", name: L("Invisible"), hint: L("A full-body photo of a person"), summary: L("Your body vanishes and only your clothes remain."), category: .viral,
                    input: .photo, symbol: "eye.slash", model: kling, aspect: "9:16",
                    identityLine: "The clothes keep their exact shape, colors and folds.",
                    template: "The person's face, hands and skin slowly turn transparent from the head down until only their clothes remain, still moving as if worn by an invisible body: the empty collar turns toward the camera and one sleeve waves. The background shows clearly through where the person was. Static camera, realistic cloth physics."),
        VideoEffect(id: "clone-army", name: L("Clone Army"), hint: L("A full-body photo of a person"), summary: L("Copies of you step out until a dozen stand in a row."), category: .viral,
                    input: .photo, symbol: "person.3.sequence.fill", model: kling, aspect: "9:16",
                    template: "Identical copies of the person step out sideways from their body one after another, each with the same face, hair and clothes, until a dozen clones stand in a line across the frame and strike the same pose at the same moment. Static wide camera, natural light, every clone sharp and realistic."),
        VideoEffect(id: "selfie-twin", name: L("Selfie Twin"), hint: L("A photo of a person, waist up"), summary: L("Your twin walks in and joins your selfie."), category: .viral,
                    input: .photo, symbol: "person.2.fill", model: kling, aspect: "9:16",
                    template: "An exact twin of the person, with the same face, hair and clothes, walks in from the side of the frame, puts an arm around them, and both lean in close for a selfie and laugh; the twin copies every expression a beat late. Handheld phone-camera feel, natural daylight."),
        VideoEffect(id: "soul-jump", name: L("Soul Jump"), hint: L("A photo of a person"), summary: L("A glowing copy of you leaps out and snaps back."), category: .viral,
                    input: .photo, symbol: "figure.walk.motion", model: kling, aspect: "9:16",
                    template: "A translucent, softly glowing copy of the person leaps forward out of their body, hangs in the air for a moment and snaps back into them, and the person jolts and blinks in surprise. The glowing copy has the same face and outline, pale blue and see-through. Static camera, slow motion on the leap."),
        VideoEffect(id: "fly-away", name: L("Fly Away"), hint: L("A full-body photo of a person outdoors"), summary: L("You launch into the sky like a superhero."), category: .viral,
                    input: .photo, symbol: "figure.arms.open", model: kling, aspect: "9:16",
                    template: "The person bends their knees and launches straight up into the sky like a superhero, clothes and hair streaming; the camera tilts up to follow as they rise into the clouds and shrink to a speck, leaving a ring of dust where they stood. Realistic motion and light, bright daytime sky."),
        VideoEffect(id: "train-rush", name: L("Train Rush"), hint: L("A photo of a person, waist up"), summary: L("A high-speed train blasts past right behind you."), category: .viral,
                    input: .photo, symbol: "tram.fill", model: kling, aspect: "9:16",
                    template: "A high-speed train blasts past right behind the person at full speed in a blur of steel and light; the rush of air whips their hair and clothes forward while they stay perfectly still and stare into the camera. Static camera, motion blur only on the train, realistic wind."),
        VideoEffect(id: "paparazzi", name: L("Paparazzi"), hint: L("A full-body photo of a person"), summary: L("Flashes go off as you pose on a red carpet."), category: .viral,
                    input: .photo, symbol: "camera.fill", model: grokLite, aspect: "9:16",
                    template: "The person walks toward the camera along a red carpet while photographers behind ropes on both sides fire bursts of camera flashes; the person pauses, glances over one shoulder, poses and waves. Bright strobing flash light, handheld camera jostled by the crowd, early-2000s red-carpet feel."),
        VideoEffect(id: "group-photo", name: L("Group Photo"), hint: L("A photo of a person"), summary: L("Friends run in and pose with you."), category: .viral,
                    input: .photo, symbol: "person.3.fill", model: kling, aspect: "9:16",
                    template: "Five friendly people of different ages and styles run into the frame from both sides, squeeze in around the person, throw arms over shoulders, and everyone poses and laughs for a group photo while the camera holds steady. The friends are new, invented people."),
        VideoEffect(id: "pool-jump", name: L("Pool Jump"), hint: L("A photo of a person outdoors"), summary: L("You cannonball into a pool with a huge splash."), category: .viral,
                    input: .photo, symbol: "figure.pool.swim", model: kling, aspect: "9:16",
                    template: "The person runs two steps and cannonballs into a bright blue swimming pool right in front of them; a huge splash bursts toward the camera in slow motion, then they surface laughing and push their wet hair back. Summer daylight, realistic water physics."),
        VideoEffect(id: "super-speed", name: L("Super Speed"), hint: L("A full-body photo of a person"), summary: L("You sprint off at superhuman speed."), category: .viral,
                    input: .photo, symbol: "figure.run", model: kling, aspect: "9:16",
                    template: "The person crouches and bursts into a superhuman sprint out of the frame; afterimages and streaks of motion blur trail behind them, loose leaves and papers whirl up in their wake and they are gone in a fraction of a second. The camera whip-pans to follow, then the dust settles on the empty spot."),
        VideoEffect(id: "stop-the-world", name: L("Stop the World"), hint: L("A photo of a person in a busy place"), summary: L("You snap your fingers and everything freezes but you."), category: .viral,
                    input: .photo, symbol: "pause.circle", model: kling, aspect: "9:16",
                    template: "The person snaps their fingers and everything around them freezes mid-motion: birds stop in the air, people stand still mid-step and drops of water hang in place. Only the person keeps moving; they walk through the frozen scene and look back at the camera with a smile. Slow arc around them."),
        VideoEffect(id: "sticker-peel", name: L("Sticker Peel"), hint: L("A photo of a person"), summary: L("You peel off the scene like a glossy sticker."), category: .viral,
                    input: .photo, symbol: "square.on.square", model: kling, aspect: "9:16",
                    template: "A thick white die-cut border appears around the person's outline, then one corner lifts and the whole person peels off the scene like a glossy sticker, curling slightly and catching the light, leaving a blank white sticker-shaped gap in the background. Crisp and playful, static camera."),
        VideoEffect(id: "cardboard-cutout", name: L("Cardboard Cutout"), hint: L("A full-body photo of a person"), summary: L("You turn into a flat cardboard standee that tips over."), category: .viral,
                    input: .photo, symbol: "rectangle.portrait", model: grokLite, aspect: "9:16",
                    identityLine: "The cutout shows the same face, hair and clothing.",
                    template: "The person suddenly turns into a flat, life-size printed cardboard cutout of themselves; as it tilts, its thin brown cardboard edge shows, it wobbles on its little stand and falls flat on its back. Static camera, comic timing, realistic cardboard."),
        VideoEffect(id: "free-fall", name: L("Free Fall"), hint: L("A photo of a person"), summary: L("You fall through the open sky above the clouds."), category: .viral,
                    input: .photo, symbol: "figure.fall", model: kling, aspect: "9:16",
                    template: "The person tips backward and falls through open sky high above the clouds, arms spread, clothes and hair flapping hard in the wind; the camera falls with them face to face, then they turn over into a calm skydiving pose. Bright sun, realistic wind physics."),
        VideoEffect(id: "magic-spell", name: L("Magic Spell"), hint: L("A photo of a person, waist up"), summary: L("A ball of magic light forms between your hands."), category: .viral,
                    input: .photo, symbol: "wand.and.stars", model: kling, aspect: "9:16",
                    template: "The person opens their palms and an orb of swirling blue magic light forms between their hands, sparks spiraling up their arms and lighting their face from below; they push it forward and it bursts into a shower of glowing sparks. Dusk light, slow arc around them."),

        VideoEffect(id: "set-on-fire", name: L("Set on Fire"), hint: L("A photo of a person"), summary: L("Stunt flames spread over you while you stay calm."), category: .visualFX,
                    input: .photo, symbol: "flame.circle", model: kling, aspect: "9:16",
                    template: "Like a controlled movie stunt, flames catch on the person's sleeve and spread over their shoulders and back while they stay completely calm, walk slowly toward the camera and look straight into the lens. Their face stays untouched; embers drift and firelight flickers on their skin. Slow motion, cinematic night."),
        VideoEffect(id: "paint-splash", name: L("Paint Splash"), hint: L("A photo of a person"), summary: L("Bright paint splashes over you in slow motion."), category: .visualFX,
                    input: .photo, symbol: "paintbrush.pointed.fill", model: kling, aspect: "9:16",
                    identityLine: "The person keeps the same face and pose.",
                    template: "Bursts of thick, glossy paint in magenta, yellow and cyan fly in from both sides and splash across the person in extreme slow motion; ribbons of paint stretch and spatter over their clothes and hair while they keep their eyes closed and smile. Bright studio light, locked-off camera."),
        VideoEffect(id: "color-powder", name: L("Color Powder"), hint: L("A photo of a person"), summary: L("A cloud of festival color powder bursts around you."), category: .visualFX,
                    input: .photo, symbol: "cloud.fill", model: kling, aspect: "9:16",
                    template: "The person throws both hands up and a huge cloud of colored powder in pink, orange and turquoise bursts around them in slow motion, billowing and glowing in the backlight, then drifting down and settling on their hair and shoulders. Festive mood, slow push-in."),
        VideoEffect(id: "fire-breath", name: L("Fire Breath"), hint: L("A photo of a person, waist up"), summary: L("You blow a jet of flame like a street performer."), category: .visualFX,
                    input: .photo, symbol: "flame", model: kling, aspect: "9:16",
                    template: "The person takes a deep breath and blows a long, roaring jet of orange flame toward the side of the frame like a street fire performer; the fire lights their face warmly and heat shimmer ripples the air, then the flame dies into a curl of smoke and they grin. Night setting, static camera, realistic fire."),
        VideoEffect(id: "floating-fish", name: L("Floating Fish"), hint: L("A photo of a person"), summary: L("Glowing fish swim through the air around you."), category: .visualFX,
                    input: .photo, symbol: "fish.fill", model: kling, aspect: "9:16",
                    template: "The air around the person fills with softly glowing fish swimming slowly as if underwater: small bright tropical fish, a drifting jellyfish and two koi circling their head. Rippling light plays across their face and they reach out to touch one. Dreamlike, slow drift of the camera."),
        VideoEffect(id: "garden-bloom", name: L("Garden Bloom"), hint: L("A photo of a person"), summary: L("Flowers grow and bloom all around you."), category: .visualFX,
                    input: .photo, symbol: "leaf.fill", model: kling, aspect: "9:16",
                    template: "In a fast time-lapse, green vines and flowers grow up from the ground around the person, curling over their shoulders and opening into roses, daisies and peonies, until they stand in a lush blooming garden with petals drifting down. Soft daylight, slow push-in."),
        VideoEffect(id: "light-trails", name: L("Light Trails"), hint: L("A photo of a person"), summary: L("Neon light trails follow your moves."), category: .visualFX,
                    input: .photo, symbol: "scribble.variable", model: kling, aspect: "9:16",
                    template: "The person moves their arms in a slow, flowing dance while bright neon light trails in pink and cyan follow their hands and trace around their body, lingering in the air like long-exposure light painting. Dark surroundings, the person lit softly by the trails, static camera."),
        VideoEffect(id: "double-exposure", name: L("Double Exposure"), hint: L("A portrait of a person"), summary: L("A misty forest fills your silhouette."), category: .visualFX,
                    input: .photo, symbol: "circle.lefthalf.filled", model: kling, aspect: "9:16",
                    template: "The person slowly turns their head into profile while their silhouette fills with a moving landscape: a misty pine forest and drifting clouds at sunrise blend inside their outline like a film double exposure, and the background fades to soft white. Elegant and slow, static camera."),
        VideoEffect(id: "night-vision", name: L("Night Vision"), hint: L("A photo of a person"), summary: L("Grainy green night-vision camera footage."), category: .visualFX,
                    input: .photo, symbol: "binoculars.fill", model: grokLite, aspect: "9:16",
                    template: "The scene turns into green night-vision camera footage: a grainy bright-green image, glowing eyes, a soft vignette and sensor noise. The person slowly turns toward the camera and raises a finger to their lips. Handheld, surveillance-camera feel."),

        VideoEffect(id: "turn-to-stone", name: L("Turn to Stone"), hint: L("A photo of a person"), summary: L("You turn into a stone statue from the feet up."), category: .transform,
                    input: .photo, symbol: "mountain.2.fill", model: kling, aspect: "9:16", identityLine: "",
                    template: "Starting at the feet, the person's clothes, skin and hair turn into gray weathered stone as cracks and fine dust spread upward; they lift a hand in surprise before the change reaches their face, then freeze as a carved stone statue in the same pose. Static camera, realistic stone texture."),
        VideoEffect(id: "ice-statue", name: L("Ice Statue"), hint: L("A photo of a person"), summary: L("Frost spreads until you're a clear ice sculpture."), category: .transform,
                    input: .photo, symbol: "snowflake.circle", model: kling, aspect: "9:16", identityLine: "",
                    template: "Frost crawls up from the person's feet and they turn into a clear, carved ice sculpture in the same pose; light refracts through the ice in rainbow glints, cold mist rolls off its surface and the eyes blink once inside the ice. Static camera, realistic ice."),
        VideoEffect(id: "clay-figure", name: L("Clay Figure"), hint: L("A photo of a person"), summary: L("You become a stop-motion clay figure."), category: .transform,
                    input: .photo, symbol: "hand.wave.fill", model: kling, aspect: "9:16",
                    identityLine: "The clay figure keeps the person's hairstyle, colors and outfit.",
                    template: "The person turns into a stop-motion clay figure: their skin, hair and clothes become soft modeling clay with tiny fingerprint marks, and they wave and bob in a choppy stop-motion rhythm while the real scene around them stays photographic. Static camera."),
        VideoEffect(id: "cartoon-me", name: L("Cartoon Me"), hint: L("A photo of a person"), summary: L("You turn into a hand-drawn cartoon."), category: .transform,
                    input: .photo, symbol: "face.smiling", model: kling, aspect: "9:16",
                    identityLine: "The cartoon keeps the person's hairstyle, hair color and outfit.",
                    template: "Starting from the edges, the person and the scene turn into a 2D hand-drawn cartoon with bold outlines, flat colors and big expressive eyes. Once the change is complete, the cartoon version bounces and waves in smooth hand-drawn animation in front of a painted cartoon backdrop."),
        VideoEffect(id: "hero-suit", name: L("Hero Suit"), hint: L("A full-body photo of a person"), summary: L("An armored suit builds itself around you."), category: .transform,
                    input: .photo, symbol: "shield.lefthalf.filled", model: kling, aspect: "9:16",
                    identityLine: "The person keeps the same face until the visor closes.",
                    template: "Sleek plates of an invented armored hero suit fly in and click into place around the person piece by piece: boots, legs, chest, arms and finally a helmet whose visor slides down and lights up. They look up, ready for action. Low angle, slow push-in, polished metal, no logos."),
        VideoEffect(id: "lava-body", name: L("Lava Body"), hint: L("A photo of a person"), summary: L("Glowing lava cracks spread across your body."), category: .transform,
                    input: .photo, symbol: "sun.max.fill", model: kling, aspect: "9:16", identityLine: "",
                    template: "Glowing cracks of molten lava spread across the person's skin and clothes until their body becomes dark cooling rock with bright orange lava flowing through the cracks and embers rising; they clench a fist and the lava pulses brighter. Static camera, realistic heat glow."),

        VideoEffect(id: "smoke-transition", name: L("Smoke Transition"), hint: L("A full-body photo of a person"), summary: L("A burst of smoke, and you reappear changed."), category: .transitions,
                    input: .photo, symbol: "smoke.fill", model: kling, aspect: "9:16",
                    textTitle: L("New outfit or place"), textPlaceholder: L("e.g. a snowy mountain top, or a white linen suit"),
                    template: "Thick white smoke billows in from the edges and swallows the frame for a moment; as it clears, the person stands in the same pose with the same face and hair, now in {text}. Steady camera."),
        VideoEffect(id: "hand-wipe", name: L("Hand Wipe"), hint: L("A photo of a person"), summary: L("Your hand covers the lens and you change."), category: .transitions,
                    input: .photo, symbol: "hand.raised.fill", model: kling, aspect: "9:16",
                    textTitle: L("New outfit or place"), textPlaceholder: L("e.g. a snowy mountain top, or a white linen suit"),
                    template: "The person moves their open palm toward the lens until it covers the whole frame; as the hand pulls away, they have the same face and hair but are now in {text}, with a confident smile. Handheld phone-video feel."),
        VideoEffect(id: "jump-transition", name: L("Jump Transition"), hint: L("A full-body photo of a person"), summary: L("You jump and land somewhere new."), category: .transitions,
                    input: .photo, symbol: "figure.jumprope", model: kling, aspect: "9:16",
                    textTitle: L("New outfit or place"), textPlaceholder: L("e.g. a snowy mountain top, or a white linen suit"),
                    template: "The person jumps straight up; at the top of the jump the frame blurs with motion, and they land with the same face and hair, now in {text}, and strike a pose. Static camera at chest height."),
        VideoEffect(id: "melt-transition", name: L("Melt Transition"), hint: L("A photo of a person"), summary: L("The picture melts away to show the new look."), category: .transitions,
                    input: .photo, symbol: "drop.halffull", model: kling, aspect: "9:16",
                    textTitle: L("New outfit or place"), textPlaceholder: L("e.g. a snowy mountain top, or a white linen suit"),
                    template: "The whole picture melts downward like wet paint, colors dripping off the frame, and underneath it the person appears with the same face and hair, now in {text}, looking into the camera as the last drips fall away. Static camera."),
        VideoEffect(id: "phone-screen", name: L("Phone Screen"), hint: L("A photo of a person"), summary: L("The scene shrinks into a phone and swipes to a new one."), category: .transitions,
                    input: .photo, symbol: "iphone", model: kling, aspect: "9:16",
                    textTitle: L("New outfit or place"), textPlaceholder: L("e.g. a snowy mountain top, or a white linen suit"),
                    template: "The camera pulls back fast to reveal the scene is playing on a phone screen held in a hand; a thumb swipes and the screen now shows the person with the same face and hair, now in {text}, and the camera pushes back into the screen until it fills the frame again."),
        VideoEffect(id: "film-burn", name: L("Film Burn"), hint: L("A photo of a person"), summary: L("An old film burn flashes to a new scene."), category: .transitions,
                    input: .photo, symbol: "film", model: kling, aspect: "9:16",
                    textTitle: L("New outfit or place"), textPlaceholder: L("e.g. a snowy mountain top, or a white linen suit"),
                    template: "The frame flickers like an old film reel and a warm orange film burn spreads from the center until the picture whites out; the image returns with soft grain and light leaks, showing the person with the same face and hair, now in {text}. Static camera."),

        VideoEffect(id: "outfit-check", name: L("Outfit Check"), hint: L("A full-body photo of a person"), summary: L("A mirror-selfie spin to show off the outfit."), category: .ugc,
                    input: .photo, symbol: "tshirt.fill", model: grokLite, aspect: "9:16",
                    template: "The person stands in front of a full-length mirror holding up their phone, turns side to side to show off the outfit, does a small spin and nods with approval. Casual phone-video look, warm room light."),
        VideoEffect(id: "sunglasses-on", name: L("Sunglasses On"), hint: L("A close portrait of a person"), summary: L("You put on sunglasses with a cool head tilt."), category: .ugc,
                    input: .photo, symbol: "sunglasses.fill", model: grokLite, aspect: "9:16",
                    template: "The person lifts a pair of dark sunglasses, slides them on with a cool head tilt and a half smile as a lens flare glints across the lenses, then looks straight into the camera. Slight slow motion, golden-hour light, handheld."),
        VideoEffect(id: "first-bite", name: L("First Bite"), hint: L("A close photo of a person"), summary: L("A big, happy bite of a juicy burger."), category: .ugc,
                    input: .photo, symbol: "fork.knife", model: grokLite, aspect: "9:16",
                    template: "The person takes a big first bite of a juicy burger, closes their eyes in delight, chews and gives the camera a thumbs up. Close-up, warm natural light, casual food-video feel."),
        VideoEffect(id: "hair-flip", name: L("Hair Flip"), hint: L("A portrait of a person"), summary: L("A slow-motion hair flip, beauty-ad style."), category: .ugc,
                    input: .photo, symbol: "wind", model: kling, aspect: "9:16",
                    template: "The person flips their hair over one shoulder in slow motion, every strand catching the light as it swings and settles, then looks at the camera with a soft smile. Beauty-commercial lighting, gentle push-in."),
        VideoEffect(id: "big-smile", name: L("Big Smile"), hint: L("A close portrait of a person"), summary: L("A straight face melts into a real laugh."), category: .ugc,
                    input: .photo, symbol: "face.smiling.inverse", model: kling, aspect: "9:16",
                    template: "The person's neutral expression slowly melts into a huge, genuine laugh: their eyes crinkle, their head tips back a little and they cover their mouth with one hand. Natural, believable emotion, static close-up."),
        VideoEffect(id: "tears", name: L("Tears"), hint: L("A close portrait of a person"), summary: L("Eyes well up and a tear rolls down."), category: .ugc,
                    input: .photo, symbol: "cloud.rain.fill", model: kling, aspect: "9:16",
                    template: "The person's lips tremble, their eyes fill with tears that slowly roll down their cheeks, and they wipe one away while trying to smile. Soft window light, static close-up, realistic and moving."),
        VideoEffect(id: "shocked", name: L("Shocked"), hint: L("A close portrait of a person"), summary: L("Your jaw drops and your hands fly to your face."), category: .ugc,
                    input: .photo, symbol: "exclamationmark.bubble.fill", model: grokLite, aspect: "9:16",
                    template: "The person glances at something just below the camera, freezes, their jaw drops and both hands fly up to their cheeks in total disbelief, then they stare straight into the lens. A quick snap zoom in on the reaction."),
        VideoEffect(id: "yacht-day", name: L("Yacht Day"), hint: L("A photo of a person"), summary: L("You cruise on a yacht across a turquoise sea."), category: .ugc,
                    input: .photo, symbol: "sailboat.fill", model: kling, aspect: "9:16",
                    template: "The person stands at the bow of a white yacht cruising across a turquoise sea, wind in their hair and sea spray sparkling; they lean on the rail and look back at the camera as a drone shot rises and pulls back to show the open water."),
        VideoEffect(id: "catwalk", name: L("Catwalk"), hint: L("A full-body photo of a person"), summary: L("You walk a fashion runway under the flashes."), category: .ugc,
                    input: .photo, symbol: "figure.walk", model: kling, aspect: "9:16",
                    template: "The person walks a fashion-show runway toward the camera with a confident model stride, pauses at the end, turns and poses while camera flashes pop in the audience on both sides. Front-on telephoto shot, bright runway lights."),

        VideoEffect(id: "exploded-view", name: L("Exploded View"), hint: L("A product photo"), summary: L("The product comes apart into floating parts and back."), category: .product,
                    input: .product, symbol: "square.stack.3d.up.fill", model: seedanceFast,
                    template: "The product slowly separates into its parts, which float apart in an orderly exploded technical view, every piece sharp and lit, then glide back together into the finished product. Clean studio background, slow orbit. The finished product's shape, label and colors stay exact."),
        VideoEffect(id: "giant-hand", name: L("Giant Hand"), hint: L("A product photo"), summary: L("A giant hand lifts the product over the city."), category: .product,
                    input: .product, symbol: "hand.point.up.left.fill", model: seedanceFast,
                    template: "A giant hand reaches down from the sky and gently picks the product up from a city street, lifts it high above the rooftops and turns it toward the camera while people below look up. Realistic scale, daylight."),
        VideoEffect(id: "product-drop", name: L("Product Drop"), hint: L("A product photo"), summary: L("The product drops onto a wet surface in slow motion."), category: .product,
                    input: .product, symbol: "arrow.down.to.line", model: seedanceFast,
                    template: "The product drops from above onto a glossy wet surface in slow motion, lands with a gentle bounce and a ring of water droplets bursts outward, then the camera pushes in to a centered hero frame. Studio light."),
        VideoEffect(id: "unboxing", name: L("Unboxing"), hint: L("A product photo"), summary: L("Hands open a box and reveal the product."), category: .product,
                    input: .product, symbol: "shippingbox.fill", model: seedanceFast,
                    template: "Top-down close-up: two hands open a plain kraft box, lift the tissue paper and reveal the product, then pick it up and turn it toward the camera. Soft daylight, satisfying unboxing pace, no writing on the box."),

        VideoEffect(id: "boxing", name: L("Boxing"), hint: L("A photo of a person"), summary: L("A fast combo on the heavy bag in a boxing gym."), category: .action,
                    input: .photo, symbol: "figure.kickboxing", model: kling, aspect: "9:16",
                    identityLine: "The person keeps the same face and hair.",
                    template: "In a gritty boxing gym, the person, in boxing gloves and training gear, throws a fast combination of jabs and a hook at a heavy bag, sweat flying and the bag swinging on its chain. Low angle, a single spotlight, slight slow motion on the hook."),
        VideoEffect(id: "slam-dunk", name: L("Slam Dunk"), hint: L("A full-body photo of a person"), summary: L("A high-flying dunk on an outdoor court."), category: .action,
                    input: .photo, symbol: "figure.basketball", model: kling, aspect: "9:16",
                    identityLine: "The person keeps the same face and hair.",
                    template: "On an outdoor basketball court, the person sprints toward the hoop, leaps high and slams the ball through the rim in slow motion, hangs on the rim for a beat, then drops down and pumps a fist. Low wide angle, late-afternoon sun."),
        VideoEffect(id: "skate-ollie", name: L("Skate Ollie"), hint: L("A full-body photo of a person"), summary: L("A clean ollie down a sunny street."), category: .action,
                    input: .photo, symbol: "figure.skateboarding", model: kling, aspect: "9:16",
                    template: "The person rides a skateboard toward the camera down a sunny street, pops a clean ollie over a crack in the pavement, lands smoothly and rolls past. Low tracking shot alongside, natural motion."),
        VideoEffect(id: "powder-run", name: L("Powder Run"), hint: L("A photo of a person"), summary: L("You carve down a snowy slope on a snowboard."), category: .action,
                    input: .photo, symbol: "figure.snowboarding", model: kling, aspect: "9:16",
                    identityLine: "The person keeps the same face.",
                    template: "The person, in winter gear, carves down a steep snowy slope on a snowboard and throws a huge plume of powder snow toward the camera on a sharp turn, bright sun on the peaks. Tracking shot from the side."),
        VideoEffect(id: "stadium-goal", name: L("Stadium Goal"), hint: L("A full-body photo of a person"), summary: L("You score and celebrate in a packed stadium."), category: .action,
                    input: .photo, symbol: "soccerball", model: kling, aspect: "9:16",
                    identityLine: "The person keeps the same face and hair.",
                    template: "In a packed floodlit stadium, the person, in a plain soccer kit with no logos, dribbles past a defender and strikes the ball into the top corner of the net, then runs toward the camera celebrating with arms wide as the crowd erupts. Broadcast camera tracking."),
        VideoEffect(id: "final-serve", name: L("Final Serve"), hint: L("A full-body photo of a person"), summary: L("A powerful tennis serve in slow motion."), category: .action,
                    input: .photo, symbol: "figure.tennis", model: kling, aspect: "9:16",
                    identityLine: "The person keeps the same face and hair.",
                    template: "On a tennis court in bright sun, the person tosses the ball and hits a powerful serve in slow motion, the racket strings flexing on impact; the camera follows the ball for a moment, then returns to their fierce focus."),
        VideoEffect(id: "podium-win", name: L("Podium Win"), hint: L("A photo of a person"), summary: L("You win and spray the crowd from the podium."), category: .action,
                    input: .photo, symbol: "trophy.fill", model: kling, aspect: "9:16",
                    identityLine: "The person keeps the same face and hair.",
                    template: "The person stands on the top step of a race podium in a plain racing suit with no logos, lifts a gold trophy and sprays a bottle of sparkling wine over the cheering crowd below as confetti falls. Low angle, bright daylight."),
        VideoEffect(id: "kung-fu", name: L("Kung Fu"), hint: L("A full-body photo of a person"), summary: L("A fast martial-arts routine in a misty courtyard."), category: .action,
                    input: .photo, symbol: "figure.martial.arts", model: kling, aspect: "9:16",
                    identityLine: "The person keeps the same face and hair.",
                    template: "In a misty bamboo courtyard, the person moves through a fast, fluid martial-arts form: a spinning kick, a palm strike and a low balanced stance, with dust and leaves swirling at each move. Slow motion on the kick, tracking camera."),

        VideoEffect(id: "moonwalk", name: L("Moonwalk"), hint: L("A full-body photo of a person"), summary: L("You glide backward in a smooth moonwalk."), category: .dance,
                    input: .photo, symbol: "figure.dance", model: kling, aspect: "9:16",
                    template: "The person glides smoothly backward across the floor in a moonwalk dance step, feet sliding heel to toe, then spins once and freezes on tiptoe with a grin. Full-body static camera, natural light."),
        VideoEffect(id: "finger-heart", name: L("Finger Heart"), hint: L("A close portrait of a person"), summary: L("A finger heart, a wink and a big arm heart."), category: .dance,
                    input: .photo, symbol: "heart.fill", model: grokLite, aspect: "9:16",
                    template: "The person smiles at the camera, crosses their thumb and index finger into a small finger heart beside their cheek, tilts their head and winks, then raises both arms to make a big heart over their head. Bright, cheerful idol-style mood, static medium close-up."),
        VideoEffect(id: "peace-sign", name: L("Peace Sign"), hint: L("A close portrait of a person"), summary: L("A playful V sign and a bouncy pose."), category: .dance,
                    input: .photo, symbol: "hand.raised.fingers.spread.fill", model: grokLite, aspect: "9:16",
                    template: "The person leans toward the camera with a bright smile, flashes a V sign beside one eye, puffs their cheeks playfully, then switches to a double V sign and bounces a little. Bright and cute, static close-up."),
        VideoEffect(id: "ending-pose", name: L("Ending Pose"), hint: L("A close portrait of a person"), summary: L("The final stage close-up after a performance."), category: .dance,
                    input: .photo, symbol: "sparkles", model: kling, aspect: "9:16",
                    template: "End-of-performance stage close-up: the person, a little out of breath with a touch of glitter on their cheeks, holds a final pose and a confident gaze into the camera, then breaks into a shy smile as colored stage lights shimmer behind them. Slow push-in."),
        VideoEffect(id: "anime-dance", name: L("Anime Dance"), hint: L("A full-body photo of a person"), summary: L("A short, upbeat anime-style dance."), category: .dance,
                    input: .photo, symbol: "figure.socialdance", model: kling, aspect: "9:16",
                    template: "The person performs a short, upbeat anime-style dance: a hop, a wave of both arms, a quick spin and a final pose with one hand on the hip and a peace sign, energetic and on the beat. Full-body static camera, bright light."),

        VideoEffect(id: "vampire", name: L("Vampire"), hint: L("A close portrait of a person"), summary: L("Pale skin, red eyes and fangs by candlelight."), category: .horror,
                    input: .photo, symbol: "moon.fill", model: kling, aspect: "9:16",
                    identityLine: "The person keeps the same face shape, hair and clothing.",
                    template: "The person's skin pales, their eyes turn deep red and two sharp fangs slide out as they slowly smile at the camera; candlelight flickers and their shadow on the wall moves a moment too late. Gothic mood, slow push-in."),
        VideoEffect(id: "witch", name: L("Witch"), hint: L("A photo of a person"), summary: L("Smoke turns you into a witch in a dark forest."), category: .horror,
                    input: .photo, symbol: "wand.and.rays", model: kling, aspect: "9:16",
                    identityLine: "The person keeps the same face.",
                    template: "Dark smoke curls around the person and their clothes become a long black cloak and a tall pointed hat; their eyes glow green and small floating candles light up around them in a misty dark forest. Slow arc, eerie moonlight."),
        VideoEffect(id: "zombie", name: L("Zombie"), hint: L("A photo of a person"), summary: L("You turn into a staggering movie zombie."), category: .horror,
                    input: .photo, symbol: "figure.walk.motion.trianglebadge.exclamationmark", model: kling, aspect: "9:16",
                    identityLine: "The person stays recognizable.",
                    template: "The person's skin turns gray and cracked, their eyes cloud over pale and their clothes become dusty and worn but stay fully on, covering the body; they tilt their head and stagger toward the camera with a slow, jerky zombie walk down a foggy street at night. Movie-makeup look, not gory."),
        VideoEffect(id: "zombie-dance", name: L("Zombie Dance"), hint: L("A full-body photo of a person"), summary: L("You lead a crowd of zombies in a spooky dance."), category: .horror,
                    input: .photo, symbol: "figure.dance", model: kling, aspect: "9:16",
                    template: "The person leads a crowd of costumed zombies behind them in a perfectly synchronized spooky dance: shoulder shrugs, claw hands and a slow sideways shuffle under a full moon, fog rolling at their feet. Fun and theatrical, not gory. Wide static camera."),
        VideoEffect(id: "black-tears", name: L("Black Tears"), hint: L("A close portrait of a person"), summary: L("Black tears run down as the light flickers."), category: .horror,
                    input: .photo, symbol: "eye.trianglebadge.exclamationmark", model: kling, aspect: "9:16",
                    template: "The person stares into the camera without blinking as slow black tears run down their cheeks; the light dims and flickers, and their reflection in a mirror behind them smiles a moment before they do. Unsettling but not gory, static close-up."),
        VideoEffect(id: "mummy", name: L("Mummy"), hint: L("A photo of a person"), summary: L("Bandages wrap you up in an ancient tomb."), category: .horror,
                    input: .photo, symbol: "bandage.fill", model: kling, aspect: "9:16", identityLine: "",
                    template: "Old linen bandages wind themselves around the person from the feet up, dust puffing from every layer, until only their eyes show through a gap; the mummy then raises its arms and steps forward in an ancient stone tomb lit by flickering torches."),

        VideoEffect(id: "bullet-time-product", name: L("Bullet Time Product"), hint: L("A product photo; the effect's image is made first"), summary: L("Frozen action around your product, then time resumes."), category: .apps,
                    input: .product, symbol: "timer", model: seedanceFast, quickStyleID: "bullet-time",
                    template: "Bullet time: the product hangs frozen mid-air among the suspended particles and debris while the camera glides in a smooth half orbit around it; at the end, time resumes and the particles burst outward in slow motion. Dramatic commercial lighting. The product stays exact."),
        VideoEffect(id: "chameleon-reveal", name: L("Chameleon Reveal"), hint: L("A product photo; the effect's image is made first"), summary: L("Your product blends in, then stands out."), category: .apps,
                    input: .product, symbol: "lizard", model: seedanceFast, quickStyleID: "chameleon",
                    template: "The camera drifts slowly across the camouflage scene where the product almost disappears into matching colors and patterns; a soft light sweep passes over it and its edges catch a bright highlight, so it stands out from the background. Slow push-in. The product stays exact."),
        VideoEffect(id: "tiny-world", name: L("Tiny World"), hint: L("A product photo; the effect's image is made first"), summary: L("Tiny people and vehicles bustle around your product."), category: .apps,
                    input: .product, symbol: "leaf", model: seedanceFast, quickStyleID: "macro-scene",
                    template: "Tilt-shift miniature world: tiny people stroll past and point up at the product, little vehicles drive by its base and the moss and tiny trees sway gently. Slow sideways slide of the camera, shallow depth of field. The product stays exact."),
        VideoEffect(id: "giant-product-rise", name: L("Giant Product Rise"), hint: L("A product photo; the effect's image is made first"), summary: L("The camera rises up your giant product over the city."), category: .apps,
                    input: .product, symbol: "building.2", model: seedanceFast, quickStyleID: "giant-product",
                    template: "The camera starts at street level among people looking up and cranes slowly upward along the colossal product towering over the skyline, birds circling it and golden-hour light glinting off its surface. Epic slow move, realistic scale. The product stays exact."),
        VideoEffect(id: "truck-drive-by", name: L("Truck Drive-By"), hint: L("A product photo; the effect's image is made first"), summary: L("The ad truck drives past through the city."), category: .apps,
                    input: .product, symbol: "truck.box", model: seedanceFast, quickStyleID: "truck-ad",
                    template: "The white box truck with the product ad on its side drives along the city street from left to right while the camera pans to follow it, the background streaked with motion blur and pedestrians turning to look. Afternoon daylight. The ad on the truck stays sharp and unchanged."),
        VideoEffect(id: "graffiti-spray", name: L("Graffiti Spray"), hint: L("A product photo; the effect's image is made first"), summary: L("A painter adds the last touch to your product mural."), category: .apps,
                    input: .product, symbol: "paintbrush", model: seedanceFast, quickStyleID: "graffiti-ad",
                    template: "The camera slowly pulls back from the mural on the brick wall as a painter with a spray can steps in, adds a final puff of fine mist at the edge and walks away; passersby slow down to look. Sunny day. The mural of the product stays unchanged."),
        VideoEffect(id: "fridge-chill", name: L("Fridge Chill"), hint: L("A product photo; the effect's image is made first"), summary: L("Cold mist rolls around your product in the fridge."), category: .apps,
                    input: .product, symbol: "refrigerator", model: seedanceFast, quickStyleID: "fridge-ad",
                    template: "Cool light glows inside the open refrigerator as cold mist rolls out over the shelves, condensation droplets slide down the product and the camera pushes in slowly toward it. Fresh, appetizing commercial look. The product stays exact."),
        VideoEffect(id: "volcano-eruption", name: L("Volcano Eruption"), hint: L("A product photo; the effect's image is made first"), summary: L("The volcano erupts around your product."), category: .apps,
                    input: .product, symbol: "mountain.2", model: seedanceFast, quickStyleID: "volcano-ad",
                    template: "The volcano roars to life: glowing lava fountains up around the product, sparks and ash fly past the camera and the product rises out of the eruption, lit orange from below. Epic slow push-in with a slight rumbling shake. The product stays exact."),
        VideoEffect(id: "tactical-intro", name: L("Tactical Shooter Intro"), hint: L("A photo of a person; the effect's image is made first"), summary: L("Your operator gets ready on the character screen."), category: .apps,
                    input: .photo, symbol: "scope", model: grokLite, quickStyleID: "nano-strike",
                    identityLine: "The character keeps the same look throughout.",
                    template: "Character-select screen animation: the operator shifts their weight, checks the rifle, lowers the helmet visor and looks into the camera, while the teal light strip pulses and the stat bars fill one by one. Game-engine 3D look throughout; the menu stays unchanged."),
        VideoEffect(id: "open-world-scene", name: L("Open World Scene"), hint: L("A photo of a person; the effect's image is made first"), summary: L("Your loading-screen art moves like a living poster."), category: .apps,
                    input: .photo, symbol: "car", model: grokLite, quickStyleID: "nano-theft",
                    identityLine: "The character keeps the same look throughout.",
                    template: "The loading-screen artwork comes alive: palm trees sway, the sunset sky shifts color, city lights flicker on along the skyline and the character turns their head and smirks. Thick ink outlines and cel-shaded flat colors throughout, never photorealistic."),
        VideoEffect(id: "plushie-alive", name: L("Plushie Comes Alive"), hint: L("A photo of a person or pet; the effect's image is made first"), summary: L("Your plush toy wiggles and waves on the bed."), category: .apps,
                    input: .image, symbol: "teddybear", model: seedanceFast, quickStyleID: "plushies",
                    template: "The plush toy comes to life on the bed: it wiggles, tilts its head, waves a soft paw and gives a little hop, its fabric squishing naturally with each move. Cozy light, slow push-in. It stays a stitched plush toy throughout."),
        VideoEffect(id: "figure-turn", name: L("Collectible Figure Turn"), hint: L("A photo of a person; the effect's image is made first"), summary: L("The camera circles your collectible figure on the desk."), category: .apps,
                    input: .photo, symbol: "figure.stand", model: kling, quickStyleID: "3d-figure",
                    identityLine: "The figure keeps the same look throughout.",
                    template: "The camera slowly arcs around the collectible figure on the desk, light glinting off its glossy painted plastic and the clear acrylic base, while the computer screen behind it keeps showing the 3D model turning. Product-photography lighting. The figure stays a still, rigid toy."),
        VideoEffect(id: "pixel-run", name: L("Pixel Game Run"), hint: L("A photo of a person; the effect's image is made first"), summary: L("Your pixel character runs and jumps through the level."), category: .apps,
                    input: .photo, symbol: "square.grid.4x3.fill", model: seedanceFast, quickStyleID: "pixel-game",
                    identityLine: "The character keeps the same look throughout.",
                    template: "The 16-bit game scene plays: the pixel character runs to the right, jumps onto a platform and grabs a spinning coin while the background scrolls in layers. Chunky pixels and a limited palette throughout, choppy retro animation, never smooth 3D."),
        VideoEffect(id: "brick-walk", name: L("Brick Figure Walk"), hint: L("A photo of a person; the effect's image is made first"), summary: L("Your brick minifigure walks in stop motion."), category: .apps,
                    input: .photo, symbol: "square.stack.3d.up", model: seedanceFast, quickStyleID: "brick-cube",
                    identityLine: "The minifigure keeps the same look throughout.",
                    template: "Stop-motion toy animation: the brick minifigure waddles forward in small choppy steps, swings its arms, turns its head toward the camera and waves, while a tiny brick car rolls past in the diorama. Macro toy photography, glossy plastic highlights."),
        VideoEffect(id: "gloss-walk", name: L("High Gloss Walk"), hint: L("A photo of a person; the effect's image is made first"), summary: L("A slow fashion walk in your glossy coat."), category: .apps,
                    input: .photo, symbol: "drop", model: kling, quickStyleID: "latex",
                    template: "High-fashion film: the person takes a slow step toward the camera and turns, the glossy black coat catching sharp moving highlights along its folds, then they stop and hold a fierce pose. Sculptural studio light, dark backdrop, slow motion."),
        VideoEffect(id: "sixties-cafe", name: L("'60s Café Scene"), hint: L("A photo of a person; the effect's image is made first"), summary: L("A sip of coffee in a 1960s diner."), category: .apps,
                    input: .photo, symbol: "cup.and.saucer", model: kling, quickStyleID: "60s-cafe",
                    template: "1960s film footage: the person stirs their coffee, takes a sip and laughs at someone off camera, while a jukebox glows and a waitress passes in the background. Kodachrome colors, soft film grain, gentle handheld camera."),
        VideoEffect(id: "card-flip", name: L("Poker Card Flip"), hint: L("A photo of a person; the effect's image is made first"), summary: L("Your playing card turns over on the poker table."), category: .apps,
                    input: .photo, symbol: "suit.spade", model: seedanceFast, quickStyleID: "victory-card", identityLine: "",
                    template: "On the poker table, the hand holding the card turns it slowly toward the camera so the gold foil catches the light, then lays it down on the felt beside a stack of chips. Warm casino light, shallow depth of field. The card's illustrated face stays unchanged."),
        VideoEffect(id: "mascot-wave", name: L("Mascot Wave"), hint: L("A photo of a person; the effect's image is made first"), summary: L("Your cartoon mascot waves and bounces."), category: .apps,
                    input: .photo, symbol: "star.circle", model: seedanceFast, quickStyleID: "mascot",
                    identityLine: "The mascot keeps the same look throughout.",
                    template: "The cartoon mascot comes alive on the pastel-yellow background: it bounces on its feet, waves with a big friendly smile, gives a thumbs up and hops once. Smooth, glossy toy-like 3D animation, bright even light."),
        VideoEffect(id: "sunset-wind", name: L("Burning Sunset Wind"), hint: L("A photo of a person; the effect's image is made first"), summary: L("The fiery sky moves as the wind lifts your hair."), category: .apps,
                    input: .photo, symbol: "sun.horizon", model: kling, quickStyleID: "burning-sunset",
                    template: "The fiery orange-red sky behind the person churns slowly as the sun sinks, heat haze shimmers and a warm wind lifts their hair; they turn their face toward the light and close their eyes. Slow push-in, golden rim light."),
        VideoEffect(id: "this-is-fine-motion", name: L("This Is Fine Motion"), hint: L("A photo of a person; the effect's image is made first"), summary: L("You sip coffee calmly while the room burns."), category: .apps,
                    input: .photo, symbol: "flame", model: seedanceFast, quickStyleID: "on-fire",
                    identityLine: "The character keeps the same look throughout.",
                    template: "Animated comic panel: the character calmly lifts the mug and takes a sip while cartoon flames flicker up the walls and smoke curls along the ceiling, then sets the mug down and smiles. 2D comic style throughout; the speech bubble stays unchanged."),
        VideoEffect(id: "cloud-surf-ride", name: L("Cloud Surf Ride"), hint: L("A photo of a person; the effect's image is made first"), summary: L("You surf a sea of clouds at sunrise."), category: .apps,
                    input: .photo, symbol: "cloud", model: kling, quickStyleID: "cloud-surf",
                    template: "The person surfs the sea of clouds at sunrise, carving a wide turn so cloud spray streams off the board, arms out for balance and hair blowing, while the camera flies alongside. Surreal but photorealistic light."),
        VideoEffect(id: "mukbang-bite", name: L("Mukbang Bite"), hint: L("A photo of a person; the effect's image is made first"), summary: L("A big, happy bite on a food livestream."), category: .apps,
                    input: .photo, symbol: "fork.knife", model: kling, quickStyleID: "mukbang",
                    template: "Food livestream: the person lifts a big bite of noodles with the chopsticks, blows on it, eats with obvious delight and gives the camera a happy thumbs up while steam rises from the dishes. Bright front light, static camera."),
        VideoEffect(id: "dripping-doodles", name: L("Dripping Doodles"), hint: L("Any photo; the effect's image is made first"), summary: L("The neon doodles wiggle and drip over your photo."), category: .apps,
                    input: .image, symbol: "scribble.variable", model: kling, quickStyleID: "melting-doodle",
                    template: "The neon doodles over the photo come alive: they wiggle, bounce and slowly melt, glowing drips sliding down and small new doodle sparkles popping up, while the photo underneath stays still and unchanged."),
        VideoEffect(id: "living-renaissance", name: L("Living Renaissance"), hint: L("A photo of a person; the effect's image is made first"), summary: L("Your Renaissance portrait comes alive in the gallery."), category: .apps,
                    input: .photo, symbol: "building.columns", model: seedanceFast, quickStyleID: "renaissance",
                    identityLine: "The painted figure keeps the same look throughout.",
                    template: "In the museum gallery, the painted figure inside the gold frame blinks, turns slightly and smiles, the oil-paint brushstrokes and canvas texture staying exactly the same, while a visitor walks slowly past in front of the painting. Slow push-in."),
        VideoEffect(id: "micro-beasts-play", name: L("Micro Beasts Play"), hint: L("A photo of a person; the effect's image is made first"), summary: L("The tiny animals around you come to life."), category: .apps,
                    input: .photo, symbol: "hare", model: kling, quickStyleID: "micro-beasts",
                    template: "The tiny animals around the person come to life: the kitten on their shoulder nuzzles their cheek, the bunny wiggles its nose from the pocket and the ducklings waddle around their feet as the person laughs. Photorealistic, soft daylight, slight handheld."),
    ]
}
