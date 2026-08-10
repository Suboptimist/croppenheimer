#!/bin/bash
# Builds Croppenheimer: regenerates the icon assets from the Icon Composer
# document, compiles a universal Release build, and packages a .dmg.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
VERSION="1.0"
VOLNAME="Croppenheimer $VERSION"
BUILD="$ROOT/build"
DMG="$ROOT/Croppenheimer-$VERSION.dmg"

echo "==> Compiling AppIcon.icon (needs Xcode 26+)"
ICONOUT="$(mktemp -d)"
actool AppIcon.icon --compile "$ICONOUT" \
  --output-format human-readable-text \
  --output-partial-info-plist "$ICONOUT/partial.plist" \
  --app-icon AppIcon --include-all-app-icons \
  --enable-on-demand-resources NO --development-region en \
  --target-device mac --minimum-deployment-target 26.0 --platform macosx >/dev/null
cp "$ICONOUT/AppIcon.icns" App/AppIcon.icns
cp "$ICONOUT/Assets.car" App/Assets.car
rm -rf "$ICONOUT"

echo "==> Building universal Release binary"
xcodebuild -project Croppenheimer.xcodeproj -target Croppenheimer -configuration Release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  SYMROOT="$BUILD" OBJROOT="$BUILD/obj" build | tail -1

APP="$BUILD/Release/Croppenheimer.app"
lipo -archs "$APP/Contents/MacOS/Croppenheimer"

echo "==> Packaging $DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
RW="$(mktemp -u).dmg"
hdiutil create -srcfolder "$STAGE" -volname "$VOLNAME" -fs HFS+ -format UDRW -size 40m -ov "$RW" >/dev/null
hdiutil attach "$RW" >/dev/null
sleep 2

# Lay the installer window out: app on the left, Applications on the right.
osascript <<EOF >/dev/null
tell application "Finder"
  tell disk "$VOLNAME"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 800, 520}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set position of item "Croppenheimer.app" of container window to {150, 190}
    set position of item "Applications" of container window to {450, 190}
    update without registering applications
    delay 2
    close
  end tell
end tell
EOF

sync
hdiutil detach "/Volumes/$VOLNAME" >/dev/null
rm -f "$DMG"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$RW"
rm -rf "$STAGE"

echo "==> Done"
ls -lh "$DMG" | awk '{print $5, $9}'
shasum -a 256 "$DMG"
