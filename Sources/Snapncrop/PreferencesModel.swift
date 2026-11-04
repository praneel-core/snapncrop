import AppKit
import SnapncropCore

/// State behind the Preferences window. Every change is written to SettingsStore straight away
/// (no OK button) and, where needed, applied to the running app through the callbacks.
final class PreferencesModel: ObservableObject {
    @Published var shortcut: Shortcut
    @Published var shortcutMessage: String?
    @Published var recording = false { didSet { onRecordingChanged?(recording) } }
    @Published var saveFolder: URL
    @Published var strokeColor: RGBA
    @Published var strokeWidth: CGFloat
    @Published var gestureEnabled: Bool
    @Published var alsoSaveOnCopy: Bool
    @Published var launchAtLogin: Bool
    @Published var loginMessage: String?

    // Wired up by AppDelegate.
    var onTryShortcut: ((Shortcut) -> Bool)?          // returns false if macOS refuses the combination
    var onRecordingChanged: ((Bool) -> Void)?         // pauses the live hotkey while you record a new one
    var onGestureChanged: ((Bool) -> Void)?

    let palette: [(name: String, color: RGBA)] = [("Red", .red), ("Blue", .blue), ("Green", .green), ("Yellow", .yellow), ("Black", .black)]
    let widths: [(name: String, value: CGFloat)] = [("S", 2), ("M", 4), ("L", 8)]

    private let store = SettingsStore.shared

    init() {
        shortcut = store.shortcut; saveFolder = store.saveFolder
        strokeColor = store.strokeColor; strokeWidth = store.strokeWidth
        gestureEnabled = store.gestureEnabled; alsoSaveOnCopy = store.alsoSaveOnCopy
        launchAtLogin = LoginItem.isEnabled
    }

    /// Re-read everything (the menu bar menu can change some of these while this window is closed).
    func reload() {
        shortcut = store.shortcut; saveFolder = store.saveFolder
        strokeColor = store.strokeColor; strokeWidth = store.strokeWidth
        gestureEnabled = store.gestureEnabled; alsoSaveOnCopy = store.alsoSaveOnCopy
        launchAtLogin = LoginItem.isEnabled
        shortcutMessage = nil; loginMessage = nil
    }

    func setShortcut(_ s: Shortcut) {
        guard s.isValid else { shortcutMessage = "Include ⌃, ⌥ or ⌘ so normal typing isn't affected."; return }
        if onTryShortcut?(s) ?? true {
            shortcut = s; store.shortcut = s; shortcutMessage = nil
        } else {
            shortcutMessage = "\(s.description) is already used by macOS or another app. Try a different one."
        }
    }

    func resetShortcut() { setShortcut(.default) }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "Choose"; panel.message = "Where should Snapncrop save screenshots?"
        panel.directoryURL = saveFolder
        if panel.runModal() == .OK, let url = panel.url { saveFolder = url; store.saveFolder = url }
    }

    func openFolder() {
        try? FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(saveFolder)
    }

    func setColor(_ c: RGBA) { strokeColor = c; store.strokeColor = c }
    func setWidth(_ w: CGFloat) { strokeWidth = w; store.strokeWidth = w }
    func setGesture(_ on: Bool) { gestureEnabled = on; store.gestureEnabled = on; onGestureChanged?(on) }
    func setAlsoSave(_ on: Bool) { alsoSaveOnCopy = on; store.alsoSaveOnCopy = on }

    func setLaunchAtLogin(_ on: Bool) {
        do { try LoginItem.set(on); loginMessage = nil }
        catch { loginMessage = "Couldn't change this: \(error.localizedDescription). Run the app from ~/Applications (./build.sh install)." }
        launchAtLogin = LoginItem.isEnabled
    }
}
