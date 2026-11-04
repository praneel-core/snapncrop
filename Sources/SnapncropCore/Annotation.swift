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

// MARK: - Phase 2 / 3 stubs (not built yet; each is one small struct like RectAnnotation)
// TODO(Phase 2): LineAnnotation, ArrowAnnotation, PenAnnotation (points array),
//                HighlightAnnotation (translucent filled rect), TextAnnotation.
// TODO(Phase 3): BlurAnnotation (pixelate the underlying crop), StepMarkerAnnotation (numbered circles).

/// Tools shown in the toolbar. Add a case here, then a branch in `makeShape`, and the toolbar/keys follow.
public enum AnnotationTool: CaseIterable {
    case rectangle
    case ellipse
    // TODO(Phase 2): line, arrow, pen, highlighter, text

    /// Builds the shape for a drag-to-draw tool from the bounding box of the drag.
    public func makeShape(rect: CGRect, style: StrokeStyle) -> any Annotation {
        switch self {
        case .rectangle: return RectAnnotation(rect: rect, style: style)
        case .ellipse:   return EllipseAnnotation(rect: rect, style: style)
        }
    }
}
