import Foundation

/// A global keyboard shortcut: a virtual key code plus Carbon modifier flags.
/// Pure data + text formatting, so it is unit-tested; the Carbon registration lives in the app.
public struct Shortcut: Equatable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    // Carbon modifier bit values (from Carbon.HIToolbox: cmdKey, shiftKey, optionKey, controlKey).
    public static let command: UInt32 = 256
    public static let shift: UInt32 = 512
    public static let option: UInt32 = 2048
    public static let control: UInt32 = 4096

    public init(keyCode: UInt32, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }

    /// Control + Option + S
    public static let `default` = Shortcut(keyCode: 1, modifiers: control | option)

    private static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
        13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I",
        35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
        47: ".", 49: "Space", 50: "`",
        36: "↩", 48: "⇥", 51: "⌫", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
    private static let functionKeys: Set<UInt32> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]

    public var keyName: String { Self.keyNames[keyCode] ?? "Key \(keyCode)" }

    /// "⌃⌥S" (macOS order: control, option, shift, command).
    public var description: String {
        var s = ""
        if modifiers & Self.control != 0 { s += "⌃" }
        if modifiers & Self.option != 0 { s += "⌥" }
        if modifiers & Self.shift != 0 { s += "⇧" }
        if modifiers & Self.command != 0 { s += "⌘" }
        return s + keyName
    }

    /// A global shortcut must include ⌃, ⌥ or ⌘ (so normal typing is never hijacked), unless it is an F-key.
    public var isValid: Bool {
        guard Self.keyNames[keyCode] != nil else { return false }
        let strong = modifiers & (Self.control | Self.option | Self.command) != 0
        return strong || Self.functionKeys.contains(keyCode)
    }
}
