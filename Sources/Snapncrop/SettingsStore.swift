import Foundation
import SnapncropCore

/// Small UserDefaults wrapper. Phase 2 adds a Preferences window on top of this.
final class SettingsStore {
    static let shared = SettingsStore()
    private let d = UserDefaults.standard

    var saveFolder: URL {
        get {
            if let p = d.string(forKey: "saveFolder") { return URL(fileURLWithPath: p) }
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Screenshots")
        }
        set { d.set(newValue.path, forKey: "saveFolder") }
    }

    var gestureEnabled: Bool {
        get { d.object(forKey: "gestureEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "gestureEnabled") }
    }

    /// "Copy" also writes a PNG into the screenshots folder.
    var alsoSaveOnCopy: Bool {
        get { d.bool(forKey: "alsoSaveOnCopy") }
        set { d.set(newValue, forKey: "alsoSaveOnCopy") }
    }

    var gestureDebug: Bool {
        get { d.bool(forKey: "gestureDebug") }
        set { d.set(newValue, forKey: "gestureDebug") }
    }

    var strokeWidth: CGFloat {
        get { d.object(forKey: "strokeWidth") as? CGFloat ?? 4 }
        set { d.set(newValue, forKey: "strokeWidth") }
    }

    var strokeColor: RGBA {
        get {
            guard let a = d.array(forKey: "strokeColor") as? [Double], a.count == 4 else { return .red }
            return RGBA(a[0], a[1], a[2], a[3])
        }
        set { d.set([newValue.r, newValue.g, newValue.b, newValue.a], forKey: "strokeColor") }
    }
}
