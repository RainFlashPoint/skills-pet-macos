#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="SkillsPetLite"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
PKGINFO_PATH="$APP_DIR/Contents/PkgInfo"
TMP_BIN="/private/tmp/$APP_NAME"
RAW_BIN="$BUILD_DIR/$APP_NAME-bin"

export DEVELOPER_DIR=/Library/Developer/CommandLineTools

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
rm -f "$TMP_BIN"
rm -f "$RAW_BIN"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>SkillsPetLite</string>
  <key>CFBundleIdentifier</key>
  <string>local.skills-pet-lite.macos</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>SkillsPetLite</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$PKGINFO_PATH"

swiftc \
  -O \
  -framework AppKit \
  "$ROOT"/Sources/*.swift \
  -o "$TMP_BIN"

cp "$TMP_BIN" "$MACOS_DIR/$APP_NAME"
cp "$TMP_BIN" "$RAW_BIN"
chmod +x "$MACOS_DIR/$APP_NAME"
chmod +x "$RAW_BIN"
xattr -cr "$APP_DIR" || true
codesign --force --deep --sign - "$APP_DIR"
rm -f "$TMP_BIN"

echo "Built app: $APP_DIR"
echo "Built bin: $RAW_BIN"
