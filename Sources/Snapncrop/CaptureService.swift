import AppKit
import ScreenCaptureKit
import SnapncropCore

/// One frozen picture of one display plus the metadata needed to map points <-> pixels.
struct DisplayShot {
    let displayID: CGDirectDisplayID
    /// Display frame in AppKit global points (bottom-left origin).
    let frame: CGRect
    let image: CGImage
    /// App windows on this display (display-local points, top-left origin), ordered front to back.
    /// Used by "click a window to select it".
    var windows: [CGRect] = []
    /// Real pixels-per-point, derived from the captured image (not assumed from backingScaleFactor).
    var scale: CGFloat { CGFloat(image.width) / frame.width }
    var pointSize: CGSize { frame.size }
}

enum CaptureError: LocalizedError {
    case noDisplays
    var errorDescription: String? { "No displays could be captured." }
}

enum CaptureService {
    /// Captures every display at full native resolution BEFORE any overlay exists,
    /// so our own windows can never end up in the picture.
    @MainActor
    static func captureAllDisplays() async throws -> [DisplayShot] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let windowBounds = visibleWindowBounds()
        var shots: [DisplayShot] = []
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let display = content.displays.first(where: { $0.displayID == id }) else { continue }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            let pxPerPt = CGFloat(filter.pointPixelScale)           // 2.0 on Retina
            config.width = Int((CGFloat(display.width) * pxPerPt).rounded())
            config.height = Int((CGFloat(display.height) * pxPerPt).rounded())
            config.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            Log.capture.debug("display \(id): \(image.width)x\(image.height) px, frame \(NSStringFromRect(screen.frame))")
            var shot = DisplayShot(displayID: id, frame: screen.frame, image: image)
            let displayBounds = CGDisplayBounds(id)                  // global, top-left origin
            shot.windows = windowBounds.compactMap { WindowSnap.localRect(windowBounds: $0, displayBounds: displayBounds) }
            shots.append(shot)
        }
        if shots.isEmpty { throw CaptureError.noDisplays }
        return shots
    }

    /// Normal app windows currently on screen, frontmost first (global top-left coordinates).
    /// CoreGraphics already lists them in stacking order. Taken before our own overlay exists.
    private static func visibleWindowBounds() -> [CGRect] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        return info.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0,                      // layer 0 = ordinary app windows (not menu bar / Dock)
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
                  (w[kCGWindowOwnerPID as String] as? Int32) != me,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict as CFDictionary) else { return nil }
            return rect
        }
    }
}
