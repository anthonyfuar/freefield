#!/bin/zsh
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Freefield.app"
VERSION="1.0"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"

cd "$ROOT"
echo "▸ Localizing (en, es)…"
python3 "$ROOT/scripts/l10n/build-strings.py"
echo "▸ Compiling ($CONFIG)…"
swift build -c "$CONFIG" --product Freefield
BIN="$(swift build -c "$CONFIG" --product Freefield --show-bin-path)/Freefield"

echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/en.lproj" "$APP/Contents/Resources/es.lproj"
cp "$BIN" "$APP/Contents/MacOS/Freefield"
cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
for folder in Presets Examples; do
  if [[ -d "$ROOT/Assets/$folder" ]]; then
    rsync -a --exclude ".DS_Store" "$ROOT/Assets/$folder/" "$APP/Contents/Resources/$folder/"
  fi
done
CLOUDFLARED_TGZ="$ROOT/Vendor/cloudflared/cloudflared-darwin-arm64.tgz"
CLOUDFLARED_SHA256="1165d14b6f6360a3b8c283d7d1100024d6ec7cd9bc9e32519e96150645f3ec55"
echo "▸ Adding cloudflared"
if [[ ! -f "$CLOUDFLARED_TGZ" || ! -f "$ROOT/Vendor/cloudflared/LICENSE" ]]; then
  echo "✗ Missing Vendor/cloudflared/cloudflared-darwin-arm64.tgz or its LICENSE" >&2
  exit 1
fi
ACTUAL_SHA256="$(shasum -a 256 "$CLOUDFLARED_TGZ" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$CLOUDFLARED_SHA256" ]]; then
  echo "✗ cloudflared archive checksum mismatch: $ACTUAL_SHA256 (expected $CLOUDFLARED_SHA256)" >&2
  exit 1
fi
mkdir -p "$APP/Contents/Resources/Helpers"
cp "$CLOUDFLARED_TGZ" "$APP/Contents/Resources/Helpers/cloudflared-darwin-arm64.tgz"
cp "$ROOT/Vendor/cloudflared/LICENSE" "$APP/Contents/Resources/Helpers/LICENSE"
cp "$ROOT/Resources/es.lproj/Localizable.strings" "$APP/Contents/Resources/es.lproj/Localizable.strings"
for lang in en es; do
  echo '"CFBundleDisplayName" = "Freefield";' > "$APP/Contents/Resources/$lang.lproj/InfoPlist.strings"
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>es</string></array>
  <key>CFBundleExecutable</key><string>Freefield</string>
  <key>CFBundleIdentifier</key><string>app.freefield.Freefield</string>
  <key>CFBundleName</key><string>Freefield</string>
  <key>CFBundleDisplayName</key><string>Freefield</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.graphics-design</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSHumanReadableCopyright</key><string>Freefield — AI image studio.</string>
</dict>
</plist>
PLIST

echo "▸ Signing (ad-hoc)"
codesign --force --deep --sign - --timestamp=none "$APP"
echo "✓ Done: $APP"
