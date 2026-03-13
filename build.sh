#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$ROOT_DIR/AppBundle"
APP_DIR="$ROOT_DIR/justQuit.app"
BIN_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
BIN_PATH="$BIN_DIR/justQuit"
ZIP_PATH="$ROOT_DIR/justQuit.zip"
ARM64_BIN="$BIN_DIR/justQuit-arm64"
X64_BIN="$BIN_DIR/justQuit-x86_64"
ICON_PNG="$ROOT_DIR/justQuit.iconset/icon_512x512@2x.png"

rm -rf "$APP_DIR"
mkdir -p "$BIN_DIR"
mkdir -p "$RESOURCES_DIR"
swift "$ROOT_DIR/generate_icon.swift"
cp "$TEMPLATE_DIR/Contents/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$TEMPLATE_DIR/Contents/Resources/justQuit.icns" "$RESOURCES_DIR/justQuit.icns"

swiftc \
  -target arm64-apple-macos13.0 \
  -framework AppKit \
  -framework SwiftUI \
  "$ROOT_DIR"/Sources/*.swift \
  -o "$ARM64_BIN"

swiftc \
  -target x86_64-apple-macos13.0 \
  -framework AppKit \
  -framework SwiftUI \
  "$ROOT_DIR"/Sources/*.swift \
  -o "$X64_BIN"

lipo -create -output "$BIN_PATH" "$ARM64_BIN" "$X64_BIN"
rm -f "$ARM64_BIN" "$X64_BIN"

codesign --force --deep --sign - "$APP_DIR"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Built $APP_DIR"
