import AppKit
import SwiftUI
import SnapncropCore

/// Records a key combination: click the button, press the keys. Esc cancels.
private struct ShortcutRecorder: View {
    @ObservedObject var model: PreferencesModel
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Button(model.recording ? "Press the new shortcut…  (Esc to cancel)" : model.shortcut.description) {
                model.recording ? stop() : start()
            }
            .frame(minWidth: 220)
            .buttonStyle(.bordered)
            .tint(model.recording ? .accentColor : nil)

            Button("Reset") { stop(); model.resetShortcut() }
                .disabled(model.shortcut == .default)
        }
        .onDisappear { stop() }
    }

    private func start() {
        model.recording = true
        model.shortcutMessage = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 53 && flags.isEmpty { stop(); return nil }          // Esc cancels
            var mods: UInt32 = 0
            if flags.contains(.control) { mods |= Shortcut.control }
            if flags.contains(.option) { mods |= Shortcut.option }
            if flags.contains(.shift) { mods |= Shortcut.shift }
            if flags.contains(.command) { mods |= Shortcut.command }
            let candidate = Shortcut(keyCode: UInt32(event.keyCode), modifiers: mods)
            if candidate.isValid { stop(); model.setShortcut(candidate) }
            else { model.shortcutMessage = "Include ⌃, ⌥ or ⌘ (or use an F-key)." }
            return nil                                                                // swallow the key press
        }
    }

    private func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        if model.recording { model.recording = false }
    }
}

struct PreferencesView: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        Form {
            Section("Capture shortcut") {
                ShortcutRecorder(model: model)
                if let m = model.shortcutMessage { Text(m).font(.callout).foregroundStyle(.orange) }
                Text("Press this anywhere to start a screenshot. You can also use the menu bar icon, snapncrop://capture, or a four-finger tap.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Screenshots folder") {
                HStack {
                    Text(model.saveFolder.path).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { model.chooseFolder() }
                    Button("Open") { model.openFolder() }
                }
                Text("Ctrl+S (or Save) puts a PNG here. Created automatically if it doesn't exist.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Drawing defaults") {
                HStack(spacing: 10) {
                    Text("Colour")
                    ForEach(model.palette, id: \.name) { item in
                        let c = item.color
                        Circle()
                            .fill(Color(red: c.r, green: c.g, blue: c.b))
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Color.primary.opacity(model.strokeColor == c ? 0.9 : 0.25),
                                                     lineWidth: model.strokeColor == c ? 2.5 : 1))
                            .onTapGesture { model.setColor(c) }
                            .help(item.name)
                    }
                }
                Picker("Width / text size", selection: Binding(get: { model.strokeWidth }, set: { model.setWidth($0) })) {
                    ForEach(model.widths, id: \.name) { Text($0.name).tag($0.value) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
            }

            Section("Behaviour") {
                Toggle("Four-finger tap to capture", isOn: Binding(get: { model.gestureEnabled }, set: { model.setGesture($0) }))
                Toggle("Also save a file when copying", isOn: Binding(get: { model.alsoSaveOnCopy }, set: { model.setAlsoSave($0) }))
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                if let m = model.loginMessage { Text(m).font(.callout).foregroundStyle(.orange) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Owns the Preferences window (opens it, reuses it, brings it to the front).
final class PreferencesWindowController {
    private var window: NSWindow?
    private let model: PreferencesModel

    init(model: PreferencesModel) { self.model = model }

    func show() {
        model.reload()
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: PreferencesView(model: model)))
            w.title = "Snapncrop Preferences"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)      // menu bar apps aren't frontmost by default
        window?.makeKeyAndOrderFront(nil)
    }
}
