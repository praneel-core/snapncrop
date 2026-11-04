import CoreGraphics
import Foundation

public struct RGBA: Equatable, Codable {
    public var r, g, b, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    public var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

    public static let red    = RGBA(0.93, 0.22, 0.20)
    public static let blue   = RGBA(0.20, 0.45, 0.95)
    public static let green  = RGBA(0.18, 0.74, 0.35)
    public static let yellow = RGBA(1.00, 0.84, 0.10)
    public static let black  = RGBA(0, 0, 0)
}

public struct StrokeStyle: Equatable {
    public var color: RGBA
    /// Width in points (not pixels). The exporter scales it, so it looks identical on screen and in the PNG.
    public var width: CGFloat
    public init(color: RGBA, width: CGFloat) { self.color = color; self.width = width }
    public static let `default` = StrokeStyle(color: .red, width: 4)
}

/// One drawn object. Annotations are plain value types in SELECTION-LOCAL POINT coordinates
/// (top-left origin, relative to the cropped screenshot). They stay vectors until export,
/// so they remain editable and render sharply at any pixel density.
public protocol Annotation {
    var id: UUID { get }
    var style: StrokeStyle { get set }
    /// Draw into a context whose origin is top-left and whose unit is one point.
    func draw(in ctx: CGContext)
    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool
    mutating func translate(by delta: CGSize)
}

// MARK: - Phase 1: rectangle

public struct RectAnnotation: Annotation {
    public let id: UUID
    public var style: StrokeStyle
    public var rect: CGRect

    public init(id: UUID = UUID(), rect: CGRect, style: StrokeStyle) {
        self.id = id; self.rect = rect; self.style = style
    }

    public func draw(in ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(style.color.cgColor)
        ctx.setLineWidth(style.width)
        ctx.setLineJoin(.miter)
        ctx.stroke(rect)
        ctx.restoreGState()
    }

    /// Outline-only hit test: true when the point is near the border.
    public func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        let t = tolerance + style.width / 2
        return rect.insetBy(dx: -t, dy: -t).contains(point) && !rect.insetBy(dx: t, dy: t).contains(point)
    }

    public mutating func translate(by delta: CGSize) {
        rect = rect.offsetBy(dx: delta.width, dy: delta.height)
    }
}

// MARK: - Ellipse

public struct EllipseAnnotation: Annotation {
    public let id: UUID
    public var style: StrokeStyle
    public var rect: CGRect   // bounding box of the ellipse

    public init(id: UUID = UUID(), rect: CGRect, style: StrokeStyle) {
        self.id = id; self.rect = rect; self.style = style
    }

    public func draw(in ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(style.color.cgColor)
        ctx.setLineWidth(style.width)
        ctx.strokeEllipse(in: rect)
        ctx.restoreGState()
    }

    /// Outline-only hit test using the ellipse equation: points near the curve count.
    public func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        let a = rect.width / 2, b = rect.height / 2
        guard a > 0, b > 0 else { return false }
        let nx = (point.x - rect.midX) / a, ny = (point.y - rect.midY) / b
        let distanceFromCurve = abs(sqrt(nx * nx + ny * ny) - 1) * min(a, b)
        return distanceFromCurve <= tolerance + style.width / 2
    }

    public mutating func translate(by delta: CGSize) {
        rect = rect.offsetBy(dx: delta.width, dy: delta.height)
    }
}

// MARK: - Line

/// Distance from `p` to the segment a-b. Shared by line and arrow hit-testing.
public func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = b.x - a.x, dy = b.y - a.y
    let lenSq = dx * dx + dy * dy
    guard lenSq > 0 else { return hypot(p.x - a.x, p.y - a.y) }
    let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
    return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
}

public struct LineAnnotation: Annotation {
    public let id: UUID
    public var style: StrokeStyle
    public var start: CGPoint
    public var end: CGPoint

    public init(id: UUID = UUID(), start: CGPoint, end: CGPoint, style: StrokeStyle) {
        self.id = id; self.start = start; self.end = end; self.style = style
    }

    public func draw(in ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(style.color.cgColor)
        ctx.setLineWidth(style.width)
        ctx.setLineCap(.round)
        ctx.move(to: start); ctx.addLine(to: end); ctx.strokePath()
        ctx.restoreGState()
    }

    public func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        distance(from: point, toSegment: start, end) <= tolerance + style.width / 2
    }

    public mutating func translate(by d: CGSize) {
        start = CGPoint(x: start.x + d.width, y: start.y + d.height)
        end = CGPoint(x: end.x + d.width, y: end.y + d.height)
    }
}

// MARK: - Arrow

/// A line with a filled triangular head at `end`. The head scales with the stroke width.
public struct ArrowAnnotation: Annotation {
    public let id: UUID
    public var style: StrokeStyle
    public var start: CGPoint
    public var end: CGPoint

    public init(id: UUID = UUID(), start: CGPoint, end: CGPoint, style: StrokeStyle) {
        self.id = id; self.start = start; self.end = end; self.style = style
    }

    /// Head length in points; never longer than the arrow itself.
    var headLength: CGFloat {
        min(max(12, style.width * 4), hypot(end.x - start.x, end.y - start.y))
    }

    public func draw(in ctx: CGContext) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let head = headLength
        let spread: CGFloat = .pi / 7          // ~26 degrees each side
        let left = CGPoint(x: end.x - head * cos(angle - spread), y: end.y - head * sin(angle - spread))
        let right = CGPoint(x: end.x - head * cos(angle + spread), y: end.y - head * sin(angle + spread))
        // Stop the shaft inside the head so a thick line doesn't poke out past the tip.
        let shaftEnd = CGPoint(x: end.x - head * 0.6 * cos(angle), y: end.y - head * 0.6 * sin(angle))

        ctx.saveGState()
        ctx.setStrokeColor(style.color.cgColor)
        ctx.setFillColor(style.color.cgColor)
        ctx.setLineWidth(style.width)
        ctx.setLineCap(.round)
        ctx.move(to: start); ctx.addLine(to: shaftEnd); ctx.strokePath()
        ctx.move(to: end); ctx.addLine(to: left); ctx.addLine(to: right); ctx.closePath()
        ctx.fillPath()
        ctx.restoreGState()
    }

    public func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        distance(from: point, toSegment: start, end) <= tolerance + max(style.width, 8) / 2
    }

    public mutating func translate(by d: CGSize) {
        start = CGPoint(x: start.x + d.width, y: start.y + d.height)
        end = CGPoint(x: end.x + d.width, y: end.y + d.height)
    }
}

// MARK: - Phase 2 / 3 stubs (not built yet; each is one small struct like RectAnnotation)
// TODO(Phase 2): PenAnnotation (points array), HighlightAnnotation (translucent filled rect), TextAnnotation.
// TODO(Phase 3): BlurAnnotation (pixelate the underlying crop), StepMarkerAnnotation (numbered circles).

/// Tools shown in the toolbar. Add a case here, then a branch in `makeShape`, and the toolbar/keys follow.
public enum AnnotationTool: CaseIterable {
    case rectangle
    case ellipse
    case line
    case arrow
    // TODO(Phase 2): pen, highlighter, text

    /// Builds the shape for a drag-to-draw tool from the two drag points.
    public func makeShape(from a: CGPoint, to b: CGPoint, style: StrokeStyle) -> any Annotation {
        switch self {
        case .rectangle: return RectAnnotation(rect: Geometry.normalizedRect(from: a, to: b), style: style)
        case .ellipse:   return EllipseAnnotation(rect: Geometry.normalizedRect(from: a, to: b), style: style)
        case .line:      return LineAnnotation(start: a, end: b, style: style)
        case .arrow:     return ArrowAnnotation(start: a, end: b, style: style)
        }
    }

    /// Ignore accidental clicks: boxes need some width AND height, lines need some length.
    public func isValidDrag(from a: CGPoint, to b: CGPoint) -> Bool {
        switch self {
        case .rectangle, .ellipse: return abs(a.x - b.x) >= 2 && abs(a.y - b.y) >= 2
        case .line, .arrow:        return hypot(a.x - b.x, a.y - b.y) >= 3
        }
    }
}
