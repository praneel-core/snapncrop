import AppKit
import ScreenCaptureKit

/// One frozen picture of one display plus the metadata needed to map points <-> pixels.
struct DisplayShot {
    let displayID: CGDirectDisplayID
    /// Display frame in AppKit global points (bottom-left origin).
    let frame: CGRect
    let image: CGImage
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
            shots.append(DisplayShot(displayID: id, frame: screen.frame, image: image))
        }
        if shots.isEmpty { throw CaptureError.noDisplays }
        return shots
    }
}
