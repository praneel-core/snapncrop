import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let router = TriggerRouter()
    private let hotkey = HotkeyManager()
    private var statusItem: StatusItemController!
    private let gesture: GestureTrigger = MultitouchGestureTrigger()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(router: router)

        hotkey.onPress = { [router] in router.fire(.hotkey) }
        if !hotkey.register() {
            Log.app.error("Control+Option+S could not be registered; menu and URL triggers still work")
        }

        gesture.onTrigger = { [router] in router.fire(.gesture) }
        gesture.onFingerCount = { [weak self] n in
            if SettingsStore.shared.gestureDebug { self?.statusItem.showFingerCount(n) }
        }
        statusItem.onGestureToggled = { [weak self] on in self?.applyGestureSetting(on) }
        statusItem.onDebugToggled = { [weak self] on in
            if !on { self?.statusItem.showFingerCount(nil) }
        }
        applyGestureSetting(SettingsStore.shared.gestureEnabled)
        Log.app.info("Snapncrop started")
    }

    private func applyGestureSetting(_ enabled: Bool) {
        if enabled {
            if !gesture.start() { Log.gesture.error("gesture unavailable; falling back to hotkey only") }
        } else {
            gesture.stop()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        gesture.stop()
        hotkey.unregister()
    }

    /// `open snapncrop://capture` (BetterTouchTool, Shortcuts, Raycast, Hammerspoon, ...)
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "snapncrop" {
            if url.host == "capture" || url.path == "/capture" { router.fire(.urlScheme) }
            else { Log.app.error("unknown snapncrop URL: \(url.absoluteString)") }
        }
    }
}
