import AppKit
import CoreGraphics

enum PermissionManager {
    static var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }

    /// Returns true if we may capture right now. Otherwise shows the system prompt (first time only)
    /// and a friendly explanation.
    static func ensureScreenRecording() -> Bool {
        if hasScreenRecording { return true }
        _ = CGRequestScreenCaptureAccess()          // shows the macOS dialog the first time
        showHelp()
        return false
    }

    static func showHelp() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Snapncrop needs Screen Recording permission"
        alert.informativeText = """
        macOS only lets an app capture the screen after you allow it.

        1. Open System Settings → Privacy & Security → Screen & System Audio Recording.
        2. Switch on Snapncrop.
        3. Quit and reopen Snapncrop (macOS requires a restart of the app after granting).

        Nothing is sent anywhere; screenshots stay on your Mac.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            NSWorkspace.shared.open(url)
        }
    }
}
