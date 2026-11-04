import AppKit

/// Menu bar icon and menu. High-level layout mirrors talk-to-me-man:
///   status line (always visible; turns into a clickable fix when something needs attention)
///   main action, recent items, toggles, utilities, quit.
/// The menu is rebuilt each time it opens, so it is always current.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let router: TriggerRouter
    var onGestureToggled: ((Bool) -> Void)?
    var onDebugToggled: ((Bool) -> Void)?
    var onPreferences: (() -> Void)?

    init(router: TriggerRouter) {
        self.router = router
        super.init()
        setIcon(active: false)
        item.button?.toolTip = "Snapncrop is on — press \(SettingsStore.shared.shortcut.description) to take a screenshot"
        let menu = NSMenu(); menu.delegate = self
        item.menu = menu
        NotificationCenter.default.addObserver(forName: .captureActiveChanged, object: nil, queue: .main) { [weak self] n in
            self?.setIcon(active: (n.object as? Bool) ?? false)
        }
    }

    /// Outline crop icon normally; filled/bold while a capture is in progress.
    private func setIcon(active: Bool) {
        let name = active ? "crop.rotate" : "crop"
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: active ? .heavy : .regular)
        item.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Snapncrop")?
            .withSymbolConfiguration(cfg)
    }

    /// Shows "✋3" next to the icon while tuning the gesture; empty otherwise.
    func showFingerCount(_ n: Int?) { item.button?.title = n.map { " ✋\($0)" } ?? "" }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // 1. Status line
        if PermissionManager.hasScreenRecording {
            let s = NSMenuItem(title: "● Snapncrop is on — press \(SettingsStore.shared.shortcut.description) to capture", action: nil, keyEquivalent: "")
            s.isEnabled = false
            menu.addItem(s)
        } else {
            menu.addItem(action("⚠︎ Screen Recording permission needed — click to fix", #selector(fixPermission)))
        }
        menu.addItem(.separator())

        // 2. Main action
        menu.addItem(action("Capture   \(SettingsStore.shared.shortcut.description)", #selector(capture)))
        menu.addItem(.separator())

        // 3. Recent screenshots: click to copy again
        let header = NSMenuItem(title: "Recent screenshots", action: nil, keyEquivalent: ""); header.isEnabled = false
        menu.addItem(header)
        let recents = RecentCaptures.shared.items
        if recents.isEmpty {
            let none = NSMenuItem(title: "  (none yet)", action: nil, keyEquivalent: ""); none.isEnabled = false
            menu.addItem(none)
        }
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        for (i, r) in recents.enumerated() {
            let m = action("  \(f.string(from: r.date))  ·  \(r.width) × \(r.height)", #selector(copyRecent(_:)))
            m.tag = i; m.toolTip = "Click to copy to clipboard again"
            menu.addItem(m)
        }
        menu.addItem(.separator())

        // 4. Toggles (remembered)
        menu.addItem(toggle("Four-finger tap to capture", #selector(toggleGesture), SettingsStore.shared.gestureEnabled))
        menu.addItem(toggle("Also save a file when copying", #selector(toggleAutoSave), SettingsStore.shared.alsoSaveOnCopy))
        menu.addItem(toggle("Launch at login", #selector(toggleLogin), LoginItem.isEnabled))
        menu.addItem(toggle("Show finger count (tuning)", #selector(toggleDebug), SettingsStore.shared.gestureDebug))
        menu.addItem(.separator())

        // 5. Utilities
        let prefs = action("Preferences…", #selector(openPreferences)); prefs.keyEquivalent = ","
        menu.addItem(prefs)
        menu.addItem(action("Open screenshots folder", #selector(openFolder)))
        menu.addItem(action("About Snapncrop", #selector(about)))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Snapncrop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func action(_ title: String, _ sel: Selector) -> NSMenuItem {
        let m = NSMenuItem(title: title, action: sel, keyEquivalent: ""); m.target = self; return m
    }
    private func toggle(_ title: String, _ sel: Selector, _ on: Bool) -> NSMenuItem {
        let m = action(title, sel); m.state = on ? .on : .off; return m
    }

    // MARK: actions

    @objc private func openPreferences() { onPreferences?() }
    @objc private func capture() { router.fire(.menu) }
    @objc private func fixPermission() { PermissionManager.showHelp() }

    @objc private func copyRecent(_ sender: NSMenuItem) {
        let items = RecentCaptures.shared.items
        guard sender.tag < items.count else { return }
        ExportService.copyToClipboard(png: items[sender.tag].png)
    }

    @objc private func toggleGesture() {
        SettingsStore.shared.gestureEnabled.toggle()
        onGestureToggled?(SettingsStore.shared.gestureEnabled)
    }
    @objc private func toggleDebug() {
        SettingsStore.shared.gestureDebug.toggle()
        onDebugToggled?(SettingsStore.shared.gestureDebug)
    }
    @objc private func toggleAutoSave() { SettingsStore.shared.alsoSaveOnCopy.toggle() }

    @objc private func toggleLogin() {
        do {
            try LoginItem.set(!LoginItem.isEnabled)
        } catch {
            Log.app.error("launch at login failed: \(error.localizedDescription)")
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert(); a.messageText = "Couldn't change Launch at login"
            a.informativeText = "\(error.localizedDescription)\n\nRun the app from ~/Applications (./build.sh install) and try again."
            a.runModal()
        }
    }

    @objc private func openFolder() {
        let url = SettingsStore.shared.saveFolder
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Snapncrop",
            .credits: NSAttributedString(string: "Snap and crop. Free, fully local, no network.\n⌃⌥S to capture · Ctrl+C copy · Ctrl+S save · Esc cancel"),
        ])
    }
}
