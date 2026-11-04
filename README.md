# Snapncrop

**Snap and crop.** A free, fully local screenshot and annotation tool for macOS that lives in your menu bar, in the spirit of Lightshot on Windows.

Press a shortcut, the screen freezes, drag over what you want (or click a window), mark it up, and copy it, save it, pin it to your screen, or copy the text out of it.

- **No accounts, no network calls, no analytics.** Everything stays on your Mac. Text recognition runs on-device.
- Native Swift and AppKit. Runs on macOS 14 or later.
- Repo: https://github.com/praneel-core/snapncrop

---

## Contents

1. [Quick start](#quick-start) · [Download without building](#download-without-building)
2. [Taking a screenshot](#taking-a-screenshot)
3. [Annotation tools](#annotation-tools)
4. [Editing what you drew](#editing-what-you-drew)
5. [Finishing: copy, save, pin, copy text](#finishing-copy-save-pin-copy-text)
6. [Keyboard shortcuts](#keyboard-shortcuts)
7. [Menu bar menu](#menu-bar-menu)
8. [Preferences](#preferences)
9. [Ways to start a capture](#ways-to-start-a-capture)
10. [Install, build and run](#install-build-and-run)
11. [Permissions](#permissions)
12. [Troubleshooting](#troubleshooting)
13. [Privacy](#privacy)
14. [Known limitations](#known-limitations)
15. [Project layout](#project-layout)
16. [Development](#development)
17. [License](#license)

---

## Quick start

```bash
git clone https://github.com/praneel-core/snapncrop.git && cd snapncrop
./scripts/create_signing_cert.sh     # ONE time (asks for your Mac password)
./build.sh install                   # builds, signs, copies to ~/Applications
open ~/Applications/Snapncrop.app
```

Then press **⌃⌥S** (Control + Option + S). The first time, macOS asks for Screen Recording permission: turn on **Snapncrop**, quit it from its menu bar icon, and open it again. See [Permissions](#permissions).

You need the Xcode **Command Line Tools** (`xcode-select --install`). Full Xcode is not required.

### Download without building

If a zip is attached to the [Releases page](https://github.com/praneel-core/snapncrop/releases) you can skip the build:

1. Download `Snapncrop-<version>-arm64.zip` (Apple Silicon Macs; macOS 14 or later) and unzip it.
2. Move `Snapncrop.app` to `~/Applications` (or `/Applications`).
3. The app is **not notarized by Apple**, so macOS blocks it the first time. Open it once, then go to System Settings → Privacy & Security, scroll down and click **Open Anyway**. (Alternatively, in Terminal: `xattr -dr com.apple.quarantine ~/Applications/Snapncrop.app`.) The exact wording varies by macOS version.
4. Grant Screen Recording permission (see [Permissions](#permissions)), quit and reopen.

Because the downloadable app is signed ad-hoc rather than with a stable certificate, macOS may ask you to grant Screen Recording again after you replace it with a newer version. Building it yourself with the local certificate (above) avoids that. Intel Macs: build from source.

---

## Taking a screenshot

1. **Start:** press **⌃⌥S**, choose *Capture* from the menu bar icon, or use any other [trigger](#ways-to-start-a-capture). The screen freezes and dims. Your own overlay never appears in the picture, because the screenshot is taken before the overlay is shown.
2. **Select** a region in one of two ways:
   - **Drag** a rectangle. A live size label shows pixels, for example `640 × 380`.
   - **Hover a window and click.** The window under your pointer lights up with a blue outline. Click without dragging to capture exactly that window. (Turn this off in [Preferences](#preferences).)
3. A **toolbar** appears next to your selection (below it, or above, or inside if there is no room). Annotate, then finish.

The selection is not locked in. After the first drag you can drag the **eight white square handles** around the crop to make it bigger or smaller at any time. Annotations stay exactly where they are on screen while the crop changes, so growing the crop reveals more of the screenshot and shrinking it hides what falls outside. Anything outside the crop is left out of the copy or save.

Each display is captured separately at full native resolution (Retina included). A selection stays within one display.

---

## Annotation tools

Pick a tool from the toolbar or press its letter. **Hover any toolbar icon** to see its name and shortcut.

| Tool | Key | What it does |
|---|---|---|
| **Select** | `V` | Click an annotation to select it, drag to move it. See [Editing what you drew](#editing-what-you-drew). |
| **Rectangle** | `R` | Drag to draw an outlined box. |
| **Ellipse** | `E` | Drag to draw an outlined ellipse or circle. |
| **Line** | `L` | Drag from start to end. |
| **Arrow** | `A` | Drag from tail to head. The head grows with the stroke width. |
| **Pen** | `P` | Freehand drawing, smoothed. A single click leaves a dot. |
| **Highlighter** | `H` | Drag a translucent box, like a marker over text. Uses your colour at 35% opacity. |
| **Step number** | `N` | Click to drop a numbered circle: 1, 2, 3 in order. Drag before releasing to fine-tune the position. If you delete one, the later numbers close the gap. |
| **Pixelate** | `B` | Drag over sensitive information to replace it with large blocks. Built from the original screenshot, so the hidden content cannot be recovered from the saved image. Use size **L** to hide text completely. |
| **Text** | `T` | Click and type directly on the screenshot. `Return` adds a new line. `Esc`, `⌘Return`, or clicking elsewhere finishes. |

**Colour:** five swatches (red, blue, green, yellow, black).

**Width S / M / L:** stroke thickness for shapes, lines, arrows and the pen; font size for text (18 / 24 / 36 pt); circle size for step numbers; block size for pixelate (6 / 12 / 24 pt). It does not apply to the highlighter.

Your last colour and width are remembered. You can change the defaults in [Preferences](#preferences).

---

## Editing what you drew

Switch to the **Select** tool (`V`):

- **Select:** click an annotation. A dashed box appears. Clicking empty space deselects. Where shapes overlap, you grab the one drawn last. Outline shapes (rectangle, ellipse) are grabbed by their outline; text, highlighter, pixelate, step numbers and the pen are grabbed anywhere on the shape.
- **Move:** drag the selected annotation.
- **Resize:** drag a round handle. Shapes, the pen and pixelate boxes get eight handles. Lines and arrows get a handle on each end. Text and step numbers scale and keep their proportions.
- **Delete:** press `Delete`.
- **Restyle:** with something selected, click a colour or S / M / L to change that item. The toolbar shows the selected item's current settings.
- **Edit text:** double-click text with the Select tool, or click it with the Text tool. The text is pre-selected, so typing replaces it. Clearing it all and finishing deletes the text box.

Every change is one undo step: `⌘Z` to undo, `⇧⌘Z` to redo.

---

## Finishing: copy, save, pin, copy text

| Action | How | Result |
|---|---|---|
| **Copy image** | `Ctrl+C`, `⌘C`, `Return`, or the **Copy** button | PNG on the clipboard at native pixel resolution, ready to paste into Notes, Slack, email. |
| **Save** | `Ctrl+S`, `⌘S`, or the **Save** button | PNG written to your screenshots folder (default `~/Pictures/Screenshots`, created if missing) as `Snapncrop 2026-11-05 at 14.03.22.png`. |
| **Pin to screen** | `Ctrl+P` or the **pin** button | The finished picture floats above your other windows exactly where you selected it. |
| **Copy text** (OCR) | `Ctrl+T` or the **text-viewfinder** button | The text in the selection goes on the clipboard as plain text. |
| **Cancel** | `Esc` or the **Cancel** button | Nothing is copied. |

**Pinned screenshots.** Drag to move. Scroll or pinch to resize (proportions kept). Hover and click the **✕**, or click it and press `Esc` / `⌘W`, to close. Right-click for *Copy image*, *Save to screenshots folder*, *Opacity* (100 / 75 / 50 / 25 %), and *Close*. A pin appears on every Space and over full-screen apps. You can pin as many as you like; the menu bar menu offers *Close all pinned screenshots*.

**Copy text (OCR).** Uses Apple's Vision framework on your Mac, reads the original pixels (not your annotations), and puts text back in reading order: top to bottom, and left to right when several pieces share a row, such as table columns. A short message confirms "Copied N characters". If nothing readable is found you get "No text found" and the editor stays open so you can adjust the crop. Tiny text or busy backgrounds can read poorly; select a tighter area for best results.

You can also turn on **Also save a file when copying** so every Copy writes a PNG too.

---

## Keyboard shortcuts

**While editing a screenshot**

| Keys | Action |
|---|---|
| `Ctrl+C` · `⌘C` · `Return` | Copy image |
| `Ctrl+S` · `⌘S` | Save PNG |
| `Ctrl+T` | Copy the text in the selection (OCR) |
| `Ctrl+P` | Pin to screen |
| `Esc` | Cancel (while typing text: finish the text instead) |
| `⌘Z` · `⇧⌘Z` | Undo · Redo (while typing: undoes the typing) |
| `Delete` | Delete the selected annotation |
| `V` `R` `E` `L` `A` `P` `H` `N` `B` `T` | Select, Rectangle, Ellipse, Line, Arrow, Pen, Highlighter, Step number, Pixelate, Text |

**Anywhere**

| Keys | Action |
|---|---|
| `⌃⌥S` | Start a capture (changeable in Preferences) |
| `⌘,` | Open Preferences (with the menu bar menu open) |

---

## Menu bar menu

Click the crop icon in the menu bar. The icon turns bold while a capture is in progress.

- **Status line** at the top: "● Snapncrop is on — press ⌃⌥S to capture". If Screen Recording permission is missing it becomes a clickable "⚠︎ Screen Recording permission needed — click to fix".
- **Capture**
- **Recent screenshots:** your last 5 (in memory only, cleared when the app quits). Click one to copy it again.
- **Close all pinned screenshots (N):** appears when you have pins.
- **Toggles (remembered):** Four-finger tap to capture · Also save a file when copying · Launch at login · Show finger count (tuning).
- **Preferences…**
- **Open screenshots folder**
- **About Snapncrop**
- **Quit Snapncrop**

---

## Preferences

Menu bar icon → **Preferences…**. Changes apply immediately; there is no OK button.

- **Capture shortcut:** click the button and press the keys you want. It must include `⌃`, `⌥` or `⌘` (or be an F-key) so normal typing is never hijacked. `Esc` cancels recording and *Reset* restores `⌃⌥S`. If macOS or another app already uses the combination, you are told and your old shortcut stays.
- **Screenshots folder:** *Choose…* a folder, or *Open* it in Finder.
- **Drawing defaults:** colour and S / M / L.
- **Behaviour:** click a window to capture it · four-finger tap · also save a file when copying · launch at login.

Settings are stored with macOS's standard preferences system under `com.praneelcore.snapncrop`. To reset everything: `defaults delete com.praneelcore.snapncrop`.

---

## Ways to start a capture

All of these go through one place (`TriggerRouter`), so they behave identically.

| Trigger | Notes |
|---|---|
| **⌃⌥S** | Global shortcut, changeable in Preferences. Uses Carbon `RegisterEventHotKey`, so it needs no Accessibility or Input Monitoring permission. |
| **Menu bar → Capture** | |
| **`snapncrop://capture`** | A registered URL scheme. `open snapncrop://capture` from Terminal, or call it from BetterTouchTool, Shortcuts, Raycast or Hammerspoon. |
| **Four-finger tap** | Tap four fingers together on the trackpad. See below. |

### Four-finger tap

Detects four fingers landing together and lifting within about 0.3 seconds with very little movement (a tap, not a swipe). It ignores five fingers and resting palms, and is debounced so one tap fires once. It only **reads** the trackpad; it never blocks or changes macOS's own gestures.

It uses Apple's **private** `MultitouchSupport` framework, loaded at runtime, so a future macOS update could break it. If that happens it fails silently and the keyboard shortcut keeps working. Switch it on or off in the menu or Preferences. To tune it, turn on *Show finger count (tuning)* in the menu: a live `✋N` appears next to the icon, and the thresholds are in `FourFingerTapDetector.Config`.

---

## Install, build and run

Requirements: macOS 14+, Command Line Tools (`xcode-select --install`). Built with Swift Package Manager; no Xcode project.

```bash
./scripts/create_signing_cert.sh   # one time: creates "Snapncrop Local Dev" certificate in your login keychain
./build.sh                         # build + sign → build/Snapncrop.app
./build.sh run                     # build, sign, launch (restarts a running copy)
./build.sh install                 # build, sign, copy to ~/Applications
./scripts/test.sh                  # run the unit tests
```

**Why the certificate?** macOS ties the Screen Recording permission to the app's code signature. Ad-hoc signing changes on every rebuild, so macOS would forget the permission each time. A stable self-signed certificate (kept only on your Mac) avoids that. `build.sh` uses it automatically, and warns if it is missing. When the keychain asks whether `codesign` may use the key, click **Always Allow**.

**Launch at login** works when the app runs from `~/Applications` (use `./build.sh install`).

**Making a release zip** (for maintainers): `./scripts/make_release.sh` builds, signs ad-hoc, and writes `build/Snapncrop-<version>-<arch>.zip` plus its SHA-256 checksum, ready to attach to a GitHub Release. It builds for this Mac's architecture only (a universal build needs full Xcode). It is not notarized; that needs a paid Apple Developer account.

**Logs** (everything is logged locally):

```bash
/usr/bin/log stream --predicate 'subsystem == "com.praneelcore.snapncrop"' --level debug
```

---

## Permissions

- **Screen Recording (required).** System Settings → Privacy & Security → *Screen & System Audio Recording* → enable **Snapncrop**. Then quit Snapncrop (menu bar icon → Quit) and open it again; macOS only applies the permission to a fresh launch. macOS may occasionally ask you to re-confirm this permission.
- **Nothing else for normal use.** The shortcut, window snap and OCR need no extra permission.
- The four-finger tap reads the trackpad through a private framework. If it never fires on your Mac, check System Settings → Privacy & Security → *Input Monitoring* and use the finger-count display to see whether touches arrive at all.

---

## Troubleshooting

| Problem | Try |
|---|---|
| Pressing the shortcut does nothing | Check the menu bar status line for a permission warning. Another app may own the combination: record a different one in Preferences. Watch the logs (command above). |
| Permission keeps resetting after each rebuild | You are running an ad-hoc-signed build. Run `./scripts/create_signing_cert.sh` once, then `./build.sh install`. |
| `create_signing_cert.sh` fails with a PKCS12 or password error | Fixed for Homebrew OpenSSL; pull the latest version of the script. |
| The screenshot is blank or the capture alert appears | Grant Screen Recording permission, then quit and reopen Snapncrop. |
| "Launch at login" shows an error | Run the app from `~/Applications` (`./build.sh install`). |
| Four-finger tap does not fire | Turn on *Show finger count (tuning)* and tap: does it show `✋4`? If not, macOS may have changed the private API; use the shortcut. |
| Text from OCR is wrong or missing | Select a tighter area around the text; very small or low-contrast text reads poorly. |
| Want to start over | `defaults delete com.praneelcore.snapncrop` resets all settings. |

---

## Privacy

- No network access: the app contains no networking code and no telemetry.
- Screenshots exist only in memory until you copy or save them. *Recent screenshots* are kept in memory only and cleared when you quit.
- OCR uses Apple's on-device Vision framework.
- The only things written to disk are the PNGs you save, and your preferences.
- The pixelate tool replaces pixels with blocks computed from the original screenshot, so hidden content cannot be recovered from the exported image.

---

## Known limitations

- A selection must stay within **one display** (multi-display selection is not built).
- After the first drag you can resize the crop with its handles, but you cannot **move** the whole crop or start a **new** selection without cancelling.
- Step numbers are automatic; you cannot type your own number.
- Pixelate uses blocks only (no Gaussian blur option).
- **Recent screenshots** hold the last 5 and reset when the app quits; there is no persistent history yet.
- Window snap highlights windows that were visible at the moment you started the capture.
- Not notarized or packaged for distribution. It is meant to be built and run locally.
- The four-finger tap depends on a private Apple framework and may break after a macOS update.

---

## Project layout

```
Package.swift                 Swift package: SnapncropCore (logic), Snapncrop (app), tests
build.sh                      build + sign (+ run / install)
scripts/
  create_signing_cert.sh      one-time local signing certificate
  make_release.sh             builds a zip for a GitHub Release (ad-hoc signed)
  test.sh                     runs the tests (adds framework paths needed with Command Line Tools only)
Resources/Info.plist          bundle id, menu-bar-only app, snapncrop:// URL scheme
Sources/SnapncropCore/        pure logic, no windows, fully unit-tested
  Geometry.swift              coordinate maths, crop/pixel conversion, resize handles, window snap, pin zoom
  Annotation.swift            all annotation types + AnnotationTool + list helpers
  Export.swift                renders crop + annotations at native pixels, PNG encoding
  History.swift               undo / redo
  Shortcut.swift              keyboard shortcut model and formatting
  TextRecognition.swift       OCR (Vision) and reading-order layout
  FourFingerTapDetector.swift trackpad tap recogniser
Sources/Snapncrop/            the app
  main.swift, AppDelegate     start-up, wiring
  TriggerRouter               single entry point for every trigger
  HotkeyManager               global shortcut
  GestureTrigger              four-finger tap (private MultitouchSupport)
  PermissionManager           Screen Recording check and help
  CaptureService              ScreenCaptureKit capture + window list
  CaptureSession              state machine for one capture (select → edit → finish)
  OverlayWindowController     frozen overlay, dimming, selecting, window snap
  CanvasView                  drawing, selecting, moving, resizing, inline text, crop handles
  ToolbarPanel                floating toolbar with hover hints
  PinWindow                   pinned screenshots
  ExportService, Toast        clipboard / disk output, small fading messages
  StatusItemController        menu bar icon and menu
  PreferencesView / Model     Preferences window (SwiftUI)
  SettingsStore, LoginItem, RecentCaptures, Log
Tests/SnapncropCoreTests/     unit tests (Swift Testing)
ARCHITECTURE.md               how it fits together and why
LICENSE                       MIT
```

---

## Development

```bash
./scripts/test.sh              # 70+ unit tests: geometry, export pixels, every annotation, OCR, shortcuts, tap detector
./build.sh run                 # rebuild and relaunch
```

The tests render annotations into real images and check actual pixels (for example: a 100 pt selection exports as 200 px on a Retina display, a rectangle lands on the right pixels, pixelate destroys fine detail, Vision reads text drawn by the app).

**Workflow:** each feature is developed on its own branch (`feature/…`), tested, then merged into `main`.

**Adding a new annotation tool:**

1. Add a small struct in `Annotation.swift` that conforms to `Annotation` (draw, hit-test, bounds, translate; override `resize` if it can be resized).
2. Add a case to `AnnotationTool`, then a branch in `makeShape` and `isValid`.
3. Add a row to the tool list in `ToolbarPanel.swift` (icon + hover hint) and a key in `OverlayWindowController.swift`.
4. Add tests that render it and check pixels.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the design in more depth.

---

## License

MIT. See [LICENSE](LICENSE). You are free to use, copy, modify and share it.
