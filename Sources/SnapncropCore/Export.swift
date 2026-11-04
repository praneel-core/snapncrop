import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum Drawing {
    /// Draw a CGImage into a context that is ALREADY top-left oriented (like our flipped views).
    /// CGContext.draw assumes bottom-left, so without this the picture would appear upside down.
    public static func drawTopLeft(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }
}

public enum ExportRenderer {

    /// Crop the frozen screenshot and burn the annotations in, at NATIVE PIXEL resolution.
    /// - Parameters:
    ///   - pixelCrop: crop rectangle in image pixels (top-left origin).
    ///   - selectionSize: the same region's size in points; used to scale annotations to pixels.
    public static func render(frozen: CGImage,
                              pixelCrop: CGRect,
                              selectionSize: CGSize,
                              annotations: [any Annotation]) -> CGImage? {
        guard let cropped = frozen.cropping(to: pixelCrop) else { return nil }
        let w = cropped.width, h = cropped.height
        guard w > 0, h > 0 else { return nil }

        let space = cropped.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                            | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }

        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Switch to top-left, point-based coordinates (same as the on-screen canvas).
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: CGFloat(w) / selectionSize.width, y: -CGFloat(h) / selectionSize.height)
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        for a in annotations { a.draw(in: ctx) }
        return ctx.makeImage()
    }

    /// Encode as PNG. DPI metadata (72 x scale) makes pasted/opened images show at the right size on Retina.
    public static func pngData(from image: CGImage, scale: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        let props: [CFString: Any] = [kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}
