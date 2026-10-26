import CoreBluetooth
import Foundation
import IOBluetooth
import SystemEventsCore

/// Reports Bluetooth devices connecting and disconnecting.
///
/// macOS asks the user for Bluetooth permission on first use. IOBluetooth blocks the calling
/// thread until that question is answered, which would freeze the whole app, so permission is
/// settled first through CoreBluetooth, whose prompt is asynchronous. Notifications are only
/// registered once permission has been granted.
@MainActor
final class BluetoothMonitor: NSObject, CBCentralManagerDelegate {
    /// Device identifier, device name, and whether it just connected (true) or disconnected.
    var onEvent: ((String, String, Bool) -> Void)?
    /// The devices connected now, each time that changes.
    var onDevicesChange: ((ConnectedDevices) -> Void)?
    private var devices = ConnectedDevices()

    /// Registering reports every device that is already connected; those are not news.
    private static let startupGrace: TimeInterval = 3

    private var isWanted = false
    private var permissionProbe: CBCentralManager?
    private var connectToken: IOBluetoothUserNotification?
    private var disconnectTokens: [String: IOBluetoothUserNotification] = [:]
    private var registeredAt = Date.distantPast

    func start() {
        isWanted = true
        registerIfPermitted()
    }

    func stop() {
        isWanted = false
        permissionProbe = nil
        connectToken?.unregister()
        connectToken = nil
        disconnectTokens.values.forEach { $0.unregister() }
        disconnectTokens = [:]
        devices = ConnectedDevices()
        onDevicesChange?(devices)
    }

    private func registerIfPermitted() {
        guard isWanted, connectToken == nil else { return }
        switch CBCentralManager.authorization {
        case .allowedAlways:
            permissionProbe = nil
            registeredAt = Date()
            connectToken = IOBluetoothDevice.register(
                forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
        case .notDetermined:
            // Creating a central manager shows the permission prompt without blocking;
            // `centralManagerDidUpdateState` fires once the user has answered.
            if permissionProbe == nil {
                permissionProbe = CBCentralManager(
                    delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
            }
        default:
            // Denied or restricted: stay quiet.
            permissionProbe = nil
        }
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // The manager was created with the main queue, so this runs on the main thread.
        MainActor.assumeIsolated { registerIfPermitted() }
    }

    /// IOBluetooth calls these on a queue of its own, not on the main thread. They only hand
    /// the device over to the main thread, where the rest of this class lives; doing the work
    /// here would trap, because the class is bound to the main thread.
    @objc private nonisolated func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        nonisolated(unsafe) let device = device
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.connected(device) }
        }
    }

    @objc private nonisolated func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        nonisolated(unsafe) let device = device
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.disconnected(device) }
        }
    }

    private func connected(_ device: IOBluetoothDevice) {
        guard isWanted else { return }
        let identifier = device.addressString ?? device.name ?? "unknown"
        disconnectTokens[identifier]?.unregister()
        disconnectTokens[identifier] = device.register(
            forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        // Those reported at registration count too: they are connected.
        devices.connected(id: identifier, name: device.name ?? "")
        onDevicesChange?(devices)

        guard Date().timeIntervalSince(registeredAt) >= Self.startupGrace else { return }
        onEvent?(identifier, device.name ?? "", true)
    }

    private func disconnected(_ device: IOBluetoothDevice) {
        let identifier = device.addressString ?? device.name ?? "unknown"
        disconnectTokens[identifier]?.unregister()
        disconnectTokens[identifier] = nil
        devices.disconnected(id: identifier)
        onDevicesChange?(devices)
        guard isWanted else { return }
        onEvent?(identifier, device.name ?? "", false)
    }
}
