# Snapncrop

Lightshot-style screenshot + annotation tool for macOS. Free, local, no network, no analytics.
Repo: https://github.com/praneel-core/snapncrop

## Use
| Action | How |
|---|---|
| Start a capture | **⌃⌥S**, menu bar icon → Capture, `open snapncrop://capture`, or **four-finger tap** on the trackpad |
| Select | drag a region, **or hover a window and click** to capture exactly that window (switch off in Preferences) |
| Annotate | rectangle tool (colour + stroke width in the toolbar); ⌘Z / ⇧⌘Z undo/redo |
| **Copy to clipboard** | **Ctrl+C** (also ⌘C, Return, or the Copy button) |
| **Save** | **Ctrl+S** (also ⌘S or Save button) → `~/Pictures/Screenshots/Snapncrop <date> at <time>.png` |
| **Copy the text** in the selection (OCR) | **Ctrl+T**, or the text-viewfinder button. Runs on-device with Apple's Vision framework |
| **Pin to screen** | **Ctrl+P**, or the pin button. The picture floats above your windows where you selected it. Drag to move, scroll/pinch to resize, right-click for copy / save / opacity / close |
| Cancel | Esc |

## Menu bar menu
- **Status line:** "● Snapncrop is on" normally; turns into a clickable "Screen Recording permission needed" when it can't capture.
- **Capture**, then **Recent screenshots** (last 5, in memory only; click one to copy it again).
- Toggles that are remembered: four-finger tap, also save a file when copying, launch at login, finger-count tuning.
- **Preferences… (⌘,)**: record your own capture shortcut, choose the screenshots folder, set default colour and width, and the toggles.
- Open screenshots folder, About, Quit. The icon turns bold while a capture is in progress.

## Build & run (needs only Command Line Tools)
```
./scripts/create_signing_cert.sh   # ONE time: stable signature so macOS remembers the permission
./build.sh run                     # build, sign, launch   (./build.sh install → ~/Applications)
./scripts/test.sh                  # unit tests
```
Live logs: `/usr/bin/log stream --predicate 'subsystem == "com.praneelcore.snapncrop"' --level debug`

## First run
System Settings → Privacy & Security → Screen & System Audio Recording → enable **Snapncrop**, then quit and reopen it.

## Four-finger tap tuning
Menu → "Show finger count in menu bar" shows ✋N live. Thresholds are in `FourFingerTapDetector.Config`.
It uses a private Apple framework and may break on a macOS update; the hotkey always works regardless.
