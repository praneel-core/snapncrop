import AppKit
import SnapncropCore

/// Sits exactly over the selection. Draws the cropped screenshot, then the annotations (vectors),
/// then the shape currently being dragged. The same `draw(in:)` code is used for export, which is
/// what guarantees "what you see is what you copy".
final class CanvasView: NSView {
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
        dragPoints = [convert(event.locationInWindow, from: nil)]
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
}
