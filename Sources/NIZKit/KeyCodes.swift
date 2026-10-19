import Foundation

public enum KeyCategory: String, CaseIterable, Codable, Identifiable {
    case keyboard, media, mouse, function, power
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .keyboard: return "Keyboard"
        case .media: return "Media"
        case .mouse: return "Mouse"
        case .function: return "Keyboard functions"
        case .power: return "Power"
        }
    }
}

public struct KeyCode: Identifiable, Hashable {
    public let code: UInt8
    public let name: String
    /// Short text for a keycap.
    public let label: String
    public let category: KeyCategory
    public var id: UInt8 { code }
}

/// The keyboard's own key codes ("HWCode" in the Windows tool). Codes 1–107 are
/// ordinary keys numbered by physical position on a full-size board; 0x6C and up
/// are media, mouse and firmware functions.
public enum KeyCodes {
    public static let all: [KeyCode] = build()
    private static let byCode: [UInt8: KeyCode] = Dictionary(uniqueKeysWithValues: all.map { ($0.code, $0) })

    public static func info(_ code: UInt8) -> KeyCode? { byCode[code] }

    public static func name(_ code: UInt8) -> String {
        byCode[code]?.name ?? String(format: "Code 0x%02X", code)
    }

    public static func label(_ code: UInt8) -> String {
        byCode[code]?.label ?? String(format: "%02X", code)
    }

    public static func codes(in category: KeyCategory) -> [KeyCode] {
        all.filter { $0.category == category }
    }

    public static let fn: UInt8 = 0x9C
    public static let modifiers: Set<UInt8> = [55, 66, 67, 68, 69, 71, 72, 74]

    private static func build() -> [KeyCode] {
        var out: [KeyCode] = []
        func add(_ code: Int, _ name: String, _ label: String? = nil, _ cat: KeyCategory = .keyboard) {
            out.append(KeyCode(code: UInt8(code), name: name, label: label ?? name, category: cat))
        }
        add(1, "Escape", "Esc")
        for i in 1...12 { add(1 + i, "F\(i)") }
        add(14, "` ~", "`")
        for (i, d) in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"].enumerated() { add(15 + i, d) }
        add(25, "- _", "-"); add(26, "= +", "=")
        add(27, "Backspace", "⌫"); add(28, "Tab")
        for (i, c) in "QWERTYUIOP".enumerated() { add(29 + i, String(c)) }
        add(39, "[ {", "["); add(40, "] }", "]"); add(41, "\\ |", "\\")
        add(42, "Caps Lock", "Caps")
        for (i, c) in "ASDFGHJKL".enumerated() { add(43 + i, String(c)) }
        add(52, "; :", ";"); add(53, "' \"", "'"); add(54, "Enter", "Enter")
        add(55, "Left Shift", "Shift")
        for (i, c) in "ZXCVBNM".enumerated() { add(56 + i, String(c)) }
        add(63, ", <", ","); add(64, ". >", "."); add(65, "/ ?", "/")
        add(66, "Right Shift", "Shift")
        add(67, "Left Ctrl", "Ctrl"); add(68, "Left Win / ⌘", "Win"); add(69, "Left Alt / ⌥", "Alt")
        add(70, "Space"); add(71, "Right Alt / ⌥", "Alt"); add(72, "Right Win / ⌘", "Win")
        add(73, "Menu"); add(74, "Right Ctrl", "Ctrl")
        add(75, "System Power", "Power", .power)
        add(76, "System Sleep", "Sleep", .power)
        add(77, "System Wake", "Wake", .power)
        add(78, "Print Screen", "PrtSc"); add(79, "Scroll Lock", "ScrLk"); add(80, "Pause")
        add(81, "Insert", "Ins"); add(82, "Home"); add(83, "Page Up", "PgUp")
        add(84, "Delete", "Del"); add(85, "End"); add(86, "Page Down", "PgDn")
        add(87, "Up", "↑"); add(88, "Left", "←"); add(89, "Down", "↓"); add(90, "Right", "→")
        add(91, "Num Lock", "NumLk")
        add(92, "Keypad /", "KP/"); add(93, "Keypad *", "KP*")
        add(94, "Keypad 7", "KP7"); add(95, "Keypad 8", "KP8"); add(96, "Keypad 9", "KP9")
        add(97, "Keypad 4", "KP4"); add(98, "Keypad 5", "KP5"); add(99, "Keypad 6", "KP6")
        add(100, "Keypad 1", "KP1"); add(101, "Keypad 2", "KP2"); add(102, "Keypad 3", "KP3")
        add(103, "Keypad 0", "KP0"); add(104, "Keypad .", "KP."); add(105, "Keypad -", "KP-")
        add(106, "Keypad +", "KP+"); add(107, "Keypad Enter", "KPEnt")
        add(0xCC, "ISO \\ |  (102nd key)", "ISO\\")

        let media: [(String, String)] = [
            ("Next Track", "⏭"), ("Previous Track", "⏮"), ("Stop", "⏹"), ("Play / Pause", "⏯"),
            ("Mute", "Mute"), ("Volume Up", "Vol+"), ("Volume Down", "Vol−"), ("Media Player", "Media"),
            ("Mail", "Mail"), ("Calculator", "Calc"), ("My Computer", "PC"), ("Browser Search", "Search"),
            ("Browser Home", "WHome"), ("Browser Back", "WBack"), ("Browser Forward", "WFwd"),
            ("Browser Stop", "WStop"), ("Browser Refresh", "WRefr"), ("Browser Favorites", "WFav"),
        ]
        for (i, m) in media.enumerated() { add(0x6C + i, m.0, m.1, .media) }

        let mouse: [(String, String)] = [
            ("Mouse Move Left", "M←"), ("Mouse Move Right", "M→"), ("Mouse Move Up", "M↑"),
            ("Mouse Move Down", "M↓"), ("Left Click", "LClk"), ("Right Click", "RClk"),
            ("Middle Click", "MClk"), ("Wheel Up", "Whl↑"), ("Wheel Down", "Whl↓"),
        ]
        for (i, m) in mouse.enumerated() { add(0x7E + i, m.0, m.1, .mouse) }

        let functions: [(Int, String, String, KeyCategory)] = [
            (0x87, "Backlight On/Off", "BL", .function),
            (0x88, "Backlight Custom (macro)", "BLCus", .function),
            (0x89, "Lighting Effect", "Effect", .function),
            (0x8A, "Effect Colour", "EfClr", .function),
            (0x8B, "Exit Effect", "EfExit", .function),
            (0x8E, "Effect Speed −", "Spd−", .function),
            (0x8F, "Effect Speed +", "Spd+", .function),
            (0x90, "Brightness −", "Bri−", .function),
            (0x91, "Brightness +", "Bri+", .function),
            (0x92, "Effect Direction Left", "Dir←", .function),
            (0x93, "Effect Direction Right", "Dir→", .function),
            (0x94, "Background Colour", "BgClr", .function),
            (0x96, "Keyboard Lock", "KbLock", .function),
            (0x97, "Adjust Trigger Point", "Trig", .function),
            (0x98, "Swap Ctrl / Caps", "C⇄C", .function),
            (0x99, "Win Key Lock", "WinLk", .function),
            (0x9A, "Fn Lock", "FnLk", .function),
            (0x9B, "Win / Mac Mode", "Win/Mac", .function),
            (0x9C, "Fn", "Fn", .function),
            (0x9D, "Mouse Step (pixels)", "MPix", .mouse),
            (0x9E, "Mouse Step (time)", "MTime", .mouse),
            (0x9F, "Programmable Keyboard", "Prog", .function),
            (0xA7, "Wired / Wireless", "USB/BT", .function),
            (0xA8, "Bluetooth Device 1", "BT1", .function),
            (0xA9, "Bluetooth Device 2", "BT2", .function),
            (0xAA, "Bluetooth Device 3", "BT3", .function),
            (0xAB, "Game Mode", "Game", .function),
            (0xAC, "ECO Mode", "ECO", .function),
            (0xAD, "Mouse First Delay", "MDly", .mouse),
            (0xAE, "Key Repeat Rate", "Rate", .function),
            (0xAF, "Key Response Delay", "Resp", .function),
            (0xB0, "Bluetooth Device 4", "BT4", .function),
            (0xB1, "Bluetooth Device 5", "BT5", .function),
            (0xB2, "Left Double Click", "Dbl", .mouse),
        ]
        for f in functions { add(f.0, f.1, f.2, f.3) }
        return out
    }
}
