import CoreGraphics

/// All coordinate / pixel maths lives here so it is unit-tested and never duplicated.
///
/// Conventions used across the whole app:
///  * "Screen space"  = AppKit global points, origin BOTTOM-left of the primary display.
///  * "View space"    = points inside our overlay/canvas views. Those views are `isFlipped`,
///                      so the origin is TOP-left, which matches how images are stored.
///  * "Pixel space"   = pixels of the captured CGImage, origin TOP-left.
public enum Geometry {

    /// Rectangle spanned by two corner points (drag in any direction).
    public static func normalizedRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// Convert a rect between bottom-left and top-left origin inside a container of the given height.
    /// (The operation is its own inverse.)
    public static func flipY(_ rect: CGRect, containerHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: containerHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Keep a rect inside `bounds`.
    public static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let r = rect.intersection(bounds)
        return r.isNull ? .zero : r
    }

    /// Snap every edge of `rect` to the physical pixel grid (`1 / scale` points).
    /// After this, point sizes convert to whole pixels exactly (100pt at 2x == 200px).
    public static func snapToPixelGrid(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let minX = (rect.minX * scale).rounded() / scale
        let minY = (rect.minY * scale).rounded() / scale
        let maxX = (rect.maxX * scale).rounded() / scale
        let maxY = (rect.maxY * scale).rounded() / scale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Selection in display points (top-left origin) -> crop rectangle in image pixels.
    /// The scale is derived from the real image size rather than trusting `backingScaleFactor`.
    public static func pixelRect(forPointRect rect: CGRect,
                                 displayPointSize: CGSize,
                                 imagePixelSize: CGSize) -> CGRect {
        let sx = imagePixelSize.width / displayPointSize.width
        let sy = imagePixelSize.height / displayPointSize.height
        let px = CGRect(x: (rect.minX * sx).rounded(),
                        y: (rect.minY * sy).rounded(),
                        width: (rect.width * sx).rounded(),
                        height: (rect.height * sy).rounded())
        return clamp(px, to: CGRect(origin: .zero, size: imagePixelSize))
    }
}

/// Decides where the floating toolbar goes relative to the selection.
public enum ToolbarPlacement {
    /// All rects are in screen space (bottom-left origin). Returns the toolbar's bottom-left origin.
    /// Preference: below the selection, right-aligned; else above; else inside at the bottom.
    public static func origin(selection: CGRect, toolbarSize: CGSize, screenFrame: CGRect,
                              margin: CGFloat = 8) -> CGPoint {
        var x = selection.maxX - toolbarSize.width
        x = max(screenFrame.minX + margin, min(x, screenFrame.maxX - toolbarSize.width - margin))

        let below = selection.minY - margin - toolbarSize.height
        if below >= screenFrame.minY + margin { return CGPoint(x: x, y: below) }

        let above = selection.maxY + margin
        if above + toolbarSize.height <= screenFrame.maxY - margin { return CGPoint(x: x, y: above) }

        return CGPoint(x: x, y: selection.minY + margin)   // selection fills the screen: sit inside it
    }
}


/// The eight grab points around a rectangle, used for both the crop and for annotations.
public enum ResizeHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    // Coordinates are top-left based (y grows downward), like everything in view space.
    public func position(in f: CGRect) -> CGPoint {
        switch self {
        case .topLeft:     return CGPoint(x: f.minX, y: f.minY)
        case .top:         return CGPoint(x: f.midX, y: f.minY)
        case .topRight:    return CGPoint(x: f.maxX, y: f.minY)
        case .right:       return CGPoint(x: f.maxX, y: f.midY)
        case .bottomRight: return CGPoint(x: f.maxX, y: f.maxY)
        case .bottom:      return CGPoint(x: f.midX, y: f.maxY)
        case .bottomLeft:  return CGPoint(x: f.minX, y: f.maxY)
        case .left:        return CGPoint(x: f.minX, y: f.midY)
        }
    }

    /// The handle under `point`, if any. Corners win over edges when handles overlap on tiny rects.
    public static func hit(_ point: CGPoint, in f: CGRect, radius: CGFloat = 7) -> ResizeHandle? {
        let order: [ResizeHandle] = [.topLeft, .topRight, .bottomRight, .bottomLeft, .top, .right, .bottom, .left]
        return order.first { hypot($0.position(in: f).x - point.x, $0.position(in: f).y - point.y) <= radius }
    }

    private var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    private var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
    private var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
    private var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }

    /// New frame when this handle of `f` is dragged to `p`. Dragging past the opposite side flips the
    /// rectangle instead of breaking it. With `keepAspect` the original proportions are kept and the
    /// side opposite the handle stays fixed (used for text, where resizing means scaling).
    public func apply(dragTo p: CGPoint, frame f: CGRect, keepAspect: Bool = false) -> CGRect {
        var minX = f.minX, maxX = f.maxX, minY = f.minY, maxY = f.maxY
        if movesLeft { minX = p.x }
        if movesRight { maxX = p.x }
        if movesTop { minY = p.y }
        if movesBottom { maxY = p.y }
        let raw = CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
        guard keepAspect, f.width > 0, f.height > 0 else { return raw }

        let sx = raw.width / f.width, sy = raw.height / f.height
        let scale = abs(sx - 1) > abs(sy - 1) ? sx : sy
        let size = CGSize(width: f.width * scale, height: f.height * scale)
        let anchor = CGPoint(x: movesLeft ? f.maxX : (movesRight ? f.minX : f.midX),
                             y: movesTop ? f.maxY : (movesBottom ? f.minY : f.midY))
        let fx = (anchor.x - f.minX) / f.width, fy = (anchor.y - f.minY) / f.height
        return CGRect(x: anchor.x - fx * size.width, y: anchor.y - fy * size.height, width: size.width, height: size.height)
    }
}

extension Geometry {
    /// Map a point from one frame to another (used when resizing pens). Zero-size axes just translate.
    public static func remap(_ p: CGPoint, from old: CGRect, to new: CGRect) -> CGPoint {
        let x = old.width > 0 ? new.minX + (p.x - old.minX) / old.width * new.width : p.x - old.minX + new.minX
        let y = old.height > 0 ? new.minY + (p.y - old.minY) / old.height * new.height : p.y - old.minY + new.minY
        return CGPoint(x: x, y: y)
    }
}


/// Resizing a pinned screenshot with the scroll wheel / pinch: keeps the proportions and the centre.
public enum PinGeometry {
    public static func resized(_ f: CGRect, factor: CGFloat, minWidth: CGFloat = 80, maxSize: CGSize) -> CGRect {
        guard f.width > 0, f.height > 0, factor > 0 else { return f }
        let aspect = f.height / f.width
        var w = max(minWidth, min(f.width * factor, maxSize.width))
        var h = w * aspect
        if h > maxSize.height { h = maxSize.height; w = h / aspect }
        return CGRect(x: f.midX - w / 2, y: f.midY - h / 2, width: w, height: h)
    }
}
