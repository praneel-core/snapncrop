import Carbon.HIToolbox

/// Global hotkey via Carbon's RegisterEventHotKey. Unlike an event tap, it needs NO
/// Accessibility / Input Monitoring permission, and it swallows the key combo system-wide.
final class HotkeyManager {
    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Default: Control + Option + S.
    @discardableResult
    func register(keyCode: UInt32 = UInt32(kVK_ANSI_S),
                  modifiers: UInt32 = UInt32(controlKey | optionKey)) -> Bool {
        unregister()
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let me = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.onPress?() }
            return noErr
        }, 1, &spec, selfPtr, &handlerRef)
        guard status == noErr else { Log.app.error("InstallEventHandler failed: \(status)"); return false }

        let id = EventHotKeyID(signature: OSType(0x534E4331) /* 'SNC1' */, id: 1)
        let reg = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if reg != noErr { Log.app.error("RegisterEventHotKey failed: \(reg) (combo already taken?)") }
        return reg == noErr
    }

    func unregister() {
        if let r = hotKeyRef { UnregisterEventHotKey(r); hotKeyRef = nil }
        if let h = handlerRef { RemoveEventHandler(h); handlerRef = nil }
    }

    deinit { unregister() }
}
