import AppKit

enum Trigger: String { case hotkey, menu, urlScheme, gesture }

/// The ONE entry point for starting a capture. Hotkey, menu, URL scheme and trackpad gesture
/// all call `fire(_:)`; none of them touch capture code directly. Adding a new trigger later
/// (e.g. a Shortcuts action) means calling this and nothing else.
final class TriggerRouter {
    private var session: CaptureSession?
    private var starting = false

    func fire(_ trigger: Trigger) {
        DispatchQueue.main.async { [self] in
            Log.app.info("capture requested via \(trigger.rawValue)")
            guard session == nil, !starting else { return }        // already capturing: ignore repeats
            guard PermissionManager.ensureScreenRecording() else { return }
            starting = true
            Task { @MainActor in
                defer { starting = false }
                do {
                    let shots = try await CaptureService.captureAllDisplays()
                    let s = CaptureSession(shots: shots)
                    s.onEnd = { [weak self] in self?.session = nil }
                    session = s
                    s.present()
                } catch {
                    // Nothing is on screen yet, so there is nothing to tear down; just explain.
                    Log.capture.error("capture failed: \(error.localizedDescription)")
                    NSApp.activate(ignoringOtherApps: true)
                    let a = NSAlert()
                    a.messageText = "Snapncrop couldn't capture the screen"
                    a.informativeText = error.localizedDescription
                        + "\n\nIf you just granted permission, quit and reopen Snapncrop."
                    a.runModal()
                }
            }
        }
    }
}
