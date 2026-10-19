import AppKit
import NIZKit
import SwiftUI

/// macOS virtual key code -> NIZ hardware code, for "press a key" capture.
enum MacKeyMap {
    static let table: [UInt16: UInt8] = {
        var t: [UInt16: UInt8] = [
            0x35: 1, 0x7A: 2, 0x78: 3, 0x63: 4, 0x76: 5, 0x60: 6, 0x61: 7, 0x62: 8,
            0x64: 9, 0x65: 10, 0x6D: 11, 0x67: 12, 0x6F: 13,
            0x32: 14, 0x12: 15, 0x13: 16, 0x14: 17, 0x15: 18, 0x17: 19, 0x16: 20,
            0x1A: 21, 0x1C: 22, 0x19: 23, 0x1D: 24, 0x1B: 25, 0x18: 26, 0x33: 27,
            0x30: 28, 0x0C: 29, 0x0D: 30, 0x0E: 31, 0x0F: 32, 0x11: 33, 0x10: 34,
            0x20: 35, 0x22: 36, 0x1F: 37, 0x23: 38, 0x21: 39, 0x1E: 40, 0x2A: 41,
            0x39: 42, 0x00: 43, 0x01: 44, 0x02: 45, 0x03: 46, 0x05: 47, 0x04: 48,
            0x26: 49, 0x28: 50, 0x25: 51, 0x29: 52, 0x27: 53, 0x24: 54,
            0x38: 55, 0x06: 56, 0x07: 57, 0x08: 58, 0x09: 59, 0x0B: 60, 0x2D: 61,
            0x2E: 62, 0x2B: 63, 0x2F: 64, 0x2C: 65, 0x3C: 66,
            0x3B: 67, 0x37: 68, 0x3A: 69, 0x31: 70, 0x3D: 71, 0x36: 72, 0x6E: 73, 0x3E: 74,
            // PC keyboards report PrtSc / ScrLk / Pause as F13 / F14 / F15 on macOS.
            0x69: 78, 0x6B: 79, 0x71: 80,
            0x72: 81, 0x73: 82, 0x74: 83, 0x75: 84, 0x77: 85, 0x79: 86,
            0x7E: 87, 0x7B: 88, 0x7D: 89, 0x7C: 90,
            0x47: 91, 0x4B: 92, 0x43: 93, 0x59: 94, 0x5B: 95, 0x5C: 96, 0x56: 97,
            0x57: 98, 0x58: 99, 0x53: 100, 0x54: 101, 0x55: 102, 0x52: 103,
            0x41: 104, 0x4E: 105, 0x45: 106, 0x4C: 107, 0x0A: 0xCC,
            0x48: 0x71, 0x49: 0x72, 0x4A: 0x70,
        ]
        t[0x3F] = KeyCodes.fn
        return t
    }()

    static let modifierFlag: [UInt16: NSEvent.ModifierFlags] = [
        0x38: .shift, 0x3C: .shift, 0x3B: .control, 0x3E: .control,
        0x3A: .option, 0x3D: .option, 0x37: .command, 0x36: .command, 0x39: .capsLock, 0x3F: .function,
    ]
}

/// Button that, once clicked, turns the next physical key press into a hardware code.
struct KeyCaptureButton: View {
    var title = "Press a key…"
    var onCapture: (UInt8) -> Void
    @State private var listening = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            listening ? stop() : start()
        } label: {
            Label(listening ? "Press a key now…" : title, systemImage: listening ? "keyboard.badge.ellipsis" : "keyboard")
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        listening = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                // Only react to the press of a modifier, not its release.
                guard let flag = MacKeyMap.modifierFlag[event.keyCode], event.modifierFlags.contains(flag) else { return nil }
            }
            if let code = MacKeyMap.table[event.keyCode] {
                onCapture(code)
            }
            stop()
            return nil
        }
    }

    private func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        listening = false
    }
}
