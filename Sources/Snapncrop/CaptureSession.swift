import AppKit
import SnapncropCore

/// Owns everything about ONE capture, from hotkey to copy/save/cancel.
///
///   idle ──present()──▶ selecting ──mouse up──▶ editing ──copy/save──▶ finished
///                          │                       │
///                          └────── Esc / error ────┴──────────────────▶ cancelled
///
/// Whatever the ending, `end()` closes every overlay window and the toolbar, so the screen
/// can never stay frozen.
final class CaptureSession {
    enum State { case idle, selecting, editing, finished, cancelled }

    private(set) var state: State = .idle
    var onEnd: (() -> Void)?

    private let shots: [DisplayShot]
    private var controllers: [OverlayWindowController] = []
    private var toolbar: ToolbarPanel?
    private var screenObserver: NSObjectProtocol?

    // Selection (valid from `.editing`)
    private(set) var activeShot: DisplayShot?
    private(set) var selection: CGRect?          // display points, top-left origin
    private(set) var pixelCrop: CGRect?
    private(set) var croppedImage: CGImage?

    // Annotations
    private(set) var history = History<[any Annotation]>(initial: [])
    var style = StrokeStyle(color: SettingsStore.shared.strokeColor, width: SettingsStore.shared.strokeWidth) {
        didSet { SettingsStore.shared.strokeColor = style.color; SettingsStore.shared.strokeWidth = style.width }
    }
    private(set) var tool: AnnotationTool = .rectangle
    func setTool(_ t: AnnotationTool) { finishTextEditing(); tool = t; toolbar?.refreshTool(t) }

    // Text typing is owned by the canvas; the session just makes sure it is finished before output.
    var isEditingText: Bool { canvas?.isEditingText ?? false }
    func finishTextEditing() { canvas?.commitText() }
    var annotations: [any Annotation] { history.current }
    var canvas: CanvasView?

    init(shots: [DisplayShot]) { self.shots = shots }

    // MARK: lifecycle

    func present() {
        state = .selecting
        controllers = shots.map { OverlayWindowController(shot: $0, session: self) }
        let mouse = NSEvent.mouseLocation
        let primary = controllers.first(where: { $0.shot.frame.contains(mouse) }) ?? controllers[0]
        for c in controllers { c.showWindow() }
        NSApp.activate(ignoringOtherApps: true)     // needed so Esc / typing reach us
        primary.makeKey()

        // Plugging/unplugging a display mid-capture would leave stale geometry: just bail out cleanly.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.cancel()
        }
    }

    func cancel() {
        guard state == .selecting || state == .editing else { return }
        end(.cancelled)
    }

    private func end(_ final: State) {
        state = final
        if let o = screenObserver { NotificationCenter.default.removeObserver(o); screenObserver = nil }
        toolbar?.orderOut(nil); toolbar = nil
        canvas = nil
        controllers.forEach { $0.close() }
        controllers.removeAll()
        let cb = onEnd; onEnd = nil
        cb?()
    }

    // MARK: selecting → editing

    /// Called by the overlay that the user dragged on.
    func finishSelection(_ rect: CGRect, on shot: DisplayShot) {
        guard state == .selecting else { return }
        let snapped = Geometry.snapToPixelGrid(rect, scale: shot.scale)
        let px = Geometry.pixelRect(forPointRect: snapped, displayPointSize: shot.pointSize,
                                    imagePixelSize: CGSize(width: shot.image.width, height: shot.image.height))
        guard px.width >= 1, px.height >= 1, let cropped = shot.image.cropping(to: px) else { return }

        activeShot = shot; selection = snapped; pixelCrop = px; croppedImage = cropped
        state = .editing

        for c in controllers {
            if c.shot.displayID == shot.displayID { c.enterEditing(selection: snapped, cropped: cropped) }
            else { c.dimFully() }
        }
        let bar = ToolbarPanel(session: self)
        toolbar = bar
        let h = shot.frame.height
        let sel = Geometry.flipY(snapped, containerHeight: h).offsetBy(dx: shot.frame.minX, dy: shot.frame.minY)
        bar.setFrameOrigin(ToolbarPlacement.origin(selection: sel, toolbarSize: bar.frame.size, screenFrame: shot.frame))
        bar.orderFrontRegardless()
        refreshToolbar()
    }

    // MARK: annotations

    func commit(_ annotation: any Annotation) {
        history.commit(annotations + [annotation])
        canvas?.needsDisplay = true
        refreshToolbar()
    }
    func undo() { if isEditingText { canvas?.cancelText(); return }; if history.undo() { canvas?.needsDisplay = true; refreshToolbar() } }
    func redo() { finishTextEditing(); if history.redo() { canvas?.needsDisplay = true; refreshToolbar() } }
    func refreshToolbar() { toolbar?.refresh(canUndo: history.canUndo, canRedo: history.canRedo) }

    // MARK: output

    private func renderPNG() -> Data? {
        guard state == .editing, let shot = activeShot, let sel = selection, let crop = pixelCrop,
              let img = ExportRenderer.render(frozen: shot.image, pixelCrop: crop,
                                              selectionSize: sel.size, annotations: annotations)
        else { return nil }
        return ExportRenderer.pngData(from: img, scale: shot.scale)
    }

    func copyAndClose() {
        finishTextEditing()
        guard let png = renderPNG() else { fail("Could not render the screenshot."); return }
        ExportService.copyToClipboard(png: png)
        Log.capture.info("copied \(png.count) bytes to clipboard")
        var saved: URL?
        if SettingsStore.shared.alsoSaveOnCopy { saved = try? ExportService.save(png: png) }
        remember(png, savedAs: saved)
        end(.finished)
    }

    func saveAndClose() {
        finishTextEditing()
        guard let png = renderPNG() else { fail("Could not render the screenshot."); return }
        do {
            let url = try ExportService.save(png: png)
            Log.capture.info("saved \(url.path)")
            remember(png, savedAs: url)
            end(.finished)
        } catch {
            fail("Could not save the file: \(error.localizedDescription)")
        }
    }

    private func remember(_ png: Data, savedAs: URL?) {
        guard let crop = pixelCrop else { return }
        RecentCaptures.shared.add(png: png, width: Int(crop.width), height: Int(crop.height), savedAs: savedAs)
    }

    private func fail(_ message: String) {
        end(.cancelled)                       // tear down FIRST so the alert isn't hidden behind the overlay
        let a = NSAlert(); a.messageText = "Snapncrop"; a.informativeText = message; a.runModal()
    }
}
