#!/usr/bin/env python3
import base64
import time
import concurrent.futures
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MODEL = "black-forest-labs/flux-3-image-klein"
KEY = os.environ.get("OPENROUTER_API_KEY", "")
FORCE = "--force" in sys.argv

SUBJECTS = [
    "a young woman with curly dark hair", "a man in his thirties with a short beard", "a Black woman with braids",
    "an East Asian man with bleached hair", "a Latina woman with long wavy hair", "a red-haired woman with freckles",
    "a South Asian man in a tailored outfit", "a young non-binary model with a buzz cut", "an older woman with silver hair",
    "a tall man with curly hair", "a woman with a sleek bob haircut", "a young man with locs",
]


def generate(prompt, ratio):
    body = json.dumps({"model": MODEL, "prompt": prompt, "aspect_ratio": ratio, "resolution": "1K"}).encode()
    request = urllib.request.Request(
        "https://openrouter.ai/api/v1/images", data=body,
        headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json", "X-OpenRouter-Title": "Freefield"},
    )
    with urllib.request.urlopen(request, timeout=240) as response:
        payload = json.load(response)
    item = payload["data"][0]
    return base64.b64decode(item["b64_json"]), payload.get("usage", {}).get("cost", 0)


def save_heic(data, destination, size=700):
    with tempfile.NamedTemporaryFile(suffix=".img", delete=False) as handle:
        handle.write(data)
        temp = handle.name
    subprocess.run(["sips", "-Z", str(size), "-s", "format", "heic", "-s", "formatOptions", "55",
                    temp, "--out", destination], check=True, capture_output=True)
    os.unlink(temp)


def preset_jobs():
    source = open(os.path.join(ROOT, "Sources/Freefield/Model/StylePresets.swift"), encoding="utf-8").read()
    text = r'"((?:[^"\\]|\\.)*)"'
    name = r'(?:L\(\s*' + text + r'\s*\)|' + text + r')'
    pattern = re.compile(r'\bp\("([^"]+)",\s*' + name + r',\s*' + name + r',\s*' + name + r',\s*' + text)
    jobs = []
    for index, match in enumerate(pattern.finditer(source)):
        groups = match.groups()
        preset_id, category, style = groups[0], groups[3] or groups[4], groups[7]
        subject = SUBJECTS[index % len(SUBJECTS)]
        prompt = f"Photo of {subject}. Visual style: {style} No text, no watermark."
        if category in ("Places", "Lugares") or preset_id in ("japandi", "gallery", "library", "self-care", "artwork"):
            prompt = f"Photo of {subject} in the scene. Visual style: {style} No text, no watermark."
        jobs.append((os.path.join(ROOT, "Assets/Presets", f"{preset_id}.heic"), prompt, "4:5"))
    return jobs


def main():
    if not KEY:
        sys.exit("Set OPENROUTER_API_KEY")
    os.makedirs(os.path.join(ROOT, "Assets/Presets"), exist_ok=True)
    jobs = [job for job in preset_jobs() if FORCE or not os.path.exists(job[0])]
    print(f"{len(jobs)} thumbnails to generate with {MODEL}", flush=True)
    total = 0.0

    def run(job):
        destination, prompt, ratio = job
        for attempt in range(4):
            try:
                data, cost = generate(prompt, ratio)
                save_heic(data, destination)
                return destination, cost, None
            except Exception as error:
                last = error
                time.sleep(6 * (attempt + 1))
        return destination, 0, last

    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        for destination, cost, error in pool.map(run, jobs):
            total += cost or 0
            name = os.path.basename(destination)
            print(f"{'✗' if error else '✓'} {name} {'' if not error else error}", flush=True)
    print(f"Done. Cost ≈ ${total:.3f}", flush=True)


if __name__ == "__main__":
    main()
