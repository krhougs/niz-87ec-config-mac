import Foundation

/// Something that moves 64-byte reports to and from the keyboard.
public protocol ReportChannel: AnyObject {
    func send(_ payload: [UInt8]) throws
    func receive(timeout: TimeInterval) -> [UInt8]?
    func drain()
}

extension HIDLink: ReportChannel {}

/// High-level operations on a connected keyboard. Calls block; run them off the main thread.
public final class NIZKeyboard {
    public let link: ReportChannel
    public let info: DeviceInfo

    /// Per-packet wait while the keyboard streams data back.
    public var replyTimeout: TimeInterval = 2.0
    /// Pause between packets the host sends.
    public var packetGap: TimeInterval = 0.004

    public convenience init() throws {
        let hid = try HIDLink()
        self.init(channel: hid, info: hid.info)
    }

    public init(channel: ReportChannel, info: DeviceInfo) {
        link = channel
        self.info = info
    }

    /// Firmware identification, e.g. "X87EC(S)BLe;V1.3.1;V1.0;".
    public func firmwareVersion() throws -> String {
        link.drain()
        try link.send(NIZProtocol.command(NIZProtocol.version))
        guard let p = link.receive(timeout: replyTimeout) else { throw NIZError.timeout("version") }
        guard p.count > 2, p[1] == NIZProtocol.version else {
            throw NIZError.protocolError("bad version reply")
        }
        let bytes = p[2...].prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Reads every layer the firmware reports. `progress` gets the count of records received.
    public func readKeymap(progress: ((Int) -> Void)? = nil) throws -> Keymap {
        link.drain()
        try link.send(NIZProtocol.command(NIZProtocol.readKeys))
        var layers: [Int: [KeyAction]] = [:]
        var count = 0
        while true {
            guard let p = link.receive(timeout: replyTimeout) else { throw NIZError.timeout("reading keys") }
            if p[0] == NIZProtocol.keysEnd { break }
            guard p[1] == NIZProtocol.keyRecord else { continue }
            var packets = [p]
            for _ in 1..<NIZProtocol.recordLength(first: p) {
                guard let q = link.receive(timeout: replyTimeout) else { throw NIZError.timeout("reading macro") }
                packets.append(q)
            }
            let (layer, key, action) = try NIZProtocol.decode(record: packets)
            guard layer >= 1, (1...Keymap.keyCount).contains(key) else { continue }
            layers[layer, default: Array(repeating: .none, count: Keymap.keyCount)][key - 1] = action
            count += 1
            progress?(count)
        }
        let maxLayer = max(2, layers.keys.max() ?? 0)
        return Keymap(layers: (1...maxLayer).map { layers[$0] ?? Array(repeating: .none, count: Keymap.keyCount) })
    }

    /// Writes the keymap into the keyboard's programmable bank (Fn + Pause switches to it).
    ///
    /// Layers the firmware is not sent are left empty, so by default this writes
    /// `Keymap.firmwareLayerCount` layers, mirroring base/Fn into any missing ones.
    /// (The Windows tool only writes 2, which blanks layers 3-6.)
    public func writeKeymap(_ map: Keymap, layerCount: Int = Keymap.firmwareLayerCount, progress: ((Int) -> Void)? = nil) throws {
        let map = map.mirrored(toLayers: layerCount)
        let n = layerCount
        link.drain()
        try link.send(NIZProtocol.command(NIZProtocol.writeKeys))
        var done = 0
        for layer in 0..<n {
            for key in 0..<Keymap.keyCount {
                for packet in NIZProtocol.encode(layer: layer + 1, key: key + 1, action: map.layers[layer][key]) {
                    try link.send(packet)
                    // A short pause keeps the firmware from dropping reports while it saves.
                    Thread.sleep(forTimeInterval: packetGap)
                }
                done += 1
                progress?(done)
            }
        }
        try link.send(NIZProtocol.keysEndPacket)
    }

    /// Per-key backlight colours (87 entries, position order).
    public func readLighting() throws -> [RGB] {
        let bytes = try readBlock(command: NIZProtocol.readLight, marker: NIZProtocol.lightRecord, what: "reading lighting")
        guard bytes.count >= Keymap.keyCount * 3 else {
            throw NIZError.protocolError("lighting block is \(bytes.count) bytes")
        }
        return (0..<Keymap.keyCount).map { RGB(r: bytes[$0 * 3], g: bytes[$0 * 3 + 1], b: bytes[$0 * 3 + 2]) }
    }

    public func writeLighting(_ colors: [RGB]) throws {
        precondition(colors.count == Keymap.keyCount)
        let bytes = colors.flatMap { [$0.r, $0.g, $0.b] }
        link.drain()
        try link.send(NIZProtocol.command(NIZProtocol.writeLight))
        for p in NIZProtocol.encodeLighting(bytes) {
            try link.send(p)
            Thread.sleep(forTimeInterval: packetGap)
        }
        try link.send(NIZProtocol.lightEndPacket)
    }

    /// Lifetime keystroke counters per key position.
    public func readCounters() throws -> [UInt32] {
        let bytes = try readBlock(command: NIZProtocol.readCounters, marker: NIZProtocol.counterRecord, what: "reading counters")
        return (0..<Keymap.keyCount).map { i in
            guard bytes.count >= i * 4 + 4 else { return 0 }
            return UInt32(bytes[i * 4]) | UInt32(bytes[i * 4 + 1]) << 8 | UInt32(bytes[i * 4 + 2]) << 16 | UInt32(bytes[i * 4 + 3]) << 24
        }
    }

    /// Sends `command`, then collects `[0x00, marker, len, data...]` packets until 0xE6.
    private func readBlock(command: UInt8, marker: UInt8, what: String) throws -> [UInt8] {
        link.drain()
        try link.send(NIZProtocol.command(command))
        var bytes: [UInt8] = []
        while true {
            guard let p = link.receive(timeout: replyTimeout) else { throw NIZError.timeout(what) }
            if p[0] == NIZProtocol.dataEnd || p[1] == NIZProtocol.dataEnd { break }
            guard p[1] == marker else { continue }
            let n = min(Int(p[2]), p.count - 3)
            bytes += p[3..<(3 + n)]
        }
        return bytes
    }
}

// Instances are confined to one serial queue by callers; the reader thread only
// touches HIDLink's lock-protected queue.
extension NIZKeyboard: @unchecked Sendable {}
extension HIDLink: @unchecked Sendable {}
