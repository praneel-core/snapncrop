import AppKit

/// Menu bar icon and its menu.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let router: TriggerRouter
    private let gestureItem = NSMenuItem()
    private let debugItem = NSMenuItem()
    var onGestureToggled: ((Bool) -> Void)?
    var onDebugToggled: ((Bool) -> Void)?

    init(router: TriggerRouter) {
        self.router = router
        super.init()
        if let b = item.button {
            b.image = NSImage(systemSymbolName: "crop", accessibilityDescription: "Snapncrop")
            b.toolTip = "Snapncrop is on — press ⌃⌥S to take a screenshot"
        }
        let menu = NSMenu()
        menu.delegate = self
        // Status header so it's obvious the tool is running and ready.
        let header = NSMenuItem(title: "● Snapncrop is on — press ⌃⌥S to capture", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        let cap = NSMenuItem(title: "Capture   ⌃⌥S", action: #selector(capture), keyEquivalent: "")
        cap.target = self
        menu.addItem(cap)
        menu.addItem(.separator())

        gestureItem.title = "Four-finger tap to capture"
        gestureItem.target = self; gestureItem.action = #selector(toggleGesture)
        menu.addItem(gestureItem)
        debugItem.title = "Show finger count in menu bar (tuning)"
        debugItem.target = self; debugItem.action = #selector(toggleDebug)
        menu.addItem(debugItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Snapncrop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        item.menu = menu
    }

    /// Shows "✋3" next to the icon while tuning the gesture; empty otherwise.
    func showFingerCount(_ n: Int?) {
        item.button?.title = n.map { " ✋\($0)" } ?? ""
    }

    func menuWillOpen(_ menu: NSMenu) {
        gestureItem.state = SettingsStore.shared.gestureEnabled ? .on : .off
        debugItem.state = SettingsStore.shared.gestureDebug ? .on : .off
    }

    @objc private func capture() { router.fire(.menu) }
    @objc private func toggleGesture() {
        SettingsStore.shared.gestureEnabled.toggle()
        onGestureToggled?(SettingsStore.shared.gestureEnabled)
    }
    @objc private func toggleDebug() {
        SettingsStore.shared.gestureDebug.toggle()
        onDebugToggled?(SettingsStore.shared.gestureDebug)
    }
}
