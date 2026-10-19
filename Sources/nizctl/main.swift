import Foundation
import NIZKit

let usage = """
usage: nizctl <command>

  info                     show the connected keyboard and firmware version
  keys [layer]             print the key table (all layers, or one 1-based layer)
  counters                 print keystroke counters, most-used first
  lights                   print per-key backlight colours
  backup <file.json>       save keymap + lighting to a JSON profile
  restore <file.json>      write a JSON profile's keymap and lighting
  restore-keys <file.json> write only the keymap
  restore-lights <file.json> write only the lighting

Keymaps are written to the programmable bank; Fn + Pause switches the keyboard
between that and its factory layout. Reads show whichever one is active.
"""

struct Profile: Codable {
    var firmware: String?
    var keymap: Keymap
    var lighting: [RGB]?
}

func describe(_ action: KeyAction) -> String {
    switch action {
    case .none: return "—"
    case .keys(let k): return k.map(KeyCodes.name).joined(separator: " + ")
    case .repeating(let i, let k): return "repeat \(k.map(KeyCodes.name).joined(separator: " + ")) every \(i) ms"
    case .macro(let m): return "macro[\(m.mode.rawValue) x\(m.cycles)] " + m.steps.map { KeyCodes.label($0.code) }.joined(separator: " ")
    }
}

func label(_ pos: Int) -> String {
    KeyCodes.label(Layout.defaultCode(forPosition: pos))
}

func run() throws {
    var args = Array(CommandLine.arguments.dropFirst())
    guard let cmd = args.first else { print(usage); return }
    args.removeFirst()

    let kb = try NIZKeyboard()
    switch cmd {
    case "info":
        let i = kb.info
        print(String(format: "%@  VID %04X PID %04X  serial %@", i.product, i.vendorID, i.productID, i.serial))
        print("firmware:", try kb.firmwareVersion())
    case "keys":
        let map = try kb.readKeymap()
        let only = args.first.flatMap(Int.init)
        for (li, layer) in map.layers.enumerated() where only == nil || only == li + 1 {
            print("== layer \(li + 1)")
            for (ki, action) in layer.enumerated() where action != .none {
                print(String(format: "%3d %-6@ %@", ki + 1, label(ki + 1), describe(action)))
            }
        }
    case "counters":
        let counts = try kb.readCounters()
        let total = counts.reduce(0) { $0 + UInt64($1) }
        print("total keystrokes:", total)
        for (i, c) in counts.enumerated().sorted(by: { $0.element > $1.element }) {
            print(String(format: "%3d %-6@ %10u", i + 1, label(i + 1), c))
        }
    case "lights":
        for (i, c) in try kb.readLighting().enumerated() {
            print(String(format: "%3d %-6@ #%02X%02X%02X", i + 1, label(i + 1), c.r, c.g, c.b))
        }
    case "backup":
        guard let path = args.first else { print(usage); return }
        let profile = Profile(firmware: try kb.firmwareVersion(), keymap: try kb.readKeymap(), lighting: try kb.readLighting())
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(profile).write(to: URL(fileURLWithPath: path))
        print("saved \(profile.keymap.layers.count) layers to \(path)")
    case "restore", "restore-keys", "restore-lights":
        guard let path = args.first else { print(usage); return }
        let profile = try JSONDecoder().decode(Profile.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        if cmd != "restore-lights" {
            for w in profile.keymap.safetyWarnings { print("warning:", w) }
            try kb.writeKeymap(profile.keymap)
            print("wrote keymap (\(Keymap.firmwareLayerCount) layers) to the programmable bank")
        }
        if cmd != "restore-keys", let lighting = profile.lighting {
            try kb.writeLighting(lighting)
            print("wrote lighting")
        }
    default:
        print(usage)
    }
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
