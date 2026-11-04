import AppKit
import SnapncropCore

/// Small round colour button.
private final class SwatchButton: NSButton {
    var color: RGBA = .red
    var isChosen = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 4, dy: 4)
        NSColor(cgColor: color.cgColor)?.setFill()
        NSBezierPath(ovalIn: r).fill()
        NSColor.white.withAlphaComponent(0.6).setStroke()
        let ring = NSBezierPath(ovalIn: r); ring.lineWidth = 1; ring.stroke()
        if isChosen {
            NSColor.white.setStroke()
            let sel = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5)); sel.lineWidth = 2; sel.stroke()
        }
    }
    override var intrinsicContentSize: NSSize { NSSize(width: 22, height: 22) }
}

/// The floating toolbar. A non-activating panel: clicking it does NOT steal keyboard focus from the
/// overlay, so Esc / Cmd+Z keep working while you use the buttons.
final class ToolbarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private unowned let session: CaptureSession
    private let undoButton = NSButton()
    private let redoButton = NSButton()
    private var swatches: [SwatchButton] = []
    private let widthControl = NSSegmentedControl(labels: ["S", "M", "L"], trackingMode: .selectOne,
                                                  target: nil, action: nil)
    private let widths: [CGFloat] = [2, 4, 8]
    private let palette: [RGBA] = [.red, .blue, .green, .yellow, .black]

    init(session: CaptureSession) {
        self.session = session
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false; backgroundColor = .clear; hasShadow = true
        hidesOnDeactivate = false; isReleasedWhenClosed = false
        buildUI()
    }

    private func symbolButton(_ symbol: String, tip: String, action: Selector) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage(),
                         target: self, action: action)
        b.bezelStyle = .texturedRounded; b.toolTip = tip; b.isBordered = true
        return b
    }

    private func buildUI() {
        // Tool (Phase 1: only rectangle exists; the others arrive in Phase 2).
        let rectTool = symbolButton("rectangle", tip: "Rectangle", action: #selector(noop))
        rectTool.state = .on; rectTool.setButtonType(.pushOnPushOff)

        for (i, c) in palette.enumerated() {
            let s = SwatchButton(); s.color = c; s.tag = i; s.isBordered = false; s.title = ""
            s.target = self; s.action = #selector(pickColor(_:)); s.isChosen = (c == session.style.color)
            s.toolTip = "Colour"
            swatches.append(s)
        }
        widthControl.target = self; widthControl.action = #selector(pickWidth(_:))
        widthControl.selectedSegment = widths.firstIndex(of: session.style.width) ?? 1
        widthControl.toolTip = "Stroke width"

        undoButton.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Undo")
        redoButton.image = NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: "Redo")
        for (b, a, tip) in [(undoButton, #selector(doUndo), "Undo (⌘Z)"), (redoButton, #selector(doRedo), "Redo (⇧⌘Z)")] {
            b.target = self; b.action = a; b.bezelStyle = .texturedRounded; b.toolTip = tip
        }

        let copy = NSButton(title: "Copy", target: self, action: #selector(doCopy))
        copy.bezelStyle = .rounded; copy.toolTip = "Copy to clipboard (Ctrl+C, ⌘C or ↩)"; copy.keyEquivalent = ""
        let save = NSButton(title: "Save", target: self, action: #selector(doSave))
        save.bezelStyle = .rounded; save.toolTip = "Save PNG to ~/Pictures/Screenshots (Ctrl+S or ⌘S)"
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(doCancel))
        cancel.bezelStyle = .rounded; cancel.toolTip = "Cancel (Esc)"

        let views: [NSView] = [rectTool, divider()] + swatches + [widthControl, divider(), undoButton, redoButton,
                                                                   divider(), copy, save, cancel]
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal; stack.spacing = 6; stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)

        let fx = NSVisualEffectView()
        fx.material = .hudWindow; fx.blendingMode = .behindWindow; fx.state = .active
        fx.wantsLayer = true; fx.layer?.cornerRadius = 10; fx.layer?.masksToBounds = true
        fx.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            stack.topAnchor.constraint(equalTo: fx.topAnchor),
            stack.bottomAnchor.constraint(equalTo: fx.bottomAnchor),
        ])
        contentView = fx
        setContentSize(stack.fittingSize)
    }

    private func divider() -> NSView {
        let v = NSBox(); v.boxType = .separator
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return v
    }

    func refresh(canUndo: Bool, canRedo: Bool) {
        undoButton.isEnabled = canUndo; redoButton.isEnabled = canRedo
    }

    @objc private func noop() { /* only one tool in Phase 1 */ }
    @objc private func pickColor(_ s: SwatchButton) {
        session.style.color = palette[s.tag]
        swatches.forEach { $0.isChosen = ($0 === s) }
    }
    @objc private func pickWidth(_ c: NSSegmentedControl) { session.style.width = widths[c.selectedSegment] }
    @objc private func doUndo() { session.undo() }
    @objc private func doRedo() { session.redo() }
    @objc private func doCopy() { session.copyAndClose() }
    @objc private func doSave() { session.saveAndClose() }
    @objc private func doCancel() { session.cancel() }
}
