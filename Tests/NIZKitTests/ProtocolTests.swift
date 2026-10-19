import XCTest
@testable import NIZKit

/// Replays captured reports and records what the host sent.
final class ScriptedChannel: ReportChannel {
    var replies: [[UInt8]]
    var sent: [[UInt8]] = []

    init(replies: [[UInt8]]) { self.replies = replies }

    func send(_ payload: [UInt8]) throws { sent.append(payload) }
    func receive(timeout: TimeInterval) -> [UInt8]? { replies.isEmpty ? nil : replies.removeFirst() }
    func drain() {}
}

func fixture(_ name: String) throws -> [[UInt8]] {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "hex"))
    return try String(contentsOf: url, encoding: .utf8)
        .split(separator: "\n")
        .map { line in
            var bytes: [UInt8] = []
            var i = line.startIndex
            while i < line.endIndex {
                let j = line.index(i, offsetBy: 2)
                bytes.append(UInt8(line[i..<j], radix: 16)!)
                i = j
            }
            return bytes
        }
}

let info = DeviceInfo(vendorID: 0x0483, productID: 0x5131, product: "X87EC-RGB", serial: "test", isMacMode: false)

final class ProtocolTests: XCTestCase {
    func testReadsCapturedKeymap() throws {
        let kb = NIZKeyboard(channel: ScriptedChannel(replies: try fixture("keymap-read")), info: info)
        let map = try kb.readKeymap()
        XCTAssertEqual(map.layers.count, 6)
        XCTAssertEqual(map.layers[0][0], .keys([1]))          // Esc
        XCTAssertEqual(map.layers[0][71], .keys([KeyCodes.fn])) // Fn in the right-Win slot
        XCTAssertEqual(map.layers[0][86], .keys([0x5A]))      // Right arrow
        XCTAssertEqual(map.layers[1][68], .keys([0x9B]))      // Fn+LAlt = Win/Mac
        XCTAssertEqual(map.layers[1][1], .none)
        XCTAssertEqual(map.layers[2], map.layers[0])
    }

    func testEncoderReproducesDevicePacketsExactly() throws {
        for packet in try fixture("keymap-read") where packet[1] == NIZProtocol.keyRecord {
            let (layer, key, action) = try NIZProtocol.decode(record: [packet])
            XCTAssertEqual(NIZProtocol.encode(layer: layer, key: key, action: action), [packet],
                           "layer \(layer) key \(key)")
        }
    }

    func testWriteSequenceMirrorsAllSixLayers() throws {
        let channel = ScriptedChannel(replies: [])
        let kb = NIZKeyboard(channel: channel, info: info)
        kb.packetGap = 0
        try kb.writeKeymap(.factoryDefault)
        XCTAssertEqual(channel.sent.first, NIZProtocol.command(0xF1))
        XCTAssertEqual(channel.sent.count, 1 + 87 * 6 + 1)
        // Layer 5 repeats the base layer, layer 6 the Fn layer.
        XCTAssertEqual(Array(channel.sent[1 + 87 * 4][4...]), Array(channel.sent[1][4...]))
        XCTAssertEqual(Array(channel.sent[1 + 87 * 5][4...]), Array(channel.sent[1 + 87][4...]))
        XCTAssertEqual(channel.sent.last, [0x00] + Array(repeating: 0xF6, count: 63))
        // Unassigned keys go out as an empty type-0 record.
        XCTAssertEqual(channel.sent[1 + 87 + 1], [0x00, 0xF0, 2, 2] + Array(repeating: 0, count: 60))
        XCTAssertTrue(channel.sent.allSatisfy { $0.count == 64 })
    }

    func testRoundTripsEveryActionKind() throws {
        let actions: [KeyAction] = [
            .none,
            .keys([67, 58]),
            .repeating(interval: 300, keys: [43, 44]),
            .macro(Macro(mode: .times, cycles: 3, perStepDelays: false, autoDelay: 20, steps: [29, 30, 31].map { .init(code: $0, delay: 0) })),
            .macro(Macro(mode: .toggle, cycles: 1, perStepDelays: true, autoDelay: 0,
                         steps: (0..<40).map { .init(code: UInt8(29 + $0 % 10), delay: UInt16($0 * 37)) })),
        ]
        for action in actions {
            let packets = NIZProtocol.encode(layer: 2, key: 33, action: action)
            XCTAssertEqual(NIZProtocol.recordLength(first: packets[0]), packets.count)
            let (layer, key, decoded) = try NIZProtocol.decode(record: packets)
            XCTAssertEqual(layer, 2)
            XCTAssertEqual(key, 33)
            XCTAssertEqual(decoded, action)
        }
    }

    func testMacroSpansPacketsIn53ByteChunks() {
        let steps = Array(repeating: Macro.Step(code: 43, delay: 100), count: 30) // 120 bytes of step data
        let packets = NIZProtocol.encode(layer: 1, key: 5, action: .macro(Macro(perStepDelays: true, steps: steps)))
        XCTAssertEqual(packets.count, 3)
        for p in packets {
            XCTAssertEqual(Array(p[0..<11]), [0, 0xF0, 1, 5, 2, 1, 1, 0, 30, 0, 120])
        }
        XCTAssertEqual(Array(packets[0][11..<15]), [43, 0xC8, 0, 100])
    }

    func testReadsCapturedLightingAndIgnoresStrayRecords() throws {
        let kb = NIZKeyboard(channel: ScriptedChannel(replies: try fixture("lighting-read")), info: info)
        let colors = try kb.readLighting()
        XCTAssertEqual(colors.count, 87)
        XCTAssertEqual(colors[0], RGB(r: 0xFF, g: 0, b: 0))
        XCTAssertEqual(colors[1], RGB(r: 0xFF, g: 0, b: 0xFF))
    }

    func testLightingWriteChunks() throws {
        let channel = ScriptedChannel(replies: [])
        let kb = NIZKeyboard(channel: channel, info: info)
        kb.packetGap = 0
        try kb.writeLighting(Array(repeating: RGB(r: 1, g: 2, b: 3), count: 87))
        XCTAssertEqual(channel.sent.first, NIZProtocol.command(0xE1))
        XCTAssertEqual(channel.sent.dropFirst().dropLast().map { $0[2] }, [61, 61, 61, 61, 17])
        XCTAssertEqual(channel.sent.last, Array(repeating: 0xE6, count: 64))
    }

    func testSafetyWarnings() {
        XCTAssertEqual(Keymap.factoryDefault.safetyWarnings, [])
        var map = Keymap.factoryDefault
        map.layers[0][71] = .keys([72])
        XCTAssertEqual(map.safetyWarnings.count, 1)
        map.layers[1][76] = .none
        XCTAssertEqual(map.safetyWarnings.count, 2)
    }

    func testLayoutCoversEveryPositionOnce() {
        XCTAssertEqual(Layout.keys.map(\.position), Array(1...87))
        XCTAssertEqual(Layout.defaultCode(forPosition: 75), 78) // PrtSc
        XCTAssertEqual(Layout.defaultCode(forPosition: 87), 90) // Right arrow
    }
}
