import AppKit
import SnapncropCore

/// Keeps track of pinned screenshots so the menu can close them all.
final class PinManager {
    static let shared = PinManager()
    private var panels: [PinPanel] = []
    var count: Int { panels.count }

    func pin(image: CGImage, scale: CGFloat, frame: CGRect) {
        let panel = PinPanel(image: image, scale: scale, frame: frame)
        panel.onClose = { [weak self, unowned panel] in self?.panels.removeAll { $0 === panel } }
        panels.append(panel)
        panel.orderFrontRegardless()
        panel.makeKey()                      // so Esc / ⌘C work right away (non-activating: your other app keeps focus)
    }

    func closeAll() { panels.forEach { $0.closePin() } }
}

/// A screenshot floating above other windows.
///   drag anywhere = move · scroll or pinch = resize · right-click = copy / save / opacity / close
///   click it, then Esc or ⌘W = close · ⌘C = copy
final class PinPanel: NSPanel {
    var onClose: (() -> Void)?
    private let image: CGImage
    private let scale: CGFloat

    override var canBecomeKey: Bool { true }       // needed for keyboard shortcuts on a borderless panel
    override var canBecomeMain: Bool { false }

    init(image: CGImage, scale: CGFloat, frame: CGRect) {
        self.image = image; self.scale = scale
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]   // follows you across Spaces and full-screen apps
        isOpaque = false; backgroundColor = .clear; hasShadow = true
        hidesOnDeactivate = false; isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        contentView = PinContentView(image: image, panel: self)
    }

    func closePin() { orderOut(nil); onClose?(); onClose = nil }

    func copyImage() {
        if let png = ExportRenderer.pngData(from: image, scale: scale) { ExportService.copyToClipboard(png: png) }
    }

    func saveImage() {
        guard let png = ExportRenderer.pngData(from: image, scale: scale) else { return }
        if let url = try? ExportService.save(png: png) { Log.capture.info("saved pinned image \(url.path)") }
    }

    func zoom(by factor: CGFloat) {
        let maxSize = (screen ?? NSScreen.main)?.visibleFrame.size ?? CGSize(width: 2000, height: 1200)
        setFrame(PinGeometry.resized(frame, factor: factor, maxSize: maxSize), display: true)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53 { closePin(); return }                                       // Esc
        if flags == .command, event.charactersIgnoringModifiers == "w" { closePin(); return }
        if flags == .command, event.charactersIgnoringModifiers == "c" { copyImage(); return }
        super.keyDown(with: event)
    }
}

private final class PinContentView: NSView {
    private let image: CGImage
    private unowned let panel: PinPanel
    private let closeButton = NSButton()
    private var area: NSTrackingArea?

    init(image: CGImage, panel: PinPanel) {
        self.image = image; self.panel = panel
        super.init(frame: .zero)
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.45).cgColor

        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close pinned screenshot")
        closeButton.isBordered = false
        closeButton.contentTintColor = .white
        closeButton.target = self; closeButton.action = #selector(close)
        closeButton.toolTip = "Close (Esc)"
        closeButton.frame = NSRect(x: 4, y: 0, width: 22, height: 22)
        closeButton.autoresizingMask = [.minYMargin]          // stay pinned to the top-left as the window resizes
        closeButton.isHidden = true
        addSubview(closeButton)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        closeButton.setFrameOrigin(NSPoint(x: 4, y: bounds.height - 26))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: bounds)
    }

    // Hover shows the close button.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = area { removeTrackingArea(a) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(a); area = a
    }
    override func mouseEntered(with event: NSEvent) { closeButton.isHidden = false }
    override func mouseExited(with event: NSEvent) { closeButton.isHidden = true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Resize with scroll wheel or pinch.
    override func scrollWheel(with event: NSEvent) {
        let k: CGFloat = event.hasPreciseScrollingDeltas ? 0.004 : 0.03
        panel.zoom(by: exp(event.scrollingDeltaY * k))
    }
    override func magnify(with event: NSEvent) { panel.zoom(by: 1 + event.magnification) }

    // Right-click menu.
    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        for (title, sel) in [("Copy image", #selector(copyImage)), ("Save to screenshots folder", #selector(saveImage))] {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: ""); i.target = self; m.addItem(i)
        }
        m.addItem(.separator())
        let op = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for pct in [100, 75, 50, 25] {
            let i = NSMenuItem(title: "\(pct)%", action: #selector(setOpacity(_:)), keyEquivalent: "")
            i.target = self; i.tag = pct
            i.state = abs(panel.alphaValue * 100 - CGFloat(pct)) < 1 ? .on : .off
            sub.addItem(i)
        }
        op.submenu = sub; m.addItem(op)
        m.addItem(.separator())
        let c = NSMenuItem(title: "Close", action: #selector(close), keyEquivalent: ""); c.target = self; m.addItem(c)
        return m
    }

    @objc private func copyImage() { panel.copyImage() }
    @objc private func saveImage() { panel.saveImage() }
    @objc private func setOpacity(_ i: NSMenuItem) { panel.alphaValue = CGFloat(i.tag) / 100 }
    @objc private func close() { panel.closePin() }
}
