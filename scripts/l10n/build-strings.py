#!/usr/bin/env python3
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.join(ROOT, "scripts/l10n")
OUT = os.path.join(ROOT, "Resources/es.lproj/Localizable.strings")

KEY = re.compile(r'\b(?:L|E)\(\s*"((?:[^"\\]|\\.)*)"')
OPTIONS = re.compile(r'(?:options|values): \[([^\]]*)\]')
SPECIFIER = re.compile(r"%(?:\d+\$)?(?:ld|lld|d|@|f|\.\d+f|lu|%)")


def swift_unescape(text):
    return text.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")


def strings_escape(text):
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def keys_in_sources():
    keys = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "Sources/**/*.swift"), recursive=True)):
        lines = open(path, encoding="utf-8").read().splitlines()
        source = "\n".join(line for line in lines if not line.lstrip().startswith("//"))
        for match in KEY.finditer(source):
            raw = match.group(1)
            if "\\(" in raw:
                print(f"warning: interpolation inside L() key in {os.path.relpath(path, ROOT)}: {raw[:60]}", file=sys.stderr)
                continue
            keys.setdefault(swift_unescape(raw), os.path.relpath(path, ROOT))
        for block in OPTIONS.finditer(source):
            for raw in re.findall(r'"((?:[^"\\]|\\.)*)"', block.group(1)):
                keys.setdefault(swift_unescape(raw), os.path.relpath(path, ROOT))
    return keys


def translations():
    table = {}
    for path in sorted(glob.glob(os.path.join(HERE, "*.json"))):
        for pair in json.load(open(path, encoding="utf-8")):
            table[pair["english"]] = pair["spanish"]
    return table


def record_names():
    def read(relative):
        return open(os.path.join(ROOT, relative), encoding="utf-8").read()

    names = set()
    title = re.search(r"var title: String \{(.*?)\n    \}", read("Sources/Freefield/Model/Tool.swift"), re.S)
    if title:
        names.update(swift_unescape(raw) for raw in KEY.findall(title.group(1)))
    names.update(swift_unescape(raw) for raw in re.findall(r'\bname: L\("((?:[^"\\]|\\.)*)"\)', read("Sources/Freefield/Model/AdCatalog.swift")))
    names.update(swift_unescape(raw) for raw in re.findall(r'AppItem\(\s*id: "[^"]*",\s*name: L\("((?:[^"\\]|\\.)*)"\)',
                                                          read("Sources/Freefield/Model/AppCatalog.swift")))
    names.update(swift_unescape(raw) for raw in re.findall(r'\bp\("[^"]*", L\("((?:[^"\\]|\\.)*)"\)',
                                                          read("Sources/Freefield/Model/StylePresets.swift")))
    for line in read("Sources/Freefield/Model/AppModel+Tools.swift").splitlines():
        if "spec.title = " in line or "startLocal(" in line:
            names.update(swift_unescape(raw) for raw in KEY.findall(line))
    named = r'\b(?:PhotoSessionSet|LightPreset|CameraAngle|GradeLook)\(id: "[^"]*", name: L\("((?:[^"\\]|\\.)*)"\)'
    for relative in ["Sources/Freefield/Views/PhotoSessionView.swift", "Sources/Freefield/Model/Recipes.swift",
                     "Sources/Freefield/Views/ColorGradeView.swift"]:
        names.update(swift_unescape(raw) for raw in re.findall(named, read(relative)))
    return names


def shared_translations(keys, table):
    by_spanish = {}
    for key in sorted(keys):
        if key in table:
            by_spanish.setdefault(table[key], []).append(key)
    return {spanish: shared for spanish, shared in sorted(by_spanish.items()) if len(shared) > 1}


def main():
    keys = keys_in_sources()
    table = translations()
    missing = [key for key in keys if key not in table]
    if "--missing" in sys.argv:
        print(json.dumps([{"english": key, "file": keys[key]} for key in missing], ensure_ascii=False, indent=1))
        return
    problems = 0
    for key in keys:
        if key in table and sorted(SPECIFIER.findall(key)) != sorted(SPECIFIER.findall(table[key])):
            print(f"specifier mismatch: {key!r} → {table[key]!r}", file=sys.stderr)
            problems += 1
    records = record_names()
    if not records:
        print("warning: found no record names (tool titles, ad tools, quick styles) to check", file=sys.stderr)
    collisions = 0
    for spanish, shared in shared_translations(keys, table).items():
        involved = [key for key in shared if key in records]
        if not involved and len({key.casefold() for key in shared}) == 1:
            continue
        label = "error" if involved else "warning"
        print(f"{label}: {spanish!r} translates {', '.join(repr(key) for key in shared)}", file=sys.stderr)
        if involved:
            collisions += 1
    if collisions:
        print(f"{collisions} shared translations involve record names; give each key its own Spanish text", file=sys.stderr)
        problems += collisions
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as handle:
        handle.write("/* Generated by scripts/l10n/build-strings.py — edit scripts/l10n/es.json instead. */\n\n")
        for key in sorted(keys):
            if key in table:
                handle.write(f'"{strings_escape(key)}" = "{strings_escape(table[key])}";\n')
    print(f"{len(keys)} keys, {len(keys) - len(missing)} translated, {len(missing)} missing, {problems} problems")
    for key in missing[:40]:
        print(f"  missing: {key!r} ({keys[key]})")
    if missing or problems:
        sys.exit(1)


if __name__ == "__main__":
    main()
