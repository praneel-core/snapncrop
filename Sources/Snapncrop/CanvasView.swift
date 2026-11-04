import AppKit
import CoreText
import SnapncropCore

/// Text box used for typing on the canvas. Esc or Cmd+Return finish; plain Return adds a new line.
final class InlineTextView: NSTextView {
    var onCommit: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCommit?() }       // Esc
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, event.modifierFlags.contains(.command) { onCommit?(); return }
        super.keyDown(with: event)
    }
}

/// Covers the whole display (transparent outside the crop). Everything on it is in DISPLAY points
/// (top-left origin), the same space as the crop rectangle. That is what lets the crop be resized
/// later without annotations moving: only the clip rectangle changes.
///
/// Draws: the frozen screenshot and the annotations clipped to the crop, then the crop's handles
/// and the selected annotation's handles on top. The same `draw(in:)` code is used for export,
/// which guarantees "what you see is what you copy".
final class CanvasView: NSView, NSTextViewDelegate {
    private let frozen: CGImage
    private unowned let session: CaptureSession

    /// What the current mouse drag is doing.
    private enum Drag {
        case none
        case draw                        // drawing a new shape with the active tool
        case move                        // moving the selected annotation
        case resizeAnnotation(ResizeHandle)
        case moveEndpoint(Int)           // line / arrow end point
        case resizeCrop(ResizeHandle)    // changing the crop rectangle
    }
    private var drag = Drag.none
    private var dragPoints: [CGPoint] = []       // mouse path while drawing
    private var preview: (any Annotation)?       // new shape being drawn
    private var moving: (any Annotation)?        // live copy of the annotation being moved / resized
    private var original: (any Annotation)?      // that annotation as it was at mouse down
    private var startFrame = CGRect.zero         // frame at mouse down (annotation or crop)
    private var lastDragPoint = CGPoint.zero
    private var totalMoved = CGSize.zero
    private var dirty = false

    private let handleRadius: CGFloat = 7

    init(frame: CGRect, frozen: CGImage, session: CaptureSession) {
        self.frozen = frozen; self.session = session
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: cursors

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
        guard let sel = session.selection else { return }
        addCursorRect(sel, cursor: session.tool == .select ? .arrow : (session.tool == .text ? .iBeam : .crosshair))
        for h in ResizeHandle.allCases {                      // added last so they win where they overlap
            let c = h.position(in: sel)
            let r = CGRect(x: c.x - handleRadius, y: c.y - handleRadius, width: handleRadius * 2, height: handleRadius * 2)
            addCursorRect(r, cursor: cursor(for: h))
        }
    }

    private func cursor(for h: ResizeHandle) -> NSCursor {
        switch h {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        default: return .crosshair
        }
    }

    func toolChanged() { window?.invalidateCursorRects(for: self); needsDisplay = true }
    func selectionChanged() { window?.invalidateCursorRects(for: self); needsDisplay = true }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let sel = session.selection else { return }

        ctx.saveGState()
        ctx.clip(to: sel)                                     // nothing is visible outside the crop
        Drawing.drawTopLeft(frozen, in: bounds, ctx: ctx)
        for a in session.annotations {
            if a.id == editingExisting?.id { continue }          // hidden while its text is being edited
            if let m = moving, m.id == a.id { m.draw(in: ctx) } else { a.draw(in: ctx) }
        }
        preview?.draw(in: ctx)
        ctx.restoreGState()

        drawAnnotationHandles(ctx)
        drawCropHandles(ctx, sel)
    }

    private func drawCropHandles(_ ctx: CGContext, _ sel: CGRect) {
        ctx.saveGState()
        for h in ResizeHandle.allCases {
            let c = h.position(in: sel)
            let r = CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(r)
            ctx.setStrokeColor(CGColor(gray: 0.15, alpha: 1)); ctx.setLineWidth(1); ctx.stroke(r)
        }
        ctx.restoreGState()
    }

    /// Dashed box + round handles on the selected annotation (Select tool only).
    private func drawAnnotationHandles(_ ctx: CGContext) {
        guard session.tool == .select, let id = session.selectedID else { return }
        guard let a = (moving?.id == id ? moving : nil) ?? session.selectedAnnotation else { return }
        let accent = NSColor.controlAccentColor.cgColor
        ctx.saveGState()
        ctx.setStrokeColor(accent)
        ctx.setLineWidth(1.5)
        var points: [CGPoint]
        if let eps = a.endpoints {
            points = eps                                       // lines / arrows: just the two ends
        } else {
            ctx.setLineDash(phase: 0, lengths: [5, 3])
            ctx.stroke(a.frame)
            ctx.setLineDash(phase: 0, lengths: [])
            points = ResizeHandle.allCases.map { $0.position(in: a.frame) }
        }
        for c in points {
            let r = CGRect(x: c.x - 4.5, y: c.y - 4.5, width: 9, height: 9)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fillEllipse(in: r)
            ctx.strokeEllipse(in: r)
        }
        ctx.restoreGState()
    }

    // MARK: mouse

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        commitText()                                          // clicking away finishes any text being typed
        guard let sel = session.selection else { return }

        // 1. Crop handles always come first, so the crop can be changed at any time.
        if let h = ResizeHandle.hit(p, in: sel, radius: handleRadius) {
            drag = .resizeCrop(h); startFrame = sel; return
        }

        // 2. Handles of the selected annotation (Select tool).
        if session.tool == .select, let a = session.selectedAnnotation {
            if let eps = a.endpoints {
                if let i = eps.firstIndex(where: { hypot($0.x - p.x, $0.y - p.y) <= handleRadius }) {
                    drag = .moveEndpoint(i); original = a; moving = a; return
                }
            } else if let h = ResizeHandle.hit(p, in: a.frame, radius: handleRadius) {
                drag = .resizeAnnotation(h); original = a; moving = a; startFrame = a.frame; return
            }
        }

        // 3. Everything else only reacts inside the crop.
        guard sel.contains(p) else { if session.tool == .select { session.select(nil) }; return }

        switch session.tool {
        case .select:
            if let i = AnnotationList.topmost(at: p, in: session.annotations) {
                let hit = session.annotations[i]
                session.select(hit.id)
                if event.clickCount == 2, let t = hit as? TextAnnotation { beginEditing(existing: t); return }   // double-click edits
                drag = .move; moving = hit; original = hit; lastDragPoint = p; totalMoved = .zero
            } else {
                session.select(nil)
            }
        case .text:
            if let i = AnnotationList.topmost(at: p, in: session.annotations),
               let t = session.annotations[i] as? TextAnnotation {
                session.select(t.id); beginEditing(existing: t)       // clicking existing text edits it
            } else {
                beginText(at: p)
            }
        default:
            drag = .draw
            dragPoints = [p]
            if session.tool == .pen { updatePreview() }       // a click should show a dot straight away
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        switch drag {
        case .resizeCrop(let h):
            session.resizeSelection(to: h.apply(dragTo: p, frame: startFrame))
        case .resizeAnnotation(let h):
            guard var a = original else { return }
            a.resize(to: h.apply(dragTo: p, frame: startFrame, keepAspect: a.keepsAspectRatio))
            moving = a; dirty = true
        case .moveEndpoint(let i):
            guard var a = original else { return }
            a.moveEndpoint(i, to: p)
            moving = a; dirty = true
        case .move:
            let d = CGSize(width: p.x - lastDragPoint.x, height: p.y - lastDragPoint.y)
            moving?.translate(by: d)
            totalMoved.width += d.width; totalMoved.height += d.height
            lastDragPoint = p
        case .draw:
            guard let last = dragPoints.last, hypot(p.x - last.x, p.y - last.y) >= 0.5 else { return }   // skip jitter
            dragPoints.append(p)
            updatePreview()
        case .none:
            return
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            drag = .none; dragPoints = []; preview = nil
            moving = nil; original = nil; dirty = false; totalMoved = .zero
            needsDisplay = true
        }
        switch drag {
        case .resizeAnnotation, .moveEndpoint:
            if dirty, let m = moving { session.replace(m) }
        case .move:
            if hypot(totalMoved.width, totalMoved.height) >= 1, let m = moving { session.replace(m) }   // a plain click only selects
        case .draw:
            if let shape = preview, session.tool.isValid(points: dragPoints) { session.commit(shape) }
        case .resizeCrop, .none:
            break
        }
    }

    private func updatePreview() {
        preview = session.tool.makeShape(points: dragPoints, style: session.style)
        needsDisplay = true
    }

    // MARK: inline text

    private var editor: InlineTextView?
    private var editorStyle = StrokeStyle.default
    var isEditingText: Bool { editor != nil }

    private var editingExisting: TextAnnotation?        // set while re-editing text that was already placed

    private func beginText(at p: CGPoint) {
        let style = session.style
        startEditor(origin: p, style: style, fontSize: TextAnnotation(origin: p, text: "", style: style).fontSize, text: "")
    }

    /// Re-open an existing text annotation for editing in place.
    private func beginEditing(existing t: TextAnnotation) {
        editingExisting = t
        startEditor(origin: t.origin, style: t.style, fontSize: t.fontSize, text: t.text)
        needsDisplay = true
    }

    private func startEditor(origin p: CGPoint, style: StrokeStyle, fontSize: CGFloat, text: String) {
        editorStyle = style
        let ct = TextAnnotation.font(size: fontSize)
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
        if !text.isEmpty {
            tv.string = text
            textDidChange(Notification(name: NSText.didChangeNotification))   // size the box to the text
        }
        window?.makeFirstResponder(tv)
        if !text.isEmpty { tv.selectAll(nil) }             // typing replaces; arrow keys to edit part of it
    }

    func textDidChange(_ notification: Notification) {
        guard let tv = editor, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc)
        tv.setFrameSize(NSSize(width: max(40, ceil(used.width) + 4), height: max(used.height, 20).rounded(.up)))
    }

    /// Turn what was typed into a TextAnnotation. Empty text is dropped (for existing text: it is deleted).
    func commitText() {
        guard let tv = editor else { return }
        editor = nil
        let text = tv.string
        let origin = tv.frame.origin
        let existing = editingExisting
        editingExisting = nil
        tv.removeFromSuperview()
        window?.makeFirstResponder(superview)               // give keyboard shortcuts back to the overlay
        let isEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if let old = existing {
            if isEmpty { session.delete(old.id) }
            else if text != old.text { var updated = old; updated.text = text; session.replace(updated) }
        } else if !isEmpty {
            session.commit(TextAnnotation(origin: origin, text: text, style: editorStyle))
        }
        needsDisplay = true
    }

    /// Throw away the text being typed (used by Undo while typing); existing text stays as it was.
    func cancelText() {
        guard let tv = editor else { return }
        editor = nil
        editingExisting = nil
        tv.removeFromSuperview()
        window?.makeFirstResponder(superview)
        needsDisplay = true
    }
}
