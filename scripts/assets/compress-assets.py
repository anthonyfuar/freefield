#!/usr/bin/env python3
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TARGETS = [("Assets/Examples/ads", 720), ("Assets/Examples/apps", 720), ("Assets/Examples/inputs", 720),
           ("Assets/Examples/tools", 720), ("Assets/Examples/video", 600), ("Assets/Presets", 600)]
RECOMPRESS = "--recompress" in sys.argv
QUALITY = "55"


def pixel_size(path):
    output = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path], capture_output=True, text=True).stdout
    values = [int(line.split(":")[1]) for line in output.splitlines() if line.strip().startswith(("pixelWidth", "pixelHeight"))]
    return (values + [0, 0])[:2]


def main():
    before = after = converted = 0
    targets = TARGETS + [(os.path.relpath(os.path.join(dirpath), ROOT), 400)
                         for dirpath, _, files in os.walk(os.path.join(ROOT, "Assets/Examples/options")) if files]
    for folder, size in targets:
        path = os.path.join(ROOT, folder)
        for name in sorted(os.listdir(path)):
            stem, ext = os.path.splitext(name)
            if ext.lower() == ".heic" and RECOMPRESS:
                source = os.path.join(path, name)
                width, height = pixel_size(source)
                if max(width, height) <= size:
                    continue
                temp = source + ".tmp.heic"
                subprocess.run(["sips", "-Z", str(size), "-s", "format", "heic", "-s", "formatOptions", QUALITY,
                                source, "--out", temp], capture_output=True)
                if os.path.exists(temp) and os.path.getsize(temp) < os.path.getsize(source):
                    before += os.path.getsize(source)
                    after += os.path.getsize(temp)
                    os.replace(temp, source)
                    converted += 1
                elif os.path.exists(temp):
                    os.remove(temp)
                continue
            if ext.lower() not in (".jpg", ".jpeg", ".png"):
                continue
            source = os.path.join(path, name)
            destination = os.path.join(path, stem + ".heic")
            result = subprocess.run(["sips", "-Z", str(size), "-s", "format", "heic", "-s", "formatOptions", QUALITY,
                                     source, "--out", destination], capture_output=True)
            if result.returncode != 0 or not os.path.exists(destination):
                print("✗", source, result.stderr.decode()[:200], file=sys.stderr)
                continue
            before += os.path.getsize(source)
            after += os.path.getsize(destination)
            os.remove(source)
            converted += 1
    if converted:
        print(f"{converted} images: {before / 1e6:.1f} MB → {after / 1e6:.1f} MB")
    else:
        print("Nothing to convert.")


if __name__ == "__main__":
    main()
