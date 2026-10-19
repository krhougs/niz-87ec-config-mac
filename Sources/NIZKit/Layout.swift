import Foundation

/// Physical layout of the 87-key board. Key positions are the 1-based indices the
/// firmware uses in key records, lighting and counters.
public enum Layout {
    public struct Key: Identifiable, Hashable {
        public let position: Int
        /// Left edge and top edge in key units (1u = one alpha key).
        public let x: Double
        public let y: Double
        public let width: Double
        public var id: Int { position }
    }

    public static let width = 18.25
    public static let height = 6.5

    public static let keys: [Key] = build()

    /// Hardware code a position sends on the base layer of a stock keyboard.
    public static func defaultCode(forPosition pos: Int) -> UInt8 {
        switch pos {
        case 72: return KeyCodes.fn
        case 75...87: return UInt8(pos + 3) // PrtSc ... Right arrow
        default: return UInt8(pos)
        }
    }

    /// Fn layer of a stock X87EC(S) (from the Windows tool's default table).
    public static let defaultFnLayer: [Int: UInt8] = [
        1: 0x96, 10: 0x97, 11: 0x87, 14: 0x88, 15: 0x94, 16: 0x8A, 17: 0x89, 18: 0x8B,
        25: 0x8E, 26: 0x8F, 67: 0x98, 68: 0x99, 69: 0x9B, 72: 0x9C, 77: 0x9F, 78: 0xA7,
        81: 0xA8, 82: 0xA9, 83: 0xAA, 84: 0x91, 85: 0x92, 86: 0x90, 87: 0x93,
    ]

    public static func key(at position: Int) -> Key? {
        keys.first { $0.position == position }
    }

    private static func build() -> [Key] {
        var out: [Key] = []
        func row(_ y: Double, _ start: Int, _ items: [(x: Double, w: Double)]) {
            for (i, k) in items.enumerated() {
                out.append(Key(position: start + i, x: k.x, y: y, width: k.w))
            }
        }
        func run(_ x: Double, _ n: Int, _ w: Double = 1) -> [(x: Double, w: Double)] {
            (0..<n).map { (x + Double($0) * w, w) }
        }
        // Function row: Esc, F1-F12
        row(0, 1, [(0, 1)] + run(2, 4) + run(6.5, 4) + run(11, 4))
        // Number row: ` 1-0 - = Backspace
        row(1.5, 14, run(0, 13) + [(13, 2)])
        // Tab row
        row(2.5, 28, [(0, 1.5)] + run(1.5, 12) + [(13.5, 1.5)])
        // Caps row
        row(3.5, 42, [(0, 1.75)] + run(1.75, 11) + [(12.75, 2.25)])
        // Shift row
        row(4.5, 55, [(0, 2.25)] + run(2.25, 10) + [(12.25, 2.75)])
        // Bottom row: Ctrl Win Alt Space Alt Fn Menu Ctrl
        row(5.5, 67, run(0, 3, 1.25) + [(3.75, 6.25)] + run(10, 4, 1.25))
        // Navigation cluster
        row(0, 75, run(15.25, 3))
        row(1.5, 78, run(15.25, 3))
        row(2.5, 81, run(15.25, 3))
        row(4.5, 84, [(16.25, 1)])
        row(5.5, 85, run(15.25, 3))
        return out.sorted { $0.position < $1.position }
    }
}
