import AppKit
import SnapncropCore

/// Borderless window that must be able to take keyboard focus (borderless windows refuse by default).
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// One full-screen overlay for one display: frozen picture + dimming + selection + (later) the canvas.
final class OverlayWindowController {
    let shot: DisplayShot
    private let window: OverlayWindow
    private let view: OverlayView

    init(shot: DisplayShot, session: CaptureSession) {
        self.shot = shot
        view = OverlayView(shot: shot, session: session)
        window = OverlayWindow(contentRect: shot.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.setFrame(shot.frame, display: false)
        window.contentView = view
        window.level = .screenSaver                       // above normal apps and full-screen apps
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isOpaque = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
    }

    func showWindow() { window.orderFrontRegardless() }
    func makeKey() { window.makeKeyAndOrderFront(nil); window.makeFirstResponder(view) }
    func close() { window.orderOut(nil); window.contentView = nil; window.close() }

    func enterEditing(selection: CGRect) {
        makeKey()
        view.enterEditing(selection: selection)
    }
    func setSelection(_ r: CGRect) { view.setSelection(r) }
    func dimFully() { view.dimFully() }
}

final class OverlayView: NSView {
    private let shot: DisplayShot
    private unowned let session: CaptureSession
    private var selection: CGRect?
    private var dragStart: CGPoint?
    private var fullyDimmed = false

    init(shot: DisplayShot, session: CaptureSession) {
        self.shot = shot; self.session = session
        super.init(frame: CGRect(origin: .zero, size: shot.frame.size))
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }              // top-left origin, same as the screenshot
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        Drawing.drawTopLeft(shot.image, in: bounds, ctx: ctx)

        // Dim everything except the selection (even-odd fill leaves a clear hole).
        ctx.setFillColor(CGColor(gray: 0, alpha: fullyDimmed ? 0.6 : 0.45))
        ctx.addRect(bounds)
        if let s = selection { ctx.addRect(s) }
        ctx.drawPath(using: .eoFill)

        guard let s = selection else { return }
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
        ctx.setLineWidth(1)
        ctx.stroke(s.insetBy(dx: -0.5, dy: -0.5))
        drawSizeLabel(for: s)
    }

    private func drawSizeLabel(for s: CGRect) {
        let w = Int((s.width * shot.scale).rounded()), h = Int((s.height * shot.scale).rounded())
        let text = "\(w) × \(h)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        let pad: CGFloat = 6
        var box = CGRect(x: s.minX, y: s.minY - size.height - pad * 2 - 4,
                         width: size.width + pad * 2, height: size.height + pad)
        if box.minY < 2 { box.origin.y = s.minY + 4 }            // no room above: tuck inside
        box.origin.x = min(box.origin.x, bounds.maxX - box.width - 2)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        text.draw(at: CGPoint(x: box.minX + pad, y: box.minY + pad / 2), withAttributes: attrs)
    }

    // MARK: selecting

    private var isMySelection: Bool { session.activeShot == nil }

    override func mouseDown(with event: NSEvent) {
        guard session.state == .selecting else { return }
        dragStart = convert(event.locationInWindow, from: nil)
        selection = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard session.state == .selecting, let start = dragStart else { return }
        let p = convert(event.locationInWindow, from: nil)
        selection = Geometry.clamp(Geometry.normalizedRect(from: start, to: p), to: bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard session.state == .selecting, dragStart != nil else { return }
        dragStart = nil
        guard let s = selection, s.width >= 4, s.height >= 4 else {   // a plain click: start over
            selection = nil; needsDisplay = true; return
        }
        session.finishSelection(s, on: shot)
    }

    // MARK: editing

    func enterEditing(selection s: CGRect) {
        selection = s
        // The canvas covers the whole display (transparent outside the crop) so the crop's handles
        // and annotations can be dragged anywhere, and annotations can live in display coordinates.
        let canvas = CanvasView(frame: bounds, frozen: shot.image, session: session)
        addSubview(canvas)
        session.canvas = canvas
        needsDisplay = true
    }

    func setSelection(_ r: CGRect) { selection = r; needsDisplay = true }

    func dimFully() { fullyDimmed = true; selection = nil; needsDisplay = true }

    // MARK: keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: session.cancel()                                          // Esc
        case 51, 117:                                                      // Delete / Forward delete
            if session.state == .editing { session.deleteSelected() }
        case 36, 76: if session.state == .editing { session.copyAndClose() } // Return / Enter
        case 8 where session.state == .editing && event.modifierFlags.contains(.control):  // Ctrl+C
            session.copyAndClose()
        case 1 where session.state == .editing && event.modifierFlags.contains(.control):  // Ctrl+S
            session.saveAndClose()
        default:
            // Tool shortcuts (plain letters while editing): R rectangle, E ellipse, L line, A arrow, P pen, H highlighter, T text, V select, B pixelate
            if session.state == .editing, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
               let key = event.charactersIgnoringModifiers?.lowercased() {
                switch key {
                case "r": session.setTool(.rectangle); return
                case "e": session.setTool(.ellipse); return
                case "l": session.setTool(.line); return
                case "a": session.setTool(.arrow); return
                case "p": session.setTool(.pen); return
                case "h": session.setTool(.highlighter); return
                case "t": session.setTool(.text); return
                case "v": session.setTool(.select); return
                case "b": session.setTool(.pixelate); return
                default: break
                }
            }
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard session.state == .editing, !session.isEditingText,   // while typing, ⌘C/⌘Z belong to the text box
              let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch (key, flags) {
        case ("c", [.command]), ("c", [.control]): session.copyAndClose(); return true
        case ("s", [.command]), ("s", [.control]): session.saveAndClose(); return true
        case ("z", [.command]): session.undo(); return true
        case ("z", [.command, .shift]): session.redo(); return true
        default: return false
        }
    }
}
