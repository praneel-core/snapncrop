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

    // Annotations
    private(set) var history = History<[any Annotation]>(initial: [])
    var style = StrokeStyle(color: SettingsStore.shared.strokeColor, width: SettingsStore.shared.strokeWidth) {
        didSet { SettingsStore.shared.strokeColor = style.color; SettingsStore.shared.strokeWidth = style.width }
    }
    private(set) var tool: AnnotationTool = .rectangle
    func setTool(_ t: AnnotationTool) {
        finishTextEditing()
        tool = t
        if t != .select { selectedID = nil }
        toolbar?.refreshTool(t)
        canvas?.toolChanged()
    }

    // Selection (Select tool): which annotation is highlighted for moving / deleting.
    private(set) var selectedID: UUID?
    func select(_ id: UUID?) {
        selectedID = id
        if let a = selectedAnnotation { style = a.style; toolbar?.syncStyle() }   // toolbar shows the selected item's settings
        canvas?.needsDisplay = true
    }

    /// Toolbar colour / width choices: always become the drawing style, and also restyle the selected annotation.
    func setColor(_ c: RGBA) {
        style.color = c
        if tool == .select, var a = selectedAnnotation { a.style.color = c; replace(a) }
    }
    func setWidth(_ w: CGFloat) {
        style.width = w
        if tool == .select, var a = selectedAnnotation { a.applyWidth(w); replace(a) }
    }
    var selectedAnnotation: (any Annotation)? { annotations.first { $0.id == selectedID } }

    /// Commit a moved/edited annotation (undoable as one step).
    func replace(_ updated: any Annotation) {
        history.commit(AnnotationList.replacing(updated, in: annotations))
        canvas?.needsDisplay = true
        refreshToolbar()
    }

    func deleteSelected() { if let id = selectedID { delete(id) } }

    func delete(_ id: UUID) {
        history.commit(AnnotationList.removing(id: id, from: annotations))
        if selectedID == id { selectedID = nil }
        canvas?.needsDisplay = true
        refreshToolbar()
    }

    private func dropStaleSelection() {
        if let id = selectedID, !annotations.contains(where: { $0.id == id }) { selectedID = nil }
    }

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
        guard px.width >= 1, px.height >= 1 else { return }

        activeShot = shot; selection = snapped; pixelCrop = px
        state = .editing

        for c in controllers {
            if c.shot.displayID == shot.displayID { c.enterEditing(selection: snapped) }
            else { c.dimFully() }
        }
        let bar = ToolbarPanel(session: self)
        toolbar = bar
        positionToolbar()
        bar.orderFrontRegardless()
        refreshToolbar()
    }

    /// Keep the toolbar next to the selection (called again whenever the crop is resized).
    private func positionToolbar() {
        guard let bar = toolbar, let shot = activeShot, let snapped = selection else { return }
        let sel = Geometry.flipY(snapped, containerHeight: shot.frame.height).offsetBy(dx: shot.frame.minX, dy: shot.frame.minY)
        bar.setFrameOrigin(ToolbarPlacement.origin(selection: sel, toolbarSize: bar.frame.size, screenFrame: shot.frame))
    }

    /// Change the crop after the first drag (the user dragged one of its handles).
    /// Annotations are stored in display coordinates, so they stay exactly where they are.
    func resizeSelection(to rect: CGRect) {
        guard state == .editing, let shot = activeShot else { return }
        let clamped = Geometry.clamp(rect, to: CGRect(origin: .zero, size: shot.pointSize))
        guard clamped.width >= 8, clamped.height >= 8 else { return }       // keep a usable minimum
        let snapped = Geometry.snapToPixelGrid(clamped, scale: shot.scale)
        let px = Geometry.pixelRect(forPointRect: snapped, displayPointSize: shot.pointSize,
                                    imagePixelSize: CGSize(width: shot.image.width, height: shot.image.height))
        guard px.width >= 1, px.height >= 1 else { return }
        selection = snapped; pixelCrop = px
        for c in controllers where c.shot.displayID == shot.displayID { c.setSelection(snapped) }
        canvas?.selectionChanged()
        positionToolbar()
    }

    // MARK: annotations

    func commit(_ annotation: any Annotation) {
        history.commit(annotations + [annotation])
        canvas?.needsDisplay = true
        refreshToolbar()
    }
    func undo() { if isEditingText { canvas?.cancelText(); return }; if history.undo() { dropStaleSelection(); canvas?.needsDisplay = true; refreshToolbar() } }
    func redo() { finishTextEditing(); if history.redo() { dropStaleSelection(); canvas?.needsDisplay = true; refreshToolbar() } }
    func refreshToolbar() { toolbar?.refresh(canUndo: history.canUndo, canRedo: history.canRedo) }

    // MARK: output

    /// The finished picture: crop plus annotations, at native pixel resolution.
    private func renderImage() -> CGImage? {
        guard state == .editing, let shot = activeShot, let sel = selection, let crop = pixelCrop else { return nil }
        return ExportRenderer.render(frozen: shot.image, pixelCrop: crop, selectionSize: sel.size,
                                     annotations: annotations, selectionOrigin: sel.origin)
    }

    private func renderPNG() -> Data? {
        guard let shot = activeShot, let img = renderImage() else { return nil }
        return ExportRenderer.pngData(from: img, scale: shot.scale)
    }

    /// Leave the finished picture floating on screen exactly where it was selected.
    func pinAndClose() {
        finishTextEditing()
        guard let shot = activeShot, let sel = selection, let img = renderImage() else { return }
        let onScreen = CGRect(x: shot.frame.minX + sel.minX, y: shot.frame.maxY - sel.maxY,
                              width: sel.width, height: sel.height)               // top-left view space -> screen space
        end(.finished)
        PinManager.shared.pin(image: img, scale: shot.scale, frame: onScreen)
    }

    // MARK: OCR (copy the text in the selection)

    private var recognizing = false

    /// Reads the text in the selected region (from the ORIGINAL pixels, without your annotations)
    /// and puts it on the clipboard. Runs on a background thread; the overlay stays up meanwhile.
    func copyTextAndClose() {
        finishTextEditing()
        guard state == .editing, !recognizing, let shot = activeShot, let sel = selection, let crop = pixelCrop,
              let image = shot.image.cropping(to: crop) else { return }
        recognizing = true
        let centre = NSPoint(x: shot.frame.minX + sel.midX, y: shot.frame.maxY - sel.midY)   // selection centre, screen coords
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let text = TextRecognizer.recognize(image).trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                guard let self else { return }
                self.recognizing = false
                guard self.state == .editing else { return }             // cancelled while reading
                if text.isEmpty {
                    Toast.show("No text found", at: centre)              // stay in the editor so you can adjust the crop
                } else {
                    ExportService.copyText(text)
                    Log.capture.info("copied \(text.count) characters of text")
                    self.end(.finished)
                    Toast.show("Copied \(text.count) characters", at: centre)
                }
            }
        }
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
