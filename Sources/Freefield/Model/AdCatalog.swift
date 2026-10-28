import FreefieldCore
import SwiftUI

struct AdCondition: Hashable {
    let group: Int
    let values: [String]
    var excluding = false
    var typingTurnsOn = false
    var note: String?
}

struct AdOptionGroup: Hashable {
    enum Style: Hashable { case tiles, segmented, chips }

    let title: String
    let values: [String]
    var style = Style.tiles
    var appliesWhen: AdCondition?
    var labels: [String: String] = [:]
    var allowsMany = false
    var pictureTitle: String?
}

enum AdKind: Hashable { case single, batch, resize, headlines, translate, multiply }

struct AdTextField: Hashable {
    enum Role: Hashable { case copy, person, direction }

    let title: String
    let placeholder: String
    var isLiteral = false
    var onePerLine = false
    var role = Role.copy
    var pipeSeparated = false
    var parts: [String] = []
    var initial = ""
    var appliesWhen: AdCondition?
    var requiredReason: String?
    var placeholders: [String: String] = [:]
    var caption: String?
}

struct AdTool: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let symbol: String
    var options: [AdOptionGroup] = []
    var text: AdTextField?
    var text2: AdTextField?
    var usesPerson = true
    var needsReference = false
    var example: [Int: String] = [:]
    var displayOrder: [Int]?
    var copyFirst = false
    var extraHint = L("e.g. a warmer light and a calmer background")
    var personHint = L("Optional. Skip it and we'll create a person for you.")
    var personWhen: AdCondition?
    var foldedGroups: [Int] = []
    var kind = AdKind.single
    var takesProduct = true
    var usesBrand = false
    var placesLogo = true
    var picturesFrom: String?
    var manyExample: [Int: [String]] = [:]
    var manyDefault: [Int: [String]] = [:]
    var inputGroups: [Int] = []
    var whenToUse: String?
    var referenceTitle = L("Reference Ad")
    var referenceHint = L("An ad you own or have rights to use")
    var referenceMissing = L("Add the reference ad")
    var aspect: AspectRatio
    var model: String
    let recipe: String

    var isCarousel: Bool { id == "carousel" }
    var isUnboxing: Bool { id == "unboxing" }

    var directionField: AdTextField? { [text, text2].compactMap { $0 }.first { $0.role == .direction } }
    var groupOrder: [Int] { (displayOrder ?? Array(options.indices)).filter { !inputGroups.contains($0) } }
    var makesSeveral: Bool { [.batch, .resize, .translate].contains(kind) }

    static let listingSet = ["Main image (pure white)", "Feature callouts", "Multi-angle grid", "Detail close-up", "Lifestyle"]
    static let fullSetValue = "Full set (5 images)"

    func makesFullSet(_ imageType: String) -> Bool { id == "marketplace" && imageType == Self.fullSetValue }
}

enum AdCatalog {
    static func tool(_ id: String) -> AdTool? { all.first { $0.id == id } }

    static let all: [AdTool] = [
        AdTool(
            id: "ugc-photo",
            name: L("Customer Photo"),
            subtitle: L("A casual TikTok-style phone photo of someone using your product."),
            symbol: "iphone.gen3",
            options: [
                    AdOptionGroup(title: L("Shot"), values: ["Front-camera selfie", "Shot by a friend", "First-person POV (hands only)", "Mid-use candid"],
                                  labels: ["Front-camera selfie": L("Selfie (front camera)"),
                                           "Shot by a friend": L("Shot by a friend (a step or two away)"),
                                           "First-person POV (hands only)": L("Through your eyes (hands only)"),
                                           "Mid-use candid": L("Candid (using it, not looking at the camera)")]),
                    AdOptionGroup(title: L("Location"), values: ["Bedroom", "Bathroom", "Kitchen", "Living room couch", "Car, driver's seat", "Gym", "Office desk", "Street", "Store aisle"],
                                  style: .chips),
                    AdOptionGroup(title: L("Light"), values: ["Window daylight", "Warm evening lamps", "Direct phone flash", "Outdoor daylight"],
                                  style: .chips),
                ],
            text: AdTextField(title: L("Extra direction (optional)"), placeholder: L("e.g. she's laughing and holds it next to her face"),
                              role: .direction),
            example: [0: "Front-camera selfie", 1: "Bathroom", 2: "Window daylight"],
            foldedGroups: [2],
            aspect: .portrait9x16,
            model: "nano-banana-pro",
            recipe: #"""
            Image 1 is the product (further product photos may follow). The person reference photo(s), if any, come after the product photos.
            Create an authentic user-generated photo of the kind a real customer posts to TikTok, Reels or Instagram Stories. Shot: {option}. Location: {option2}. Light: {option3}.
            Shot rules. Front-camera selfie: taken at arm's length with the phone's front camera, with slight wide-angle distortion, the holding arm partly in frame and eye contact with the lens. Shot by a friend: a casual vertical phone photo taken from one or two meters away; the person is relaxed and not posing. First-person POV (hands only): only the person's hands and forearms with the product, seen from their own eye line, with no face. Mid-use candid: the person is caught naturally using the product and is not looking at the camera.
            Person: if person reference photos are attached, the person is exactly that person: same face and facial structure, skin tone, hair, age and body type, unmistakably recognizable. Do not beautify, slim or de-age them. If none are attached, cast an ordinary, believable person in casual everyday clothes who would plausibly buy this product.
            Product: the person holds or uses the exact product from Image 1, with the label turned toward the camera and in focus. Reproduce it exactly: the same silhouette and proportions, colors, materials and finish, cap or closure, label layout, logo and every printed word, all legible. Do not redesign, relabel, translate or add anything. Keep its true real-world size in the hand. The hands look natural, with five fingers, and grip it the way people really hold this kind of object.
            Look: a real, unedited smartphone photo with phone auto-exposure and white balance, mild noise in the shadows and slightly imperfect framing and horizon. The space is real and lived-in, with ordinary everyday clutter. Skin is natural, with pores, fine lines and stray hairs, and color is true to life. It is not a studio shot and not cinematic: no retouching, no glossy or plastic AI look, no HDR glow, no oversaturation, no fake background blur.
            Text: add no captions, stickers, app interface, watermarks, brand names or other words. The only text in the image is what is printed on the product.
            Additional direction (may be empty): {text}
            """#
        ),
        AdTool(
            id: "model-shoot",
            name: L("Model Shoot"),
            subtitle: L("Your product held, worn or used by a model, shot like a pro photo shoot."),
            symbol: "figure.stand",
            options: [
                    AdOptionGroup(title: L("Shot"), values: ["Closeup", "Faceless (hands and body only)", "Full body", "Editorial", "Wearing it (try-on)"],
                                  labels: ["Closeup": L("Close-up (face, hands and product)"),
                                           "Full body": L("Full body (head to toe)"),
                                           "Editorial": L("Editorial (fashion magazine style)"),
                                           "Wearing it (try-on)": L("Wearing it (clothes or accessories)")]),
                    AdOptionGroup(title: L("Environment"), values: ["Seamless white (e-commerce)", "Studio clean", "Outdoor natural", "Street style", "Home cozy"],
                                  style: .chips,
                                  labels: ["Seamless white (e-commerce)": L("White background (online store)")]),
                ],
            text: AdTextField(title: L("Who the model is (optional)"), placeholder: L("e.g. woman in her 30s, short curly hair, minimal makeup"),
                              role: .person),
            example: [0: "Faceless (hands and body only)", 1: "Street style"],
            extraHint: L("e.g. soft morning light, she smiles slightly"),
            personHint: L("Optional. Skip it and we'll create a model."),
            aspect: .portrait3x4,
            model: "seedream-4.5",
            recipe: #"""
            Image 1 is the product (further product photos may follow). The model reference photo(s), if any, come after the product photos.
            Create a professional product photoshoot image of a model with the exact product from Image 1. Shot: {option}. Environment: {option2}.
            Shot rules. Closeup: a tight crop on the face, hands and product together, with the product sharp and dominant. Faceless: framed from the chin or shoulders down, or hands only, with no face visible, while the product is held or used. Full body: head to toe, a natural confident stance, the product clearly visible. Editorial: fashion-magazine art direction, with an intentional pose and composed negative space. Wearing it (try-on): the model wears the product, and its cut, fit, drape, fabric, color, pattern, hardware and logos are reproduced faithfully on the body.
            Environment rules. Seamless white (e-commerce): an evenly lit pure white sweep with a soft floor shadow and nothing else in frame. Any other environment: a real location that matches the name, styled simply so the product stays the hero.
            Model: if reference photos are attached, the model is exactly that person: same face and facial structure, skin tone, hair, age and body type, unmistakably recognizable. Do not beautify, slim or de-age them. If none are attached, cast a natural-looking model suited to the product's buyer. Model description (may be empty): {text}
            Product: reproduce it exactly, with the same silhouette and proportions, colors, materials and finish, label layout, logo and every printed word, all legible. Do not redesign, relabel or add anything. Keep it at true real-world scale against the body. The hands are natural, with five fingers.
            Look: a real photograph from a professional shoot. Use a full-frame camera with an 85 mm or 50 mm lens and real softbox or natural light, with physically correct shadows and reflections. Color is true to life, skin is natural with visible pores, and detail is crisp but not over-sharpened. No CGI or render look, no plastic or waxy skin, no HDR glow, no oversaturation, no distorted hands.
            Add no text, captions, badges, watermarks or logos beyond what is printed on the product.
            """#
        ),
        AdTool(
            id: "product-shoot",
            name: L("Product Shoot"),
            subtitle: L("Catalog photos of your product, with no people."),
            symbol: "camera.aperture",
            options: [
                    AdOptionGroup(title: L("Style"), values: ["Studio white", "Color pop", "Natural light", "In use (no people)", "Flat lay"],
                                  labels: ["Studio white": L("Studio white (pure white background)"),
                                           "Color pop": L("Color pop (one-color background)"),
                                           "Natural light": L("Natural light (soft window light)"),
                                           "Flat lay": L("From above (laid flat)")]),
                    AdOptionGroup(title: L("Surface"), values: ["None", "Marble", "Wood", "Linen fabric", "Concrete"], style: .chips,
                                  appliesWhen: AdCondition(group: 0, values: ["Studio white"], excluding: true),
                                  labels: ["None": L("No surface")]),
                    AdOptionGroup(title: L("Season"), values: ["None", "Christmas", "Valentine's Day", "Halloween", "Black Friday"], style: .chips,
                                  appliesWhen: AdCondition(group: 0, values: ["Studio white"], excluding: true),
                                  labels: ["None": L("No season")]),
                ],
            text: AdTextField(title: L("Extra direction (optional)"), placeholder: L("e.g. with fresh lemons and ice around it"),
                              role: .direction),
            usesPerson: false,
            example: [0: "Natural light", 1: "Linen fabric", 2: "None"],
            foldedGroups: [1, 2],
            aspect: .portrait3x4,
            model: "gpt-image-2.5-sunburst",
            recipe: #"""
            Image 1 is the product (further product photos, such as other angles, may follow). No people appear.
            Create a commercial product photograph of exactly this product. Style: {option}. Surface: {option2}. Season: {option3}.
            Style rules. Studio white: a pure seamless white background (#FFFFFF), soft even light and a natural soft contact shadow, with the product centered and filling about 80% of the frame; ignore the surface and season. Color pop: a bold solid backdrop in one color that complements the label, with crisp hard light and a clean, defined shadow. Natural light: soft directional window daylight, gentle shadows and a calm, realistic setting. In use (no people): the product in the real place it is used, caught mid-use (opened, poured, switched on or applied), with believable traces of use. Flat lay: a 90-degree top-down view, with the product and a few relevant props in a tidy, balanced composition.
            If the surface is not None, the product rests on that real material, with accurate texture and reflections. If the season is not None, add a few subtle props and colors for that occasion around the product; they never cover it and carry no lettering.
            Product: reproduce it exactly, with the same silhouette and proportions, colors, materials and finish, cap or closure, label layout, logo and every printed word, sharp and legible. Do not redesign, relabel, translate or add claims. Keep the scale correct relative to the props.
            Look: a real photograph by a professional product photographer, with real lens perspective, physically correct reflections, highlights and contact shadows, true-to-life color and fine material texture. No CGI or 3D-render look, no floating product, no HDR glow, no oversaturation, and no props that could be mistaken for part of the product.
            Add no text, prices, badges, watermarks or extra logos. The only text is what is printed on the product.
            Additional direction (may be empty): {text}
            """#
        ),
        AdTool(
            id: "unboxing",
            name: L("Unboxing"),
            subtitle: L("Someone opens the package and shows your product, in one photo or three."),
            symbol: "gift",
            options: [
                    AdOptionGroup(title: L("Moment"), values: ["Box just arrived (sealed)", "Opening, product half-revealed", "Product out, first reaction", "Haul spread on the bed"],
                                  appliesWhen: AdCondition(group: 2, values: ["3-photo sequence"], excluding: true,
                                                           note: L("The sequence shows: it arrives → it's opened → first reaction.")),
                                  labels: ["Opening, product half-revealed": L("Opening the box (product half out)"),
                                           "Product out, first reaction": L("First reaction (product in hand)"),
                                           "Haul spread on the bed": L("All on the bed (product and packaging)")]),
                    AdOptionGroup(title: L("View"), values: ["POV hands only", "Creator in frame"], style: .segmented,
                                  labels: ["POV hands only": L("Hands only (through your eyes)"),
                                           "Creator in frame": L("Person in the photo")]),
                    AdOptionGroup(title: L("Output"), values: ["Single photo", "3-photo sequence"], style: .segmented),
                ],
            example: [1: "POV hands only", 2: "3-photo sequence"],
            displayOrder: [2, 0, 1],
            extraHint: L("e.g. a white duvet and a cat asleep nearby"),
            aspect: .portrait9x16,
            model: "nano-banana-pro",
            recipe: #"""
            Image 1 is the product (further product photos may follow). The person reference photo(s), if any, come next. If a previous frame of this unboxing sequence is attached, it is the last image.
            Create an authentic unboxing photo of the kind a real customer posts on TikTok or Instagram. Moment: {option}. View: {option2}.
            Moment rules. Box just arrived (sealed): the sealed parcel on a bed or a doorstep, with hands about to open it. Opening, product half-revealed: the box is open and the tissue paper pulled back, with the product half-revealed. Product out, first reaction: the product is lifted out and held toward the camera, with a genuine excited first reaction. Haul spread on the bed: the product and its opened packaging spread on a bed, with the empty box and tissue nearby.
            View rules. POV hands only: a first-person, top-down view of the hands, with no face. Creator in frame: the person is visible, sitting on the bed and reacting naturally.
            Person: if person reference photos are attached, the person is exactly that person: same face and facial structure, skin tone, hair, age and body type. Do not beautify them. If none are attached, use an ordinary, believable person in casual home clothes.
            Packaging: show branded packaging only if it appears in the product photos, and then reproduce it exactly. Otherwise use a plain kraft shipping box or mailer and plain tissue paper, with no printed logos, labels or text.
            Product: reproduce it exactly, with the same silhouette, proportions, colors, materials, label layout, logo and every printed word, all legible. Do not redesign or relabel it. Keep its true real-world size in the hands.
            Continuity: if a previous frame is attached, keep the same room, bedding, light, outfit, hands and box, so the photos read as one continuous unboxing.
            Look: a real, unedited smartphone photo with phone auto-exposure, soft window light or warm room light, mild noise and slightly imperfect framing. The bedroom is real, with everyday details. Skin is natural and hands have five fingers. It is not a studio shot: no glossy AI look, no HDR glow, no fake blur.
            Add no captions, stickers, app interface, watermarks or extra words. The only text is what is printed on the product or on its real packaging.
            """#
        ),
        AdTool(
            id: "before-after",
            name: L("Before & After"),
            subtitle: L("A matched split image showing the change your product makes."),
            symbol: "rectangle.split.2x1",
            options: [
                    AdOptionGroup(title: L("Transformation"), values: ["Space (messy to clean)", "Person (look or routine)", "Object (worn to restored)"]),
                    AdOptionGroup(title: L("Layout"), values: ["side by side", "top and bottom"], style: .segmented),
                ],
            text: AdTextField(title: L("Panel labels (optional)"), placeholder: L("Before | After"), isLiteral: true, pipeSeparated: true,
                              parts: [L("Before panel label"), L("After panel label")], initial: L("Before") + " | " + L("After")),
            example: [0: "Object (worn to restored)", 1: "side by side"],
            extraHint: L("e.g. in the “Before” photo the shoes are muddy, not torn"),
            personWhen: AdCondition(group: 0, values: ["Person (look or routine)"]),
            aspect: .portrait4x5,
            model: "nano-banana-pro",
            recipe: #"""
            Image 1 is the product (further product photos may follow). The person reference photo(s), if any, come next.
            Create one before-and-after comparison image made of two panels, {option2}, separated by a thin, clean divider. Transformation: {option}.
            Both panels show the same scene, photographed from the same camera position with the same framing, lens and lighting. The only difference is the believable change the product makes. The Before panel (left or top) shows the problem state, without the product. The After panel (right or bottom) shows the improved state, with the exact product from Image 1 visible and naturally placed or in use.
            Transformation rules. Space (messy to clean): the same room or surface, messy or dirty before and clean and tidy after. Person (look or routine): the same person in the same pose, outfit and light, where only the change the product plausibly delivers differs. Object (worn to restored): the same object, worn, stained or broken before and cleaned, restored or fixed after. Keep the result modest and realistic, never miraculous or exaggerated, and never change body shape or weight.
            Person: if person reference photos are attached, both panels show exactly that person: same face and facial structure, skin tone, hair, age and body type. Do not beautify them.
            Product: reproduce it exactly, with the same silhouette, proportions, colors, materials, label layout, logo and every printed word, all legible. Do not redesign or relabel it.
            Labels: render exactly these labels, spelled as written, one in a top corner of each panel, in a small, clean white sans-serif with a subtle shadow: "{text}". The part before "|" goes on the Before panel and the part after it on the After panel. If the quoted labels are empty, add no text at all.
            Look: real photographs with natural light, true-to-life color, real textures and real skin with pores. No CGI look, no HDR glow, no oversaturation. Add no other text, arrows, badges, watermarks or logos beyond what is printed on the product.
            """#
        ),
        AdTool(
            id: "testimonial",
            name: L("Testimonial"),
            subtitle: L("A real-looking customer photo with their review quote."),
            symbol: "quote.bubble",
            options: [
                    AdOptionGroup(title: L("Layout"), values: ["Caption over photo", "Quote card beside photo", "Quote first, photo inset"],
                                  labels: ["Caption over photo": L("Text over the photo (in a band at the bottom)"),
                                           "Quote card beside photo": L("Card beside the photo (quote on one side)"),
                                           "Quote first, photo inset": L("Quote on top (small photo below)")]),
                    AdOptionGroup(title: L("Moment"), values: ["talking to the camera", "holding the product up", "using the product"], style: .chips),
                ],
            text: AdTextField(title: L("A real customer's quote"), placeholder: L("Paste a real review, e.g. My skin has never felt this soft."),
                              isLiteral: true, requiredReason: L("Write the customer's quote"),
                              caption: L("Use the customer's exact words — never invent a review.")),
            text2: AdTextField(title: L("Attribution (optional)"), placeholder: L("e.g. – Ana, verified buyer ★★★★★"), isLiteral: true),
            example: [0: "Caption over photo", 1: "holding the product up"],
            copyFirst: true,
            extraHint: L("e.g. she's in her kitchen, in a green sweater"),
            usesBrand: true,
            aspect: .portrait4x5,
            model: "gpt-image-2.5-sunburst",
            recipe: #"""
            Image 1 is the product (further product photos may follow). The person reference photo(s), if any, come next.
            Create a social-proof testimonial ad for paid social: a real customer photo with their quote. Layout: {option}.
            Photo: an authentic smartphone photo of the customer {option2}, in a real home. When talking to the camera, they are mid-sentence with natural eye contact. If person reference photos are attached, the customer is exactly that person: same face and facial structure, skin tone, hair, age and body type, not beautified. Otherwise use an ordinary, believable customer. The exact product from Image 1 is clearly visible, label toward the camera.
            Product: reproduce it exactly, with the same silhouette, proportions, colors, materials, label layout, logo and every printed word, all legible. Do not redesign or relabel it.
            Layout rules. Caption over photo: the quote sits in a semi-transparent dark bar across the lower third, never covering the face or the product label. Quote card beside photo: the photo is on one side and a clean off-white card with the quote in large type is on the other. Quote first, photo inset: a large quote with the photo below it as a rounded inset.
            Quote: render exactly this text, word for word, inside straight quotation marks: "{text}". Under it, render the attribution exactly as written (it may be empty): "{text2}". Add no star ratings, verified badges, names, dates, numbers or other words unless they are part of the text above. If the quote is empty, leave the bar or card as clean, empty space and add no text. Use one clean, highly legible sans-serif, sized to read on a phone.
            Look: the photo is a real phone photo, with natural light, mild noise, real skin with pores and a lived-in background. No glossy AI look, no HDR glow. The layout is simple and restrained, like a real brand's ad. No watermarks.
            """#
        ),
        AdTool(
            id: "static-ad",
            name: L("Static Ad"),
            subtitle: L("A finished ad with your headline, benefits and button."),
            symbol: "text.below.photo",
            options: [formatGroup, angleGroup],
            text: AdTextField(title: L("Headline (optional, one ad per line)"), placeholder: L("e.g. Hydration that lasts 72 hours"), isLiteral: true, onePerLine: true),
            text2: supportingField,
            example: [0: "Benefit bullets", 1: "Ingredient or material"],
            copyFirst: true,
            extraHint: L("e.g. a soft green background with plenty of space"),
            personHint: L("Optional. Skip it and we'll add a person if needed."),
            usesBrand: true,
            aspect: .portrait4x5,
            model: "gpt-image-2.5-sunburst",
            recipe: staticAdRecipe
        ),
        AdTool(
            id: "hook-frame",
            name: L("Hook Frame"),
            subtitle: L("Eye-catching first frames for vertical videos, one per line you write."),
            symbol: "bolt",
            options: [
                    AdOptionGroup(title: L("Visual hook"), values: ["Extreme close-up", "Shocked reaction", "Product mid-action", "Unexpected angle", "Problem moment"],
                                  labels: ["Extreme close-up": L("Extreme close-up (the product fills the frame)"),
                                           "Shocked reaction": L("Surprised reaction (face close to the camera)"),
                                           "Product mid-action": L("Product in action (pouring, opening, switching on)"),
                                           "Unexpected angle": L("Unexpected angle (very low or very high)"),
                                           "Problem moment": L("Problem moment (the product at the edge)")]),
                    AdOptionGroup(title: L("Caption style"), values: ["Native caption", "Bold block caption", "No text"], style: .segmented,
                                  labels: ["Native caption": L("TikTok-style caption"), "Bold block caption": L("Caption in a white box")]),
                ],
            text: AdTextField(title: L("Catchy lines (one image per line)"), placeholder: L("e.g. I didn't expect this to work…"), isLiteral: true, onePerLine: true,
                              appliesWhen: AdCondition(group: 1, values: ["No text"], excluding: true)),
            example: [0: "Product mid-action", 1: "Native caption"],
            copyFirst: true,
            extraHint: L("e.g. at night, in a parked car"),
            personHint: L("Optional. Skip it and we'll add a person if needed."),
            aspect: .portrait9x16,
            model: "nano-banana-pro",
            recipe: #"""
            Image 1 is the product (further product photos may follow). The person reference photo(s), if any, come next.
            Create the first frame of a short vertical video ad for TikTok or Reels, built to stop the scroll in under a second. Visual hook: {option}. Caption style: {option2}.
            Visual hook rules. Extreme close-up: the product fills most of the frame, shot very close on a phone, with sharp texture detail. Shocked reaction: the person's genuinely surprised face close to the lens, holding the product. Product mid-action: the product caught mid-use (pouring, spraying, opening or switching on), frozen like a paused video frame. Unexpected angle: a strange, very low or very high phone angle on the product in hand. Problem moment: the relatable everyday frustration the product fixes, with the product visible at the edge of the frame.
            Person: if person reference photos are attached, the person is exactly that person: same face and facial structure, skin tone, hair, age and body type. Do not beautify them. If none are attached and the hook needs a person, use an ordinary, believable person.
            Product: reproduce it exactly, with the same silhouette, proportions, colors, materials, label layout, logo and every printed word. Do not redesign or relabel it.
            Caption: render exactly this hook line, spelled as written: "{text}". Native caption means white text with a thin black outline in the classic short-video caption look. Bold block caption means black text on a white rounded box. Place the caption in the upper middle of the frame, between 15% and 60% of the height, in at most two lines, and never over the face or the product label. If the hook line is empty or the caption style is No text, add no text at all.
            Look: a real paused frame from a phone video, with slight motion blur where things move, phone exposure, mild noise, a real room and natural skin. Not a studio photo: no glossy AI look, no HDR glow. Add no other words, stickers, app interface, watermarks or logos.
            """#
        ),
        AdTool(
            id: "carousel",
            name: L("Carousel"),
            subtitle: L("3 to 7 matching images that tell one story about your product."),
            symbol: "rectangle.on.rectangle.angled",
            options: [
                    AdOptionGroup(title: L("Story"), values: ["Hook → problem → product → proof → offer", "How to use (steps)", "Photo dump"],
                                  labels: ["Hook → problem → product → proof → offer": L("Sales story (hook → problem → product → proof → offer)"),
                                           "How to use (steps)": L("How to use (one step per slide)"),
                                           "Photo dump": L("Photos from one day (casual moments)")]),
                    AdOptionGroup(title: L("Slides"), values: ["3", "4", "5", "6", "7"], style: .segmented),
                ],
            text: AdTextField(title: L("Slide captions (optional)"), placeholder: L("No caption on this slide"), isLiteral: true),
            example: [0: "Hook → problem → product → proof → offer", 1: "3"],
            extraHint: L("e.g. the same cozy living room in every slide"),
            usesBrand: true,
            placesLogo: false,
            aspect: .portrait4x5,
            model: "nano-banana-2",
            recipe: #"""
            Image 1 is the product (further product photos may follow). The person reference photo(s), if any, come next. If earlier slides of this carousel are attached, they are the last images.
            This is slide {index} of a {count}-slide social carousel (an Instagram or Facebook carousel, or TikTok photo mode). Story: {option}. This slide's beat: {beat}. Render only this slide's beat, as one single photo.
            Story context, for reference only. Hook → problem → product → proof → offer: a scroll-stopping hook image, then the everyday problem without the product, then the product hero in hand, then proof showing the product in use with its visible result, then a clean product hero with space for a call to action. With fewer slides, beats merge; with more, extra proof shots are added. How to use (steps): one step per slide, in order, with the hands performing that step with the product. Photo dump: candid moments from one day of the creator's life (coffee, getting ready, desk, outside, evening), with the product appearing naturally in most of them.
            Consistency: every slide belongs to one locked visual system. Match the attached earlier slides: the same person, outfit, location, light, color grade, framing logic and caption style, so the set reads as one post.
            Person: if person reference photos are attached, the person is exactly that person: same face and facial structure, skin tone, hair, age and body type. Do not beautify them. Otherwise use one ordinary, believable person and keep them identical across slides.
            Product: reproduce it exactly, with the same silhouette, proportions, colors, materials, label layout, logo and every printed word, all legible. Do not redesign or relabel it.
            Caption for this slide: render "{caption}" exactly as written, in a clean, legible sans-serif, in the same position as on the other slides. If it is empty, add no text. Do not add step numbers, arrows or slide counters unless they are part of the caption.
            Look: real smartphone photos with natural light, true-to-life color, real skin and real rooms. No glossy AI look, no HDR glow, no collage, grid or border, no watermarks and no extra words.
            """#
        ),
        AdTool(
            id: "marketplace",
            name: L("Marketplace Images"),
            subtitle: L("The photos for your store listing: white background, details, angles and more."),
            symbol: "cart",
            options: [
                    AdOptionGroup(title: L("Image type"), values: ["Main image (pure white)", "Feature callouts", "Multi-angle grid", "Detail close-up", "What's in the box", "Lifestyle", "Styled cover", "Full set (5 images)"],
                                  labels: ["Feature callouts": L("Features with arrows (pointing at each part)"),
                                           "Multi-angle grid": L("Multi-angle grid (front, back and sides)"),
                                           "Detail close-up": L("Detail close-up (texture or mechanism)"),
                                           "What's in the box": L("What's in the box (all on white)"),
                                           "Lifestyle": L("Lifestyle (the product in use)"),
                                           "Styled cover": L("Styled cover (the product as the star)")]),
                    AdOptionGroup(title: L("Cover style"), values: ["Dark premium", "3D surreal", "Pastel", "Clean studio"], style: .chips,
                                  appliesWhen: AdCondition(group: 0, values: ["Styled cover"])),
                ],
            text: AdTextField(title: L("Callouts or headline (optional, one per line)"), placeholder: L("e.g. 72-hour hydration · Vegan · Fragrance-free"),
                              isLiteral: true, pipeSeparated: true,
                              appliesWhen: AdCondition(group: 0, values: ["Feature callouts", "Styled cover", "Full set (5 images)"])),
            text2: AdTextField(title: L("Items in the box (optional, one per line)"), placeholder: L("e.g. Serum · Dropper · Pouch"),
                               isLiteral: true, pipeSeparated: true,
                               appliesWhen: AdCondition(group: 0, values: ["What's in the box"])),
            usesPerson: false,
            example: [0: "Feature callouts"],
            extraHint: L("e.g. show the cap open in the close-up"),
            aspect: .square,
            model: "nano-banana-pro",
            recipe: #"""
            Image 1 is the product (further product photos, ideally other angles, may follow).
            Create one listing image for an online store or marketplace product page. Image type: {option}. Cover style (used only for Styled cover): {option2}.
            Type rules. Main image (pure white): the product alone on a pure white background (RGB 255,255,255), centered and filling about 85% of the frame, with a soft natural shadow and no props, text or badges. Feature callouts: the product large on a light, clean background, with thin leader lines pointing to real parts of it, each ending in one short callout from the copy below. Multi-angle grid: a clean 2x2 grid of front, back, side and three-quarter views on white, with identical lighting. Detail close-up: a macro view of the most important material, texture, finish or mechanism. What's in the box: the product and only the listed items, laid out neatly top-down on white; if no items are listed, show only the product, plus its real packaging if it appears in the photos. Lifestyle: the product in use in a realistic everyday setting, large and sharp. Styled cover: the product as a bold hero in the chosen style. Dark premium is a deep charcoal set with rim light and glossy reflections. 3D surreal uses floating sculptural shapes and soft gradients. Pastel is a soft pastel set with beauty-style light. Clean studio is a bright, minimal set.
            Product: reproduce it exactly, with the same silhouette, proportions, colors, materials, finish, label layout, logo and every printed word, sharp and legible. Do not redesign, relabel or add claims. Views that are not shown in the photos must stay consistent with them; do not invent buttons, ports, colors or features.
            Copy: use only these words, spelled exactly as written. Callouts or cover headline, separated by "|": "{text}". Items in the box, separated by "|": "{text2}". Never invent features, specifications, prices, ratings, certifications, awards or badges. If a field is empty, render nothing for it.
            Look: a real professional e-commerce photograph, with accurate color, crisp detail and physically correct reflections and shadows. No CGI look, no HDR glow, no watermarks.
            """#
        ),
        AdTool(
            id: "recreate-ad",
            name: L("Recreate Ad"),
            subtitle: L("Copy the style of an ad you like, with your product."),
            symbol: "arrow.triangle.2.circlepath",
            options: [
                    AdOptionGroup(title: L("Fidelity"), values: ["Close match", "Loose"],
                                  labels: ["Close match": L("Close match (same layout)"), "Loose": L("Loose (same idea, new scene)")]),
                    AdOptionGroup(title: L("Text from the reference ad"), values: ["Remove all text", "Use my copy"], style: .segmented,
                                  labels: ["Use my copy": L("Use my text")]),
                ],
            text: AdTextField(title: L("Your text (one per line, biggest first)"), placeholder: L("e.g. Glow that lasts · 30% off today"),
                              isLiteral: true, pipeSeparated: true,
                              appliesWhen: AdCondition(group: 1, values: ["Use my copy"], typingTurnsOn: true)),
            text2: AdTextField(title: L("Other changes (optional)"), placeholder: L("e.g. make the background pastel blue"), role: .direction),
            needsReference: true,
            example: [0: "Close match", 1: "Use my copy"],
            usesBrand: true,
            aspect: .auto,
            model: "gpt-image-2.5-sunburst",
            recipe: #"""
            Image 1 is a reference ad that the user owns or has the rights to use. Image 2 is the user's product (further product photos may follow). The person reference photo(s), if any, come after the product photos.
            Recreate the reference ad for the user's product. Fidelity: {option}. Copy: {option2}.
            Fidelity rules. Close match: keep the reference's composition, camera angle, crop, product placement, pose, lighting, color grade, background and layout grid as closely as possible. Loose: keep its concept, mood, lighting style and layout logic, but build a fresh scene around the new product.
            Product: replace the reference's product completely with the exact product from Image 2. Reproduce its silhouette, proportions, colors, materials, label layout, logo and every printed word, all legible, at a believable scale. No trace of the original product, its packaging or its branding may remain.
            Person: if person reference photos are attached, the person in the ad becomes exactly that person (same face and facial structure, skin tone, hair, age and body type), keeping the reference's pose and expression. Otherwise keep a person similar in role, age range and styling, but not the same individual as in the reference.
            Copy rules. Remove all text: erase every word, logo and badge from the reference and leave clean design space. Use my copy: replace the reference's text with this copy, spelled exactly as written, keeping the reference's typographic hierarchy, sizes and positions: "{text}". Lines separated by "|" fill the reference's text blocks from most to least prominent; leave any unused blocks empty. Never keep the reference's brand names, logos, slogans, prices or claims, and do not invent new ones.
            Other changes requested by the user (may be empty): {text2}
            Look: match the reference's medium. If it is a photograph, the result must look like a real photograph, with natural skin, real light and true-to-life color, not a glossy AI render. No watermarks.
            """#
        ),
        AdTool(
            id: "ad-batch",
            name: L("Ad Batch"),
            subtitle: L("Lots of finished ads in one run: each product × each selling angle × each size."),
            symbol: "square.grid.3x3",
            options: [
                    formatGroup,
                    AdOptionGroup(title: L("Selling angles"), values: ["Benefit", "Pain point", "Real-life use", "Ingredient or material", "Lifestyle moment"],
                                  style: .chips, allowsMany: true, pictureTitle: "Scene angle"),
                    sizeGroup(L("Sizes"), style: .chips),
                    AdOptionGroup(title: L("Text in the ad"), values: ["AI writes it", "No text"], style: .segmented,
                                  labels: ["AI writes it": L("AI writes it (headline and short lines)"),
                                           "No text": L("No text (space left for your own)")]),
                ],
            usesPerson: false,
            example: [0: "Benefit bullets", 3: "AI writes it"],
            extraHint: L("e.g. a soft green background with plenty of space"),
            kind: .batch,
            usesBrand: true,
            picturesFrom: "static-ad",
            manyExample: [1: ["Benefit", "Pain point"], 2: ["4:5"]],
            whenToUse: L("Many products at once — use Static Ad for a single ad."),
            aspect: .portrait4x5,
            model: "gpt-image-2.5-flare",
            recipe: staticAdRecipe
        ),
        AdTool(
            id: "ad-headlines",
            name: L("Headline Test"),
            subtitle: L("One ad, several headlines: a version for each, to see which one sells best."),
            symbol: "text.badge.star",
            options: [formatGroup, angleGroup],
            text: AdTextField(title: L("Headlines (one ad per line)"), placeholder: L("e.g. Hydration that lasts 72 hours"), isLiteral: true, onePerLine: true,
                              requiredReason: L("Write or generate the headlines"),
                              caption: L("Each line becomes its own ad, labeled A, B, C… Check that every claim is true before you publish.")),
            text2: supportingField,
            example: [0: "Headline hero", 1: "Benefit"],
            copyFirst: true,
            extraHint: L("e.g. a soft green background with plenty of space"),
            personHint: L("Optional. Skip it and we'll add a person if needed."),
            kind: .headlines,
            usesBrand: true,
            picturesFrom: "static-ad",
            whenToUse: L("Compare headlines on one ad — use Static Ad for a single ad."),
            aspect: .portrait4x5,
            model: "gpt-image-2.5-sunburst",
            recipe: staticAdRecipe
        ),
        AdTool(
            id: "ad-resize",
            name: L("Ad Resizer"),
            subtitle: L("An ad you already have, redrawn in other sizes: stories, feed, square and wide."),
            symbol: "aspectratio",
            options: [sizeGroup(L("New sizes"), style: .tiles)],
            usesPerson: false,
            needsReference: true,
            extraHint: L("e.g. keep the logo in the top-left corner"),
            kind: .resize,
            takesProduct: false,
            manyExample: [0: ["9:16", "1:1"]],
            whenToUse: L("Your ad in other sizes — use Static Ad to make a new ad."),
            referenceTitle: L("Your finished ad"),
            referenceHint: L("The ad image you want in other sizes"),
            referenceMissing: L("Add your finished ad"),
            aspect: .auto,
            model: "nano-banana-pro",
            recipe: #"""
            Image 1 is a finished ad that the user owns.
            Redraw this same ad for a new {option} canvas ({shape}). It is the same ad in a new size, not a new design.
            Keep every element of the original: the product, any people, the logo, every line of text spelled exactly as it is, the typefaces, colors, icons, buttons, stickers and the visual style. Keep the same visual hierarchy (headline, product, supporting lines, call to action) and the same brand look.
            Re-layout for the new shape: move, scale and regroup the elements so the layout feels designed for this size. Extend the background, set or scene naturally to fill the new space, matching its texture, light and perspective. Nothing may be cropped, squeezed, stretched, mirrored or overlapping. Keep the product and faces at the same size relative to each other, and keep generous margins around the text.
            Placement rules. 9:16: stack the elements vertically and keep all text out of the top 14% and the bottom 20% of the frame. 1:1 and 4:5: a balanced feed layout. 16:9: spread the elements horizontally, with the text on one side and the product on the other.
            Product: reproduce it exactly as in Image 1, with the same silhouette, colors, label layout, logo and every printed word. Do not add, remove, rewrite or translate any text, and do not add new elements, prices, badges or claims.
            Look: match the original's medium and finish exactly. No watermarks.
            """#
        ),
        AdTool(
            id: "ad-translate",
            name: L("Translate Ad"),
            subtitle: L("An ad you already have, with its text in other languages: one ad per language."),
            symbol: "character.bubble",
            options: [AdOptionGroup(title: L("Languages"), values: VideoCatalog.languageGroup.values, style: .chips, allowsMany: true)],
            usesPerson: false,
            needsReference: true,
            extraHint: L("e.g. keep the slogan “Just glow” in English"),
            kind: .translate,
            takesProduct: false,
            manyExample: [0: ["Spanish", "Japanese"]],
            manyDefault: [0: [VideoCatalog.interfaceLanguage == "Spanish" ? "English" : "Spanish"]],
            whenToUse: L("Your ad in other languages — use Static Ad to make a new ad."),
            referenceTitle: L("Your finished ad"),
            referenceHint: L("The ad image whose text you want translated"),
            referenceMissing: L("Add your finished ad"),
            aspect: .auto,
            model: "nano-banana-pro",
            recipe: #"""
            Image 1 is a finished ad that the user owns.
            Redraw this exact ad with its marketing text translated into {option}. Everything else stays identical: the layout, the product, any people, the background, the colors, the icons, buttons and stickers, and the position, size, weight, color and style of each text block.
            Translation rules. Translate every headline, supporting line, label, button and call to action naturally, the way a native {option} copywriter would write it, keeping the meaning and the tone. Keep each translation about as long as the original so it fits the same space; if it is longer, make the type slightly smaller instead of moving other elements. Spell every word correctly, with the right accents and characters for {option}. Keep brand names, product names, logos, prices, numbers, measurements, URLs and social handles exactly as they are. Do not translate or change anything printed on the product or its packaging.
            Do not add new words, claims, prices, badges or ratings. If the ad's text is already in {option}, keep it exactly as it is.
            Look: match the original's medium and finish exactly. No watermarks.
            """#
        ),
        AdTool(
            id: "ad-multiply",
            name: L("Ad Multiplier"),
            subtitle: L("An ad that works, remade with one thing changed: the product, outfit, place or person."),
            symbol: "square.on.square.dashed",
            options: [
                    AdOptionGroup(title: L("What to swap"), values: ["Product", "Outfit", "Location", "Person"],
                                  labels: ["Product": L("Product (yours replaces theirs)"),
                                           "Outfit": L("Outfit (the person wears it)"),
                                           "Location": L("Location (new place, same shot)"),
                                           "Person": L("Person (same pose and framing)")]),
                    AdOptionGroup(title: L("Text from the reference ad"), values: ["Keep the text", "Remove the text", "Use my text"], style: .segmented),
                ],
            text: AdTextField(title: L("Your text (one per line, biggest first)"), placeholder: L("e.g. Glow that lasts · 30% off today"),
                              isLiteral: true, pipeSeparated: true,
                              appliesWhen: AdCondition(group: 1, values: ["Use my text"], typingTurnsOn: true)),
            usesPerson: false,
            needsReference: true,
            example: [0: "Product", 1: "Keep the text"],
            extraHint: L("e.g. a beach at sunset instead of the city street"),
            kind: .multiply,
            takesProduct: false,
            inputGroups: [0],
            whenToUse: L("Remake an ad that works — use Static Ad to start from scratch."),
            referenceTitle: L("The ad that works"),
            referenceHint: L("An ad you own or have rights to use"),
            referenceMissing: L("Add the ad that works"),
            aspect: .auto,
            model: "nano-banana-pro",
            recipe: #"""
            Image 1 is a winning ad that the user owns or has the rights to use. Any images after it show the new {swap} to swap in.
            Make a new version of this ad that changes only one thing: the {swap}. Keep everything else identical to Image 1: the composition, camera angle, crop and framing, poses and expressions, lighting and color grade, background design, graphic elements, layout grid and typography.
            Swap rules. Product: replace the ad's product completely with the exact product from Image 2, reproducing its silhouette, proportions, colors, materials, label layout, logo and every printed word, all legible, at a believable scale, in the same position and the same hand pose; no trace of the original product, its packaging or its branding may remain. Outfit: dress the person in the exact outfit from Image 2, with the same cut, fit, drape, fabric, color, pattern, hardware and logos, keeping their face, body, pose and the rest of the scene. Location: move the scene into the place shown in Image 2, or the place described in the additional direction if no image of it is attached, matching its light and perspective, and keep the subject, product, pose and all graphic elements in place. Person: replace the person with exactly the person in Image 2 and any further person photos (same face and facial structure, skin tone, hair, age and body type, not beautified), keeping the original pose, expression, outfit and framing.
            Text: {option2}. Keep the text: keep every word of the ad's text exactly as it is, in the same positions and typefaces; if the product is swapped, remove only words that name the old product or its brand. Remove the text: erase every word, logo and badge and leave clean design space. Use my text: replace the ad's text with this copy, spelled exactly as written, keeping the original hierarchy, sizes and positions: "{text}". Lines separated by "|" fill the text blocks from most to least prominent; leave any unused blocks empty. Never invent prices, claims, ratings or reviews.
            Look: match the original's medium. If it is a photograph, the result must look like a real photograph, with natural skin, real light and true-to-life color, not a glossy AI render. No watermarks.
            """#
        ),
    ]

    static let formatGroup = AdOptionGroup(
        title: L("Format"), values: ["Headline hero", "Benefit bullets", "Us vs. them", "Problem → solution", "Offer / price"],
        labels: ["Headline hero": L("Big headline (with the product)"),
                 "Benefit bullets": L("Benefit list (3–4 with ✓)"),
                 "Us vs. them": L("Us vs. them (comparison)"),
                 "Offer / price": L("Offer (with a price sticker)")])

    static let angleGroup = AdOptionGroup(
        title: L("Scene angle"), values: ["Benefit", "Pain point", "Real-life use", "Ingredient or material", "Lifestyle moment"],
        style: .chips)

    static func sizeGroup(_ title: String, style: AdOptionGroup.Style) -> AdOptionGroup {
        AdOptionGroup(title: title, values: ["9:16", "1:1", "4:5", "16:9"], style: style,
                      labels: ["9:16": L("9:16 (stories and reels)"), "1:1": L("1:1 (square feed)"),
                               "4:5": L("4:5 (tall feed)"), "16:9": L("16:9 (wide: YouTube and web)")],
                      allowsMany: true)
    }

    static let supportingField = AdTextField(
        title: L("Supporting text (optional, one per line)"), placeholder: L("e.g. Vegan · Fragrance-free · Shop now, one per line"),
        isLiteral: true, pipeSeparated: true,
        placeholders: ["Benefit bullets": L("e.g. 3–4 short benefits, one per line"),
                       "Us vs. them": L("e.g. the comparison rows, one per line"),
                       "Offer / price": L("e.g. the offer, then the call to action, one per line")])

    static let staticAdRecipe = #"""
    Image 1 is the product (further product photos may follow). The person reference photo(s), if any, come next.
    Design a finished static ad for Meta, TikTok and Google placements. Format: {option}. Scene angle: {option2}.
    Format rules. Headline hero: one large headline above or beside a dominant product photo. Benefit bullets: the product photo with three or four short benefit lines, each with a simple check icon. Us vs. them: a split layout with this product on one side and a generic alternative on the other. The alternative is plain, unbranded and label-free, and resembles no real brand. Matching rows of check and cross marks compare the two. Problem → solution: the problem appears on one side or at the top, and the product appears as the solution on the other side. Offer / price: a product hero with a bold offer sticker or burst.
    Scene angle rules. Benefit: the product delivering its main benefit. Pain point: the everyday frustration the product solves. Real-life use: hands or a person using it in a real setting. Ingredient or material: the product with its key raw ingredients or materials arranged around it. Lifestyle moment: the product in an aspirational everyday moment.
    Product: reproduce it exactly, with the same silhouette, proportions, colors, materials, label layout, logo and every printed word, sharp and legible. Do not redesign, relabel or add claims to the pack. If a person reference is attached, keep that person's exact face, skin tone, hair, age and body type.
    Copy: render only this copy, spelled exactly as written. Headline: "{text}". Supporting lines, separated by "|" (bullets, comparison rows, offer or call to action, as the format needs): "{text2}". Do not invent any other words, prices, percentages, ratings, claims, badges, URLs or logos. If a field is empty, render nothing for it. If both are empty, leave clean negative space where the copy would go and render no text.
    Design: a clear hierarchy (headline, product, supporting lines, call to action). Use one bold sans-serif display face and one simple text face, with high contrast, legibility at phone size and generous margins. Draw a restrained palette from the product's own label colors. In 9:16, keep all text out of the top 14% and the bottom 20% of the frame.
    Any photography inside the ad looks like a real photo, with true-to-life color, real light and shadows, and natural skin if a person appears. No CGI or glossy AI look. No watermarks.
    """#
}
