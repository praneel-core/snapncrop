# Snapncrop architecture

A native Swift + AppKit menu bar app, built with Swift Package Manager (no Xcode project). SwiftUI is used only for the Preferences window.

Two code targets keep logic testable:

- **SnapncropCore**: pure logic with no windows (geometry, annotations, export, undo, OCR, shortcut model, tap detector). Fully unit-tested, including real pixel checks.
- **Snapncrop**: the app (AppKit windows, ScreenCaptureKit, Carbon hotkey, private MultitouchSupport, SwiftUI preferences).

## The one idea: freeze-frame capture

1. On any trigger, **capture every display first** at native resolution (ScreenCaptureKit), and read the list of on-screen windows.
2. Only then show one borderless overlay window per display, displaying the **frozen** image, dimmed.
3. Everything the user does works on the frozen image; the final picture is cut from it.

So the overlay never appears in the screenshot, and the result is exactly what was on screen when the shortcut was pressed.

## Flow

```
trigger ──▶ TriggerRouter ──▶ permission check ──▶ CaptureService (frozen shots + window list)
                                                          │
                                                          ▼
                                                   CaptureSession
                              ┌─ OverlayWindowController (one per display): dim, drag-select, window snap
                              └─ ToolbarPanel (floating, non-activating)
                                                          │ (selection made)
                                                          ▼
                              CanvasView: draw / select / move / resize annotations, crop handles, inline text
                                                          │
              ┌──────────────┬────────────────┬───────────┴───────┬──────────────────┐
              ▼              ▼                ▼                   ▼                  ▼
            Copy PNG       Save PNG        Pin to screen      OCR → text          Cancel
        (ExportService) (ExportService)    (PinManager)    (TextRecognizer)
```

## State machine (`CaptureSession`)

```
idle ──present()──▶ selecting ──mouse up──▶ editing ──copy / save / pin / OCR──▶ finished
                        │                      │
                        └──── Esc, error, display change ────────────────────────▶ cancelled
```

`end()` is the single teardown path: it closes every overlay and the toolbar, so the screen can never stay frozen. Any error path calls it first, and only then shows an alert.

## Triggers

Every way to start a capture calls `TriggerRouter.fire(_:)`; none touch capture code directly.

| Trigger | Mechanism |
|---|---|
| Global shortcut (default ⌃⌥S) | Carbon `RegisterEventHotKey` (no Input Monitoring permission). Re-registered when changed in Preferences; unregistered while recording a new one. |
| Menu bar item | `StatusItemController` |
| `snapncrop://capture` | URL scheme in `Info.plist`, handled in `AppDelegate` |
| Four-finger tap | `MultitouchGestureTrigger` behind the `GestureTrigger` protocol. Private `MultitouchSupport` loaded with `dlopen`, read-only, any failure falls back silently. The recognising logic is `FourFingerTapDetector` in Core (hardware-free, unit-tested). |

## Coordinate spaces

Defined once, converted in one place (`Geometry`):

| Space | Origin | Used for |
|---|---|---|
| Screen (AppKit global) | bottom-left | window frames, toolbar placement, pins |
| Display view | **top-left** | overlay and canvas views (`isFlipped = true`), the crop, **all annotations** |
| Image pixels | top-left | the captured `CGImage`, export crop |
| CoreGraphics global | top-left | window list from `CGWindowListCopyWindowInfo` |

**Annotations live in display coordinates** (points, top-left, relative to the display), not relative to the crop. That is what lets the crop be resized after the first drag without annotations moving: only the clip rectangle changes. Export translates by the crop origin and scales by `pixelWidth / pointWidth`, so strokes look identical on screen and in the PNG.

The pixel scale is derived from the real image (`image.width / display points`), never assumed from `backingScaleFactor`. Selections are snapped to the pixel grid so point sizes convert to whole pixels (100 pt at 2x is 200 px).

## Annotation model

`Annotation` is a protocol; each type is a plain value type that knows how to `draw(in: CGContext)`, hit-test, report `bounds` / `frame`, `translate`, and optionally `resize`. They stay vectors until export, so they remain editable.

| Type | Notes |
|---|---|
| `RectAnnotation`, `EllipseAnnotation` | outline shapes |
| `LineAnnotation`, `ArrowAnnotation` | two end points; resized by dragging ends |
| `PenAnnotation` | point list, smoothed with quadratic curves; resized by remapping points |
| `HighlightAnnotation` | translucent filled box |
| `TextAnnotation` | CoreText; font size from S/M/L or a dragged size; resize scales the font |
| `StepAnnotation` | numbered circle; numbers renumber when one is deleted |
| `BlurAnnotation` | pixelate; re-samples the **original** screenshot, so content cannot be recovered |

`AnnotationTool` enumerates the tools and builds shapes from a drag path (`makeShape`). `ToolContext` carries what a tool needs (the frozen image for pixelate, the next step number).

**Undo / redo** is `History<State>`: snapshots of the whole annotation array. Because annotations are values, a snapshot is cheap and no inverse operation has to be written for each edit. Move, resize, restyle, delete and add are each one step.

## Editing interactions (`CanvasView`)

One transparent view covers the whole display. A single `Drag` state decides what a mouse drag does:

`draw` (new shape) · `move` · `resizeAnnotation(handle)` · `moveEndpoint(i)` · `resizeCrop(handle)`

Hit order on mouse down: crop handles, then the selected annotation's handles, then the tool's own action (only inside the crop). Inline text editing is an `NSTextView` placed on the canvas and committed into a `TextAnnotation` on Esc, ⌘Return or click-away; the same font bridges between the editor and the exporter so what you type matches what is exported.

## Export and output

- `ExportRenderer.render` crops the frozen image and draws the annotations into a bitmap at **native pixel resolution**, then `pngData` writes a PNG with DPI metadata so it pastes at the right size on Retina.
- Copy puts PNG on the pasteboard; Save writes a timestamped file; OCR (`TextRecognizer`, Vision) reads the *original* crop and copies plain text; Pin hands the rendered image to `PinManager`.
- `PinPanel`: borderless floating panel (`.floating` level, all Spaces, full-screen auxiliary) that can become key for shortcuts without activating the app.

## Window snap

At capture time `CGWindowListCopyWindowInfo` returns on-screen windows front-to-back. Layer-0 windows (not menu bar / Dock / our own) are converted to each display's local space and clipped (`WindowSnap.localRect`). The overlay tracks the mouse, highlights the frontmost window under it (`WindowSnap.topmost`), and a click without a drag selects it.

## Windows and macOS behaviour worth knowing

- Overlay windows set `canBecomeKey = true` (borderless windows refuse by default), sit at `.screenSaver` level, and join all Spaces and full-screen apps. The app activates itself so Esc and typing reach it.
- The toolbar is a **non-activating panel** so clicking it never steals keyboard focus from the overlay.
- Toolbar hover hints use our own small panel because system tooltips are unreliable on a floating, non-key window.
- The Screen Recording permission is tied to the code signature. `build.sh` signs with a stable local certificate so the permission survives rebuilds; ad-hoc signing would reset it every build.
- The display configuration changing mid-capture cancels the session cleanly.

## Persistence and privacy

Only user preferences (`UserDefaults`, domain `com.praneelcore.snapncrop`) and the PNGs the user saves are written. *Recent screenshots* (last 5) are in memory only. There is no networking code and no telemetry; OCR runs on-device.

## Testing

`./scripts/test.sh` runs Swift Testing suites against SnapncropCore (the script adds the framework paths needed when only the Command Line Tools are installed). Tests render real bitmaps and read pixels back: crop size in pixels on a Retina scale, each annotation landing on the right pixels, moved and resized annotations exporting at their new place, pixelate destroying fine detail but leaving the outside untouched, Vision reading text the app drew, the tap detector rejecting swipes / holds / five fingers / staggered landings, and the pure geometry for handles, window snap, toolbar placement and pin zoom.

The AppKit layer (windows, mouse handling, menus) is verified by hand (press the shortcut, select, annotate, copy, paste into Notes, check sharpness on Retina, try a full-screen app and a second display).

## Status

Built: freeze-frame capture, selection with resizable crop, window snap, ten annotation tools, select / move / resize / restyle / delete, inline text editing, copy / save / pin / OCR, global shortcut with recorder, menu bar menu, Preferences, URL scheme, four-finger tap.

Not built (see README, *Known limitations*): multi-display selection, moving the whole crop, persistent history, a Gaussian-blur option.
