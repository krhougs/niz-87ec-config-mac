import Foundation
import IOKit.hid

public enum NIZError: Error, LocalizedError {
    case notFound
    case macMode(String)
    case openFailed(IOReturn)
    case sendFailed(IOReturn)
    case timeout(String)
    case protocolError(String)

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "No NIZ keyboard found. Plug it in via USB."
        case .macMode(let name):
            return "\(name) is in Mac mode, which hides the configuration interface. Press Fn + Left Alt, then unplug and replug the USB cable."
        case .openFailed(let r):
            return String(format: "Could not open the keyboard (IOReturn 0x%08x).", r)
        case .sendFailed(let r):
            return String(format: "Sending to the keyboard failed (IOReturn 0x%08x).", r)
        case .timeout(let what):
            return "The keyboard did not answer in time (\(what))."
        case .protocolError(let msg):
            return "Unexpected data from the keyboard: \(msg)"
        }
    }
}

/// A USB HID device the scanner recognised as a NIZ keyboard.
public struct DeviceInfo: Equatable, Sendable {
    public var vendorID: Int
    public var productID: Int
    public var product: String
    public var serial: String
    /// True when the keyboard enumerated in Mac mode (Apple VID, no config interface).
    public var isMacMode: Bool
}

/// Raw 64-byte report channel to the keyboard's vendor HID interface
/// (USB interface 1, usage page 0x8C, no report IDs).
public final class HIDLink {
    public static let configVendorID = 0x0483
    /// PIDs the Windows tool accepts (one per X87EC variant).
    public static let configProductIDs: Set<Int> = [0x5031, 0x5131, 0x5231, 0x5331]
    public static let configUsagePage = 0x8C
    public static let reportSize = 64

    public let info: DeviceInfo
    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: HIDLink.reportSize)
    private let cond = NSCondition()
    private var pending: [[UInt8]] = []
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var stopping = false

    /// Finds keyboards in either mode, config-capable ones first.
    public static func scan() -> [DeviceInfo] {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(mgr, [
            [kIOHIDVendorIDKey: configVendorID, kIOHIDPrimaryUsagePageKey: configUsagePage],
            [kIOHIDVendorIDKey: 0x05AC],
        ] as CFArray)
        guard let set = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice> else { return [] }
        var found: [DeviceInfo] = []
        for dev in set {
            let info = describe(dev)
            if info.vendorID == configVendorID && configProductIDs.contains(info.productID) {
                found.append(info)
            } else if info.vendorID == 0x05AC && looksLikeNIZ(dev) {
                found.append(info)
            }
        }
        var seen = Set<String>()
        return found
            .sorted { !$0.isMacMode && $1.isMacMode }
            .filter { seen.insert("\($0.vendorID):\($0.productID):\($0.serial)").inserted }
    }

    public init() throws {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: HIDLink.configVendorID,
            kIOHIDPrimaryUsagePageKey: HIDLink.configUsagePage,
        ] as CFDictionary)
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        guard let dev = devices.first(where: { HIDLink.configProductIDs.contains(HIDLink.intProp($0, kIOHIDProductIDKey)) }) else {
            if let mac = HIDLink.scan().first(where: { $0.isMacMode }) {
                throw NIZError.macMode(mac.product)
            }
            throw NIZError.notFound
        }
        device = dev
        info = HIDLink.describe(dev)
        let r = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else { throw NIZError.openFailed(r) }
        startReader()
    }

    deinit {
        stopping = true
        if let rl = runLoop { CFRunLoopStop(rl) }
        while thread?.isExecuting == true { usleep(1000) }
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        inputBuffer.deallocate()
    }

    /// Sends one 64-byte output report (shorter payloads are zero-padded).
    public func send(_ payload: [UInt8]) throws {
        var buf = payload
        buf += [UInt8](repeating: 0, count: max(0, HIDLink.reportSize - buf.count))
        let r = buf.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, $0.baseAddress!, HIDLink.reportSize)
        }
        guard r == kIOReturnSuccess else { throw NIZError.sendFailed(r) }
    }

    /// Waits for the next input report.
    public func receive(timeout: TimeInterval) -> [UInt8]? {
        let deadline = Date().addingTimeInterval(timeout)
        cond.lock()
        defer { cond.unlock() }
        while pending.isEmpty {
            if !cond.wait(until: deadline) { return nil }
        }
        return pending.removeFirst()
    }

    /// Discards reports left over from an earlier exchange.
    public func drain() {
        cond.lock()
        pending.removeAll()
        cond.unlock()
    }

    // MARK: - Private

    private func startReader() {
        let ready = DispatchSemaphore(value: 0)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let t = Thread { [device, inputBuffer] in
            self.runLoop = CFRunLoopGetCurrent()
            IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, HIDLink.reportSize, { ctx, _, _, _, _, report, length in
                guard let ctx else { return }
                let link = Unmanaged<HIDLink>.fromOpaque(ctx).takeUnretainedValue()
                link.enqueue(Array(UnsafeBufferPointer(start: report, count: length)))
            }, context)
            IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            ready.signal()
            while !self.stopping {
                CFRunLoopRunInMode(.defaultMode, 0.25, false)
            }
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
        t.name = "NIZ HID reader"
        thread = t
        t.start()
        ready.wait()
    }

    private func enqueue(_ report: [UInt8]) {
        cond.lock()
        pending.append(report)
        cond.signal()
        cond.unlock()
    }

    private static func describe(_ dev: IOHIDDevice) -> DeviceInfo {
        let vid = intProp(dev, kIOHIDVendorIDKey)
        return DeviceInfo(
            vendorID: vid,
            productID: intProp(dev, kIOHIDProductIDKey),
            product: stringProp(dev, kIOHIDProductKey) ?? "NIZ keyboard",
            serial: stringProp(dev, kIOHIDSerialNumberKey) ?? "",
            isMacMode: vid == 0x05AC
        )
    }

    private static func looksLikeNIZ(_ dev: IOHIDDevice) -> Bool {
        let product = stringProp(dev, kIOHIDProductKey) ?? ""
        let maker = stringProp(dev, kIOHIDManufacturerKey) ?? ""
        return product.hasPrefix("X87") || maker.localizedCaseInsensitiveContains("milsky")
            || maker.localizedCaseInsensitiveContains("niz")
    }

    private static func intProp(_ dev: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(dev, key as CFString) as? NSNumber)?.intValue ?? 0
    }

    private static func stringProp(_ dev: IOHIDDevice, _ key: String) -> String? {
        IOHIDDeviceGetProperty(dev, key as CFString) as? String
    }
}
