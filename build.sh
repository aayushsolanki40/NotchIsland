#!/bin/zsh
# Builds a universal (Apple Silicon + Intel) NotchIsland.app into ./build.
#
# Usage: ./build.sh [version]
#   version  Optional marketing version stamped into Info.plist (e.g. 1.2.0).
set -euo pipefail
cd "$(dirname "$0")"

APP=build/NotchIsland.app
VERSION="${1:-}"
FRAMEWORKS=(-framework IOKit -framework IOBluetooth -framework CoreAudio -framework AudioToolbox)

rm -rf "$APP" build/obj
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj

for arch in arm64 x86_64; do
  echo "Compiling $arch…"
  swiftc -O -swift-version 5 -target $arch-apple-macos14.0 Sources/*.swift \
    "${FRAMEWORKS[@]}" -o build/obj/NotchIsland-$arch
done
lipo -create build/obj/NotchIsland-* -output "$APP/Contents/MacOS/NotchIsland"
rm -rf build/obj

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
if [[ -n "$VERSION" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION#v}" "$APP/Contents/Info.plist"
fi

# Ad-hoc signature: enough to run locally. Distribution builds need a Developer ID.
codesign --force --sign - "$APP"

# Quit the running copy so the following `open` launches this build, not the old one.
pkill -x NotchIsland || true
echo "Built $APP"
