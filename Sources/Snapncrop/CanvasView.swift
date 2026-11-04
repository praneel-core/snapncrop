import AppKit
import CoreText
import SnapncropCore

/// Sits exactly over the selection. Draws the cropped screenshot, then the annotations (vectors),
/// then the shape currently being dragged. The same `draw(in:)` code is used for export, which is
/// what guarantees "what you see is what you copy".
/// Text box used for typing on the canvas. Esc or Cmd+Return finish; plain Return adds a new line.
final class InlineTextView: NSTextView {
    var onCommit: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCommit?() }       // Esc
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, event.modifierFlags.contains(.command) { onCommit?(); return }
        super.keyDown(with: event)
    }
}

final class CanvasView: NSView, NSTextViewDelegate {
    private let image: CGImage
    private unowned let session: CaptureSession
    private var dragPoints: [CGPoint] = []   // mouse path of the current drag
    private var preview: (any Annotation)?

    init(frame: CGRect, image: CGImage, session: CaptureSession) {
        self.image = image; self.session = session
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        Drawing.drawTopLeft(image, in: bounds, ctx: ctx)
        for a in session.annotations { a.draw(in: ctx) }
        preview?.draw(in: ctx)
    }

    // MARK: tool input (drag-to-draw shapes; the tool comes from the session)

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        commitText()                                     // clicking away finishes any text being typed
        if session.tool == .text { beginText(at: p); return }
        dragPoints = [p]
        if session.tool == .pen { updatePreview() }      // a click should show a dot straight away
    }

    override func mouseDragged(with event: NSEvent) {
        guard let last = dragPoints.last else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard hypot(p.x - last.x, p.y - last.y) >= 0.5 else { return }   // skip jitter
        dragPoints.append(p)
        updatePreview()
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragPoints = []; preview = nil; needsDisplay = true }
        guard let shape = preview, session.tool.isValid(points: dragPoints) else { return }
        session.commit(shape)
    }

    private func updatePreview() {
        preview = session.tool.makeShape(points: dragPoints, style: session.style)
        needsDisplay = true
    }

    // MARK: inline text

    private var editor: InlineTextView?
    private var editorStyle = StrokeStyle.default
    var isEditingText: Bool { editor != nil }

    private func beginText(at p: CGPoint) {
        editorStyle = session.style
        let probe = TextAnnotation(origin: p, text: "", style: editorStyle)
        let ct = TextAnnotation.font(size: probe.fontSize)
        let font = unsafeBitCast(ct, to: NSFont.self)     // CTFont and NSFont are toll-free bridged
        let lineH = ceil(CTFontGetAscent(ct) + CTFontGetDescent(ct) + CTFontGetLeading(ct))

        let tv = InlineTextView(frame: CGRect(x: p.x, y: p.y, width: 40, height: lineH))
        tv.drawsBackground = false
        tv.isRichText = false
        tv.font = font
        let color = NSColor(cgColor: editorStyle.color.cgColor) ?? .red
        tv.textColor = color
        tv.insertionPointColor = color
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isHorizontallyResizable = true
        tv.isVerticallyResizable = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.wantsLayer = true                               // faint outline so you can see the box
        tv.layer?.borderWidth = 1
        tv.layer?.borderColor = NSColor.white.withAlphaComponent(0.6).cgColor
        tv.delegate = self
        tv.onCommit = { [weak self] in self?.commitText() }
        addSubview(tv)
        editor = tv
        window?.makeFirstResponder(tv)
    }

    func textDidChange(_ notification: Notification) {
        guard let tv = editor, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc)
        tv.setFrameSize(NSSize(width: max(40, ceil(used.width) + 4), height: max(used.height, 20).rounded(.up)))
    }

    /// Turn what was typed into a TextAnnotation (empty text is simply dropped).
    func commitText() {
        guard let tv = editor else { return }
        editor = nil
        let text = tv.string
        let origin = tv.frame.origin
        tv.removeFromSuperview()
        window?.makeFirstResponder(superview)               // give keyboard shortcuts back to the overlay
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            session.commit(TextAnnotation(origin: origin, text: text, style: editorStyle))
        }
    }

    /// Throw away the text being typed (used by Undo while typing).
    func cancelText() {
        guard let tv = editor else { return }
        editor = nil
        tv.removeFromSuperview()
        window?.makeFirstResponder(superview)
    }
}
