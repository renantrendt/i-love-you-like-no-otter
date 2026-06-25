#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="I love you like no otter.app"
BIN="NoOtter"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

echo "Compiling (universal: arm64 + x86_64)…"
FRAMEWORKS="-framework AppKit -framework CoreImage -framework ServiceManagement"
swiftc -swift-version 5 -O Sources/main.swift -target arm64-apple-macos13  -o "/tmp/nootter_arm64"  $FRAMEWORKS
swiftc -swift-version 5 -O Sources/main.swift -target x86_64-apple-macos13 -o "/tmp/nootter_x86_64" $FRAMEWORKS
lipo -create "/tmp/nootter_arm64" "/tmp/nootter_x86_64" -o "$APP/Contents/MacOS/$BIN"
rm -f "/tmp/nootter_arm64" "/tmp/nootter_x86_64"

cp Info.plist "$APP/Contents/Info.plist"
cp Resources/frame0.png "$APP/Contents/Resources/frame0.png"
cp Resources/frame1.png "$APP/Contents/Resources/frame1.png"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/bark.wav "$APP/Contents/Resources/bark.wav"
cp Resources/otter.wav "$APP/Contents/Resources/otter.wav"

# Ad-hoc sign so Gatekeeper is a little friendlier on the recipient's Mac.
codesign --force --deep -s - "$APP" 2>/dev/null || true

echo "Built $APP"
echo "Run with: open \"$APP\"   (or \"./$APP/Contents/MacOS/$BIN\" to see logs)"
