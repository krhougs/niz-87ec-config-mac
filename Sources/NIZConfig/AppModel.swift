import AppKit
import Foundation
import NIZKit
import Observation
import UniformTypeIdentifiers

struct Profile: Codable {
    var firmware: String?
    var keymap: Keymap
    var lighting: [RGB]?
}

enum ConnectionState: Equatable {
    case searching
    case macMode(String)
    case connected(DeviceInfo)
    case failed(String)
}

@Observable
@MainActor
final class AppModel {
    var connection: ConnectionState = .searching
    var firmware = ""
    var keymap = Keymap.factoryDefault
    var deviceKeymap: Keymap?
    var lighting = Array(repeating: RGB.off, count: Keymap.keyCount)
    var deviceLighting: [RGB]?
    var counters: [UInt32]?
    var busy: String?
    var progress: Double?
    var lastError: String?
    var notice: String?

    @ObservationIgnored private var keyboard: NIZKeyboard?
    @ObservationIgnored private let io = DispatchQueue(label: "niz.io")
    @ObservationIgnored private var pollTimer: Timer?

    var isConnected: Bool {
        if case .connected = connection { return true }
        return false
    }

    var keysDirty: Bool {
        guard let device = deviceKeymap else { return false }
        return Array(keymap.layers.prefix(2)) != Array(device.layers.prefix(2))
    }

    var lightingDirty: Bool {
        deviceLighting.map { $0 != lighting } ?? false
    }

    init() {
        connect()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollConnection() }
        }
    }

    // MARK: - Connection

    func connect() {
        guard busy == nil else { return }
        run("Connecting") { kb in kb.info } done: { _ in self.readAll() }
    }

    private func pollConnection() {
        guard busy == nil else { return }
        let found = HIDLink.scan()
        switch connection {
        case .connected(let info):
            if !found.contains(where: { !$0.isMacMode && $0.serial == info.serial }) {
                keyboard = nil
                connection = found.first.map { $0.isMacMode ? .macMode($0.product) : .searching } ?? .searching
            }
        default:
            if let d = found.first {
                if d.isMacMode {
                    connection = .macMode(d.product)
                } else {
                    connect()
                }
            } else {
                connection = .searching
            }
        }
    }

    // MARK: - Device operations

    func readAll() {
        run("Reading keyboard") { kb in
            let version = try kb.firmwareVersion()
            let map = try kb.readKeymap { n in self.report(Double(n) / Double(Keymap.keyCount * 6)) }
            let light = try kb.readLighting()
            let counts = try kb.readCounters()
            return (version, map, light, counts)
        } done: { (result: (String, Keymap, [RGB], [UInt32])) in
            self.firmware = result.0
            self.deviceKeymap = result.1
            self.keymap = result.1
            self.deviceLighting = result.2
            self.lighting = result.2
            self.counters = result.3
        }
    }

    func readCounters() {
        run("Reading counters") { kb in try kb.readCounters() } done: { self.counters = $0 }
    }

    /// Warnings shown before a write that could lock the user out of Fn.
    var pendingWriteWarnings: [String] = []

    func requestWriteKeys() {
        let warnings = keymap.safetyWarnings
        if warnings.isEmpty {
            writeKeys()
        } else {
            pendingWriteWarnings = warnings
        }
    }

    func writeKeys() {
        pendingWriteWarnings = []
        // Base/Fn are mirrored into layers 3-6 like the factory layout; the firmware
        // leaves any layer it isn't sent empty.
        let map = keymap.withMirroredExtraLayers()
        run("Writing keys") { kb in
            try kb.writeKeymap(map) { n in self.report(Double(n) / Double(Keymap.keyCount * Keymap.firmwareLayerCount)) }
            Thread.sleep(forTimeInterval: 0.3)
            return try kb.readKeymap()
        } done: { (readBack: Keymap) in
            self.deviceKeymap = map
            self.keymap = map
            if readBack == map {
                self.notice = "Keys written and verified."
            } else {
                self.notice = "Keys written to the programmable layout. The keyboard is on its factory layout right now: press Fn + Pause to switch."
            }
        }
    }

    func writeLighting() {
        let colors = lighting
        run("Writing lighting") { kb in
            try kb.writeLighting(colors)
            Thread.sleep(forTimeInterval: 0.2)
            return try kb.readLighting()
        } done: { (readBack: [RGB]) in
            self.deviceLighting = readBack
            if readBack == colors {
                self.notice = "Lighting written and verified."
            } else {
                self.lastError = "Lighting was written, but reading it back gave different values."
            }
        }
    }

    func revertKeys() {
        if let d = deviceKeymap { keymap = d }
    }

    func revertLighting() {
        if let d = deviceLighting { lighting = d }
    }

    func loadFactoryKeys() {
        var map = Keymap.factoryDefault
        // Keep any extra layers the firmware reported so the layer count stays stable.
        if keymap.layers.count > 2 { map.layers += keymap.layers[2...] }
        keymap = map
    }

    // MARK: - Profiles

    func saveProfile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "NIZ profile.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(Profile(firmware: firmware, keymap: keymap, lighting: lighting)).write(to: url)
            notice = "Saved \(url.lastPathComponent)."
        } catch {
            lastError = error.localizedDescription
        }
    }

    func openProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let p = try JSONDecoder().decode(Profile.self, from: Data(contentsOf: url))
            guard p.keymap.layers.allSatisfy({ $0.count == Keymap.keyCount }), p.keymap.layers.count >= 2 else {
                throw NIZError.protocolError("profile has the wrong number of keys")
            }
            keymap = p.keymap
            if let l = p.lighting, l.count == Keymap.keyCount { lighting = l }
            notice = "Loaded \(url.lastPathComponent). Write it to the keyboard to apply."
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Plumbing

    nonisolated private func report(_ fraction: Double) {
        Task { @MainActor in self.progress = min(1, fraction) }
    }

    private func run<T>(_ label: String,
                        _ work: @escaping (NIZKeyboard) throws -> T,
                        done: ((T) -> Void)? = nil) {
        busy = label
        progress = nil
        lastError = nil
        notice = nil
        let existing = keyboard
        io.async {
            let result: Result<(NIZKeyboard, T), Error> = Result {
                let kb = try existing ?? NIZKeyboard()
                return (kb, try work(kb))
            }
            Task { @MainActor in
                self.busy = nil
                self.progress = nil
                switch result {
                case .success(let (kb, value)):
                    self.keyboard = kb
                    self.connection = .connected(kb.info)
                    done?(value)
                case .failure(let error):
                    if case NIZError.macMode(let name) = error {
                        self.keyboard = nil
                        self.connection = .macMode(name)
                    } else if case NIZError.notFound = error {
                        self.keyboard = nil
                        self.connection = .searching
                    } else {
                        if existing == nil { self.keyboard = nil }
                        self.lastError = error.localizedDescription
                        if !self.isConnected { self.connection = .failed(error.localizedDescription) }
                    }
                }
            }
        }
    }
}
