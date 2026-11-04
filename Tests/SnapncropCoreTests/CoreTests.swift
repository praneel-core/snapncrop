import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import SnapncropCore

// MARK: helpers

private func solidImage(width: Int, height: Int, rgba: (UInt8, UInt8, UInt8, UInt8) = (255, 255, 255, 255)) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(red: CGFloat(rgba.0) / 255, green: CGFloat(rgba.1) / 255, blue: CGFloat(rgba.2) / 255, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()!
}

/// Reads pixel (x, y) with y counted from the TOP of the image. Returns (r,g,b).
private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (Int, Int, Int) {
    var buf = [UInt8](repeating: 0, count: 4)
    let ctx = CGContext(data: &buf, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Shift so the wanted pixel lands in the 1x1 context (CG draws bottom-left, so flip y).
    ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return (Int(buf[0]), Int(buf[1]), Int(buf[2]))
}

// MARK: geometry

@Suite struct GeometryTests {
    @Test func normalizedRectAnyDirection() {
        let r = Geometry.normalizedRect(from: CGPoint(x: 50, y: 40), to: CGPoint(x: 10, y: 90))
        #expect(r == CGRect(x: 10, y: 40, width: 40, height: 50))
    }

    @Test func flipYRoundTrips() {
        let r = CGRect(x: 10, y: 20, width: 30, height: 40)
        let flipped = Geometry.flipY(r, containerHeight: 100)
        #expect(flipped == CGRect(x: 10, y: 40, width: 30, height: 40))
        #expect(Geometry.flipY(flipped, containerHeight: 100) == r)
    }

    @Test func retinaSelectionIsDoublePixels() {
        // 100 x 60 pt selection on a 2x display: 1000x600 pt screen -> 2000x1200 px image.
        let px = Geometry.pixelRect(forPointRect: CGRect(x: 10, y: 20, width: 100, height: 60),
                                    displayPointSize: CGSize(width: 1000, height: 600),
                                    imagePixelSize: CGSize(width: 2000, height: 1200))
        #expect(px == CGRect(x: 20, y: 40, width: 200, height: 120))
    }

    @Test func nonRetinaIsOneToOne() {
        let px = Geometry.pixelRect(forPointRect: CGRect(x: 5, y: 5, width: 100, height: 100),
                                    displayPointSize: CGSize(width: 800, height: 600),
                                    imagePixelSize: CGSize(width: 800, height: 600))
        #expect(px == CGRect(x: 5, y: 5, width: 100, height: 100))
    }

    @Test func cropIsClampedToImage() {
        let px = Geometry.pixelRect(forPointRect: CGRect(x: 90, y: 90, width: 50, height: 50),
                                    displayPointSize: CGSize(width: 100, height: 100),
                                    imagePixelSize: CGSize(width: 200, height: 200))
        #expect(px == CGRect(x: 180, y: 180, width: 20, height: 20))
    }

    @Test func snapToPixelGrid() {
        let r = Geometry.snapToPixelGrid(CGRect(x: 10.3, y: 10.3, width: 99.9, height: 50.1), scale: 2)
        #expect(r.minX == 10.5 && r.minY == 10.5)
        #expect((r.width * 2).truncatingRemainder(dividingBy: 1) == 0)
        #expect((r.height * 2).truncatingRemainder(dividingBy: 1) == 0)
    }

    @Test func toolbarPlacement() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 300, height: 40)
        // Plenty of room below: goes below, right-aligned with the selection.
        let a = ToolbarPlacement.origin(selection: CGRect(x: 100, y: 300, width: 400, height: 200), toolbarSize: size, screenFrame: screen)
        #expect(a == CGPoint(x: 200, y: 252))
        // Selection touches the bottom edge: flips above.
        let b = ToolbarPlacement.origin(selection: CGRect(x: 100, y: 0, width: 400, height: 200), toolbarSize: size, screenFrame: screen)
        #expect(b.y == 208)
        // Selection spans the full height: ends up inside.
        let c = ToolbarPlacement.origin(selection: screen, toolbarSize: size, screenFrame: screen)
        #expect(c.y == 8)
        // Never off the left edge.
        let d = ToolbarPlacement.origin(selection: CGRect(x: 0, y: 300, width: 50, height: 50), toolbarSize: size, screenFrame: screen)
        #expect(d.x == 8)
    }
}

// MARK: history

@Suite struct HistoryTests {
    @Test func undoRedo() {
        var h = History<[Int]>(initial: [])
        #expect(!h.canUndo && !h.canRedo)
        h.commit([1]); h.commit([1, 2])
        #expect(h.current == [1, 2])
        h.undo(); #expect(h.current == [1]); #expect(h.canRedo)
        h.redo(); #expect(h.current == [1, 2])
        h.undo(); h.undo(); #expect(h.current == [])
        #expect(h.undo() == false)
    }

    @Test func newEditClearsRedo() {
        var h = History<Int>(initial: 0)
        h.commit(1); h.undo()
        h.commit(5)
        #expect(!h.canRedo)
        #expect(h.current == 5)
    }
}

// MARK: export

@Suite struct ExportTests {
    @Test func exportSizeIsPixelsNotPoints() {
        let frozen = solidImage(width: 2000, height: 1200)
        let pts = CGRect(x: 10, y: 20, width: 100, height: 60)
        let crop = Geometry.pixelRect(forPointRect: pts, displayPointSize: CGSize(width: 1000, height: 600),
                                      imagePixelSize: CGSize(width: 2000, height: 1200))
        let out = ExportRenderer.render(frozen: frozen, pixelCrop: crop, selectionSize: pts.size, annotations: [])!
        #expect(out.width == 200 && out.height == 120)
    }

    @Test func rectangleIsBurnedIntoCorrectPixels() {
        // White 200x200 px image that represents a 100x100 pt selection at 2x.
        let frozen = solidImage(width: 200, height: 200)
        let rect = RectAnnotation(rect: CGRect(x: 10, y: 10, width: 50, height: 30),
                                  style: StrokeStyle(color: RGBA(1, 0, 0), width: 4))
        let out = ExportRenderer.render(frozen: frozen, pixelCrop: CGRect(x: 0, y: 0, width: 200, height: 200),
                                        selectionSize: CGSize(width: 100, height: 100), annotations: [rect])!
        // Top edge of the rectangle: y = 10pt -> 20px, 4pt wide -> 8px thick centred on it (px 16...24).
        let edge = pixel(out, 60, 20)
        #expect(edge.0 > 200 && edge.1 < 60 && edge.2 < 60, "expected red on the top edge, got \(edge)")
        // Inside the rectangle and far outside stay white.
        let inside = pixel(out, 60, 40)
        #expect(inside.0 > 240 && inside.1 > 240 && inside.2 > 240)
        let outside = pixel(out, 180, 180)
        #expect(outside.0 > 240 && outside.1 > 240 && outside.2 > 240)
        // And the line is thicker at 2x: 6px below the edge centre (px 26) must still be white.
        let beyond = pixel(out, 60, 27)
        #expect(beyond.1 > 240)
    }

    @Test func ellipseIsBurnedIntoCorrectPixels() {
        let frozen = solidImage(width: 200, height: 200)   // 100x100 pt at 2x
        let e = EllipseAnnotation(rect: CGRect(x: 10, y: 10, width: 80, height: 60),
                                  style: StrokeStyle(color: RGBA(1, 0, 0), width: 4))
        let out = ExportRenderer.render(frozen: frozen, pixelCrop: CGRect(x: 0, y: 0, width: 200, height: 200),
                                        selectionSize: CGSize(width: 100, height: 100), annotations: [e])!
        let top = pixel(out, 100, 20)        // top of the ellipse: x = midX (50pt), y = 10pt
        #expect(top.0 > 200 && top.1 < 60 && top.2 < 60, "expected red at the ellipse top, got \(top)")
        let corner = pixel(out, 24, 24)      // inside the bounding box corner, outside the curve
        #expect(corner.0 > 240 && corner.1 > 240 && corner.2 > 240)
        let centre = pixel(out, 100, 80)
        #expect(centre.1 > 240)              // not filled
    }

    @Test func lineIsBurnedIntoCorrectPixels() {
        let frozen = solidImage(width: 200, height: 200)
        let l = LineAnnotation(start: CGPoint(x: 10, y: 50), end: CGPoint(x: 90, y: 50),
                               style: StrokeStyle(color: RGBA(1, 0, 0), width: 4))
        let out = ExportRenderer.render(frozen: frozen, pixelCrop: CGRect(x: 0, y: 0, width: 200, height: 200),
                                        selectionSize: CGSize(width: 100, height: 100), annotations: [l])!
        let on = pixel(out, 100, 100)        // middle of a horizontal line at y = 50pt
        #expect(on.0 > 200 && on.1 < 60 && on.2 < 60, "expected red on the line, got \(on)")
        let off = pixel(out, 100, 120)       // 10px below, thicker than the 8px stroke allows
        #expect(off.1 > 240)
    }

    @Test func arrowHeadIsFilledAtTheTip() {
        let frozen = solidImage(width: 200, height: 200)
        let a = ArrowAnnotation(start: CGPoint(x: 10, y: 50), end: CGPoint(x: 90, y: 50),
                                style: StrokeStyle(color: RGBA(1, 0, 0), width: 4))
        let out = ExportRenderer.render(frozen: frozen, pixelCrop: CGRect(x: 0, y: 0, width: 200, height: 200),
                                        selectionSize: CGSize(width: 100, height: 100), annotations: [a])!
        // Head is 16pt long (width*4), about 5.8pt either side of the axis 12pt behind the tip.
        // A plain 4pt-wide line (2pt either side) would be white 4pt off the axis, so red here means head.
        let inHead = pixel(out, 156, 92)         // x=78pt, 4pt above the axis
        #expect(inHead.0 > 200 && inHead.1 < 60, "expected the arrowhead here, got \(inHead)")
        let shaft = pixel(out, 60, 100)
        #expect(shaft.0 > 200 && shaft.1 < 60)
        let beyondTip = pixel(out, 190, 100)     // past the tip
        #expect(beyondTip.1 > 240)
    }

    @Test func lineAndArrowHitTestAndTools() {
        let l = LineAnnotation(start: .zero, end: CGPoint(x: 100, y: 0), style: .default)
        #expect(l.hitTest(CGPoint(x: 50, y: 4), tolerance: 3))
        #expect(!l.hitTest(CGPoint(x: 50, y: 20), tolerance: 3))
        #expect(!l.hitTest(CGPoint(x: 150, y: 0), tolerance: 3))     // beyond the end
        var a = ArrowAnnotation(start: .zero, end: CGPoint(x: 100, y: 0), style: .default)
        a.translate(by: CGSize(width: 10, height: 5))
        #expect(a.start == CGPoint(x: 10, y: 5) && a.end == CGPoint(x: 110, y: 5))
        #expect(AnnotationTool.arrow.makeShape(from: .zero, to: CGPoint(x: 9, y: 9), style: .default) is ArrowAnnotation)
        #expect(!AnnotationTool.line.isValidDrag(from: .zero, to: CGPoint(x: 1, y: 1)))     // just a click
        #expect(AnnotationTool.line.isValidDrag(from: .zero, to: CGPoint(x: 50, y: 0)))     // flat line is fine
        #expect(!AnnotationTool.rectangle.isValidDrag(from: .zero, to: CGPoint(x: 50, y: 0)))
    }

    @Test func penFollowsItsPoints() {
        let frozen = solidImage(width: 200, height: 200)
        let pen = PenAnnotation(points: [CGPoint(x: 10, y: 50), CGPoint(x: 50, y: 50), CGPoint(x: 90, y: 50)],
                                style: StrokeStyle(color: RGBA(1, 0, 0), width: 4))
        let out = ExportRenderer.render(frozen: frozen, pixelCrop: CGRect(x: 0, y: 0, width: 200, height: 200),
                                        selectionSize: CGSize(width: 100, height: 100), annotations: [pen])!
        let on = pixel(out, 100, 100), off = pixel(out, 100, 130)
        #expect(on.0 > 200 && on.1 < 60, "expected red on the pen stroke, got \(on)")
        #expect(off.1 > 240)
        let end = pixel(out, 178, 100)       // curve is drawn right up to the last point (90pt = 180px)
        #expect(end.1 < 60, "stroke should reach its final point, got \(end)")
    }

    @Test func penClickLeavesADot() {
        let frozen = solidImage(width: 200, height: 200)
        let pen = PenAnnotation(points: [CGPoint(x: 50, y: 50)], style: StrokeStyle(color: RGBA(1, 0, 0), width: 8))
        let out = ExportRenderer.render(frozen: frozen, pixelCrop: CGRect(x: 0, y: 0, width: 200, height: 200),
                                        selectionSize: CGSize(width: 100, height: 100), annotations: [pen])!
        #expect(pixel(out, 100, 100).1 < 60)
        #expect(AnnotationTool.pen.isValid(points: [CGPoint(x: 1, y: 1)]))
    }

    @Test func highlighterIsTranslucent() {
        let frozen = solidImage(width: 200, height: 200)
        let h = HighlightAnnotation(rect: CGRect(x: 20, y: 20, width: 60, height: 20),
                                    style: StrokeStyle(color: RGBA(1, 1, 0), width: 4))
        let out = ExportRenderer.render(frozen: frozen, pixelCrop: CGRect(x: 0, y: 0, width: 200, height: 200),
                                        selectionSize: CGSize(width: 100, height: 100), annotations: [h])!
        let inside = pixel(out, 100, 60)         // yellow over white: blue drops, red/green stay high
        #expect(inside.0 > 240 && inside.1 > 240 && inside.2 > 120 && inside.2 < 200, "got \(inside)")
        let outside = pixel(out, 100, 120)
        #expect(outside.2 > 240)
        #expect(h.hitTest(CGPoint(x: 50, y: 30), tolerance: 2))      // filled: inside counts
    }

    /// How many pixels in the rectangle (pixel coords, top-left origin) are clearly red.
    private func redCount(_ img: CGImage, x: ClosedRange<Int>, y: ClosedRange<Int>) -> Int {
        var n = 0
        for yy in y { for xx in x { let p = pixel(img, xx, yy); if p.0 > 200 && p.1 < 100 && p.2 < 100 { n += 1 } } }
        return n
    }

    @Test func textIsDrawnInsideItsBoundsOnly() {
        let frozen = solidImage(width: 400, height: 200)                       // 200x100 pt at 2x
        let t = TextAnnotation(origin: CGPoint(x: 10, y: 10), text: "HIHI",
                               style: StrokeStyle(color: RGBA(1, 0, 0), width: 4))   // 24pt font
        let out = ExportRenderer.render(frozen: frozen, pixelCrop: CGRect(x: 0, y: 0, width: 400, height: 200),
                                        selectionSize: CGSize(width: 200, height: 100), annotations: [t])!
        let b = t.bounds
        #expect(b.width > 20 && b.height > 20 && b.minX == 10 && b.minY == 10)
        let inside = redCount(out, x: Int(b.minX * 2)...Int(b.maxX * 2), y: Int(b.minY * 2)...Int(b.maxY * 2))
        #expect(inside > 100, "expected red glyph pixels inside the text box, got \(inside)")
        let farAway = redCount(out, x: 300...390, y: 100...190)
        #expect(farAway == 0)
        // Text must sit the right way up: the glyph ink should be in the upper box area, not mirrored below it.
        let below = redCount(out, x: 20...390, y: Int(b.maxY * 2) + 6...199)
        #expect(below == 0, "text leaked below its box (upside down?)")
    }

    @Test func textBoundsGrowWithContentAndSize() {
        let s = StrokeStyle(color: .red, width: 4)
        let one = TextAnnotation(origin: .zero, text: "Hello", style: s)
        let two = TextAnnotation(origin: .zero, text: "Hello\nWorld!!", style: s)
        #expect(two.bounds.height > one.bounds.height * 1.8)
        #expect(two.bounds.width > one.bounds.width)
        let big = TextAnnotation(origin: .zero, text: "Hello", style: StrokeStyle(color: .red, width: 8))
        #expect(big.fontSize == 36 && big.bounds.width > one.bounds.width)
        #expect(TextAnnotation(origin: .zero, text: "", style: s).bounds.width == 0)
    }

    @Test func textHitTestMoveAndNotADragTool() {
        var t = TextAnnotation(origin: CGPoint(x: 10, y: 10), text: "Hi", style: .default)
        #expect(t.hitTest(CGPoint(x: 12, y: 15), tolerance: 2))
        #expect(!t.hitTest(CGPoint(x: 300, y: 300), tolerance: 2))
        t.translate(by: CGSize(width: 5, height: 5))
        #expect(t.origin == CGPoint(x: 15, y: 15))
        #expect(!AnnotationTool.text.isValid(points: [.zero, CGPoint(x: 50, y: 50)]))
    }

    @Test func penAndHighlighterTools() {
        let path = [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 5), CGPoint(x: 9, y: 2)]
        #expect((AnnotationTool.pen.makeShape(points: path, style: .default) as? PenAnnotation)?.points.count == 3)
        #expect(AnnotationTool.highlighter.makeShape(points: path, style: .default) is HighlightAnnotation)
        var pen = PenAnnotation(points: path, style: .default)
        pen.translate(by: CGSize(width: 1, height: 1))
        #expect(pen.points[0] == CGPoint(x: 1, y: 1))
        #expect(pen.hitTest(CGPoint(x: 5, y: 6), tolerance: 2))
    }

    @Test func ellipseHitTestAndTool() {
        let e = EllipseAnnotation(rect: CGRect(x: 0, y: 0, width: 100, height: 60), style: .default)
        #expect(e.hitTest(CGPoint(x: 50, y: 0), tolerance: 3))
        #expect(!e.hitTest(CGPoint(x: 50, y: 30), tolerance: 3))
        #expect(AnnotationTool.ellipse.makeShape(from: .zero, to: CGPoint(x: 5, y: 5), style: .default) is EllipseAnnotation)
    }

    @Test func pngRoundTrip() throws {
        let img = solidImage(width: 40, height: 30)
        let data = try #require(ExportRenderer.pngData(from: img, scale: 2))
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))   // PNG magic number
        let src = CGImageSourceCreateWithData(data as CFData, nil)!
        let back = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        #expect(back.width == 40 && back.height == 30)
    }

    @Test func rectHitTest() {
        let r = RectAnnotation(rect: CGRect(x: 0, y: 0, width: 100, height: 100), style: .default)
        #expect(r.hitTest(CGPoint(x: 50, y: 0), tolerance: 3))
        #expect(!r.hitTest(CGPoint(x: 50, y: 50), tolerance: 3))
    }
}

// MARK: four-finger tap

private func fire(_ d: inout FourFingerTapDetector, _ t: [TouchPoint], _ ts: Double) -> Bool {
    d.process(t, timestamp: ts)
}

@Suite struct TapDetectorTests {
    private func fingers(_ n: Int, dx: Float = 0, dy: Float = 0) -> [TouchPoint] {
        (0..<n).map { TouchPoint(x: 0.3 + Float($0) * 0.1 + dx, y: 0.5 + dy) }
    }

    @Test func quickTapFires() {
        var d = FourFingerTapDetector()
        #expect(!fire(&d, fingers(4), 1.00))
        #expect(!fire(&d, fingers(4), 1.05))
        #expect(fire(&d, fingers(3), 1.10))       // first finger lifts
        #expect(!fire(&d, fingers(0), 1.12))
    }

    @Test func fingersLandingStaggeredStillCounts() {
        var d = FourFingerTapDetector()
        _ = d.process(fingers(1), timestamp: 1.00)
        _ = d.process(fingers(2), timestamp: 1.03)
        _ = d.process(fingers(4), timestamp: 1.06)
        #expect(fire(&d, fingers(3), 1.15))
    }

    @Test func slowLandingDoesNotFire() {
        var d = FourFingerTapDetector()
        _ = d.process(fingers(1), timestamp: 1.0)
        _ = d.process(fingers(4), timestamp: 1.5)             // 0.5s between first and fourth finger
        #expect(!fire(&d, fingers(3), 1.55))
    }

    @Test func longHoldDoesNotFire() {
        var d = FourFingerTapDetector()
        _ = d.process(fingers(4), timestamp: 1.0)
        _ = d.process(fingers(4), timestamp: 1.4)
        #expect(!fire(&d, fingers(3), 1.5))
    }

    @Test func swipeDoesNotFire() {
        var d = FourFingerTapDetector()
        _ = d.process(fingers(4), timestamp: 1.00)
        _ = d.process(fingers(4, dx: 0.10), timestamp: 1.08)  // fingers slide sideways
        #expect(!fire(&d, fingers(3, dx: 0.10), 1.12))
    }

    @Test func fiveFingersOrPalmDoesNotFire() {
        var d = FourFingerTapDetector()
        _ = d.process(fingers(4), timestamp: 1.00)
        _ = d.process(fingers(5), timestamp: 1.03)
        _ = d.process(fingers(4), timestamp: 1.06)
        #expect(!fire(&d, fingers(3), 1.10))
    }

    @Test func threeFingerTapDoesNotFire() {
        var d = FourFingerTapDetector()
        _ = d.process(fingers(3), timestamp: 1.0)
        #expect(!fire(&d, fingers(0), 1.1))
    }

    @Test func debounceAndFiresOncePerTap() {
        var d = FourFingerTapDetector()
        _ = d.process(fingers(4), timestamp: 1.00)
        #expect(fire(&d, fingers(3), 1.10))
        #expect(!fire(&d, fingers(2), 1.12))      // remaining lifts don't refire
        _ = d.process(fingers(0), timestamp: 1.14)
        _ = d.process(fingers(4), timestamp: 1.20)            // second tap inside the debounce window
        #expect(!fire(&d, fingers(3), 1.28))
        _ = d.process(fingers(0), timestamp: 1.30)
        _ = d.process(fingers(4), timestamp: 2.00)            // later tap works again
        #expect(fire(&d, fingers(3), 2.08))
    }
}


// MARK: select / move / delete

@Suite struct SelectionTests {
    private let red = StrokeStyle(color: .red, width: 4)

    @Test func everyAnnotationHasSensibleBounds() {
        let all: [any Annotation] = [
            RectAnnotation(rect: CGRect(x: 10, y: 10, width: 40, height: 20), style: red),
            EllipseAnnotation(rect: CGRect(x: 10, y: 10, width: 40, height: 20), style: red),
            LineAnnotation(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 50, y: 30), style: red),
            ArrowAnnotation(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 50, y: 30), style: red),
            PenAnnotation(points: [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 30)], style: red),
            HighlightAnnotation(rect: CGRect(x: 10, y: 10, width: 40, height: 20), style: red),
            TextAnnotation(origin: CGPoint(x: 10, y: 10), text: "Hi", style: red),
        ]
        for a in all {
            #expect(a.bounds.minX <= 10 && a.bounds.minY <= 10, "\(type(of: a)) bounds start too late: \(a.bounds)")
            #expect(a.bounds.width > 0 && a.bounds.height > 0, "\(type(of: a)) has empty bounds")
        }
        // Outline shapes include the stroke thickness (2pt each side at width 4).
        #expect(all[0].bounds == CGRect(x: 8, y: 8, width: 44, height: 24))
    }

    @Test func topmostPicksTheLastDrawnAndMissesEmptySpace() {
        // Two lines crossing at (50, 50): the second one is drawn on top.
        let l1 = LineAnnotation(start: CGPoint(x: 0, y: 50), end: CGPoint(x: 100, y: 50), style: red)
        let l2 = LineAnnotation(start: CGPoint(x: 50, y: 0), end: CGPoint(x: 50, y: 100), style: red)
        let list: [any Annotation] = [l1, l2]
        #expect(AnnotationList.topmost(at: CGPoint(x: 50, y: 50), in: list) == 1)
        #expect(AnnotationList.topmost(at: CGPoint(x: 20, y: 50), in: list) == 0)
        #expect(AnnotationList.topmost(at: CGPoint(x: 90, y: 90), in: list) == nil)
    }

    @Test func movingThroughTheExistentialChangesTheCopyNotTheOriginal() {
        let original: any Annotation = RectAnnotation(rect: CGRect(x: 0, y: 0, width: 10, height: 10), style: red)
        var moved = original
        moved.translate(by: CGSize(width: 5, height: 7))
        #expect((moved as? RectAnnotation)?.rect.origin == CGPoint(x: 5, y: 7))
        #expect((original as? RectAnnotation)?.rect.origin == .zero)
        #expect(moved.id == original.id)       // same identity, so it can replace the original
    }

    @Test func replaceAndDeleteKeepOrderAndAreUndoable() {
        let a = RectAnnotation(rect: CGRect(x: 0, y: 0, width: 10, height: 10), style: red)
        let b = EllipseAnnotation(rect: CGRect(x: 20, y: 20, width: 10, height: 10), style: red)
        var h = History<[any Annotation]>(initial: [])
        h.commit([a]); h.commit([a, b])

        var movedA = a; movedA.translate(by: CGSize(width: 100, height: 0))
        h.commit(AnnotationList.replacing(movedA, in: h.current))
        #expect(h.current.count == 2 && h.current[0].id == a.id)          // order kept
        #expect((h.current[0] as? RectAnnotation)?.rect.minX == 100)

        h.commit(AnnotationList.removing(id: b.id, from: h.current))
        #expect(h.current.count == 1)
        h.undo(); #expect(h.current.count == 2)                          // delete undone
        h.undo(); #expect((h.current[0] as? RectAnnotation)?.rect.minX == 0)   // move undone
    }

    @Test func movedAnnotationExportsAtItsNewPlace() {
        let frozen = solidImage(width: 200, height: 200)
        var r = RectAnnotation(rect: CGRect(x: 10, y: 10, width: 30, height: 30),
                               style: StrokeStyle(color: RGBA(1, 0, 0), width: 4))
        r.translate(by: CGSize(width: 40, height: 0))                     // top edge now spans x 50...80pt at y=10pt
        let out = ExportRenderer.render(frozen: frozen, pixelCrop: CGRect(x: 0, y: 0, width: 200, height: 200),
                                        selectionSize: CGSize(width: 100, height: 100), annotations: [r])!
        #expect(pixel(out, 130, 20).1 < 60)       // x = 65pt on the new top edge: red
        #expect(pixel(out, 40, 20).1 > 240)       // old position: white again
        #expect(AnnotationTool.select.isValid(points: [.zero, CGPoint(x: 50, y: 50)]) == false)
    }
}
