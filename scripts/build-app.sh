#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build --configuration release --product Snipper
BIN_DIR="$(swift build --configuration release --show-bin-path)"
APP="$PWD/dist/Snipper.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Snipper" "$APP/Contents/MacOS/Snipper"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Personal local build only; not a Developer ID signature or notarization.
codesign --force --sign - "$APP"
printf '\nBuilt %s\nLaunch with: open "%s"\n' "$APP" "$APP"
