import Foundation
import SwiftUI

struct StylePreset: Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let summary: String
    let prompt: String
    var isFeatured = false

    var thumbnailURL: URL? {
        Bundle.main.url(forResource: id, withExtension: "heic", subdirectory: "Presets")
    }

    var symbol: String { StylePresets.symbols[category] ?? "paintpalette" }
}

enum StylePresets {
    static let allCategory = L("All")
    static let featuredCategory = L("Featured")

    static let categories = [L("Camera"), L("TikTok Core"), "Instagram", L("Beauty"), L("Fashion"), L("Places"), L("Mood"), L("Surreal"), L("Graphic art"), L("Mixed media"), L("Moodboards")]
    static var categoryNames: [String] { [allCategory, featuredCategory] + categories }

    static let symbols: [String: String] = Dictionary([
        (L("Camera"), "camera"), (L("TikTok Core"), "music.note"), ("Instagram", "camera.aperture"), (L("Beauty"), "face.smiling"),
        (L("Fashion"), "tshirt"), (L("Places"), "map"), (L("Mood"), "cloud.sun"), (L("Surreal"), "eye"), (L("Graphic art"), "paintbrush"),
        (L("Mixed media"), "square.3.layers.3d"), (L("Moodboards"), "square.grid.3x3.square"),
    ], uniquingKeysWith: { first, _ in first })

    static func preset(_ id: String) -> StylePreset? { all.first { $0.id == id } }

    static var featured: [StylePreset] { all.filter(\.isFeatured) }

    static func filtered(category: String, search: String) -> [StylePreset] {
        var list: [StylePreset] = switch category {
        case allCategory: all
        case featuredCategory: featured
        default: all.filter { $0.category == category }
        }
        if !search.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.summary.localizedCaseInsensitiveContains(search) }
        }
        return list
    }

    private static func p(_ id: String, _ name: String, _ category: String, _ summary: String, _ prompt: String, featured: Bool = false) -> StylePreset {
        StylePreset(id: id, name: name, category: category, summary: summary, prompt: prompt, isFeatured: featured)
    }

    static let all: [StylePreset] = [
        p("general", L("General"), L("Camera"), L("Clean, balanced and natural."), "clean, balanced, natural photograph with true-to-life color and soft light."),
        p("realistic", L("Realistic"), L("Camera"), L("No filters: pores and fabrics as they are."), "unfiltered true-to-life photo, visible skin pores and real fabric texture, no retouching, natural color.", featured: true),
        p("iphone", "iPhone", L("Camera"), L("Natural light, casual framing, soft HDR."), "shot on an iPhone, natural light, casual framing, soft smartphone HDR glow, slightly imperfect candid composition.", featured: true),
        p("digicam", L("Digicam"), L("Camera"), L("Harsh flash, date in the corner, 2007 texture."), "2007 compact digital camera photo, harsh direct flash, orange date stamp in the corner, raw low-dynamic-range texture.", featured: true),
        p("cctv", "CCTV", L("Camera"), L("Grainy, raw security camera."), "grainy CCTV security camera still, high-angle wide lens, desaturated greenish tint, timestamp overlay, low resolution noise."),
        p("half-selfie", L("0.5 selfie"), L("Camera"), L("Half-body wide-angle selfie."), "0.5x ultra-wide front camera selfie, half body, strong wide-angle perspective, real-life light."),
        p("half-outfit", L("0.5 outfit"), L("Camera"), L("From the waist down, wide-angle."), "0.5x ultra-wide shot from the waist down showing the outfit, wide-angle distortion, candid street feel."),
        p("fisheye", L("Fisheye"), L("Camera"), L("Exaggerated depth and a stretched background."), "fisheye lens photo, exaggerated depth, face close to the lens, curved stretched background.", featured: true),
        p("360cam", L("360 camera"), L("Camera"), L("Immersive wrap-around distortion."), "360 camera tiny-planet wrap-around distortion, immersive spherical perspective."),
        p("2000s-cam", L("2000s camera"), L("Camera"), L("Turn-of-the-century paparazzi glam."), "early-2000s paparazzi point-and-shoot photo, on-camera flash, low-rise fashion, rhinestones, slight motion blur."),
        p("90s-grain", L("90s grain"), L("Camera"), L("Warm tones, film texture."), "1990s 35mm film photo, warm tones, visible film grain, soft focus, light leaks."),
        p("photo-booth", L("Vintage photo booth"), L("Camera"), L("Photo booth strip with flash and glare."), "vintage photo booth strip, flash-lit, grainy black-and-white or faded color, glare, four frames."),
        p("disposable", L("Disposable cam"), L("Camera"), L("Strong flash and saturated disposable-camera colors."), "disposable camera photo, strong flash falloff, saturated colors, soft vignette, 400 ISO grain."),
        p("movie", L("Movie"), L("Camera"), L("Cinematic film still."), "cinematic film still, anamorphic lens, shallow depth of field, color graded like a feature film, 2.39:1 framing feel."),
        p("street-view", "Street View", L("Camera"), L("Street-level map view."), "street-level map camera capture, wide 360 panorama look, slightly blurred faces, overcast daylight, GPS UI feel."),

        p("y2k", "Y2K", L("TikTok Core"), L("Gloss, glitter, baby tees and flip phones."), "Y2K aesthetic, glossy lips, glitter, baby tee, flip phone, butterfly clips, pink and chrome palette.", featured: true),
        p("y2k-posters", L("Y2K posters"), L("TikTok Core"), L("Chrome text, airbrushed skin."), "Y2K teen-magazine poster, chrome bubble text, airbrushed skin, floating objects, bedroom-wall collage."),
        p("bimbocore", "Bimbocore", L("TikTok Core"), L("Hyper-feminine: glossy lips, miniskirts."), "bimbocore hyper-feminine look, glossy lips, pink everything, tiny skirts, flash photography."),
        p("indie-sleaze", "Indie sleaze", L("TikTok Core"), L("Flash chaos and smudged eyeliner."), "indie sleaze 2009 party photo, direct flash chaos, smudged eyeliner, messy hair, Tumblr-era nightlife."),
        p("tumblr", "Tumblr", L("TikTok Core"), L("GIF-like grain, bluish melancholy."), "2012 Tumblr aesthetic, grainy soft blur, blue-toned melancholy, pastel grunge."),
        p("coquette", "Coquette", L("TikTok Core"), L("Soft focus, lace, bows, blush."), "coquette core, soft focus, lace, satin bows, blush pink tones, delicate romantic styling."),
        p("grunge", "Grunge", L("TikTok Core"), L("Worn denim, flannel, messy hair."), "90s grunge, distressed denim, flannel shirt, messy hair, moody desaturated film look."),
        p("gorpcore", "Gorpcore", L("TikTok Core"), L("Technical outdoor gear as fashion."), "gorpcore fashion, technical outdoor jackets, trail shoes, utility gear styled as streetwear, mountain backdrop."),
        p("afterparty", L("Afterparty"), L("TikTok Core"), L("Party aftermath with direct flash."), "after-party aftermath photo, direct flash, confetti and empty glasses, candid tired glamour."),
        p("birthday-mess", L("Chaotic birthday"), L("TikTok Core"), L("Cake, confetti and flash."), "chaotic birthday party, cake smeared, confetti, balloons, harsh flash, joyful mess."),
        p("elevator-mirror", L("Elevator mirror"), L("TikTok Core"), L("Selfie in the elevator mirror."), "mirror selfie in a metallic elevator, phone covering part of the face, fluorescent light, outfit check."),

        p("sunset-beach", L("Sunset beach"), "Instagram", L("Purple-to-peach sky, backlit."), "sunset beach, purple-to-peach gradient sky, backlit golden glow, wind in the hair.", featured: true),
        p("flight-mode", L("Airplane mode"), "Instagram", L("Airports and terminals: the main character takes off."), "airport terminal travel shot, main-character energy, suitcase, big windows with planes, soft daylight.", featured: true),
        p("amalfi", L("Amalfi summer"), "Instagram", L("Lemon light, linen and cobblestones."), "Amalfi coast summer, lemon trees, linen outfits, cobblestones, Mediterranean sun."),
        p("sunbathing", L("Sunbathing"), "Instagram", L("Turquoise water, woven bags, towels."), "sunbathing by turquoise water, woven bag, striped towel texture, high summer sun."),
        p("japandi", "Japandi", "Instagram", L("Warm minimalism and natural light."), "Japandi interior, warm minimalism, light oak, linen, soft natural light, calm composition."),
        p("self-care", L("Self-care"), "Instagram", L("Candles, skincare, robes, soft tones."), "self-care evening, candles, skincare products, bathrobe, muted warm tones, cozy bathroom."),
        p("quiet-luxury", L("Quiet luxury"), "Instagram", L("Understated old-money neutrals."), "quiet luxury old-money style, cashmere and tailored neutrals, understated elegance, soft daylight.", featured: true),
        p("its-french", L("Very French"), "Instagram", L("Parisian chic."), "Parisian chic, striped top, red lipstick, café terrace, Haussmann buildings, effortless style."),
        p("night-beach", L("Night beach"), "Instagram", L("Moonlit waves, silhouettes."), "night beach, moonlit waves, silhouettes, flash on subject, deep blue ambience."),
        p("eating-food", L("Eating"), "Instagram", L("Candid close-up of someone eating."), "candid close-up of someone eating, messy and fun, flash, food in focus."),

        p("babydoll", L("Babydoll makeup"), L("Beauty"), L("Lashes, pout, porcelain skin."), "babydoll makeup, doll lashes, pouty lips, porcelain skin, soft pink blush, beauty close-up."),
        p("glazed-skin", L("Glazed skin"), L("Beauty"), L("Glass skin, dewy effect."), "glazed doll skin makeup, glass-like dewy highlight, beauty macro close-up, soft studio light."),
        p("bleached-brows", L("Bleached brows"), L("Beauty"), L("Nearly invisible brows, alien glam."), "bleached eyebrows, alien glam editorial makeup, high-fashion beauty portrait."),
        p("object-makeup", L("Object makeup"), L("Beauty"), L("Collage with an object below and makeup above."), "editorial collage: makeup look above, matching object below, playful beauty concept."),
        p("nail-check", L("Nail check"), L("Beauty"), L("Close-up of hands with nail art and rings."), "close-up of hands showing intricate nail art and rings, glossy, beauty macro."),
        p("ring-selfie", L("Ring selfie"), L("Beauty"), L("Manicured hands, glossy lips, sparkle."), "close selfie with manicured hands and rings near glossy lips, flash catching the sparkle."),
        p("hair-clips", L("Hair clips"), L("Beauty"), L("Chunky or pearl clips framing the face."), "chunky and pearl hair clips framing the face, playful beauty portrait, soft light."),
        p("grillz", L("Grillz selfie"), L("Beauty"), L("Flash close-up of shiny grillz."), "flash-heavy close-up smile showing shiny diamond grillz, underground luxury vibe."),

        p("tokyo-street", L("Tokyo fashion"), L("Fashion"), L("Layers and fearless color."), "Tokyo street style, layered avant-garde outfit, bold colors, Harajuku street backdrop, candid editorial.", featured: true),
        p("90s-editorial", L("90s editorial"), L("Fashion"), L("Retro fashion magazine, grain and moody color."), "1990s fashion magazine editorial, film grain, moody color, minimal set, supermodel attitude."),
        p("2000s-fashion", L("2000s fashion"), L("Fashion"), L("Shiny Y2K looks, low-rise."), "2000s fashion, shiny low-rise outfits, tinted sunglasses, metallic fabrics."),
        p("fashion-show", L("Fashion show"), L("Fashion"), L("Backstage flash, runway energy."), "fashion show runway and backstage flash photography, models in motion, audience bokeh."),
        p("burgundy-suit", L("Burgundy suit"), L("Fashion"), L("Monochrome burgundy tailoring."), "monochrome burgundy tailored suit, matching backdrop, sharp editorial lighting."),
        p("green-editorial", L("Green editorial"), L("Fashion"), L("Fashion editorial in shades of green."), "green-toned fashion editorial, emerald set and wardrobe, painterly light."),
        p("bike-mafia", L("Bike mafia"), L("Fashion"), L("Biker gang editorial."), "motorcycle crew editorial, leather jackets, chrome bikes, night street, cinematic flash."),
        p("long-legs", L("Long legs"), L("Fashion"), L("Elongated limbs, runway drama."), "low-angle fashion shot elongating the legs, runway drama, minimal background."),
        p("shoe-check", L("Shoe check"), L("Fashion"), L("Footwear focus, from above or at ground level."), "footwear-focused shot, top-down or ground-level, sneakers or heels in sharp focus."),
        p("sitting-street", L("Sitting on the street"), L("Fashion"), L("Relaxed pose, gritty city."), "sitting on the curb in the city, laid-back pose, urban grit, natural daylight."),
        p("crossing-street", L("Crossing the street"), L("Fashion"), L("Overhead angle, hard shadows, confident stride."), "overhead shot crossing a zebra crossing, harsh midday shadows, mid-stride boss walk."),
        p("escalator", L("Escalator"), L("Fashion"), L("Mall paparazzi, steel."), "mall escalator paparazzi shot, steel gradients, frozen motion, stylish outfit."),

        p("mt-fuji", L("Mount Fuji"), L("Places"), L("Postcard surrealism and konbini."), "Mount Fuji postcard view with a Japanese convenience store in front, clear sky, surreal travel snapshot.", featured: true),
        p("gallery", L("Gallery"), L("Places"), L("Neutral walls, the subject as artwork."), "minimal art gallery, neutral white walls, subject framed like an artwork, soft museum light."),
        p("library", L("Library"), L("Places"), L("Cozy academia, soft indoor light."), "cozy dark academia library, wooden shelves, warm lamps, soft indoor light."),
        p("subway", L("Subway"), L("Places"), L("Candid on the subway."), "candid subway car photo, fluorescent light, motion blur outside windows, urban commute."),
        p("office-beach", L("Office at the beach"), L("Places"), L("Suits and sand, sun-bleached light."), "people in office suits on a sunny beach, surreal corporate humor, sun-bleached colors."),
        p("sand", L("Dunes"), L("Places"), L("Windswept dunes, survivalist couture."), "windswept desert dunes, neutral survivalist couture, vast sweeping scale, warm low sun."),
        p("swords-hill", L("Hill of swords"), L("Places"), L("High fantasy on the hillside: capes and steel."), "high-fantasy mountain slope, capes and steel swords, towering storm clouds, cinematic wide shot."),
        p("medieval", L("Medieval"), L("Places"), L("Chainmail, velvet and candles."), "medieval scene, chainmail and velvet, candlelight, stone castle interior."),
        p("hallway-noir", L("Noir hallway"), L("Places"), L("Noir lighting in a corridor."), "film noir hallway, venetian-blind shadows, single hard light, smoky atmosphere."),
        p("505room", L("Room 505"), L("Places"), L("Melancholy hotel room."), "moody hotel room at night, tungsten lamp, unmade bed, cinematic loneliness."),
        p("tokyo-drift", L("Tokyo drift"), L("Places"), L("JDM night with neon."), "JDM night street racing, neon signs, wet asphalt, tuned cars, long exposure light trails."),
        p("night-rider", L("Night rider"), L("Places"), L("Night ride with light trails."), "night ride on a motorcycle, city light trails, motion blur, cinematic."),

        p("spotlight", L("Spotlight"), L("Mood"), L("Hard direct light, paparazzi flash."), "hard direct spotlight on the subject, deep black background, paparazzi flash intensity."),
        p("foggy-morning", L("Foggy morning"), L("Mood"), L("Muted, blurry horizons."), "foggy morning, muted colors, blurred horizon, quiet atmosphere."),
        p("rainy-day", L("Rainy day"), L("Mood"), L("Reflections on wet pavement, sweaters."), "rainy day, wet pavement reflections, umbrellas, cozy sweaters, cool tones.", featured: true),
        p("overexposed", L("Overexposed"), L("Mood"), L("Blown-out whites and crushed detail."), "overexposed photo, blown-out whites, crushed detail, dreamy high-key look."),
        p("through-glass", L("Through the glass"), L("Mood"), L("Shot through fogged-up windows."), "shot through a fogged window with condensation and reflections, intimate mood."),
        p("avant-garde", L("Avant-garde"), L("Mood"), L("Sculptural shapes, bold silhouettes."), "avant-garde fashion, sculptural shapes, bold silhouettes, gallery-like set."),
        p("fairycore", L("Fairycore"), L("Mood"), L("Glittery woodland and pastels."), "fairycore, glittery woodland, pastel tones, flowers and soft magical light."),
        p("2049", "2049", L("Mood"), L("Sci-fi dystopia in an orange haze."), "orange-haze sci-fi dystopia, brutalist structures, dust in the air, Blade Runner 2049 color."),
        p("nicotine-glow", L("Night glow"), L("Mood"), L("Warm, smoky nighttime glow."), "smoky warm night glow, tungsten and neon, intimate bar atmosphere."),
        p("static-glow", L("Static glow"), L("Mood"), L("CRT TV glow with static."), "CRT television glow, static noise, retro living room, blue light on face."),
        p("clouded-dream", L("Clouded dream"), L("Mood"), L("Dreamlike landscape among the clouds."), "dreamy cloudscape, soft pastel sky, floating ethereal feeling."),
        p("sea-breeze", L("Sea breeze"), L("Mood"), L("Coastal and breezy."), "breezy coastal day, white linen, wind, bright soft sunlight."),

        p("giant-accessory", L("Giant accessory"), L("Surreal"), L("One object at a surreal scale."), "one accessory blown up to giant surreal scale next to the subject, playful editorial."),
        p("duplicate", L("Duplicated"), L("Surreal"), L("Repeated or mirrored figures."), "the same person duplicated several times in one frame, surreal symmetry."),
        p("creatures", L("Creatures"), L("Surreal"), L("Animal details fused with the human form."), "surreal fashion with animal-like details fused with the human figure."),
        p("angel-wings", L("Angel wings"), L("Surreal"), L("Soft, delicate wings, weightlessness."), "soft delicate angel wings, weightless ethereal light, dreamy portrait."),
        p("giant-people", L("Giant people"), L("Surreal"), L("A giant subject in a miniature world."), "giant person in a miniature city, tilt-shift perspective, playful scale."),
        p("too-big", L("It's huge!"), L("Surreal"), L("Humor with oversized objects."), "humorous oversized everyday object dwarfing the subject."),
        p("red-balloon", L("Red balloon"), L("Surreal"), L("Red balloon motif."), "a single red balloon as the focal motif, muted surroundings, poetic mood."),
        p("fireproof", L("Fireproof"), L("Surreal"), L("Editorial with fire and flames."), "fire editorial, flames around the calm subject, dramatic warm light."),

        p("invertethereal", L("Inverted ethereal"), L("Graphic art"), L("Negative tones, ghostly hues."), "inverted negative tones, ghostly ethereal hues, photographic negative effect."),
        p("mixed-media", L("Mixed media"), L("Graphic art"), L("Collage of photo, paint and text."), "mixed-media collage combining photo, paint strokes and typography."),
        p("paper-face", L("Paper face"), L("Graphic art"), L("A face in torn-paper collage."), "face collaged from torn paper pieces, handmade texture."),
        p("pixel-face", L("Pixel face"), L("Graphic art"), L("Retro pixelated face, early internet."), "retro pixelated face, early-internet low-res mosaic effect."),
        p("glitch", L("Glitch"), L("Graphic art"), L("Pixel sorting, color distortion."), "digital glitch art, pixel sorting, RGB split, noise.", featured: true),
        p("graffiti", L("Graffiti"), L("Graphic art"), L("Spray-paint texture and bold color."), "graffiti spray-paint texture, bold colors, urban wall art."),
        p("geominimal", L("Geominimal"), L("Graphic art"), L("Clean lines and overlaid geometry."), "clean geometric overlays, minimal lines, Swiss design composition."),
        p("artwork", L("Artwork"), L("Graphic art"), L("Framed painterly still life."), "framed painterly still life, oil painting texture, museum quality."),
        p("aphex", L("Distortion"), L("Graphic art"), L("Distorted, eerie realism."), "distorted eerie realism, uncanny grin, Aphex Twin album art vibe."),

        p("double-take", L("Double take"), "Instagram", L("Caught looking back over the shoulder."), "candid street photo caught mid double take, looking back over the shoulder at the camera, slight motion blur, passers-by in the background."),
        p("rhyme-blues", L("Rhyme & blues"), L("Mood"), L("Late-90s R&B video: blue light and satin."), "late-90s R&B music video look, moody blue and purple light, satin and denim styling, glossy lips, soft haze."),
        p("dmv", L("ID photo"), L("Camera"), L("Flat, harsh ID-photo flash."), "flat front-facing ID-photo style portrait, harsh on-camera flash, plain blue-gray backdrop, deadpan expression, no card and no text."),
        p("fisheye-twin", L("Fisheye twin"), L("Surreal"), L("Two of you leaning into a fisheye lens."), "fisheye lens shot with two identical copies of the same person leaning into the lens together, exaggerated wide-angle distortion, playful mood."),
        p("chrome-exit", L("Chrome exit"), L("Fashion"), L("Futuristic chrome and silver."), "stepping out of a mirror-chrome car, reflective silver surfaces and styling, cool futuristic light, editorial pose."),
        p("brick-shade", L("Brick shade"), "Instagram", L("Hard shadows on a sunlit brick wall."), "posing against a sunlit red brick wall, hard leaf and window shadow patterns across the body, warm afternoon light."),
        p("blackout-fit", L("Blackout fit"), L("Fashion"), L("All black, low-key light."), "all-black monochrome outfit, black backdrop, low-key side light carving out the silhouette, sleek editorial mood."),
        p("cocktail", L("Cocktail"), L("Places"), L("Evening glamour at a cocktail bar."), "glamorous cocktail bar scene holding a cocktail, warm amber bar light, direct flash, glossy evening styling."),
        p("mount-view", L("Mountain view"), L("Places"), L("A lookout over a vast valley."), "standing at a mountain lookout above a vast valley, crisp clear air, layered peaks, bright outdoor adventure light."),
        p("sunburnt", L("Sunburnt"), L("Mood"), L("Harsh summer sun and sun-kissed skin."), "harsh midday summer sun, sun-kissed slightly reddened skin, squinting, warm faded film color, hazy heat."),
        p("mm-layers", L("Layered"), L("Mixed media"), L("Photo cutout over paper and paint layers."), "layered mixed-media artwork: the subject as a crisp photo cutout over painted paper, torn magazine scraps and pencil marks, visible layer edges and soft drop shadows."),
        p("mm-sketch", L("Sketch"), L("Mixed media"), L("The photo half redrawn in pencil and ink."), "mixed-media artwork: the photographed subject partly redrawn in loose graphite and ink lines, unfinished construction lines spilling onto white paper."),
        p("mm-canvas", L("Canvas"), L("Mixed media"), L("Printed on canvas with paint on top."), "mixed-media artwork on raw canvas: the photo printed onto coarse canvas weave, thick acrylic brushstrokes painted over the background."),
        p("mm-flash-comic", L("Flash comic"), L("Mixed media"), L("Ink outlines, halftone and a speed burst."), "mixed-media flash comic look: the photographed subject with bold black ink outlines, halftone dots and a bright speed-line burst behind them, punchy primary colors."),
        p("mm-overexposed", L("Overexposed collage"), L("Mixed media"), L("Bleached photo layers with ink accents."), "mixed-media artwork: blown-out overexposed photo layers, bleached highlights, white paper cutouts and a few sharp ink accents."),
        p("mm-paper", L("Paper cutout"), L("Mixed media"), L("Rebuilt from layered cut paper."), "mixed-media paper-craft artwork: the subject and scene rebuilt from layered cut and torn colored paper, visible paper fibers, soft shadows between layers."),
        p("mm-noir", L("Noir collage"), L("Mixed media"), L("Black and white with one red accent."), "mixed-media noir artwork: high-contrast black and white photo cutout, ink splatters, a single red accent, gritty paper texture."),
        p("mm-particles", L("Particles"), L("Mixed media"), L("Edges dissolving into glowing dust."), "mixed-media artwork: the subject's edges dissolving into drifting glowing particles and dust over a dark painted background."),
        p("mm-hand-paint", L("Hand-painted"), L("Mixed media"), L("Gouache brushstrokes over the photo."), "mixed-media artwork: the photo with visible hand-painted gouache strokes over the clothing and background, brush texture and paint drips."),
        p("mm-toxic", L("Toxic"), L("Mixed media"), L("Acid green, black and dripping shapes."), "mixed-media artwork: acid neon green and black palette, dripping slime shapes, halftone grit and a glowing outline around the subject."),
        p("mm-tracking", L("Tracking"), L("Mixed media"), L("Motion-tracking boxes and markers."), "mixed-media artwork styled like motion-tracking footage: thin white tracking boxes, crosshair markers and dotted motion paths over the photo, a technical overlay with no readable text."),
        p("mm-ultraviolet", L("Ultraviolet"), L("Mixed media"), L("Blacklight paint glowing in the dark."), "mixed-media blacklight artwork: deep violet darkness, fluorescent UV paint strokes glowing on the subject and background, neon pink and cyan."),
        p("mm-windows", L("Windows"), L("Mixed media"), L("Split into retro computer windows."), "mixed-media artwork: the scene split into overlapping retro computer window frames, each one showing a different crop of the subject, pixel borders, no readable text."),
        p("mm-acid", L("Acid graphic"), L("Mixed media"), L("Liquid chrome and warped grids."), "mixed-media acid graphic design: liquid chrome shapes, warped wireframe grids, high-contrast black, silver and lime, the subject as a sharp cutout."),
        p("mm-palette", L("Palette"), L("Mixed media"), L("Only three bold colors."), "mixed-media artwork limited to a bold three-color palette: flat color-blocked background, posterized subject, screen-print texture."),
        p("mm-comic", L("Comic"), L("Mixed media"), L("Inked outlines and dot shading."), "mixed-media comic-book artwork: inked outlines, cel shading, Ben-Day dot shading and flat colors over the photographed subject."),
        p("mm-acrylic", L("Acrylic"), L("Mixed media"), L("Thick acrylic paint over the photo."), "mixed-media acrylic painting: thick impasto strokes and palette-knife texture over a photographic base, vivid saturated color."),
        p("mm-two-color", L("Two color"), L("Mixed media"), L("Two inks only, risograph grain."), "mixed-media duotone artwork: the whole image in two inks only, deep blue and warm orange, risograph grain and slight misregistration."),
        p("mm-multiverse", L("Multiverse"), L("Mixed media"), L("Several copies in different styles."), "mixed-media artwork: the subject repeated in several overlapping offset copies, each in a different art style and color, layered like parallel versions of the same moment."),
        p("mm-fragments", L("Fragments"), L("Mixed media"), L("Shattered into shifted shards."), "mixed-media artwork: the image shattered into angular fragments shifted slightly out of place, each shard with its own texture and tint."),
        p("mm-origami", L("Origami"), L("Mixed media"), L("Folded paper with sharp creases."), "mixed-media origami artwork: the scene and background folded from crisp paper with sharp creases, the clothing echoing folded paper shapes."),
        p("mm-random-glow", L("Random glow"), L("Mixed media"), L("Glowing orbs and neon scribbles."), "mixed-media artwork: scattered soft glowing light orbs and neon scribbles drawn around the subject on a dreamy dark background."),
        p("mm-vintage", L("Vintage collage"), L("Mixed media"), L("Sepia cutout on aged paper."), "mixed-media vintage collage: a sepia photo cutout on aged paper with old postage stamps, ticket stubs and botanical engravings, worn edges, no readable text."),
        p("mm-leaves", L("Leaves"), L("Mixed media"), L("Layered green leaf cutouts."), "mixed-media artwork: lush layered cutouts of green leaves and botanical shapes framing the subject, deep greens with touches of gold."),
        p("mm-bubbles", L("Bubbles"), L("Mixed media"), L("Iridescent bubbles floating around."), "mixed-media artwork: iridescent soap bubbles and round glossy cutouts floating over the subject, pastel holographic sheen."),
        p("mm-magazine", L("Magazine collage"), L("Mixed media"), L("Made from torn magazine pieces."), "mixed-media magazine collage: the subject assembled from torn magazine pieces with mismatched color patches and glossy paper edges, no readable text."),
        p("mm-cold-vision", L("Cold vision"), L("Mixed media"), L("Icy thermal-camera colors."), "mixed-media artwork in a cold thermal-vision palette: icy blues and cyan, a glowing white outline around the subject, scan-line texture."),
        p("mm-modern", L("Modern"), L("Mixed media"), L("Clean shapes and bold color fields."), "mixed-media modern art: clean geometric shapes, bold color fields and thin line work layered around a crisp photo cutout of the subject."),
        p("mm-psychedelic", L("Psychedelic"), L("Mixed media"), L("Swirling rainbow patterns."), "mixed-media psychedelic artwork: swirling rainbow patterns, melting liquid shapes and kaleidoscope repeats radiating from the subject."),
        p("mm-broken-mirror", L("Broken mirror"), L("Mixed media"), L("Seen through shattered glass."), "mixed-media artwork: the subject seen through a shattered mirror, sharp cracks splitting the image into reflected, slightly misaligned pieces."),
        p("mm-lava", L("Lava"), L("Mixed media"), L("Molten cracks and glowing orange."), "mixed-media artwork: molten lava textures and glowing orange cracks flowing around the subject over black volcanic rock."),
        p("mm-marble", L("Marble"), L("Mixed media"), L("Veined marble and statue fragments."), "mixed-media artwork: the subject cut out over veined white and gold marble, classical statue fragments layered behind."),
        p("mm-ocean", L("Ocean"), L("Mixed media"), L("Wave cutouts and watercolor blues."), "mixed-media artwork: layered wave cutouts, watercolor sea blues and foam textures swirling around the subject."),
        p("mb-warm-ambient", L("Warm ambient"), L("Moodboards"), L("Warm, enveloping ambience."), "warm ambient interior light, amber tones, soft shadows, intimate editorial."),
        p("mb-y2k-studio", L("Y2K studio"), L("Moodboards"), L("Glossy neon studio with fairy wings."), "glossy neon Y2K studio set, fairy wings, iridescent props, high-shine lighting."),
        p("mb-swag-era", L("Swag era"), L("Moodboards"), L("Pink flash selfie from the 2010s."), "2010s swag era, pink tones, flash selfie, snapback and bold jewelry."),
        p("mb-theatrical", L("Theatrical light"), L("Moodboards"), L("Dark set with a hard spotlight."), "dark theatrical stage, single hard spotlight, dramatic chiaroscuro."),
        p("mb-y2k-street", L("Y2K street"), L("Moodboards"), L("Street with a Y2K aesthetic."), "Y2K street photography, tinted shades, cargo pants, early-2000s city."),
        p("mb-flash-editorial", L("Flash editorial"), L("Moodboards"), L("Editorial with direct flash."), "direct-flash fashion editorial, crisp shadows, glossy magazine look."),
        p("mb-old-smartphone", L("Old smartphone"), L("Moodboards"), L("Old cell phone photo."), "early smartphone photo, low resolution, oversharpened, muted colors."),
        p("mb-street", L("Street photography"), L("Moodboards"), L("Documentary street photography."), "documentary street photography, candid moment, 35mm, natural contrast."),
        p("mb-retro-bw", L("Retro BW"), L("Moodboards"), L("Retro black and white."), "retro black-and-white photograph, deep blacks, silver gelatin texture."),
        p("mb-asian-nostalgia", L("Asian nostalgia"), L("Moodboards"), L("Asian nostalgia on film."), "nostalgic East Asian film photo, 90s Hong Kong colors, soft halation."),
        p("mb-solarization", L("Surreal solarization"), L("Moodboards"), L("Surrealist solarization."), "surreal solarized photograph, partially inverted tones, Man Ray style."),
        p("mb-subtle-flash", L("Subtle flash"), L("Moodboards"), L("Subtle fill flash."), "subtle fill flash, natural ambient, clean modern editorial."),
        p("mb-digital-camera", L("Digital camera"), L("Moodboards"), L("Compact digital camera."), "compact digital camera look, crisp flash, mid-2000s colors."),
        p("mb-siren", L("Siren"), L("Moodboards"), L("Wet, in the water, siren."), "wet hair in water, mermaid siren mood, glistening skin, deep sea tones."),
        p("mb-mystique-city", L("Mystique city"), L("Moodboards"), L("Overcast, hooded figure, moody."), "overcast city, hooded figure, moody blue-gray palette, mysterious."),
        p("mb-candy-pop", L("Candy pop"), L("Moodboards"), L("Sweet pastel pink."), "candy pop pastel pink world, bubblegum props, bright even light."),
        p("mb-double-exposure", L("Double exposure"), L("Moodboards"), L("Double exposure."), "double exposure photograph blending portrait and landscape."),
        p("mb-2000s-band", L("2000s band"), L("Moodboards"), L("2000s band photo."), "2000s rock band promo photo, grungy alley, flash, attitude."),
        p("mb-frutiger-aero", "Frutiger aero", L("Moodboards"), L("Aqua and green tech optimism."), "Frutiger Aero aesthetic, glossy aqua and green, bubbles, clean tech optimism."),
        p("mb-drain", L("Drain"), L("Moodboards"), L("Dark drain gang street style."), "drain gang dark street style, washed-out night, grainy and moody."),
        p("mb-extraterrestrial", L("Extraterrestrial"), L("Moodboards"), L("Chrome alien futurism."), "chrome alien futurism, metallic skin highlights, otherworldly set."),
        p("mb-editorial-street", L("Editorial street style"), L("Moodboards"), L("Street style editorial."), "editorial street style shot, fashion week outside, long lens compression."),
        p("mb-nature-light", L("Nature light"), L("Moodboards"), L("Natural outdoor light."), "soft natural outdoor light, greenery, organic tones."),
        p("mb-new-indie", L("New Indie"), L("Moodboards"), L("Today's indie, warm and spontaneous."), "new indie aesthetic, warm candid snapshots, film-like colors."),
        p("mb-underwater", L("Underwater"), L("Moodboards"), L("Beneath the water."), "underwater photograph, caustic light patterns, floating fabric, blue depth."),
        p("mb-80s-horror", L("80s horror"), L("Moodboards"), L("Eighties horror."), "1980s horror movie still, red and blue gels, fog, VHS grain."),
        p("mb-disposable", L("Disposable camera"), L("Moodboards"), L("Disposable camera."), "disposable camera snapshot, flash falloff, warm saturated colors."),
        p("mb-neutral-pastel", L("Neutral pastel film"), L("Moodboards"), L("Neutral pastel film."), "neutral pastel film stock color grade, soft contrast, airy."),
        p("mb-warm-vivid", L("Warm vivid film"), L("Moodboards"), L("Warm, vivid film."), "warm vivid film stock, rich saturated reds and yellows."),
        p("mb-bw-film", L("BW film"), L("Moodboards"), L("Black-and-white film."), "black-and-white film stock, natural grain, classic contrast."),
        p("mb-warm-contrast", L("Warm contrast film"), L("Moodboards"), L("Warm, high-contrast film."), "warm high-contrast film look, deep shadows, golden highlights."),
        p("mb-muted-cool", L("Muted cool film"), L("Moodboards"), L("Cool, muted film."), "muted cool film stock, desaturated blues and greens, quiet mood."),
    ]
}

enum CinemaCamera {
    static let bodies: [(id: String, name: String, prompt: String)] = [
        ("auto", L("Auto"), ""),
        ("modern", L("Modern"), "shot on a modern digital cinema camera, clean high dynamic range"),
        ("35mm", L("35 mm film"), "shot on 35mm motion picture film, organic grain and halation"),
        ("8mm", L("8 mm film"), "shot on 8mm film, heavy grain, soft vignette, flickering exposure"),
        ("dv", L("DV camcorder"), "captured on a 2000s DV camcorder, interlaced video look, low resolution, timestamp feel"),
        ("modular-8k", L("Modular 8K digital"), "shot on a modular 8K digital cinema camera, extremely fine detail, clean low-noise shadows, wide dynamic range"),
        ("full-frame-cine", L("Full-frame cine digital"), "shot on a full-frame digital cinema camera, natural shallow depth of field, smooth highlight roll-off, rich skin tones"),
        ("70mm", L("Large-format 70 mm film"), "shot on 65mm large-format film for a 70mm print, immense detail, very fine grain, deep rich color"),
        ("s35-digital", L("Studio digital S35"), "shot on a Super 35 studio digital cinema camera, classic cinematic field of view, natural film-like color"),
        ("16mm", L("16 mm film"), "shot on 16mm film, visible organic grain, softer detail, gentle halation, documentary texture"),
        ("large-format-digital", L("Premium large-format digital"), "shot on a premium large-format digital cinema camera, expansive sense of space, creamy focus falloff, polished high-end color"),
        ("red-v-raptor", "RED V-Raptor", "shot on a RED V-Raptor 8K cinema camera, crisp punchy detail, vivid saturated color"),
        ("sony-venice", "Sony Venice", "shot on a Sony Venice cinema camera, soft natural skin tones, smooth gradations, clean low-light detail"),
        ("arri-alexa-35", "ARRI Alexa 35", "shot on an ARRI Alexa 35, filmic highlight roll-off, natural skin tones, gentle organic texture"),
        ("imax", L("IMAX film"), "shot on IMAX 15/70 film, monumental scale, extreme detail and clarity"),
        ("panavision-dxl2", "Panavision DXL2", "shot on a Panavision Millennium DXL2, large-format depth, warm polished cinematic color"),
    ]
    static let lenses: [(id: String, name: String, prompt: String)] = [
        ("auto", L("Auto"), ""),
        ("clean", L("Sharp"), "clean sharp spherical lens"),
        ("anamorphic", L("Anamorphic"), "anamorphic lens with oval bokeh and horizontal flares"),
        ("vintage-anamorphic", L("Vintage anamorphic"), "vintage anamorphic lens, soft edges, blue streak flares"),
        ("warm-vintage", L("Warm vintage"), "warm vintage glass, gentle softness and low contrast"),
        ("halation", L("Vintage halation"), "vintage lens with strong halation glow around highlights"),
        ("creative-tilt", L("Creative tilt"), "tilt-shift lens, a thin slanted plane of focus with blurred edges, miniature-like feel"),
        ("compact-anamorphic", L("Compact anamorphic"), "compact anamorphic lens, subtle oval bokeh and gentle horizontal flares, slight edge softness"),
        ("extreme-macro", L("Extreme macro"), "extreme macro lens, life-size close focus, razor-thin depth of field, micro textures visible"),
        ("70s-prime", L("70s cinema prime"), "1970s cinema prime lens, soft contrast, warm veiling flare, gentle vignette"),
        ("classic-anamorphic", L("Classic anamorphic"), "classic anamorphic lens, oval bokeh, blue horizontal streak flares, gentle barrel distortion"),
        ("modern-prime", L("Modern prime"), "premium modern prime lens, crisp edge-to-edge sharpness, high contrast, clean smooth bokeh"),
        ("warm-prime", L("Warm cinema prime"), "warm cinema prime lens, creamy flattering skin tones, soft gentle contrast"),
        ("swirl-bokeh", L("Swirl bokeh portrait"), "swirl-bokeh portrait lens, sharp center with swirling, spinning background blur"),
        ("vintage-prime", L("Vintage prime"), "vintage prime lens, lower contrast, soft glow and characterful imperfect rendering"),
        ("halation-diffusion", L("Halation diffusion"), "diffusion filter over the lens, glowing halation around highlights, softened fine detail, dreamy bloom"),
        ("clinical-sharp", L("Clinical sharp prime"), "clinical sharp prime lens, maximum resolution and micro-contrast, no flare, neutral rendering"),
        ("petzval", "Petzval", "Petzval portrait lens, sharp center with strong swirling bokeh and soft falloff toward the edges"),
        ("jdc-xtal-xpress", "JDC Xtal Xpress", "JDC Xtal Xpress vintage anamorphic, warm oval bokeh and amber streak flares"),
        ("cooke-s4", "Cooke S4", "Cooke S4 prime, the warm, gentle Cooke look with flattering skin tones"),
        ("panavision-c-series", "Panavision C-Series", "Panavision C-Series anamorphic, classic 1970s blue streak flares and oval bokeh"),
        ("lensbaby", "Lensbaby", "Lensbaby selective-focus lens, a small sweet spot of focus with streaky blurred edges"),
        ("zeiss-ultra-prime", "Zeiss Ultra Prime", "Zeiss Ultra Prime, crisp neutral sharpness and high contrast"),
        ("helios", "Helios 44", "Helios 44 vintage lens, swirling bokeh and soft warm flare"),
        ("arri-signature-prime", "ARRI Signature Prime", "ARRI Signature Prime, smooth large-format rendering, gentle sharpness and creamy bokeh"),
        ("canon-k35", "Canon K-35", "Canon K-35 vintage prime, soft warm 1970s glow and low-contrast flare"),
        ("laowa-macro", L("Laowa macro probe"), "Laowa probe macro lens, bug's-eye close-up perspective with deep focus"),
        ("hawk-v-lite", "Hawk V-Lite", "Hawk V-Lite anamorphic, clean modern anamorphic look with oval bokeh and restrained flare"),
    ]
    static let focalLengths: [(id: String, name: String, prompt: String)] = [
        ("auto", L("Auto"), ""),
        ("8mm", L("8 mm (ultra-wide)"), "8mm ultra-wide focal length, strongly curved fisheye-like perspective"),
        ("14mm", L("14 mm (very wide)"), "14mm very wide focal length, expansive view, exaggerated depth and perspective"),
        ("24mm", L("24 mm (wide)"), "24mm wide focal length, environmental framing with natural depth"),
        ("35mm", L("35 mm (natural)"), "35mm focal length, natural cinematic perspective"),
        ("50mm", L("50 mm (standard)"), "50mm standard focal length, true-to-eye perspective, gentle background separation"),
        ("85mm", L("85 mm (portrait)"), "85mm portrait focal length, flattering compression, softly blurred background"),
    ]
    static let apertures: [(id: String, name: String, prompt: String)] = [
        ("auto", L("Auto"), ""),
        ("f1.4", L("f/1.4 (blurry background)"), "aperture f/1.4, very shallow depth of field, background melted into creamy bokeh"),
        ("f4", L("f/4 (balanced)"), "aperture f/4, moderate depth of field, background softly recognizable"),
        ("f11", L("f/11 (everything sharp)"), "aperture f/11, deep focus, foreground and background both sharp"),
    ]

    static func prompt(body: String, lens: String, focalLength: String = "auto", aperture: String = "auto") -> String? {
        let parts = [bodies.first { $0.id == body }?.prompt, lenses.first { $0.id == lens }?.prompt,
                     focalLengths.first { $0.id == focalLength }?.prompt, apertures.first { $0.id == aperture }?.prompt]
            .compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

struct ColorPalette: Identifiable, Hashable {
    let id: String
    let name: String
    let hexes: [String]

    var colors: [Color] { hexes.map { Color(hex: $0) } }

    var prompt: String {
        let tagged = hexes.map { "\(Self.name(forHex: $0)) hex \($0)" }
        guard let dominant = tagged.first else { return "" }
        var roles = ["dominant \(dominant)"]
        if tagged.count > 1 { roles.append("secondary \(tagged[1])") }
        if tagged.count > 2 { roles.append("accents " + tagged.dropFirst(2).joined(separator: ", ")) }
        return "Color palette: \(roles.joined(separator: "; ")). Apply these colors to the scene's surfaces, wardrobe, props and light, not as swatches or codes."
    }

    private static let names: [(name: String, value: UInt64)] = [
        ("black", 0x101010), ("dark gray", 0x2E2E2E), ("charcoal", 0x36454F), ("gray", 0x808080), ("silver", 0xC0C0C0),
        ("white", 0xF8F8F8), ("ivory", 0xF6F1E4), ("cream", 0xEFE3CC), ("beige", 0xD9C4A5), ("sand", 0xE3C389), ("tan", 0xC6A26E),
        ("taupe", 0x8B7D6B), ("brown", 0x7B4B2A), ("dark brown", 0x3D2817), ("rust", 0x9A4A2A), ("terracotta", 0xC4683F),
        ("burgundy", 0x800020), ("dark red", 0x8B0000), ("red", 0xD62828), ("coral", 0xFF7F50), ("orange", 0xF28C28),
        ("gold", 0xD4A62A), ("mustard", 0xD8B13A), ("yellow", 0xFFD93B), ("lime green", 0xB5E61D), ("olive green", 0x6B7F2A),
        ("sage green", 0x9CAF88), ("deep green", 0x2C3E32), ("forest green", 0x2F5D3A), ("green", 0x2E9B47), ("mint", 0xA8E6C1), ("teal", 0x1F7A7A),
        ("turquoise", 0x3FC1C9), ("pale aqua", 0xBFE6E6), ("sky blue", 0x87CEEB), ("steel blue", 0x4F7A99), ("navy", 0x1B2A4A),
        ("blue", 0x2563EB), ("indigo", 0x3F2A8C), ("lavender", 0xC8B6E6), ("purple", 0x7B2D9B), ("plum", 0x6E2A5C),
        ("magenta", 0xC0168F), ("hot pink", 0xFF4F9A), ("pink", 0xFF8FC7), ("pale pink", 0xFFD6E8),
    ]

    static func name(forHex hex: String) -> String {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
        func channels(_ value: UInt64) -> (Double, Double, Double) {
            (Double((value >> 16) & 0xFF), Double((value >> 8) & 0xFF), Double(value & 0xFF))
        }
        let (red, green, blue) = channels(value)
        func distance(_ other: UInt64) -> Double {
            let (otherRed, otherGreen, otherBlue) = channels(other)
            let mean = (red + otherRed) / 2, dr = red - otherRed, dg = green - otherGreen, db = blue - otherBlue
            return (2 + mean / 256) * dr * dr + 4 * dg * dg + (2 + (255 - mean) / 256) * db * db
        }
        return names.min { distance($0.value) < distance($1.value) }?.name ?? "color"
    }

    static let builtIn: [ColorPalette] = [
        ColorPalette(id: "film", name: L("Film colors"), hexes: ["#2E3B32", "#C8A46B", "#8C4A2F", "#E9DCC3", "#4F6D7A"]),
        ColorPalette(id: "lime-jam", name: L("Lime jam"), hexes: ["#C6F432", "#1E1E1E", "#F4F1E8", "#7A9E2E", "#FFD23F"]),
        ColorPalette(id: "candy-pink", name: L("Candy pink"), hexes: ["#FF8FC7", "#FFD1E8", "#FF4F9A", "#FFF4F9", "#B5179E"]),
        ColorPalette(id: "nostalgic-blue", name: L("Nostalgic blue"), hexes: ["#1D3557", "#457B9D", "#A8DADC", "#F1FAEE", "#E8C07D"]),
        ColorPalette(id: "soft", name: L("Soft palette"), hexes: ["#EADBC8", "#DAC0A3", "#F8F0E5", "#B8B5A8", "#8D7B68"]),
        ColorPalette(id: "black-gloss", name: L("Glossy black"), hexes: ["#0A0A0A", "#2B2B2B", "#C0C0C0", "#F5F5F5", "#8B0000"]),
    ]
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
