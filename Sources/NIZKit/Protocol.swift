import Foundation

/// Packet layout of the NIZ X87EC configuration protocol.
///
/// Every report is 64 bytes. Host commands are `[0x00, cmd, 0...]`; data records
/// carry `0x00, marker` in the first two bytes. See PROTOCOL.md for details.
public enum NIZProtocol {
    public static let keyRecord: UInt8 = 0xF0
    public static let writeKeys: UInt8 = 0xF1
    public static let readKeys: UInt8 = 0xF2
    public static let keysEnd: UInt8 = 0xF6
    public static let version: UInt8 = 0xF9
    public static let lightRecord: UInt8 = 0xE0
    public static let writeLight: UInt8 = 0xE1
    public static let readLight: UInt8 = 0xE2
    public static let counterRecord: UInt8 = 0xE3
    public static let readCounters: UInt8 = 0xE3
    public static let dataEnd: UInt8 = 0xE6

    static let macroHeaderSize = 11
    static let macroChunk = 64 - macroHeaderSize
    static let lightChunk = 61

    public static func command(_ cmd: UInt8) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: 64)
        p[1] = cmd
        return p
    }

    /// Terminator the host sends after the key records.
    public static var keysEndPacket: [UInt8] {
        [0x00] + [UInt8](repeating: keysEnd, count: 63)
    }

    public static var lightEndPacket: [UInt8] {
        [UInt8](repeating: dataEnd, count: 64)
    }

    // MARK: - Key records

    /// Encodes one key's action as one or more 64-byte records (layer and key are 1-based).
    public static func encode(layer: Int, key: Int, action: KeyAction) -> [[UInt8]] {
        var p = [UInt8](repeating: 0, count: 64)
        p[1] = keyRecord
        p[2] = UInt8(layer)
        p[3] = UInt8(key)
        switch action {
        case .none:
            return [p]
        case .keys(let codes):
            let codes = codes.prefix(58)
            p[4] = 0
            p[5] = UInt8(codes.count)
            p.replaceSubrange(6..<(6 + codes.count), with: codes)
            return [p]
        case .repeating(let interval, let codes):
            let codes = codes.prefix(56)
            p[4] = 1
            p[5] = UInt8(interval >> 8)
            p[6] = UInt8(interval & 0xFF)
            p[7] = UInt8(codes.count)
            p.replaceSubrange(8..<(8 + codes.count), with: codes)
            return [p]
        case .macro(let m):
            guard !m.steps.isEmpty else { return [p] }
            var data: [UInt8] = []
            for s in m.steps {
                if m.perStepDelays {
                    data += [s.code, s.flag, UInt8(s.delay >> 8), UInt8(s.delay & 0xFF)]
                } else {
                    data.append(s.code)
                }
            }
            let size = min(data.count, 0xFFFF)
            p[4] = macroType(m.mode)
            p[5] = m.cycles
            p[6] = m.perStepDelays ? 1 : 0
            p[7] = UInt8(m.autoDelay >> 8)
            p[8] = UInt8(m.autoDelay & 0xFF)
            p[9] = UInt8(size >> 8)
            p[10] = UInt8(size & 0xFF)
            var out: [[UInt8]] = []
            var offset = 0
            while offset < size {
                let n = min(macroChunk, size - offset)
                var q = p
                q.replaceSubrange(macroHeaderSize..<(macroHeaderSize + n), with: data[offset..<(offset + n)])
                out.append(q)
                offset += n
            }
            return out
        }
    }

    /// How many packets a record that starts with `first` spans.
    public static func recordLength(first p: [UInt8]) -> Int {
        guard p.count >= 11, (2...4).contains(p[4]) else { return 1 }
        let size = Int(p[9]) << 8 | Int(p[10])
        return max(1, (size + macroChunk - 1) / macroChunk)
    }

    /// Decodes a complete record (all of its packets). Returns 1-based layer and key.
    public static func decode(record packets: [[UInt8]]) throws -> (layer: Int, key: Int, action: KeyAction) {
        guard let p = packets.first, p.count >= 8, p[1] == keyRecord else {
            throw NIZError.protocolError("not a key record")
        }
        let layer = Int(p[2]), key = Int(p[3])
        switch p[4] {
        case 0:
            let n = min(Int(p[5]), p.count - 6)
            return (layer, key, n == 0 ? .none : .keys(Array(p[6..<(6 + n)])))
        case 1:
            let interval = UInt16(p[5]) << 8 | UInt16(p[6])
            let n = min(Int(p[7]), p.count - 8)
            return (layer, key, .repeating(interval: interval, keys: Array(p[8..<(8 + n)])))
        case 2, 3, 4:
            let mode: Macro.Mode = p[4] == 2 ? .times : p[4] == 3 ? .whileHeld : .toggle
            let size = Int(p[9]) << 8 | Int(p[10])
            var data: [UInt8] = []
            for q in packets where q.count > macroHeaderSize {
                data += q[macroHeaderSize..<min(q.count, 64)]
            }
            data = Array(data.prefix(size))
            let perStep = p[6] != 0
            var steps: [Macro.Step] = []
            if perStep {
                var i = 0
                while i < data.count {
                    let delay = i + 3 < data.count ? UInt16(data[i + 2]) << 8 | UInt16(data[i + 3]) : 0
                    let flag = i + 1 < data.count ? data[i + 1] : 0xC8
                    steps.append(.init(code: data[i], delay: delay, flag: flag))
                    i += 4
                }
            } else {
                steps = data.map { .init(code: $0, delay: 0) }
            }
            let m = Macro(mode: mode, cycles: p[5], perStepDelays: perStep,
                          autoDelay: UInt16(p[7]) << 8 | UInt16(p[8]), steps: steps)
            return (layer, key, .macro(m))
        default:
            throw NIZError.protocolError(String(format: "unknown key type 0x%02x", p[4]))
        }
    }

    static func macroType(_ mode: Macro.Mode) -> UInt8 {
        switch mode {
        case .times: return 2
        case .whileHeld: return 3
        case .toggle: return 4
        }
    }

    // MARK: - Lighting

    /// 87 keys x RGB = 261 bytes, sent in 61-byte chunks.
    public static func encodeLighting(_ bytes: [UInt8]) -> [[UInt8]] {
        var out: [[UInt8]] = []
        var offset = 0
        while offset < bytes.count {
            let n = min(lightChunk, bytes.count - offset)
            var p = [UInt8](repeating: 0, count: 64)
            p[1] = lightRecord
            p[2] = UInt8(n)
            p.replaceSubrange(3..<(3 + n), with: bytes[offset..<(offset + n)])
            out.append(p)
            offset += n
        }
        return out
    }
}

public struct RGB: Equatable, Hashable, Codable, Sendable {
    public var r: UInt8, g: UInt8, b: UInt8
    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }
    public static let off = RGB(r: 0, g: 0, b: 0)
}
