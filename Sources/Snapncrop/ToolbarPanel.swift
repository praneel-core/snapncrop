import AppKit
import SnapncropCore

/// A button that tells its toolbar to show a hover label (name + shortcut). We draw our own label
/// because macOS tooltips are unreliable on a floating, non-key panel like this one.
class HintButton: NSButton {
    var hint = ""
    weak var hintOwner: ToolbarPanel?
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = area { removeTrackingArea(a) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(a); area = a
    }
    override func mouseEntered(with event: NSEvent) { if !hint.isEmpty { hintOwner?.showHint(hint, over: self) } }
    override func mouseExited(with event: NSEvent) { hintOwner?.hideHint() }
    override func mouseDown(with event: NSEvent) { hintOwner?.hideHint(); super.mouseDown(with: event) }
}

/// Small round colour button.
private final class SwatchButton: HintButton {
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
    private let undoButton = HintButton()
    private let redoButton = HintButton()
    private let hintPanel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: false)
    private let hintLabel = NSTextField(labelWithString: "")
    private var swatches: [SwatchButton] = []
    private var toolButtons: [(tool: AnnotationTool, button: HintButton)] = []
    private let widthControl = NSSegmentedControl(labels: ["S", "M", "L"], trackingMode: .selectOne,
                                                  target: nil, action: nil)
    private let widths: [CGFloat] = [2, 4, 8]
    private let palette: [RGBA] = [.red, .blue, .green, .yellow, .black]
    private let colorNames = ["Red", "Blue", "Green", "Yellow", "Black"]

    init(session: CaptureSession) {
        self.session = session
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false; backgroundColor = .clear; hasShadow = true
        hidesOnDeactivate = false; isReleasedWhenClosed = false
        buildUI()
    }

    private func symbolButton(_ symbol: String, hint: String, action: Selector) -> HintButton {
        let b = HintButton()
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: hint)
        b.target = self; b.action = action
        b.bezelStyle = .texturedRounded; b.isBordered = true
        b.hint = hint; b.hintOwner = self
        return b
    }

    private func textButton(_ title: String, hint: String, action: Selector) -> HintButton {
        let b = HintButton()
        b.title = title; b.target = self; b.action = action
        b.bezelStyle = .rounded; b.hint = hint; b.hintOwner = self
        return b
    }

    private func buildUI() {
        // Tools. To add one: new case in AnnotationTool + a row here.
        let toolDefs: [(AnnotationTool, String, String)] = [
            (.select, "cursorarrow", "Select & move  ·  V   (Delete removes)"),
            (.rectangle, "rectangle", "Rectangle  ·  R"),
            (.ellipse, "circle", "Ellipse  ·  E"),
            (.line, "line.diagonal", "Line  ·  L"),
            (.arrow, "arrow.up.right", "Arrow  ·  A"),
            (.pen, "scribble", "Pen  ·  P"),
            (.highlighter, "highlighter", "Highlighter  ·  H"),
            (.step, "1.circle.fill", "Step number  ·  N   (click to place 1, 2, 3…)"),
            (.pixelate, "square.grid.3x3.fill", "Pixelate (hide info)  ·  B   (S/M/L = block size)"),
            (.text, "textformat", "Text  ·  T   (Esc to finish)"),
        ]
        for (i, d) in toolDefs.enumerated() {
            let b = symbolButton(d.1, hint: d.2, action: #selector(pickTool(_:)))
            b.tag = i; b.setButtonType(.pushOnPushOff)
            toolButtons.append((d.0, b))
        }
        configureHintPanel()
        refreshTool(session.tool)

        for (i, c) in palette.enumerated() {
            let s = SwatchButton(); s.color = c; s.tag = i; s.isBordered = false; s.title = ""
            s.target = self; s.action = #selector(pickColor(_:)); s.isChosen = (c == session.style.color)
            s.hint = "Colour  ·  \(colorNames[i])"; s.hintOwner = self
            swatches.append(s)
        }
        widthControl.target = self; widthControl.action = #selector(pickWidth(_:))
        widthControl.selectedSegment = widths.firstIndex(of: session.style.width) ?? 1
        widthControl.toolTip = "Stroke width (S / M / L). For text this sets the font size."

        undoButton.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Undo")
        redoButton.image = NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: "Redo")
        for (b, a, tip) in [(undoButton, #selector(doUndo), "Undo  ·  ⌘Z"), (redoButton, #selector(doRedo), "Redo  ·  ⇧⌘Z")] {
            b.target = self; b.action = a; b.bezelStyle = .texturedRounded
            b.hint = tip; b.hintOwner = self
        }

        let ocr = symbolButton("text.viewfinder", hint: "Copy the TEXT in this area (OCR)  ·  Ctrl+T", action: #selector(doOCR))
        let copy = textButton("Copy", hint: "Copy to clipboard  ·  Ctrl+C", action: #selector(doCopy))
        let save = textButton("Save", hint: "Save to Screenshots folder  ·  Ctrl+S", action: #selector(doSave))
        let cancel = textButton("Cancel", hint: "Cancel  ·  Esc", action: #selector(doCancel))

        let views: [NSView] = toolButtons.map { $0.button } + [divider()] + swatches + [widthControl, divider(), undoButton, redoButton,
                                                                   divider(), ocr, copy, save, cancel]
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

    // MARK: hover hints

    private func configureHintPanel() {
        hintPanel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        hintPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hintPanel.isOpaque = false; hintPanel.backgroundColor = .clear; hintPanel.hasShadow = true
        hintPanel.ignoresMouseEvents = true; hintPanel.hidesOnDeactivate = false
        hintPanel.isReleasedWhenClosed = false
        hintLabel.font = .systemFont(ofSize: 12, weight: .medium)
        hintLabel.textColor = .white
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        box.layer?.cornerRadius = 6
        box.addSubview(hintLabel)
        hintPanel.contentView = box
    }

    func showHint(_ text: String, over view: NSView) {
        hintLabel.stringValue = text
        hintLabel.sizeToFit()
        let size = NSSize(width: hintLabel.frame.width + 16, height: hintLabel.frame.height + 10)
        hintLabel.setFrameOrigin(NSPoint(x: 8, y: 5))
        let screenFrame = (screen ?? NSScreen.main)?.frame ?? frame
        let anchor = convertToScreen(view.convert(view.bounds, to: nil))
        var y = frame.minY - size.height - 4                     // preferably just below the toolbar
        if y < screenFrame.minY + 4 { y = frame.maxY + 4 }       // no room: show above it
        var x = anchor.midX - size.width / 2
        x = max(screenFrame.minX + 4, min(x, screenFrame.maxX - size.width - 4))
        hintPanel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
        hintPanel.orderFrontRegardless()
    }

    func hideHint() { hintPanel.orderOut(nil) }

    override func orderOut(_ sender: Any?) { hintPanel.orderOut(nil); super.orderOut(sender) }

    private func divider() -> NSView {
        let v = NSBox(); v.boxType = .separator
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return v
    }

    func refresh(canUndo: Bool, canRedo: Bool) {
        undoButton.isEnabled = canUndo; redoButton.isEnabled = canRedo
    }

    /// Show the current drawing style (called when an annotation is selected).
    func syncStyle() {
        let st = session.style
        swatches.enumerated().forEach { $0.element.isChosen = (palette[$0.offset] == st.color) }
        widthControl.selectedSegment = widths.firstIndex(of: st.width) ?? -1
    }

    func refreshTool(_ t: AnnotationTool) {
        for (tool, b) in toolButtons { b.state = (tool == t) ? .on : .off }
    }
    @objc private func pickTool(_ b: NSButton) {   // b is one of our HintButtons
        session.setTool(toolButtons[b.tag].tool)
        refreshTool(session.tool)    // keep the clicked button lit even if clicked twice
    }
    @objc private func pickColor(_ s: SwatchButton) {
        session.setColor(palette[s.tag])
        swatches.forEach { $0.isChosen = ($0 === s) }
    }
    @objc private func pickWidth(_ c: NSSegmentedControl) { session.setWidth(widths[c.selectedSegment]) }
    @objc private func doUndo() { session.undo() }
    @objc private func doRedo() { session.redo() }
    @objc private func doOCR() { session.copyTextAndClose() }
    @objc private func doCopy() { session.copyAndClose() }
    @objc private func doSave() { session.saveAndClose() }
    @objc private func doCancel() { session.cancel() }
}
