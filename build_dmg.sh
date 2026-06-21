#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="I love you like no otter.app"
VOL="I love you like no otter"
DMG="I love you like no otter.dmg"
STAGE="dmg_stage"
TMP_DMG="dmg_tmp.dmg"

# Make sure the app is built and signed.
./build.sh

rm -rf "$STAGE" "$TMP_DMG" "$DMG"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp dmg_background.png "$STAGE/.background/bg.png"

echo "Creating disk image…"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$TMP_DMG" >/dev/null

MOUNT="/Volumes/$VOL"
hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
hdiutil attach "$TMP_DMG" -nobrowse >/dev/null
sleep 2

echo "Styling installer window…"
osascript <<EOF || echo "  (Finder styling skipped — DMG still works)"
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 800, 520}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 110
    set background picture of theViewOptions to file ".background:bg.png"
    set position of item "$APP" of container window to {150, 200}
    set position of item "Applications" of container window to {450, 200}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF

sync
hdiutil detach "$MOUNT" >/dev/null 2>&1 || true

echo "Compressing…"
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$TMP_DMG"
rm -rf "$STAGE"

echo "Built \"$DMG\""
