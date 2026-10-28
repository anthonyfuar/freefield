#!/usr/bin/env python3
import base64
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "Assets/Examples/options")
SOURCES = os.path.join(ROOT, "Sources/Freefield")
MODEL = "recraft/recraft-v4.1-flash"
BASELINE = 152.920804227
STOP = float(sys.argv[sys.argv.index("--stop") + 1]) if "--stop" in sys.argv else 4.85
ONLY = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else ""
KEYS = set(sys.argv[sys.argv.index("--keys") + 1].split(",")) if "--keys" in sys.argv else None
FORCE = "--force" in sys.argv
DRY = "--dry-run" in sys.argv

PHOTO = " Realistic photograph, natural colors, sharp focus. No text, no letters, no captions, no watermark, no logos."
PRODUCT = "a small amber glass skincare serum bottle with a black dropper cap and a plain cream label"
WOMAN = "a young woman with shoulder-length brown hair wearing an olive green sweater and jeans, standing in a sunlit city park"
MAN = "head-and-shoulders portrait of a man in his thirties with short dark hair and a light grey t-shirt"


OVERRIDES = {
    "ads/ugc-photo/shot-shot-by-a-friend": "A woman standing in her living room holding {p} toward the camera, photographed by a friend "
                                           "from about two meters away, waist-up, phone-camera look",
    "ads/product-shoot/style-color-pop": "Product photo of {p} on a bold, saturated solid orange background with a cobalt blue shadow",
    "ads/product-shoot/season-halloween": "Product photo of {p} surrounded by small carved pumpkins, autumn leaves and candles",
    "ads/product-shoot/season-valentines-day": "Product photo of {p} with red rose petals and small red paper hearts around it",
    "ads/product-shoot/season-black-friday": "Product photo of {p} on black wrapping paper with black gift boxes and a black shopping bag",
    "ads/unboxing/moment-box-just-arrived-sealed": "A closed, taped kraft shipping box lying on a doormat in front of a front door",
    "ads/unboxing/output-3-photo-sequence": "A collage of three photos side by side with thin white gaps: a closed kraft box, the box "
                                            "open with {p} inside, a woman smiling holding {p}",
    "ads/before-after/layout-top-and-bottom": "One image split horizontally: the top half a messy desk covered in papers, the bottom "
                                              "half the same desk clean and tidy",
    "ads/marketplace/cover-style-pastel": "Styled cover photo of {p} on soft pastel pink and mint green blocks, pastel background",
    "video/talkingAvatar-scene/cctv": "Grainy black-and-white security camera footage from a high ceiling corner, wide angle, a woman "
                                      "talking in a shop",
    "video/editVideo-restyle/vhs": "A woman walking a golden retriever on a city street, as an old VHS tape: scan lines, color bleeding, "
                                   "tracking noise, soft blurry colors",
    "video/editVideo-restyle/thermal-camera": "A woman walking a golden retriever on a city street, as a thermal camera image: "
                                              "false-color heat map, purple background, yellow and orange warm bodies",
    "video/editVideo-restyle/felt-stop-motion": "A woman walking a golden retriever on a city street, made of soft felt fabric puppets "
                                                "and felt buildings, stop-motion animation",
    "video/editVideo-restyle/toy-bricks": "A woman walking a golden retriever on a city street, everything built from plastic toy "
                                          "building bricks, minifigure style",
}
UGC_PLACES = {"bedroom": "her bedroom with the bed behind her", "bathroom": "a bathroom with the mirror and sink visible",
              "kitchen": "a kitchen with counters and cabinets visible", "living-room-couch": "sitting on a living room couch",
              "car-drivers-seat": "sitting in the driver's seat of a car, steering wheel visible", "gym": "a gym with weights "
              "and machines behind her", "office-desk": "at an office desk with a laptop", "street": "on a busy city sidewalk",
              "store-aisle": "in a supermarket aisle with shelves behind her"}
for place, words in UGC_PLACES.items():
    OVERRIDES[f"ads/ugc-photo/location-{place}"] = ("Medium-wide creator photo of a woman holding {p}, " + words +
                                                     ", the place clearly visible, phone-camera look")


def slug(text):
    text = text.lower().replace("'", "").replace("’", "")
    text = re.sub(r"[^a-z0-9]+", "-", text)
    return text.strip("-")


def read(relative):
    return open(os.path.join(SOURCES, relative), encoding="utf-8").read()


def manifest():
    items = []
    recipes = read("Model/Recipes.swift")
    for match in re.finditer(r'CameraAngle\(id: "([^"]+)".*?prompt: "([^"]+)"', recipes, re.S):
        items.append(("angles", match.group(1), f"Photo of {WOMAN}, {match.group(2)}" + PHOTO, "4:3"))
    for match in re.finditer(r'LightPreset\(id: "([^"]+)".*?prompt: "([^"]+)"', recipes, re.S):
        items.append(("light", match.group(1), f"{MAN}, lit with {match.group(2)}" + PHOTO, "4:3"))
    sessions = read("Views/PhotoSessionView.swift")
    for match in re.finditer(r'PhotoSessionSet\(id: "([^"]+)".*?scenes: \[\s*"([^"]+)"', sessions, re.S):
        person = "a young man" if "male" in match.group(1) else "a young woman"
        items.append(("sessions", match.group(1), f"Photo of {person}: {match.group(2)}." + PHOTO, "4:3"))
    storyboard = read("Views/StoryboardView.swift")
    for match in re.finditer(r'\("(\w+)", L\("[^"]+"\), L\("[^"]+"\), "[^"]+", "([^"]*)"\)', storyboard):
        style = match.group(2) or "rough pencil storyboard sketch on white paper"
        items.append(("storyboard", match.group(1), f"A girl in a yellow raincoat and her dog finding a treasure map in a "
                      f"colorful old town street, as {style}. No text, no letters, no watermark.", "16:9"))
    items += [
        ("background", "remove", f"Product cutout of {PRODUCT} on a pure white background with a faint gray checkerboard "
         "pattern showing transparency." + PHOTO, "4:3"),
        ("background", "replace", f"{PRODUCT} standing on wet sand at a sunny beach with waves behind." + PHOTO, "4:3"),
    ]
    items += ads()
    items += video()
    return items


AD_SCENES = {
    ("ugc-photo", "Shot"): "A woman taking a {v} photo of herself holding {p} in a bright bedroom, phone-camera look",
    ("ugc-photo", "Location"): "Casual creator photo of a woman holding {p}, in a {v}, phone-camera look",
    ("ugc-photo", "Light"): "Casual creator photo of a woman holding {p} at home, lit by {v}, phone-camera look",
    ("model-shoot", "Shot"): "Fashion model photo, {v}, wearing a cream knit sweater",
    ("model-shoot", "Environment"): "Fashion model wearing a cream knit sweater, setting: {v}",
    ("product-shoot", "Style"): "Product photo of {p}, style: {v}",
    ("product-shoot", "Surface"): "Product photo of {p} standing on a {v} surface",
    ("product-shoot", "Season"): "Product photo of {p} with subtle {v} decorations around it",
    ("unboxing", "Moment"): "Unboxing photo of {p} in a kraft shipping box: {v}",
    ("unboxing", "View"): "Unboxing photo of {p}, {v}",
    ("before-after", "Transformation"): "A before-and-after image split down the middle showing a {v}",
    ("before-after", "Layout"): "A before-and-after image of a messy then clean desk, arranged {v}",
    ("testimonial", "Moment"): "A smiling customer {v}, holding {p}, natural home setting",
    ("static-ad", "Scene angle"): "Advertising photo of {p} that shows the {v}",
    ("hook-frame", "Visual hook"): "Scroll-stopping social media photo with {p}: {v}",
    ("marketplace", "Image type"): "Online store product image of {p}: {v}",
    ("marketplace", "Cover style"): "Styled cover photo of {p}, {v} look",
}
AD_SKIP = {"None"}
AD_SPECIAL = {
    ("ugc-photo", "Shot", "Front-camera selfie"): "Front-camera selfie of a woman holding {p} up next to her face, arm stretched "
                                                  "out, phone-camera look",
    ("ugc-photo", "Shot", "Shot by a friend"): "Casual photo a friend took of a woman holding {p}, a few steps away, phone-camera look",
    ("ugc-photo", "Shot", "First-person POV (hands only)"): "First-person view looking down at two hands holding {p}, no face visible",
    ("ugc-photo", "Shot", "Mid-use candid"): "Candid photo of a woman putting a drop of {p} on her cheek, not looking at the camera",
    ("unboxing", "View", "POV hands only"): "First-person view of two hands opening a kraft box with {p} inside, no face visible",
    ("unboxing", "View", "Creator in frame"): "A woman sitting on her bed opening a kraft box with {p}, facing the camera",
    ("before-after", "Transformation", "Space (messy to clean)"): "One image split down the middle: on the left a messy cluttered "
                                                                  "bedroom, on the right the same bedroom tidy and clean",
    ("before-after", "Transformation", "Person (look or routine)"): "One image split down the middle: on the left a tired woman "
                                                                    "with messy hair, on the right the same woman fresh and groomed",
    ("before-after", "Transformation", "Object (worn to restored)"): "One image split down the middle: on the left a scuffed worn "
                                                                     "leather boot, on the right the same boot restored and polished",
    ("static-ad", "Scene angle", "Benefit"): "{p} next to a close-up of glowing, hydrated skin",
    ("static-ad", "Scene angle", "Pain point"): "A woman frowning at dry flaky skin in a bathroom mirror, {p} on the counter",
    ("static-ad", "Scene angle", "Real-life use"): "A woman applying {p} during her morning routine at the bathroom sink",
    ("static-ad", "Scene angle", "Ingredient or material"): "{p} surrounded by fresh aloe leaves and water droplets",
    ("static-ad", "Scene angle", "Lifestyle moment"): "{p} on a sunny breakfast table next to a coffee cup and an open book",
    ("hook-frame", "Visual hook", "Extreme close-up"): "Extreme macro close-up of a golden drop falling from the dropper of {p}",
    ("hook-frame", "Visual hook", "Shocked reaction"): "A woman with a shocked, amazed face holding {p}",
    ("hook-frame", "Visual hook", "Product mid-action"): "{p} with serum dripping from the dropper, frozen in motion",
    ("hook-frame", "Visual hook", "Unexpected angle"): "{p} seen from directly below through a glass table",
    ("hook-frame", "Visual hook", "Problem moment"): "A woman noticing a red pimple in the bathroom mirror, {p} nearby",
    ("unboxing", "Output", "Single photo"): "One unboxing photo of hands lifting {p} out of a kraft box",
    ("unboxing", "Output", "3-photo sequence"): "Three photos side by side as a sequence: a sealed kraft box, the box opening with {p} "
                                                 "half revealed, and a woman smiling holding {p}",
    ("marketplace", "Image type", "Multi-angle grid"): "A two-by-two grid showing {p} from four different angles on white",
    ("marketplace", "Image type", "Feature callouts"): "{p} on white with thin lines pointing to the dropper, the glass and the "
                                                       "label, small blank rounded tags at the ends of the lines",
    ("marketplace", "Image type", "What's in the box"): "Flat lay on white of everything in the box: {p}, its kraft box, a small "
                                                        "booklet and a cotton pouch",
}


def ads():
    source = read("Model/AdCatalog.swift")
    items = []
    for tool in re.finditer(r'AdTool\(\s*id: "([^"]+)"(.*?)(?=AdTool\(\s*id: |\Z)', source, re.S):
        tool_id = tool.group(1)
        for group in re.finditer(r'AdOptionGroup\(title: L\("([^"]+)"\)(.*?)values: \[(.*?)\]', tool.group(2), re.S):
            title = group.group(1)
            template = AD_SCENES.get((tool_id, title))
            for value in re.findall(r'"((?:[^"\\]|\\.)*)"', group.group(3)):
                special = AD_SPECIAL.get((tool_id, title, value))
                if value in AD_SKIP or not (template or special):
                    continue
                prompt = (special or template).replace("{v}", value.lower()).replace("{p}", PRODUCT)
                items.append((f"ads/{tool_id}", slug(title) + "-" + slug(value), prompt + "." + PHOTO, "4:3"))
    return items


VIDEO_SCENES = {
    ("editVideo", "restyle"): ("A woman walking a golden retriever on a city street, rendered as {v}. No text, no letters, "
                               "no watermark.", False),
    ("editVideo", "relight"): ("A woman walking a golden retriever on a city street, lit by {v}.", True),
    ("editVideo", "weather"): ("A woman walking a golden retriever on a city street, {v}.", True),
    ("talkingAvatar", "scene"): ("Video still of a woman talking to the camera, {v}", True),
    ("videoAd", "mode"): (f"A video still from a product ad for {PRODUCT}: {{v}}", True),
}
VIDEO_SKIP = {"My moodboard"}
VIDEO_WORDS = {"Weather & time": "", "Rain": "in heavy rain with wet pavement", "Snow": "in falling snow",
               "Fog": "in thick fog", "Night": "at night under streetlights", "Sunset": "at sunset with a warm sky",
               "CCTV": "a grainy security camera view from a high corner", "Static": "a fixed tripod shot in a living room",
               "Angry": "an angry rant", "Happy": "a happy cheerful moment", "Crying": "an emotional moment with tears",
               "UGC talking": "a creator recommending it to the camera", "Hook to video": "a surprising close-up opening shot",
               "Before and after": "a split screen of before and after using it",
               "Product showcase": "the product turning slowly on a pedestal under a sweeping light",
               "Unboxing": "hands opening a kraft box and lifting it out",
               "Selfie": "a handheld front-camera selfie video", "Podcast": "sitting at a podcast desk with a microphone",
               "Car talking": "in the driver's seat of a parked car", "Selling": "presenting a product to the camera like a live seller",
               "Mirror selfie": "filming herself in a bedroom mirror with her phone",
               "Stream": "live streaming at a desk with a ring light and a headset",
               "Steadicam": "walking down a street, filmed with a smooth gimbal", "Handheld": "a shaky handheld shot outdoors",
               "Singing": "singing into a microphone", "Rapping": "rapping with hand gestures in a recording studio"}


def video():
    source = read("Model/VideoCatalog.swift")
    tool_ids = "|".join(tool for tool, _ in VIDEO_SCENES)
    parts = re.split(r'\n\s*(?:VideoTool\(\s*)?id: "(' + tool_ids + r'|[a-zA-Z]+)"(?=, name:)', source)
    items = []
    for index in range(1, len(parts), 2):
        tool, body = parts[index], parts[index + 1]
        for group in re.finditer(r'VideoOptionGroup\(id: "([^"]+)", title: L\("[^"]+"\)(.*?)values: \[(.*?)\]', body, re.S):
            spec = VIDEO_SCENES.get((tool, group.group(1)))
            if not spec:
                continue
            template, realistic = spec
            for value in re.findall(r'"((?:[^"\\]|\\.)*)"', group.group(3)):
                if value in VIDEO_SKIP:
                    continue
                words = VIDEO_WORDS.get(value, value.lower())
                prompt = template.replace("{v}", words) + ("." + PHOTO if realistic else "")
                items.append((f"video/{tool}-{group.group(1)}", slug(value), prompt, "16:9"))
    return items


def spent():
    key = re.search(r"sk-or-v1-[A-Za-z0-9]+", open(os.path.join(ROOT, ".env")).read()).group(0)
    request = urllib.request.Request("https://openrouter.ai/api/v1/key", headers={"Authorization": f"Bearer {key}"})
    return json.load(urllib.request.urlopen(request, timeout=30))["data"]["usage"] - BASELINE, key


def generate(key, prompt, ratio):
    for aspect in (ratio, "1:1"):
        body = {"model": MODEL, "prompt": prompt, "aspect_ratio": aspect}
        request = urllib.request.Request("https://openrouter.ai/api/v1/images", data=json.dumps(body).encode(),
                                         headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json",
                                                  "X-OpenRouter-Title": "Freefield"})
        try:
            payload = json.load(urllib.request.urlopen(request, timeout=300))
            return base64.b64decode(payload["data"][0]["b64_json"]), payload.get("usage", {}).get("cost", 0) or 0
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")[:200]
            if error.code == 400 and aspect != "1:1":
                continue
            raise RuntimeError(f"HTTP {error.code}: {detail}")
    raise RuntimeError("no aspect ratio accepted")


def save(data, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".img", delete=False) as handle:
        handle.write(data)
        temp = handle.name
    subprocess.run(["sips", "-Z", "480", "-s", "format", "heic", "-s", "formatOptions", "55", temp, "--out", path],
                   check=True, capture_output=True)
    os.unlink(temp)


def main():
    items = []
    for family, name, prompt, ratio in manifest():
        key = f"{family}/{name}"
        if key in OVERRIDES:
            realistic = "restyle" not in family
            prompt = OVERRIDES[key].replace("{p}", PRODUCT) + ("." + PHOTO if realistic else ". No text, no letters, no watermark.")
        if key.startswith(ONLY) and (KEYS is None or key in KEYS):
            items.append((family, name, prompt, ratio))
    todo = [item for item in items if FORCE or not os.path.exists(os.path.join(OUT, item[0], item[1] + ".heic"))]
    print(f"{len(items)} option images, {len(todo)} to make")
    if DRY:
        for family, name, prompt, ratio in todo:
            print(f"{family}/{name} [{ratio}] {prompt[:140]}")
        return
    total = 0.0
    for number, (family, name, prompt, ratio) in enumerate(todo, 1):
        used, key = spent() if number == 1 or number % 10 == 0 else (used, key)
        if used + total >= STOP:
            print(f"stopping: ${used:.3f} spent of the extra budget (stop at ${STOP:.2f})")
            break
        for attempt in range(3):
            try:
                data, cost = generate(key, prompt, ratio)
                save(data, os.path.join(OUT, family, name + ".heic"))
                total += cost
                print(f"[{number}/{len(todo)}] {family}/{name} ${cost:.4f}", flush=True)
                break
            except Exception as error:
                print(f"  retry {family}/{name}: {error}", flush=True)
                time.sleep(5 * (attempt + 1))
        if number % 10 == 0:
            total = 0.0
    print(f"done; extra budget spent: ${spent()[0]:.3f}")


if __name__ == "__main__":
    main()
