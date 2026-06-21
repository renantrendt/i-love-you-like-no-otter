# I love you like no otter

**A tiny macOS menu-bar buddy that nudges you to log your working hours.**

Every interval a little otter pops onto your screen. Click it and it dissolves into
pixels — a gentle, hard-to-ignore reminder so you don't lose track of time.

> Forked from [worklog-buddy](https://github.com/renantrendt/worklog-buddy) — same idea, dressed up as an otter (and a dog) and packaged as a gift.

## Features

- 🦦 **Your otter** (a 2-frame pixel animation) appears on a schedule and **pixel-dissolves** away when clicked.
- 🖱️ **Drag it anywhere** — drop it where you like and it reappears there next time.
- 📊 **Menu-bar control** with a live countdown (in the dropdown), snooze, and pause.
- ⏰ **Active hours & days** so it never nags you at 2 a.m. or on weekends.
- 🚀 **Launch at Login** toggle (native `SMAppService`).
- 🎚️ **Preferences** for interval, placement, otter size, and sound.
- 🪶 Native **Swift + AppKit**, a single source file, no Xcode project and no runtime dependencies.

## Build & run

Requires macOS 13+ with the Swift toolchain (Xcode or the Command Line Tools).

```bash
./build.sh          # compiles a universal (arm64 + x86_64) "I love you like no otter.app"
open "I love you like no otter.app"
```

The app lives in the menu bar (no Dock icon). Click the otter icon for options, or
**Show otter now** to preview it immediately.

## Package the gift (DMG)

```bash
./build_dmg.sh      # builds the app, then a drag-to-Applications "I love you like no otter.dmg"
```

AirDrop or send the resulting `.dmg`. The recipient opens it and drags the otter into Applications.

### Opening it on macOS (Gatekeeper)

The app isn't notarized by Apple (no paid Developer account), so on first launch macOS will
block it. Either:

- **System Settings → Privacy & Security → Open Anyway**, then confirm and **Open Anyway** once more, or
- if it says the app is *"damaged"*, clear the quarantine flag in Terminal:

```bash
xattr -cr "/Applications/I love you like no otter.app"
```

After the first launch it opens normally.

## How it works

- A lightweight timer checks every few seconds whether it's time to nudge, but only inside
  your configured **active hours and days**.
- When it's time, a borderless, always-on-top window pops in (fade + slide) at your chosen spot.
- A **click** dissolves the otter into growing pixel blocks (`CIPixellate`) while fading, then
  schedules the next nudge; a **drag** repositions it.
- All settings persist via `UserDefaults`.

## Project layout

| Path | Purpose |
|------|---------|
| `Sources/main.swift` | The entire app — frame animation, pixel-dissolve, scheduling, menu bar, preferences. |
| `Resources/frame0.png`, `frame1.png` | The buddy animation frames (exported from Piskel). |
| `Resources/AppIcon.icns` | The app icon (otter + dog on a card-blue plate). |
| `build.sh` | Compiles and bundles the universal `.app`. |
| `build_dmg.sh` | Builds the drag-to-Applications DMG. |
| `dmg_background.png` | The installer window background. |
| `Info.plist` | Bundle metadata (`LSUIElement` = menu-bar agent). |

## License

MIT
