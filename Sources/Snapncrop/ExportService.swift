import AppKit

/// Clipboard and disk output. Rendering itself lives in SnapncropCore.ExportRenderer.
enum ExportService {
    static func copyToClipboard(png: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
    }

    /// Saves "Snapncrop 2026-11-05 at 14.03.22.png" into the default folder (created if missing).
    @discardableResult
    static func save(png: Data, folder: URL = SettingsStore.shared.saveFolder) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        var url = folder.appendingPathComponent("Snapncrop \(f.string(from: Date())).png")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {   // two shots in the same second
            url = folder.appendingPathComponent("Snapncrop \(f.string(from: Date())) (\(n)).png"); n += 1
        }
        try png.write(to: url, options: .atomic)
        return url
    }
}
