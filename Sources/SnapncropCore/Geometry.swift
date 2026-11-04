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
