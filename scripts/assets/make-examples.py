#!/usr/bin/env python3
import base64
import concurrent.futures
import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
EXAMPLES = os.path.join(ROOT, "Assets/Examples")
CATALOG = os.path.join(ROOT, "Sources/Freefield/Model/AppCatalog.swift")
LINEUP = os.path.join(ROOT, "Sources/Freefield/Model/Lineup.swift")
INPUT_MODEL = "bytedance-seed/seedream-5-0-flash"
KEY = os.environ.get("OPENROUTER_API_KEY", "")
FORCE = "--force" in sys.argv
ONLY = set(sys.argv[sys.argv.index("--only") + 1].split(",")) if "--only" in sys.argv else None
BUDGET = float(sys.argv[sys.argv.index("--budget") + 1]) if "--budget" in sys.argv else 3.5

PERSON = (" Candid unretouched smartphone photo, natural light, realistic skin texture with pores, "
          "sharp focus, true-to-life color, no filters, no watermark or text overlay.")
PRODUCT = " Realistic product photo taken with a good phone camera, natural light, sharp, true-to-life color, no watermark or text overlay."
SCENE = " Realistic documentary photograph, natural light, true-to-life color, sharp, no watermark or text overlay."

INPUTS = {
    "shots": ("A street musician playing saxophone at a subway entrance in the evening, commuters passing by." + SCENE, "16:9"),
    "zooms": ("A white lighthouse on a rocky cliff above crashing waves on an overcast day, a small figure walking on the path." + SCENE, "3:2"),
    "whats-next": ("A woman in a long red coat standing alone on an empty train platform at night as a train approaches." + SCENE, "16:9"),
    "plushies": ("A fluffy orange tabby cat sitting on a sunny windowsill next to a potted plant." + SCENE, "4:5"),
    "3d-render": ("A vintage mint-green Vespa scooter parked on a cobblestone street in an Italian town." + SCENE, "4:3"),
    "paint-app": ("A family having a picnic in a park with a red blanket, a dog and a kite in the sky." + SCENE, "4:3"),
    "meme": ("A barn owl perched on a wooden fence post, staring straight at the camera with wide eyes." + SCENE, "4:5"),
    "melting-doodle": ("A young man with a beanie reading a newspaper on a bench in a city square, pigeons around." + SCENE, "4:5"),
    "outfit-shot": ("E-commerce photo of an emerald green satin slip midi dress on a wooden hanger against a white wall." + PRODUCT, "4:5"),
    "poster": ("A can of sparkling lime soda with a minimal white label that reads VERDE, on a wet countertop." + PRODUCT, "4:5"),
    "packshot": ("Matte black over-ear wireless headphones lying on a wooden desk." + PRODUCT, "1:1"),
    "bullet-time": ("A glass perfume bottle with an amber liquid and a gold cap on a marble shelf." + PRODUCT, "4:5"),
    "chameleon": ("A turquoise ceramic coffee mug with white polka dots on a kitchen counter." + PRODUCT, "1:1"),
    "macro-scene": ("A glass jar of golden honey with a wooden honey dipper resting on top, on a rustic table." + PRODUCT, "4:5"),
    "macroshot": ("A mechanical wristwatch with a deep blue dial and a brown leather strap on a dark wooden surface." + PRODUCT, "1:1"),
    "magic-button": ("A rose-pink lipstick in a gold metal tube, uncapped, standing on a vanity table." + PRODUCT, "4:5"),
    "giant-product": ("A glass bottle of fresh orange juice with a simple label that reads SOL, on a picnic table." + PRODUCT, "4:5"),
    "billboard": ("A box of granola cereal with a kraft-paper label that reads MORNING OATS, on a breakfast table." + PRODUCT, "4:5"),
    "truck-ad": ("A bag of tortilla chips with a bold yellow and red label that reads CRUNCHO, on a kitchen island." + PRODUCT, "4:5"),
    "graffiti-ad": ("A purple energy drink can with a lightning bolt logo and the word VOLT, on a concrete ledge." + PRODUCT, "4:5"),
    "fridge-ad": ("A carton of oat milk with a minimalist beige label that reads OAT, on a kitchen counter." + PRODUCT, "4:5"),
    "volcano-ad": ("A bottle of hot sauce with a red label that reads FUEGO and a chili illustration, on a dark wooden table." + PRODUCT, "4:5"),
    "ai-stylist": ("Full-body photo of a Black man in his late twenties wearing a plain grey hoodie and jeans, standing on a sunny sidewalk." + PERSON, "2:3"),
    "skin-enhancer": ("Close-up portrait of a woman in her thirties with freckles, some redness on her cheeks and a few blemishes, by a window." + PERSON, "4:5"),
    "style-snap": ("Full-body photo of a young East Asian man in a white t-shirt and chinos standing in a park." + PERSON, "2:3"),
    "outfit-vending": ("Full-body photo of a woman in her twenties wearing a denim jacket, striped top, black jeans, white sneakers and a red crossbody bag on a city street." + PERSON, "2:3"),
    "glitter-sticker": ("Waist-up photo of a smiling young woman with long braids making a peace sign, plain light wall behind her." + PERSON, "4:5"),
    "headshot": ("Casual selfie of a South Asian man in his forties wearing a navy polo shirt, in his kitchen." + PERSON, "4:5"),
    "commercial-faces": ("Portrait of a Latina woman in her forties with natural makeup and shoulder-length hair, outdoors in soft shade." + PERSON, "4:5"),
    "game-dump": ("Full-body photo of a young man in a red flannel shirt doing a trick on a skateboard in a concrete skatepark." + PERSON, "4:5"),
    "nano-strike": ("Waist-up photo of a bearded man in his thirties wearing a black t-shirt, in a garage workshop." + PERSON, "4:5"),
    "nano-theft": ("A woman in her thirties with sunglasses and a leather jacket leaning against an old car on a street lined with palm trees." + PERSON, "4:5"),
    "simlife": ("A man in his twenties wearing a brown cardigan holding a coffee mug in a cozy living room." + PERSON, "4:5"),
    "3d-figure": ("Full-body photo of a young woman in a yellow raincoat and rubber boots on a rainy street." + PERSON, "2:3"),
    "pixel-game": ("A woman in her twenties in running clothes jogging along a park path with trees." + PERSON, "4:3"),
    "brick-cube": ("An older man in his sixties with a grey beard and a fishing vest holding a fishing rod by a lake." + PERSON, "4:5"),
    "signboard": ("A smiling woman in her seventies with short white hair and a floral blouse on her front porch." + PERSON, "4:5"),
    "micro-beasts": ("A young woman with a ponytail sitting cross-legged on the grass in a sunny meadow." + PERSON, "4:5"),
    "latex": ("A man in his twenties with a buzz cut and sharp cheekbones against a plain grey wall." + PERSON, "4:5"),
    "j-magazine": ("A young Japanese woman with a short bob haircut and an oversized coat on a Tokyo side street." + PERSON, "4:5"),
    "j-poster": ("A man in his fifties with slicked-back grey hair and a leather jacket on a street at dusk." + PERSON, "4:5"),
    "roller-coaster": ("A man in his thirties with curly hair wearing a green t-shirt, laughing, at an amusement park." + PERSON, "4:5"),
    "60s-cafe": ("A young woman with long red hair wearing a knit sweater, sitting in a modern coffee shop." + PERSON, "4:5"),
    "victory-card": ("A dignified Black woman in her sixties with grey hair and an elegant burgundy blouse." + PERSON, "4:5"),
    "sand-worm": ("Full-body photo of a hiker in desert clothing and a scarf standing on top of a sand dune." + PERSON, "2:3"),
    "mascot": ("A cheerful man in his forties with glasses and a flour-dusted apron in a bakery." + PERSON, "4:5"),
    "storm-creature": ("A woman in her fifties in a plaid shirt standing in a golden wheat field." + PERSON, "4:5"),
    "burning-sunset": ("A young Middle Eastern man in a white linen shirt standing on a beach in the afternoon." + PERSON, "4:5"),
    "on-fire": ("A woman in her thirties in a blazer sitting at an office desk with a laptop." + PERSON, "4:3"),
    "comic-book": ("An athletic young Black woman in sportswear standing on a city rooftop." + PERSON, "4:5"),
    "cloud-surf": ("A surfer in his twenties with long blond hair holding a surfboard on a beach." + PERSON, "4:5"),
    "mukbang": ("A young Korean man in a grey sweatshirt sitting at his desk at home." + PERSON, "4:5"),
    "giallo": ("A woman in her thirties with dark wavy hair and a beige trench coat in an old apartment hallway." + PERSON, "4:5"),
    "renaissance": ("A young man with a thin mustache wearing a plain white t-shirt against a neutral wall." + PERSON, "4:5"),
    "rap-god": ("A woman in her twenties with box braids and a bomber jacket against a painted urban wall." + PERSON, "4:5"),
}

EXAMPLE_OPTION = {"game-dump": "Voxel blocks", "style-snap": "Astronaut", "ai-stylist": "Old money"}
SAMPLE_TEXT = {"meme": "When the code compiles on the first try", "poster": "Ice cold. Zero sugar."}
RATIOS = {"square": "1:1", "portrait2x3": "2:3", "landscape3x2": "3:2", "portrait3x4": "3:4", "landscape4x3": "4:3",
          "portrait4x5": "4:5", "landscape5x4": "5:4", "portrait9x16": "9:16", "landscape16x9": "16:9", "ultrawide21x9": "21:9"}

spent = 0.0
lock = threading.Lock()


def swift_string(raw):
    return raw.replace('\\"', '"').replace("\\n", "\n")


def lineup_ids():
    source = open(LINEUP, encoding="utf-8").read()
    ids = {}
    for block in source.split('LineupModel(id: "')[1:]:
        match = re.search(r'openRouter: \["([^"]+)"', block)
        if match:
            ids[block.split('"')[0]] = match.group(1)
    return ids


def capabilities():
    with urllib.request.urlopen("https://openrouter.ai/api/v1/images/models", timeout=60) as response:
        return {m["id"]: m["supported_parameters"] for m in json.load(response)["data"]}


def apps():
    source = open(CATALOG, encoding="utf-8").read()
    real_people = swift_string(re.search(r'static let realPeople = "((?:[^"\\]|\\.)*)"', source).group(1))
    real_scene = swift_string(re.search(r'static let realScene = "((?:[^"\\]|\\.)*)"', source).group(1))
    no_marks = swift_string(re.search(r'static let noMarks = "((?:[^"\\]|\\.)*)"', source).group(1))
    items = []
    for block in source.split("AppItem(id: ")[1:]:
        app_id = block.split('"')[1]
        template = re.search(r'template: "((?:[^"\\]|\\.)*)"', block)
        if not template:
            continue
        slots = re.search(r"slots: \[([^\]]*)\]", block)
        slot_list = [s.strip().lstrip(".") for s in (slots.group(1).split(",") if slots else ["photo"])]
        options = re.findall(r'"([^"]+)"', re.search(r'options: \[([^\]]*)\]', block).group(1)) if "options: [" in block else []
        aspect = re.search(r"aspect: \.(\w+)", block)
        model = re.search(r'model: "([^"]+)"', block).group(1)
        stylized = "stylized: true" in block
        option = EXAMPLE_OPTION.get(app_id) or (options[0] if options else "")
        text_value = SAMPLE_TEXT.get(app_id, "")
        raw = swift_string(template.group(1))
        if not text_value:
            raw = raw.replace('"{text}"', "a short line written to fit the image")
        roles = {"photo": "a photo of the person", "product": "the product", "garment": "the garment"}
        legend = " ".join(f"Image {i + 1} is {roles.get(slot, 'the source image')}." for i, slot in enumerate(slot_list))
        prompt = (legend + "\n" if legend else "") + raw.replace("{option}", option).replace("{text}", text_value).replace("  ", " ")
        if text_value and "{text}" not in raw:
            prompt += f"\nAlso: {text_value}"
        if "photo" in slot_list:
            index = slot_list.index("photo") + 1
            prompt += f"\nKeep the person from Image {index} " + (
                "recognizable in the new style: same face shape, features, skin tone, hairstyle and hair color." if stylized
                else "unmistakably the same person: identical face, facial structure, eye shape and skin tone.")
        if "product" in slot_list:
            index = slot_list.index("product") + 1
            prompt += f"\nUse this exact product from Image {index}: identical shape, proportions, label text, logo and colors."
        if not stylized:
            prompt += real_people if ("photo" in slot_list or "garment" in slot_list) else real_scene
        prompt += no_marks
        items.append({"id": app_id, "prompt": prompt, "model": model,
                      "aspect": RATIOS.get(aspect.group(1)) if aspect else None})
    return items


def call(model, prompt, caps, ratio=None, reference=None):
    global spent
    with lock:
        if spent >= BUDGET:
            raise RuntimeError(f"budget of ${BUDGET:.2f} reached")
    params = caps.get(model, {})
    body = {"model": model, "prompt": prompt}
    if ratio and ratio in params.get("aspect_ratio", {}).get("values", [ratio]):
        body["aspect_ratio"] = ratio
    resolutions = params.get("resolution", {}).get("values")
    if resolutions:
        body["resolution"] = "1K" if "1K" in resolutions else resolutions[0]
    if "quality" in params:
        body["quality"] = "high" if "2.5" in model else "medium"
    if reference:
        body["input_references"] = [{"type": "image_url", "image_url": {"url": "data:image/jpeg;base64," + reference}}]
    request = urllib.request.Request("https://openrouter.ai/api/v1/images", data=json.dumps(body).encode(),
                                     headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json",
                                              "X-OpenRouter-Title": "Freefield"})
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        if error.code == 400 and "size" in detail and resolutions and body.get("resolution") in resolutions[:-1]:
            body["resolution"] = resolutions[resolutions.index(body["resolution"]) + 1]
            request = urllib.request.Request(request.full_url, data=json.dumps(body).encode(), headers=dict(request.header_items()))
            with urllib.request.urlopen(request, timeout=300) as response:
                payload = json.load(response)
        else:
            raise RuntimeError(f"HTTP {error.code}: {detail[:300]}") if error.code == 402 else Exception(f"HTTP {error.code}: {detail[:300]}")
    cost = payload.get("usage", {}).get("cost", 0) or 0
    with lock:
        spent += cost
    return base64.b64decode(payload["data"][0]["b64_json"]), cost


def save_image(data, destination, long_side=900):
    with tempfile.NamedTemporaryFile(suffix=".img", delete=False) as handle:
        handle.write(data)
        temp = handle.name
    subprocess.run(["sips", "-Z", str(long_side), "-s", "format", "heic", "-s", "formatOptions", "55", temp,
                    "--out", destination], check=True, capture_output=True)
    os.unlink(temp)


def jpeg_base64(path):
    with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as handle:
        temp = handle.name
    subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "90", path, "--out", temp], check=True, capture_output=True)
    data = base64.b64encode(open(temp, "rb").read()).decode()
    os.unlink(temp)
    return data


def with_retries(function):
    last = None
    for attempt in range(3):
        try:
            return function(), None
        except RuntimeError as error:
            return None, error
        except Exception as error:
            last = error
            if hasattr(error, "read"):
                last = f"{error} {error.read()[:300]}"
            time.sleep(6 * (attempt + 1))
    return None, last


def main():
    if not KEY:
        sys.exit("Set OPENROUTER_API_KEY")
    caps = capabilities()
    models = lineup_ids()
    items = [item for item in apps() if ONLY is None or item["id"] in ONLY]
    missing = [item["id"] for item in items if item["id"] not in INPUTS]
    if missing:
        sys.exit(f"No input defined for: {missing}")
    inputs_dir = os.path.join(EXAMPLES, "inputs")
    apps_dir = os.path.join(EXAMPLES, "apps")
    os.makedirs(inputs_dir, exist_ok=True)
    os.makedirs(apps_dir, exist_ok=True)
    index_path = os.path.join(apps_dir, "index.json")
    index = json.load(open(index_path)) if os.path.exists(index_path) else {}

    def run(item):
        app_id = item["id"]
        input_path = os.path.join(inputs_dir, f"{app_id}.heic")
        if "--inputs" in sys.argv and (FORCE or not os.path.exists(input_path)):
            prompt, ratio = INPUTS[app_id]
            result, error = with_retries(lambda: call(INPUT_MODEL, prompt, caps, ratio))
            if error:
                return app_id, 0, f"input: {error}"
            save_image(result[0], input_path)
        output_path = os.path.join(apps_dir, f"{app_id}.heic")
        if os.path.exists(output_path) and not FORCE and ONLY is None:
            return app_id, 0, None
        reference = jpeg_base64(input_path)
        model = models[item["model"]]
        result, error = with_retries(lambda: call(model, item["prompt"], caps, item["aspect"], reference))
        if error:
            return app_id, 0, f"{model}: {error}"
        save_image(result[0], output_path)
        return app_id, result[1], None

    print(f"{len(items)} apps · budget ${BUDGET:.2f}", flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        for app_id, cost, error in pool.map(run, items):
            if not error:
                index[app_id] = app_id
            print(f"{'✗' if error else '✓'} {app_id} {f'${cost:.3f}' if cost else ''} {error or ''}", flush=True)
    json.dump(index, open(index_path, "w"), indent=1, sort_keys=True)
    print(f"Done. Spent ${spent:.3f}", flush=True)


if __name__ == "__main__":
    main()
