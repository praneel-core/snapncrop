import CoreGraphics
import CoreText
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
    /// Box around everything drawn, including stroke thickness. Used for the selection outline.
    var bounds: CGRect { get }
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
    public var bounds: CGRect { rect.insetBy(dx: -style.width / 2, dy: -style.width / 2) }

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
    public var bounds: CGRect { rect.insetBy(dx: -style.width / 2, dy: -style.width / 2) }

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

    public var bounds: CGRect { Geometry.normalizedRect(from: start, to: end).insetBy(dx: -style.width / 2, dy: -style.width / 2) }

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

    public var bounds: CGRect { Geometry.normalizedRect(from: start, to: end).insetBy(dx: -max(style.width, 12), dy: -max(style.width, 12)) }

    public func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        distance(from: point, toSegment: start, end) <= tolerance + max(style.width, 8) / 2
    }

    public mutating func translate(by d: CGSize) {
        start = CGPoint(x: start.x + d.width, y: start.y + d.height)
        end = CGPoint(x: end.x + d.width, y: end.y + d.height)
    }
}

// MARK: - Pen (freehand)

public struct PenAnnotation: Annotation {
    public let id: UUID
    public var style: StrokeStyle
    public var points: [CGPoint]

    public init(id: UUID = UUID(), points: [CGPoint], style: StrokeStyle) {
        self.id = id; self.points = points; self.style = style
    }

    public func draw(in ctx: CGContext) {
        guard let first = points.first else { return }
        ctx.saveGState()
        ctx.setStrokeColor(style.color.cgColor)
        ctx.setFillColor(style.color.cgColor)
        ctx.setLineWidth(style.width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        if points.count == 1 {                       // a click: draw a dot
            let r = style.width / 2
            ctx.fillEllipse(in: CGRect(x: first.x - r, y: first.y - r, width: style.width, height: style.width))
        } else {
            // Smooth the hand-drawn wobble: curve through the midpoints, using each point as a control point.
            ctx.move(to: first)
            for i in 1..<points.count - 1 {
                let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
                ctx.addQuadCurve(to: mid, control: points[i])
            }
            ctx.addLine(to: points[points.count - 1])
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    public var bounds: CGRect {
        guard let f = points.first else { return .zero }
        var minX = f.x, maxX = f.x, minY = f.y, maxY = f.y
        for p in points { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            .insetBy(dx: -style.width / 2, dy: -style.width / 2)
    }

    public func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        let t = tolerance + style.width / 2
        if points.count == 1 { return hypot(point.x - points[0].x, point.y - points[0].y) <= t }
        return zip(points, points.dropFirst()).contains { distance(from: point, toSegment: $0, $1) <= t }
    }

    public mutating func translate(by d: CGSize) {
        points = points.map { CGPoint(x: $0.x + d.width, y: $0.y + d.height) }
    }
}

// MARK: - Highlighter

/// A translucent filled box, like a marker pen over text. Uses the chosen colour at 35% opacity;
/// the stroke width setting does not apply.
public struct HighlightAnnotation: Annotation {
    public static let opacity: Double = 0.35
    public let id: UUID
    public var style: StrokeStyle
    public var rect: CGRect

    public init(id: UUID = UUID(), rect: CGRect, style: StrokeStyle) {
        self.id = id; self.rect = rect; self.style = style
    }

    public func draw(in ctx: CGContext) {
        ctx.saveGState()
        ctx.setFillColor(style.color.cgColor.copy(alpha: Self.opacity) ?? style.color.cgColor)
        ctx.fill(rect)
        ctx.restoreGState()
    }

    /// Filled shape: anywhere inside counts.
    public var bounds: CGRect { rect }

    public func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
    }

    public mutating func translate(by d: CGSize) {
        rect = rect.offsetBy(dx: d.width, dy: d.height)
    }
}

// MARK: - Text

/// Text typed directly on the screenshot. `origin` is the top-left of the text box. The colour comes
/// from the style; the font size is derived from the stroke-width setting (S/M/L -> 18/24/36 pt).
public struct TextAnnotation: Annotation {
    public let id: UUID
    public var style: StrokeStyle
    public var origin: CGPoint
    public var text: String

    public init(id: UUID = UUID(), origin: CGPoint, text: String, style: StrokeStyle) {
        self.id = id; self.origin = origin; self.text = text; self.style = style
    }

    public var fontSize: CGFloat { 12 + style.width * 3 }

    /// Shared with the on-screen editor so what you type looks the same as what gets exported.
    public static func font(size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    }

    private var lineHeight: CGFloat {
        let f = Self.font(size: fontSize)
        return CTFontGetAscent(f) + CTFontGetDescent(f) + CTFontGetLeading(f)
    }

    private func makeLines() -> [CTLine] {
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: Self.font(size: fontSize),
            kCTForegroundColorAttributeName: style.color.cgColor,
        ]
        return text.components(separatedBy: "\n").map {
            CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, $0 as CFString, attrs as CFDictionary))
        }
    }

    /// Box around the text in the same coordinates as `origin` (top-left based).
    public var bounds: CGRect {
        let lines = makeLines()
        let width = lines.map { CTLineGetTypographicBounds($0, nil, nil, nil) }.max() ?? 0
        return CGRect(x: origin.x, y: origin.y, width: CGFloat(width), height: lineHeight * CGFloat(lines.count))
    }

    public func draw(in ctx: CGContext) {
        guard !text.isEmpty else { return }
        let f = Self.font(size: fontSize)
        let ascent = CTFontGetAscent(f), lh = lineHeight
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)      // our context is y-down; CoreText is y-up
        for (i, line) in makeLines().enumerated() {
            ctx.textPosition = CGPoint(x: origin.x, y: origin.y + ascent + CGFloat(i) * lh)
            CTLineDraw(line, ctx)
        }
        ctx.restoreGState()
    }

    public func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
    }

    public mutating func translate(by d: CGSize) {
        origin = CGPoint(x: origin.x + d.width, y: origin.y + d.height)
    }
}

// MARK: - Working with a list of annotations (select / move / delete)

public enum AnnotationList {
    /// Index of the topmost (most recently drawn) annotation under `point`, if any.
    public static func topmost(at point: CGPoint, in list: [any Annotation], tolerance: CGFloat = 6) -> Int? {
        list.indices.reversed().first { list[$0].hitTest(point, tolerance: tolerance) }
    }

    public static func removing(id: UUID, from list: [any Annotation]) -> [any Annotation] {
        list.filter { $0.id != id }
    }

    /// Same list with the annotation that has `updated.id` swapped for `updated` (keeps drawing order).
    public static func replacing(_ updated: any Annotation, in list: [any Annotation]) -> [any Annotation] {
        list.map { $0.id == updated.id ? updated : $0 }
    }
}

// MARK: - Phase 2 / 3 stubs (not built yet; each is one small struct like RectAnnotation)
// TODO(Phase 3): BlurAnnotation (pixelate the underlying crop), StepMarkerAnnotation (numbered circles).

/// Tools shown in the toolbar. Add a case here, then a branch in `makeShape`, and the toolbar/keys follow.
public enum AnnotationTool: CaseIterable {
    case rectangle
    case ellipse
    case line
    case arrow
    case pen
    case highlighter
    case select    // not a drawing tool: click an annotation to select it, drag to move, Delete removes
    case text      // placed by a click, typed inline (see CanvasView); not a drag shape

    /// Builds the shape from the mouse path of a drag (first point = mouse down, last = current position).
    public func makeShape(points: [CGPoint], style: StrokeStyle) -> any Annotation {
        let a = points.first ?? .zero, b = points.last ?? .zero
        switch self {
        case .rectangle:   return RectAnnotation(rect: Geometry.normalizedRect(from: a, to: b), style: style)
        case .ellipse:     return EllipseAnnotation(rect: Geometry.normalizedRect(from: a, to: b), style: style)
        case .line:        return LineAnnotation(start: a, end: b, style: style)
        case .arrow:       return ArrowAnnotation(start: a, end: b, style: style)
        case .pen:         return PenAnnotation(points: points, style: style)
        case .highlighter: return HighlightAnnotation(rect: Geometry.normalizedRect(from: a, to: b), style: style)
        case .text:        return TextAnnotation(origin: a, text: "", style: style)   // placeholder; see CanvasView
        case .select:      return RectAnnotation(rect: .zero, style: style)           // placeholder; never drawn
        }
    }

    public func makeShape(from a: CGPoint, to b: CGPoint, style: StrokeStyle) -> any Annotation {
        makeShape(points: [a, b], style: style)
    }

    /// Ignore accidental clicks: boxes need some width AND height, lines need some length.
    public func isValid(points: [CGPoint]) -> Bool {
        guard let a = points.first, let b = points.last else { return false }
        switch self {
        case .rectangle, .ellipse, .highlighter: return abs(a.x - b.x) >= 2 && abs(a.y - b.y) >= 2
        case .line, .arrow:                      return hypot(a.x - b.x, a.y - b.y) >= 3
        case .pen:                               return true      // even a click leaves a dot
        case .text, .select:                     return false     // never created by dragging
        }
    }

    public func isValidDrag(from a: CGPoint, to b: CGPoint) -> Bool { isValid(points: [a, b]) }
}
