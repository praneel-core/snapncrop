# Snapncrop architecture

Native Swift + AppKit menu bar app, built with Swift Package Manager (no Xcode needed).
Two targets: **SnapncropCore** (pure logic, unit-tested) and **Snapncrop** (the app).

## Flow
trigger → `TriggerRouter` → permission check → `CaptureService` (freeze every display) →
`CaptureSession` shows one `OverlayWindowController` per display → drag to select →
editing (`CanvasView` + `ToolbarPanel`) → Copy / Save / Cancel → `ExportRenderer` → clipboard or file.

The screenshot is taken **before** any overlay window exists, so our UI never appears in it.

## State machine (`CaptureSession`)
```
idle → selecting → editing → finished
          └─ Esc / error / display change ─┴→ cancelled
```
`end()` always closes every overlay and the toolbar.

## Modules
| File | Role |
|---|---|
| `TriggerRouter` | single entry point; hotkey, menu, `snapncrop://capture`, gesture all call `fire(_:)` |
| `HotkeyManager` | Carbon `RegisterEventHotKey` (⌃⌥S), no extra permission |
| `GestureTrigger` / `MultitouchGestureTrigger` | optional four-finger tap via private MultitouchSupport, loaded with `dlopen`; read-only |
| `PermissionManager` | Screen Recording check + help dialog |
| `CaptureService` | ScreenCaptureKit, returns `DisplayShot` (CGImage + frame; scale derived from pixels) |
| `OverlayWindowController` / `OverlayView` | frozen image, dim, drag-select, size label (pixels), keyboard |
| `CanvasView` | shows crop + annotations, handles tool mouse input |
| `ToolbarPanel` | non-activating floating panel (keeps keyboard focus on the overlay) |
| `ExportService` | clipboard + timestamped PNG in the screenshots folder |
| `SettingsStore` | UserDefaults |
| Core: `Geometry` | one place for flip-Y, pixel snapping, point→pixel crop, toolbar placement |
| Core: `Annotation` | protocol + `RectAnnotation`; value types in selection-local points |
| Core: `History<State>` | snapshot undo/redo |
| Core: `ExportRenderer` | crop + draw annotations at native pixels, PNG with DPI |
| Core: `FourFingerTapDetector` | tap recogniser, hardware-free |

## Coordinates
Overlay/canvas views are `isFlipped` (top-left origin) like the image, so the only flip is
`Geometry.flipY` when placing the toolbar in AppKit screen space. Annotations are in points;
export scales by `pixelWidth / pointWidth`, so line widths match on screen and in the PNG.
Selections are snapped to the pixel grid so point sizes convert to whole pixels.

## Plan
- **Phase 2:** ellipse, line, arrow, pen, highlighter, text (inline editor), select/move/delete,
  tool shortcuts, Preferences window (SwiftUI), hotkey recorder, selection resize handles, NSSavePanel option.
- **Phase 3:** blur/pixelate, numbered steps, pin to screen, history, OCR (Vision), window snap, multi-display selection.
- **Gesture polish:** four-finger click, sensitivity settings, Preferences toggle.
