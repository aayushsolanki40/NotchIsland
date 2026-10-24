import AppKit
import IOBluetooth
import SwiftUI

/// Announces Bluetooth devices as they connect, AirPods-style.
final class BluetoothService: NSObject, ObservableObject {
    struct Device: Equatable {
        var name: String
        var symbol: String
        var battery: Int?
    }

    @Published private(set) var lastConnected: Device?

    var onConnect: (() -> Void)?
    private var connectNotification: IOBluetoothUserNotification?
    private var startedAt = Date()

    func start() {
        // Register off the launch call stack; registration replays connected
        // devices synchronously and must not hold up app startup.
        DispatchQueue.main.async { [self] in
            startedAt = Date()
            connectNotification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                             selector: #selector(deviceConnected(_:device:)))
        }
    }

    func preview() {
        lastConnected = Device(name: "AirPods Pro", symbol: "airpodspro", battery: 85)
        onConnect?()
    }

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        // IOBluetooth calls this on its own queue as well as the main thread. Touching the
        // device or our state here can deadlock against IOBluetooth's internal locks, so
        // only hand the device over and return immediately.
        DispatchQueue.main.async { [weak self] in self?.handleConnect(device) }
    }

    private func handleConnect(_ device: IOBluetoothDevice) {
        // Registering replays every device that is already connected; only announce new ones.
        guard Date().timeIntervalSince(startedAt) > 3 else { return }
        let name = device.name ?? "Bluetooth Device"
        lastConnected = Device(name: name, symbol: Self.symbol(for: device, name: name), battery: nil)
        onConnect?()
        fetchBattery(address: device.addressString ?? "", name: name, retries: 2)
    }

    private static func symbol(for device: IOBluetoothDevice, name: String) -> String {
        let n = name.lowercased()
        let candidates: [(String, String)] = [("airpods pro", "airpodspro"), ("airpods max", "airpodsmax"),
                                              ("airpods", "airpods"), ("beats", "beats.headphones"),
                                              ("keyboard", "keyboard"), ("mouse", "magicmouse"),
                                              ("trackpad", "rectangle.and.hand.point.up.left")]
        if let match = candidates.first(where: { n.contains($0.0) }),
           NSImage(systemSymbolName: match.1, accessibilityDescription: nil) != nil {
            return match.1
        }
        switch device.deviceClassMajor {
        case BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorAudio): return "headphones"
        case BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorPeripheral): return "keyboard"
        case BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorPhone): return "iphone"
        default: return "dot.radiowaves.left.and.right"
        }
    }

    /// There is no public battery API for AirPods, but system_profiler reports
    /// left/right/case levels shortly after they connect.
    private func fetchBattery(address: String, name: String, retries: Int) {
        let wanted = address.uppercased().replacingOccurrences(of: "-", with: ":")
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let level = Self.readBattery(address: wanted, name: name)
            DispatchQueue.main.async {
                guard let self, self.lastConnected?.name == name else { return }
                if let level {
                    withAnimation(IslandModel.spring) { self.lastConnected?.battery = level }
                } else if retries > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.fetchBattery(address: address, name: name, retries: retries - 1)
                    }
                }
            }
        }
    }

    private static func readBattery(address: String, name: String) -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["-json", "SPBluetoothDataType"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
        for controller in controllers {
            for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                for (deviceName, value) in entry {
                    guard let info = value as? [String: Any] else { continue }
                    let addr = (info["device_address"] as? String ?? "").uppercased()
                    guard addr == address || deviceName == name else { continue }
                    let levels = ["device_batteryLevelLeft", "device_batteryLevelRight", "device_batteryLevelMain"]
                        .compactMap { (info[$0] as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "")) } }
                    return levels.min()
                }
            }
        }
        return nil
    }
}
