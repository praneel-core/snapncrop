import AppKit

/// A small message that fades away by itself ("Copied 128 characters", "No text found").
/// Stays on screen after the capture overlay has closed, so you still get confirmation.
enum Toast {
    private static var panel: NSPanel?

    /// `center` is a point in screen coordinates (bottom-left origin).
    static func show(_ text: String, at center: NSPoint, seconds: TimeInterval = 1.8) {
        panel?.orderOut(nil)
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .white
        label.sizeToFit()
        let size = NSSize(width: label.frame.width + 28, height: label.frame.height + 18)
        label.setFrameOrigin(NSPoint(x: 14, y: 9))

        let box = NSView(frame: NSRect(origin: .zero, size: size))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        box.layer?.cornerRadius = 10
        box.addSubview(label)

        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.contentView = box
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.ignoresMouseEvents = true; p.hidesOnDeactivate = false; p.isReleasedWhenClosed = false
        p.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)   // above the overlay too
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.setFrameOrigin(NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
        p.alphaValue = 1
        p.orderFrontRegardless()
        panel = p

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            guard panel === p else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; p.animator().alphaValue = 0 },
                                                 completionHandler: { if panel === p { p.orderOut(nil); panel = nil } })
        }
    }
}
