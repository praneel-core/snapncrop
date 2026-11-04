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
