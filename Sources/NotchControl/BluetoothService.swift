import Foundation
import IOBluetooth

/// Connected Bluetooth devices, with battery levels where macOS reports them.
final class BluetoothService: ObservableObject {
    struct Device: Identifiable, Equatable {
        let id: String        // address
        let name: String
        let kind: String      // e.g. "Headphones"
        let battery: Int?     // single level (percent)
        let batteryLeft: Int?
        let batteryRight: Int?
        let batteryCase: Int?

        var batterySummary: String? {
            if let l = batteryLeft, let r = batteryRight {
                var s = "L \(l)% · R \(r)%"
                if let c = batteryCase { s += " · Case \(c)%" }
                return s
            }
            return battery.map { "\($0)%" }
        }
        /// Lowest reported level, if any component reports one.
        var minBattery: Int? {
            [battery, batteryLeft, batteryRight].compactMap { $0 }.min()
        }
        var isLowBattery: Bool { (minBattery ?? 100) < 20 }
        var icon: String {
            let n = name.lowercased() + " " + kind.lowercased()
            if n.contains("airpods max") { return "airpodsmax" }
            if n.contains("airpods pro") { return "airpodspro" }
            if n.contains("airpods") { return "airpods" }
            if n.contains("headphone") { return "headphones" }
            if n.contains("keyboard") { return "keyboard" }
            if n.contains("mouse") { return "computermouse" }
            if n.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
            if n.contains("speaker") { return "hifispeaker" }
            if n.contains("watch") { return "applewatch" }
            return "wave.3.right"
        }
    }

    @Published private(set) var devices: [Device] = []
    @Published private(set) var lastChange: String?
    private var clearChangeWork: DispatchWorkItem?

    var onConnect: ((Device) -> Void)?
    private var timer: Timer?
    private let queue = DispatchQueue(label: "notchcontrol.bluetooth")

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.poll() }
    }

    func poll() {
        queue.async { [weak self] in
            guard let self else { return }
            let connected = self.connectedDevices()
            let batteries = self.batteryLevels()
            let merged = connected.map { d -> Device in
                let b = batteries[d.name] ?? [:]
                return Device(id: d.id, name: d.name, kind: d.kind,
                              battery: b["main"], batteryLeft: b["left"], batteryRight: b["right"], batteryCase: b["case"])
            }
            DispatchQueue.main.async { self.apply(merged) }
        }
    }

    private func apply(_ new: [Device]) {
        let oldIDs = Set(devices.map(\.id))
        let newlyConnected = new.filter { !oldIDs.contains($0.id) }
        let disconnected = devices.filter { d in !new.contains { $0.id == d.id } }
        let first = devices.isEmpty && lastChange == nil
        devices = new
        if !first {
            for d in newlyConnected { announce("\(d.name) connected"); onConnect?(d) }
            for d in disconnected { announce("\(d.name) disconnected") }
        }
    }

    /// Shows a change in the pill for a few seconds, then hands the line back to the agents.
    private func announce(_ text: String) {
        lastChange = text
        clearChangeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.lastChange = nil }
        clearChangeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    // MARK: IOBluetooth

    private func connectedDevices() -> [(id: String, name: String, kind: String)] {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }
        return paired.compactMap { d in
            guard d.isConnected(), let name = d.name, let addr = d.addressString else { return nil }
            return (addr, name, Self.describe(major: d.deviceClassMajor, minor: d.deviceClassMinor))
        }
    }

    private static func describe(major: BluetoothDeviceClassMajor, minor: BluetoothDeviceClassMinor) -> String {
        switch Int(major) {
        case 0x04: // audio/video
            switch Int(minor) {
            case 0x01: return "Headset"
            case 0x02: return "Hands-free"
            case 0x06: return "Headphones"
            case 0x05: return "Speaker"
            default: return "Audio"
            }
        case 0x05: // peripheral
            switch Int(minor) >> 4 {
            case 0x01: return "Keyboard"
            case 0x02: return "Mouse"
            case 0x03: return "Keyboard & mouse"
            default: return "Peripheral"
            }
        case 0x01: return "Computer"
        case 0x02: return "Phone"
        case 0x07: return "Wearable"
        default: return "Device"
        }
    }

    /// Battery levels from system_profiler, keyed by device name.
    private func batteryLevels() -> [String: [String: Int]] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["SPBluetoothDataType", "-json"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return [:] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return [:] }
        var result: [String: [String: Int]] = [:]
        func percent(_ v: Any?) -> Int? {
            guard let s = v as? String else { return v as? Int }
            return Int(s.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
        }
        for section in sections {
            guard let connected = section["device_connected"] as? [[String: Any]] else { continue }
            for entry in connected {
                for (name, value) in entry {
                    guard let info = value as? [String: Any] else { continue }
                    var levels: [String: Int] = [:]
                    if let v = percent(info["device_batteryLevelMain"]) { levels["main"] = v }
                    if let v = percent(info["device_batteryLevelLeft"]) { levels["left"] = v }
                    if let v = percent(info["device_batteryLevelRight"]) { levels["right"] = v }
                    if let v = percent(info["device_batteryLevelCase"]) { levels["case"] = v }
                    if !levels.isEmpty { result[name] = levels }
                }
            }
        }
        return result
    }
}
