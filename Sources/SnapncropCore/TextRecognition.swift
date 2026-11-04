import CoreGraphics
import Foundation
import Vision

/// One line of recognised text with where it was in the picture (Vision's normalised box: 0...1, origin bottom-left).
public struct RecognizedLine: Equatable {
    public var text: String
    public var box: CGRect
    public init(text: String, box: CGRect) { self.text = text; self.box = box }
}

public enum TextLayout {
    /// Put recognised lines into reading order: top to bottom, and left to right when several pieces
    /// share a row (table cells, columns). Rows are joined with newlines, pieces in a row with spaces.
    public static func join(_ lines: [RecognizedLine]) -> String {
        let sorted = lines.sorted { $0.box.midY > $1.box.midY }            // top first (Vision's y goes up)
        var rows: [[RecognizedLine]] = []
        var rowMid: CGFloat = 0, rowHeight: CGFloat = 0
        for line in sorted {
            if !rows.isEmpty, abs(line.box.midY - rowMid) <= max(line.box.height, rowHeight) * 0.5 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line]); rowMid = line.box.midY; rowHeight = line.box.height
            }
        }
        return rows.map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
                   .joined(separator: "\n")
    }
}

/// Reads text out of an image with Apple's on-device Vision framework. Nothing leaves the Mac.
public enum TextRecognizer {
    /// Synchronous and can take a moment on large images: call it off the main thread.
    public static func recognize(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([request]) }
        catch { return "" }
        let lines = (request.results ?? []).compactMap { obs -> RecognizedLine? in
            guard let best = obs.topCandidates(1).first else { return nil }
            return RecognizedLine(text: best.string, box: obs.boundingBox)
        }
        return TextLayout.join(lines)
    }
}
