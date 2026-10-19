import Foundation

/// What one key position does on one layer.
public enum KeyAction: Equatable, Hashable, Sendable {
    /// Unassigned (record type 0 with no codes).
    case none
    /// A single key or a chord of keys pressed together (record type 0).
    case keys([UInt8])
    /// "Emulate": re-sends the keys every `interval` ms while held (record type 1).
    case repeating(interval: UInt16, keys: [UInt8])
    /// A recorded key sequence (record types 2, 3, 4).
    case macro(Macro)

    public var codes: [UInt8] {
        switch self {
        case .none: return []
        case .keys(let k), .repeating(_, let k): return k
        case .macro(let m): return m.steps.map(\.code)
        }
    }
}

public struct Macro: Equatable, Hashable, Codable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Hashable, Sendable {
        /// Plays `cycles` times per press (record type 2).
        case times
        /// Plays while the key is held, stops on release (record type 3).
        case whileHeld
        /// First press starts looping, second press stops (record type 4).
        case toggle
    }

    public struct Step: Equatable, Hashable, Codable, Sendable {
        public var code: UInt8
        /// Delay after this step in ms (only used when `perStepDelays`).
        public var delay: UInt16
        /// Unknown per-step byte; the Windows tool always writes 0xC8.
        public var flag: UInt8

        public init(code: UInt8, delay: UInt16 = 50, flag: UInt8 = 0xC8) {
            self.code = code
            self.delay = delay
            self.flag = flag
        }
    }

    public var mode: Mode
    public var cycles: UInt8
    /// When false the keyboard waits `autoDelay` ms between every step.
    public var perStepDelays: Bool
    public var autoDelay: UInt16
    public var steps: [Step]

    public init(mode: Mode = .times, cycles: UInt8 = 1, perStepDelays: Bool = false, autoDelay: UInt16 = 30, steps: [Step] = []) {
        self.mode = mode
        self.cycles = cycles
        self.perStepDelays = perStepDelays
        self.autoDelay = autoDelay
        self.steps = steps
    }
}

extension KeyAction: Codable {
    private enum CodingKeys: String, CodingKey { case type, keys, interval, macro }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "none": self = .none
        case "keys": self = .keys(try c.decode([UInt8].self, forKey: .keys))
        case "repeating":
            self = .repeating(interval: try c.decode(UInt16.self, forKey: .interval),
                              keys: try c.decode([UInt8].self, forKey: .keys))
        case "macro": self = .macro(try c.decode(Macro.self, forKey: .macro))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown action type \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try c.encode("none", forKey: .type)
        case .keys(let k):
            try c.encode("keys", forKey: .type)
            try c.encode(k, forKey: .keys)
        case .repeating(let interval, let k):
            try c.encode("repeating", forKey: .type)
            try c.encode(interval, forKey: .interval)
            try c.encode(k, forKey: .keys)
        case .macro(let m):
            try c.encode("macro", forKey: .type)
            try c.encode(m, forKey: .macro)
        }
    }
}

/// The full key table. `layers[0]` is the base layer, `layers[1]` the Fn layer;
/// the X87EC(S) firmware also reports four more layers (copies of the first two
/// on a stock keyboard).
public struct Keymap: Equatable, Codable, Sendable {
    public static let keyCount = 87
    /// Layers the X87EC(S) firmware stores: three base/Fn pairs.
    public static let firmwareLayerCount = 6
    public var layers: [[KeyAction]]

    public init(layers: [[KeyAction]]) {
        self.layers = layers
    }

    public init(layerCount: Int = 2) {
        layers = Array(repeating: Array(repeating: .none, count: Keymap.keyCount), count: layerCount)
    }

    /// Pads to `count` layers by repeating the base/Fn pair, as the factory layout does.
    public func mirrored(toLayers count: Int) -> Keymap {
        var out = self
        while out.layers.count < count {
            out.layers.append(layers[out.layers.count % 2])
        }
        out.layers = Array(out.layers.prefix(count))
        return out
    }

    /// Same keymap with layers 3+ replaced by copies of base/Fn.
    public func withMirroredExtraLayers() -> Keymap {
        Keymap(layers: Array(layers.prefix(2))).mirrored(toLayers: max(layers.count, Keymap.firmwareLayerCount))
    }

    /// Problems that could leave the keyboard hard to use after writing.
    public var safetyWarnings: [String] {
        var out: [String] = []
        let fnBoth = (0..<Keymap.keyCount).contains { layers[0][$0] == .keys([KeyCodes.fn]) && layers[1][$0] == .keys([KeyCodes.fn]) }
        if !fnBoth {
            out.append("No key is Fn on both the base and Fn layer, so the Fn layer (and Fn + Pause to get back to the factory layout) would be unreachable.")
        }
        if !layers[1].contains(.keys([0x9F])) {
            out.append("The Fn layer has no \"Programmable Keyboard\" key, so you could not switch back to the factory layout from the keyboard.")
        }
        return out
    }

    /// Factory layout of the X87EC(S)/RGB (taken from the Windows tool's table).
    public static var factoryDefault: Keymap {
        var map = Keymap(layerCount: 2)
        for pos in 1...keyCount {
            map.layers[0][pos - 1] = .keys([Layout.defaultCode(forPosition: pos)])
        }
        for (pos, code) in Layout.defaultFnLayer {
            map.layers[1][pos - 1] = .keys([code])
        }
        return map
    }
}
