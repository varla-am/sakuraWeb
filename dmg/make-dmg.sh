#!/bin/zsh
# Builds Sakura (Release, Apple Silicon + Intel) and packs it into a tall DMG:
# the app on top, an Applications link below, the night-sky background with a dotted arrow between.
#
# Usage: ./make-dmg.sh [output.dmg]     (default: ~/Desktop/Sakura.dmg)
# Needs: Xcode, create-dmg (brew install create-dmg), Pillow (pip3 install pillow).
# The first run asks to let Terminal control Finder: Finder lays out the window.
set -euo pipefail

here=${0:A:h}
project=${here:h}
out=${1:-$HOME/Desktop/Sakura.dmg}
work=$(mktemp -d /tmp/sakura-dmg.XXXX)
trap 'rm -rf "$work"' EXIT

echo "Building Sakura…"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project "$project/Sakura.xcodeproj" -scheme Sakura -configuration Release \
  -derivedDataPath "$work/build" ONLY_ACTIVE_ARCH=NO -quiet build
app="$work/build/Build/Products/Release/Sakura.app"

echo "Drawing the background…"
python3 "$here/background.py" "$work"
# One TIFF with both sizes, so the background is sharp on Retina screens
tiffutil -cathidpicheck "$work/background.png" "$work/background@2x.png" -out "$work/background.tiff"

mkdir "$work/source"
cp -R "$app" "$work/source/"

echo "Packing the DMG…"
rm -f "$out"
# Window and icon positions match APP and APPLICATIONS in background.py
create-dmg \
  --volname "Sakura" \
  --volicon "$app/Contents/Resources/AppIcon.icns" \
  --background "$work/background.tiff" \
  --window-pos 200 120 \
  --window-size 420 600 \
  --icon-size 112 \
  --text-size 13 \
  --icon "Sakura.app" 210 175 \
  --hide-extension "Sakura.app" \
  --app-drop-link 210 445 \
  --no-internet-enable \
  "$out" "$work/source"

echo "Done: $out"
