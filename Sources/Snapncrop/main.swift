import AppKit

// Entry point. `.accessory` = menu bar app with no Dock icon (same effect as LSUIElement in Info.plist).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
