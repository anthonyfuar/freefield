import FreefieldCore
import SwiftUI

struct AppSlot: Hashable {
    let label: String
    let hint: String
    let symbol: String

    static let photo = AppSlot(label: L("Your photo"), hint: L("A clear photo of the person"), symbol: "person.crop.square")
    static let product = AppSlot(label: L("Your product"), hint: L("Best with a clean background"), symbol: "shippingbox")
    static let image = AppSlot(label: L("Image"), hint: L("Any image"), symbol: "photo")
    static let garment = AppSlot(label: L("Garment"), hint: L("Photo of the garment"), symbol: "tshirt")
}

struct AppItem: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let category: String
    let symbol: String
    var badge: String?
    var slots: [AppSlot] = [.photo]
    var options: [String] = []
    var optionTitle: String?
    var textTitle: String?
    var textPlaceholder: String?
    var aspect: AspectRatio = .auto
    var resolution: Resolution = .oneK
    var model: String?
    var stylized = false
    var splitsIntoCells = false
    var template: String = ""

    var textIsLiteral: Bool { template.contains("\"{text}\"") }

    var takesExtraInstructions: Bool { template.contains("{text}") }

    static let extraInstructionLimit = 300

    func prompt(option: String?, text: String, extra: String = "") -> String {
        let legend = Self.legend(slots)
        let body = text.isEmpty ? template.replacingOccurrences(of: "\"{text}\"", with: "a short line written to fit the image") : template
        var result = (legend.isEmpty ? "" : legend + "\n") + body
            .replacingOccurrences(of: "{option}", with: option ?? "")
            .replacingOccurrences(of: "{text}", with: text)
            .replacingOccurrences(of: "  ", with: " ")
        if !text.isEmpty, !template.contains("{text}") { result += "\nAlso: \(text)" }
        if !extra.isEmpty, takesExtraInstructions { result += "\nAlso: \(extra)" }
        if let index = slots.firstIndex(of: .photo) {
            result += "\nKeep the person from Image \(index + 1) " + (stylized
                ? "recognizable in the new style: same face shape, features, skin tone, hairstyle and hair color."
                : "unmistakably the same person: identical face, facial structure, eye shape and skin tone.")
        }
        if let index = slots.firstIndex(of: .product) {
            result += "\nUse this exact product from Image \(index + 1): identical shape, proportions, label text, logo and colors."
        }
        if !stylized {
            result += slots.contains(.photo) || slots.contains(.garment) ? Self.realPeople : Self.realScene
        }
        return result + Self.noMarks
    }

    var promptOverhead: Int {
        let longest = (options.isEmpty ? [nil] : options.map(Optional.some)).map { prompt(option: $0, text: "").utf16.count }.max() ?? 0
        return longest + (template.contains("{text}") ? 0 : "\nAlso: ".utf16.count)
    }

    func textLimit(model: ImageModel?) -> Int {
        let reserved = takesExtraInstructions ? "\nAlso: ".utf16.count + Self.extraInstructionLimit : 0
        return PromptBudget.userLimit(model: model, overhead: promptOverhead + reserved)
    }

    func extraLimit(model: ImageModel?) -> Int {
        min(Self.extraInstructionLimit, PromptBudget.userLimit(model: model, overhead: promptOverhead + "\nAlso: ".utf16.count))
    }

    static func legend(_ slots: [AppSlot]) -> String {
        slots.enumerated().map { index, slot in
            let role = slot == .photo ? "a photo of the person" : slot == .product ? "the product" : slot == .garment ? "the garment" : "the source image"
            return "Image \(index + 1) is \(role)."
        }.joined(separator: " ")
    }

    static let realPeople = "\nPhotorealistic, like a real photograph: real skin texture with visible pores, natural color balance, believable light and shadows, natural depth of field, subtle grain. Natural hands and anatomy, no plastic smoothing."
    static let noMarks = "\nNo watermarks, signatures, or brand names and logos beyond those in the input."
    static let realScene = "\nPhotorealistic, like a real photograph: true-to-life materials and color, believable light, shadows and reflections, natural lens optics, crisp undistorted shapes and lettering."
}

enum AppCatalog {
    static let allCategory = L("All")
    static let categories = [L("Professional"), L("Enhance & Style"), L("Face & Identity"), L("Ads & Products"), L("Games & Characters"), L("Extras"), L("Trending")]
    static var categoryNames: [String] { [allCategory] + categories }

    static func item(_ id: String) -> AppItem? { all.first { $0.id == id } }

    static func filtered(category: String, search: String) -> [AppItem] {
        var list = category == allCategory ? all : all.filter { $0.category == category }
        if !search.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.subtitle.localizedCaseInsensitiveContains(search) }
        }
        return list
    }

    private static let pro = L("Professional"), style = L("Enhance & Style"), face = L("Face & Identity")
    private static let ads = L("Ads & Products"), games = L("Games & Characters"), extras = L("Extras"), trend = L("Trending")

    static let all: [AppItem] = [
        AppItem(id: "shots", name: L("9 Shots"), subtitle: L("Upload an image and get 9 different cinematic shots."),
                category: pro, symbol: "rectangle.split.3x3", slots: [.image], aspect: .square,
                model: "nano-banana-2", splitsIntoCells: true,
                template: "Create a 3×3 contact sheet of nine distinct cinematic shots of this exact scene and subject: wide establishing shot, medium shot, medium close-up, close-up, extreme close-up detail, over-the-shoulder, low angle, high angle and profile. Keep identity, wardrobe, setting, lighting and color grade identical across panels. Thin white gutters between panels, no text."),
        AppItem(id: "zooms", name: L("9 Zooms"), subtitle: L("9 zoom levels of the same image, from wide shot to macro."),
                category: pro, symbol: "plus.magnifyingglass", slots: [.image], aspect: .square,
                model: "seedream-4.5", splitsIntoCells: true,
                template: "Create a 3×3 grid of nine frames zooming progressively into this image: from an ultra-wide view revealing much more of the surroundings, through the original framing, down to an extreme macro of the central subject's details. Same scene, lighting and style in every frame. Thin white gutters, no text."),
        AppItem(id: "contact-sheet", name: L("Contact Sheet"),
                subtitle: L("4, 9 or 16 variations in one image. Click the one you like to keep it at full size."),
                category: pro, symbol: "square.grid.3x3.square", badge: L("NEW"), slots: [.image],
                options: ["2×2", "3×3", "4×4"], optionTitle: L("Grid size"),
                textTitle: L("What should change (optional)"), textPlaceholder: L("E.g. different facial expressions, all close-ups"),
                aspect: .square, resolution: .twoK, model: "nano-banana-2", splitsIntoCells: true,
                template: "Create a {option} contact sheet: one image split into an evenly spaced {option} grid of equal square panels, each panel a distinct variation of this exact subject: a different pose, camera angle, framing or moment in every panel. Keep the subject's identity, wardrobe, setting, lighting and style consistent across all panels. Panels edge to edge, separated only by thin straight white gutters of equal width, no outer border, no text, no numbers."),
        AppItem(id: "whats-next", name: L("What's Next?"), subtitle: L("8 story possibilities from a single scene."),
                category: pro, symbol: "arrow.triangle.branch", badge: L("NEW"), slots: [.image], aspect: .landscape16x9,
                model: "gpt-image-2.5-flare",
                template: "Create a 2×4 storyboard grid of eight different plausible next moments that could happen right after this scene, each one a different story direction. Keep the same characters, wardrobe, location and cinematic style. Thin white gutters, small panel numbers 1–8."),

        AppItem(id: "ai-stylist", name: L("AI Stylist"), subtitle: L("Change your whole outfit to another style, keeping your pose and background."),
                category: style, symbol: "hanger", badge: L("NEW"),
                options: ["Casual chic", "Streetwear", "Business", "Old money", "Y2K", "Boho", "Techwear", "Evening gala", "Sporty", "Minimalist"],
                optionTitle: L("Style"), textTitle: L("Specific garments (optional)"), textPlaceholder: L("E.g. leather jacket and white boots"),
                model: "seedream-4.5",
                template: "Restyle the person's complete outfit into a {option} look, head to toe, with realistic fabrics and fit. Keep their face, body, pose, hair and the background unchanged."),
        AppItem(id: "skin-enhancer", name: L("Skin Enhancer"), subtitle: L("Natural, realistic skin texture with no plastic look."),
                category: style, symbol: "face.smiling", options: ["Natural", "Soft retouch", "Editorial glow"], optionTitle: L("Mode"),
                model: "gpt-image-2.5-sunburst",
                template: "Retouch the skin in a {option} way: even out blemishes and redness while keeping real pores, fine texture and natural skin tone. Keep the facial features, makeup, hair and lighting exactly as they are."),
        AppItem(id: "style-snap", name: L("Instant Outfit"), subtitle: L("Pick an outfit style; the pose and background stay the same."),
                category: style, symbol: "camera.shutter.button",
                options: ["Cyberpunk", "Cowboy", "Festival", "Gothic", "Safari", "Princess", "Astronaut", "Rock star", "Preppy", "'90s hip-hop"],
                optionTitle: L("Outfit"),
                model: "seedream-5-pro",
                template: "Dress the person in a complete {option} outfit with accessories, realistic and stylish. Keep the same pose, face, hair and background."),
        AppItem(id: "outfit-vending", name: L("Outfit Vending Machine"), subtitle: L("Your outfit broken down in a lit-up vending machine."),
                category: style, symbol: "square.grid.3x3.topleft.filled", aspect: .portrait3x4,
                model: "gpt-image-2.5-flare",
                template: "Show the person standing next to an illuminated vending machine whose glass slots display each individual item of their current outfit (top, bottoms, shoes, bag, accessories) as separate products with small price tags. Night street, neon glow, photorealistic."),
        AppItem(id: "glitter-sticker", name: L("Glitter Sticker"), subtitle: L("A sparkly sticker version of you."),
                category: style, symbol: "seal", aspect: .square,
                model: "grok-imagine-2", stylized: true,
                template: "Turn the person into a die-cut vinyl sticker covered in sparkling holographic glitter, thick white sticker border, slight drop shadow, on a plain light background."),
        AppItem(id: "outfit-shot", name: L("Outfit Shot"), subtitle: L("Turn a garment into a professional photo shoot."),
                category: style, symbol: "camera", slots: [.garment],
                textTitle: L("Model (optional)"), textPlaceholder: L("E.g. 25-year-old woman, short hair"), aspect: .portrait3x4,
                model: "seedream-4.5",
                template: "Create a professional fashion e-commerce photoshoot of a model wearing exactly this garment. {text} Studio lighting, clean backdrop, natural confident pose, the garment's design, color, pattern and logos reproduced faithfully."),

        AppItem(id: "headshot", name: L("Professional Headshot"), subtitle: L("Turn a selfie into a studio photo for LinkedIn."),
                category: face, symbol: "person.crop.rectangle", options: ["Studio gray", "Blurred office", "Plain white", "Urban outdoors", "Library"],
                optionTitle: L("Background"), aspect: .portrait4x5,
                model: "flux-2-pro",
                template: "Create a professional corporate headshot of this person: head and shoulders, business attire, confident friendly expression, flattering softbox lighting, {option} background, sharp focus on the eyes."),
        AppItem(id: "commercial-faces", name: L("Commercial Faces"), subtitle: L("Transform the portrait for a professional ad."),
                category: face, symbol: "megaphone",
                options: ["Skincare", "Fitness", "Technology", "Banking or insurance", "Food", "Fashion", "Travel"], optionTitle: L("Industry"),
                model: "seedream-5-pro",
                template: "Transform this portrait into a polished commercial photograph for a {option} advertising campaign: art-directed wardrobe and set, bright, flattering commercial lighting, authentic smile, clean composition with empty negative space where copy could go later. Do not render any text, letters or logos."),

        AppItem(id: "poster", name: L("Poster"), subtitle: L("Your product on a boldly designed poster."),
                category: ads, symbol: "doc.richtext", slots: [.product],
                textTitle: L("Poster text (optional)"), textPlaceholder: L("E.g. NEW · Mango flavor"), aspect: .portrait2x3,
                model: "gpt-image-2.5-sunburst", stylized: true,
                template: "Design a bold graphic advertising poster featuring this product as the hero, striking typography and layout, vibrant complementary colors. Headline text: \"{text}\"."),
        AppItem(id: "packshot", name: L("Packshot"), subtitle: L("A polished studio end frame."),
                category: ads, symbol: "cube.box", slots: [.product], aspect: .square,
                model: "flux-2-pro",
                template: "Create a studio packshot photo of the product from Image 1, centered and filling about 60% of the frame, seen slightly above eye level. Seamless light-gray backdrop fading to white, a large softbox from camera-left and a white bounce card on the right, crisp edge highlights, a soft contact shadow and a faint reflection on the glossy surface beneath."),
        AppItem(id: "bullet-time", name: L("Bullet Time"), subtitle: L("Your product frozen mid-air in the middle of the action."),
                category: ads, symbol: "timer", slots: [.product],
                options: ["Urban scene", "White background", "Liquid splash"], optionTitle: L("Variant"), aspect: .landscape16x9,
                model: "seedream-4.5",
                template: "Bullet-time frozen moment: the product floats mid-air in dynamic motion with debris, particles and motion trails frozen around it, {option}, dramatic commercial lighting."),
        AppItem(id: "chameleon", name: L("Chameleon"), subtitle: L("The product blends into a setting of its own color."),
                category: ads, symbol: "lizard", slots: [.product], aspect: .portrait4x5,
                model: "seedream-5-pro",
                template: "Create a camouflage ad: the product sits in an environment whose colors, patterns and textures exactly match the product's own design, so it almost blends in, artistic and eye-catching."),
        AppItem(id: "macro-scene", name: L("Macro Scene"), subtitle: L("Your product in a miniature world."),
                category: ads, symbol: "leaf", slots: [.product], aspect: .landscape4x3,
                model: "flux-3",
                template: "Macro photograph of the product in a tiny miniature world built around it (moss, tiny people, little vehicles), tilt-shift depth of field, whimsical and detailed."),
        AppItem(id: "macroshot", name: L("Product Macro"), subtitle: L("Extreme close-up details of texture and materials."),
                category: ads, symbol: "camera.macro", slots: [.product], aspect: .square,
                model: "flux-2-pro",
                template: "Extreme macro shot of the product's finest details: materials, texture, droplets, edges, shallow depth of field, soft raking light."),
        AppItem(id: "magic-button", name: L("Magic Button"), subtitle: L("A magical, whimsical scene around the product."),
                category: ads, symbol: "button.programmable", slots: [.product], aspect: .portrait4x5,
                model: "seedream-5-pro",
                template: "Design a whimsical fantasy advertising image: the product from Image 1 stands on a mossy stone in an enchanted forest at dusk, label facing the camera, surrounded by drifting golden sparkles. Soft beams of light fall through the trees behind it, with deep teal and violet shadows and a warm glow outlining the product, which stays sharp and fully legible."),
        AppItem(id: "giant-product", name: L("Giant Product"), subtitle: L("Your product as a giant on the city skyline."),
                category: ads, symbol: "building.2", slots: [.product], aspect: .landscape16x9,
                model: "seedream-4.5",
                template: "The product appears as a colossal giant towering over a real city skyline, people on the street looking up, photorealistic CGI ad, golden hour."),
        AppItem(id: "billboard", name: L("Billboard"), subtitle: L("Your ad on a billboard in the middle of the city."),
                category: ads, symbol: "rectangle.on.rectangle", slots: [.product], aspect: .landscape16x9,
                model: "gpt-image-2.5-flare",
                template: "Generate a street photograph at dusk of a busy city square under a huge illuminated billboard. The billboard shows a clean ad: the product from Image 1 large and centered on a solid background in the product's main color, with no slogan or copy. Crowds and car light trails below, warm shop lights, deep blue sky; wide shot at eye level from across the square."),
        AppItem(id: "truck-ad", name: L("Truck Ad"), subtitle: L("Your product on the side of a truck driving through the city."),
                category: ads, symbol: "truck.box", slots: [.product], aspect: .landscape16x9,
                model: "seedream-4.5",
                template: "Generate a street photograph of a white box truck driving down a city street, seen side-on at eye level. Its side panel carries a full wrap ad: the product from Image 1, large and centered on a solid background in the product's main color, with no slogan or copy. Panning shot: the truck sharp, the background streaked with motion blur, soft afternoon daylight."),
        AppItem(id: "graffiti-ad", name: L("Graffiti Ad"), subtitle: L("Your product painted as a street mural."),
                category: ads, symbol: "paintbrush", slots: [.product], aspect: .landscape4x3,
                model: "grok-imagine-2",
                template: "Create a photo of a huge spray-painted graffiti mural of the product from Image 1 covering a brick wall on a sunny city street. The mural copies the product's shape, colors and label design with bold outlines, drips and soft overspray, seen straight on at eye level. An aluminum ladder and three spray cans stand at the wall's base. Hard midday sun from the upper left, bright readable exposure. The mural uses the product's own colors; the bricks are warm red and the sidewalk pale gray. Wide shot, the whole mural sharp."),
        AppItem(id: "fridge-ad", name: L("Fridge Ad"), subtitle: L("The star of the show inside a lit-up fridge."),
                category: ads, symbol: "refrigerator", slots: [.product], aspect: .portrait3x4,
                model: "seedream-4.5",
                template: "Open refrigerator glowing with cool light, the product placed as the hero on the middle shelf among fresh ingredients, condensation, appetizing commercial shot."),
        AppItem(id: "volcano-ad", name: L("Volcano Ad"), subtitle: L("Your product bursting out of an epic volcano."),
                category: ads, symbol: "mountain.2", slots: [.product], aspect: .landscape16x9,
                model: "flux-3",
                template: "Wide scene of the product bursting out of an erupting volcano, glowing lava and sparks flying around it, an ash-dark sky lit orange from below, composed like an action movie poster."),

        AppItem(id: "game-dump", name: L("Video Games"), subtitle: L("You in 12 iconic video game styles."),
                category: games, symbol: "gamecontroller",
                options: ["Open-world crime", "Life simulator", "Voxel blocks", "Fantasy adventure", "Collectible monsters",
                          "Arcade fighting", "Battle royale", "Animal village", "Tactical shooter", "Kart racing", "JRPG", "16-bit pixel"],
                optionTitle: L("Game style"), aspect: .portrait3x4,
                model: "nano-banana-2", stylized: true,
                template: "Turn the whole image into a screenshot from a {option} video game: re-render the person as a stylized game character and the setting as game graphics in that genre's signature art style (not a photograph), with the HUD and UI elements typical of the genre, while the character stays recognizable as the person."),
        AppItem(id: "nano-strike", name: L("Tactical Shooter"), subtitle: L("A tactical shooter character with your face."),
                category: games, symbol: "scope", aspect: .portrait3x4,
                model: "gpt-image-2.5-flare", stylized: true,
                template: "Render a tactical shooter video game character-select screen: the person from Image 1 as an operator in a three-quarter view, wearing a helmet with the visor raised, a plate carrier, gloves and a slung rifle, in game-engine 3D graphics. Dark steel-gray menu background with a teal light strip. On the right, four horizontal stat bars and the label \"OPERATOR\" in white capitals. No other text."),
        AppItem(id: "nano-theft", name: L("Open World"), subtitle: L("You as loading-screen art for an open-world game."),
                category: games, symbol: "car", aspect: .portrait3x4,
                model: "gpt-image-2", stylized: true,
                template: "Repaint the person as illustrated loading-screen artwork for an invented open-world crime video game (no real game titles, logos or city names) — not a photograph: thick black ink outlines, cel-shaded flat colors, comic-poster painting style, dramatic pose, saturated sunset palette, city skyline and palm trees behind."),
        AppItem(id: "simlife", name: L("Simlife"), subtitle: L("You inside a life simulator."),
                category: games, symbol: "house", aspect: .landscape4x3,
                model: "seedream-5-pro", stylized: true,
                template: "Render a life-simulation video game screenshot: the person from Image 1 as a stylized 3D game character standing in a cozy furnished living room, seen from a high isometric camera with the walls cut away. A small glowing blue ring floats above their head. Soft warm interior light, bright cheerful colors. In the bottom corner, a simple needs panel with six colored bars and no readable text."),
        AppItem(id: "plushies", name: L("Plushie"), subtitle: L("Turn a person or pet into a plush toy."),
                category: games, symbol: "teddybear", slots: [.image], aspect: .square,
                model: "nano-banana-2", stylized: true,
                template: "Transform the main subject into a stuffed plush toy version of itself: soft minky fabric instead of skin or fur, visible stitched seams, embroidered or button eyes, simplified rounded proportions, stuffing-filled shapes. It must clearly be a toy, not a real animal or person, sitting on a bed in cozy light."),
        AppItem(id: "3d-render", name: L("3D Render"), subtitle: L("A flawless 3D-rendered object."),
                category: games, symbol: "cube", slots: [.image], aspect: .square,
                model: "flux-3", stylized: true,
                template: "Re-create the main subject of Image 1 as a stylized 3D render: softly rounded, simplified forms in smooth matte clay-like materials, keeping its pose, colors and key features. Soft global illumination with a gentle key light from the upper left; centered on a plain light-gray studio backdrop with a soft floor shadow."),
        AppItem(id: "3d-figure", name: L("Collectible Figure"), subtitle: L("Your 3D figure on the desk, with its box."),
                category: games, symbol: "figure.stand", aspect: .portrait4x5,
                model: "nano-banana-pro", stylized: true,
                template: "Create a 1/7 scale commercialized collectible figure of the person on a computer desk, realistic PVC material, a clear acrylic round base, next to it the toy's printed packaging box with the figure's artwork, and the computer screen showing the 3D modeling process."),
        AppItem(id: "pixel-game", name: L("Pixel Game"), subtitle: L("You in 16-bit pixel art."),
                category: games, symbol: "square.grid.4x3.fill", aspect: .square,
                model: "gpt-image-2", stylized: true,
                template: "Recreate the image as authentic 16-bit video game sprite art: large chunky square pixels clearly visible, a limited 32-color palette, simplified shapes and flat shading like a classic console game scene. It must look drawn pixel by pixel, not a pixelated photo."),
        AppItem(id: "brick-cube", name: L("Bricks"), subtitle: L("You as a building-brick figure."),
                category: games, symbol: "square.stack.3d.up", aspect: .square,
                model: "seedream-5-pro", stylized: true,
                template: "Turn the person from Image 1 into a small plastic building-brick minifigure: a cylindrical head with their face printed in simple lines, a molded hair piece in their hairstyle and hair color, and a printed torso matching their outfit. The figure stands in a little diorama built from colorful interlocking bricks. Macro toy photography, glossy plastic highlights, shallow depth of field, soft daylight."),

        AppItem(id: "paint-app", name: L("Retro Paint"), subtitle: L("Art from a '90s paint program."),
                category: extras, symbol: "paintpalette", slots: [.image],
                model: "nano-banana-2", stylized: true,
                template: "Completely redraw the scene as a crude amateur drawing made with the mouse in a 1990s paint program: wobbly jagged outlines, flat bucket-fill colors with no shading, spray-can texture dots, limited 16-color palette, pixelated edges. It must look hand-drawn in the paint program, not like a photo, shown inside the program's window with its toolbar and color palette."),
        AppItem(id: "signboard", name: L("Mural"), subtitle: L("You painted on a giant mural or sign."),
                category: extras, symbol: "signpost.right", aspect: .landscape4x3,
                model: "seedream-4.5", stylized: true,
                template: "The person painted as a huge hand-painted mural on the side of a building, with painters' scaffolding, realistic street photo."),
        AppItem(id: "micro-beasts", name: L("Micro Beasts"), subtitle: L("Surround yourself with tiny, cute animals."),
                category: extras, symbol: "hare",
                model: "seedream-4.5",
                template: "Add six to ten tiny, palm-sized cute animals around the person — a kitten on one shoulder, a bunny peeking from a pocket, ducklings and a hamster at their feet — each clearly a separate real animal, photorealistic, joyful moment. Keep the person and their clothes unchanged."),
        AppItem(id: "meme", name: L("Meme Generator"), subtitle: L("Turn your photo into a meme with text."),
                category: extras, symbol: "face.smiling.inverse", slots: [.image],
                textTitle: L("Meme text"), textPlaceholder: L("E.g. When you say “just one more image”"),
                model: "gpt-image-2.5-flare",
                template: "Turn the image into a classic meme: bold white Impact-style caption with black outline that reads \"{text}\", funny framing, keep the image recognizable."),

        AppItem(id: "latex", name: L("High Gloss"), subtitle: L("A glossy patent-vinyl fashion editorial."),
                category: trend, symbol: "drop", aspect: .portrait4x5,
                model: "flux-2-pro",
                template: "High-fashion editorial portrait of the person wearing an elegant glossy black patent-vinyl trench coat, sculptural studio lighting with sharp specular highlights on the shiny fabric, dark backdrop, fashion-magazine look."),
        AppItem(id: "j-magazine", name: L("Japanese Cover"), subtitle: L("You on the cover of a Japanese magazine."),
                category: trend, symbol: "book", aspect: .portrait3x4,
                model: "gpt-image-2.5-sunburst",
                template: "Design a Japanese fashion magazine cover: the person from Image 1 in a bright, high-key waist-up studio photo, wearing a colorful street-style outfit and looking into the camera. The masthead \"KIRAMEKI\" runs across the top in large white sans-serif letters. Three short cover lines in bold Japanese type sit on the left, announcing spring arrivals, Tokyo street style and a collector's edition. A small barcode in the bottom-right corner. No other text."),
        AppItem(id: "j-poster", name: L("Japanese Poster"), subtitle: L("A classic Japanese movie poster."),
                category: trend, symbol: "film", aspect: .portrait2x3,
                model: "gpt-image-2", stylized: true,
                template: "Vintage Japanese movie poster starring the person, painted illustration style, vertical Japanese title text, bold graphic layout, credited to an invented film studio (no real company names or logos)."),
        AppItem(id: "roller-coaster", name: L("Roller Coaster"), subtitle: L("The theme park photo, mid-drop."),
                category: trend, symbol: "tram", aspect: .landscape4x3,
                model: "seedream-4.5",
                template: "Generate an on-ride theme park photo: the person from Image 1 screams with joy in the front row of a roller coaster car plunging down a steep drop, hair flying back and both arms raised, other riders screaming behind them. Captured by the ride's fixed camera just ahead of the car: bright on-ride flash on the faces, slight motion blur in the track and the blue summer sky."),
        AppItem(id: "60s-cafe", name: L("'60s Café"), subtitle: L("A photo in a 1960s café."),
                category: trend, symbol: "cup.and.saucer", aspect: .portrait4x5,
                model: "flux-2-pro",
                template: "1960s photograph of the person in a retro diner café, period outfit and hairstyle, Kodachrome colors, film grain."),
        AppItem(id: "victory-card", name: L("Poker Card"), subtitle: L("You as the winning card."),
                category: trend, symbol: "suit.spade", aspect: .portrait2x3,
                model: "seedream-5-pro", stylized: true,
                template: "The person illustrated as the king/queen face of an ornate playing card, symmetric mirrored design, gold foil details, card held on a poker table."),
        AppItem(id: "sand-worm", name: L("Sandworm"), subtitle: L("A colossal worm bursts out of the desert behind you."),
                category: trend, symbol: "tornado", aspect: .landscape16x9,
                model: "seedream-5-lite",
                template: "Wide desert scene: a colossal sandworm erupting from the dunes behind the person and towering far above them, sand cascading from its body, hazy golden light, like a sci-fi film still."),
        AppItem(id: "mascot", name: L("Brand Mascot"), subtitle: L("Become a brand's mascot."),
                category: trend, symbol: "star.circle", aspect: .square,
                model: "grok-imagine-2", stylized: true,
                template: "Create a friendly cartoon mascot version of the person from Image 1, standing in a cheerful waving pose, centered on a plain pastel-yellow background. The mascot has an oversized head, simple bold shapes and a smooth glossy toy-like 3D finish, keeping their hairstyle, hair color and signature features. Soft even studio light from the front, bright readable exposure. Full body, everything sharp. No text or logo."),
        AppItem(id: "storm-creature", name: L("Storm Creature"), subtitle: L("A creature made of clouds and lightning."),
                category: trend, symbol: "cloud.bolt", aspect: .portrait3x4,
                model: "seedream-5-pro",
                template: "A gigantic creature made of storm clouds and lightning looming over the person in an open field, under a dark churning sky, with lightning lighting the scene in cold blue flashes."),
        AppItem(id: "burning-sunset", name: L("Burning Sunset"), subtitle: L("A sky on fire behind you."),
                category: trend, symbol: "sun.horizon", aspect: .portrait4x5,
                model: "seedream-4.5",
                template: "The person standing in front of an intensely burning orange-red sunset sky, warm golden rim light outlining their hair and shoulders while their face stays clearly visible and softly lit, heat haze, cinematic."),
        AppItem(id: "on-fire", name: L("This Is Fine"), subtitle: L("Calm in a room on fire, comic style."),
                category: trend, symbol: "flame", aspect: .landscape4x3,
                model: "gpt-image-2.5-flare", stylized: true,
                template: "Cartoon comic panel of the person calmly sitting at a table with a coffee mug while the room around them is on fire, speech bubble saying \"This is fine\"."),
        AppItem(id: "comic-book", name: L("Comic Book"), subtitle: L("You as a comic book hero."),
                category: trend, symbol: "book.pages", aspect: .portrait2x3,
                model: "gpt-image-2", stylized: true,
                template: "Draw a comic book cover: the person from Image 1 as an original superhero in a dynamic mid-leap pose over a city skyline at dusk, wearing a bold red and deep-blue suit with an invented chest emblem. Bold black inks, flat colors, halftone dot shading and speed lines. A masthead reading \"LEGEND\" in big yellow block letters across the top and a small \"#1\" in a box at the top-left. No other text."),
        AppItem(id: "cloud-surf", name: L("Cloud Surfing"), subtitle: L("Surfing on a sea of clouds."),
                category: trend, symbol: "cloud", aspect: .landscape16x9,
                model: "seedream-5-pro",
                template: "The person surfing on a board over a sea of fluffy clouds at sunrise, surreal and photorealistic."),
        AppItem(id: "mukbang", name: L("Mukbang"), subtitle: L("A huge table of food in front of the camera."),
                category: trend, symbol: "fork.knife", aspect: .landscape16x9,
                model: "seedream-4.5",
                template: "Generate a frame from a mukbang livestream: the person from Image 1 sits at a table facing the camera, holding chopsticks mid-bite. The table is packed with dishes: fried chicken, a large bowl of noodles, dumplings, tteokbokki and drinks. A ring light reflects in their eyes and a small microphone on a stand sits at the table edge. Bright, even front light and a softly blurred bedroom behind."),
        AppItem(id: "melting-doodle", name: L("Melting Doodle"), subtitle: L("Doodles melting over the photo."),
                category: trend, symbol: "scribble.variable", slots: [.image],
                model: "nano-banana-2", stylized: true,
                template: "Add playful hand-drawn neon doodles over the photo that appear to melt and drip down, mixed-media illustration on photography."),
        AppItem(id: "giallo", name: L("Giallo Horror"), subtitle: L("A still from a '70s Italian horror film."),
                category: trend, symbol: "eye", aspect: .landscape16x9,
                model: "flux-2-pro",
                template: "1970s Italian giallo horror film still of the person, saturated red and blue lighting, dramatic shadows, film grain."),
        AppItem(id: "renaissance", name: L("Renaissance"), subtitle: L("You as a Renaissance painting in a gallery."),
                category: trend, symbol: "building.columns", aspect: .portrait4x5,
                model: "seedream-5-pro", stylized: true,
                template: "The person depicted as a Renaissance oil painting with period clothing, hung in an ornate gold frame in a museum gallery."),
        AppItem(id: "rap-god", name: L("Rap Cover"), subtitle: L("Your rap album cover."),
                category: trend, symbol: "music.mic", aspect: .square,
                model: "gpt-image-2.5-sunburst",
                template: "Design a hip-hop album cover: the person from Image 1 in a low-angle waist-up portrait, wearing a black leather jacket and gold chains against a matte black backdrop. One hard spotlight from camera-left carves deep shadows, with a warm gold rim light on the right. The title \"NO DAYS OFF\" runs across the top in heavy condensed chrome letters, exactly once, with no extra punctuation. No other text, signage or logos."),
    ]
}
