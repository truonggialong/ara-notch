import Foundation
import Testing
@testable import SystemEventsCore

private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

@Suite struct BluetoothDeviceKindTests {
    @Test(arguments: [
        ("AirPods Pro", BluetoothDeviceKind.headphones), ("Long's AirPods Max", .headphones),
        ("Beats Studio Buds", .headphones), ("WH-1000XM5", .headphones), ("Tai nghe Sony", .headphones),
        ("Bose QC Headphones", .headphones), ("Jabra Elite Headset", .headphones),
        ("Magic Keyboard", .keyboard), ("Keychron K2", .keyboard), ("Bàn phím Logitech", .keyboard),
        ("Magic Mouse", .mouse), ("MX Master 3", .mouse), ("Chuột không dây", .mouse),
        ("Magic Trackpad", .trackpad),
        ("DualSense Wireless Controller", .gamepad), ("Xbox Wireless Controller", .gamepad),
        ("JBL Flip 6", .speaker), ("HomePod mini", .speaker), ("Loa Bluetooth", .speaker),
        ("iPhone của Long", .phone),
        ("Thiết bị lạ", .other), ("", .other),
    ])
    func guessedFromTheName(name: String, kind: BluetoothDeviceKind) {
        #expect(BluetoothDeviceKind.guess(fromName: name) == kind)
    }
}

@Suite struct BluetoothEventFilterTests {
    @Test func firstEventForADevicePasses() {
        var filter = BluetoothEventFilter()
        let result1 = filter.shouldReport(deviceID: "aa", isConnected: true, at: at(0))
        #expect(result1)
    }

    @Test func repeatedSameStateWithinTheWindowIsDropped() {
        var filter = BluetoothEventFilter()
        _ = filter.shouldReport(deviceID: "aa", isConnected: true, at: at(0))
        let result2 = filter.shouldReport(deviceID: "aa", isConnected: true, at: at(2))
        #expect(!result2)
        let result3 = filter.shouldReport(deviceID: "aa", isConnected: true, at: at(6))
        #expect(result3)
    }

    @Test func changeOfStateAlwaysPasses() {
        var filter = BluetoothEventFilter()
        _ = filter.shouldReport(deviceID: "aa", isConnected: true, at: at(0))
        let result4 = filter.shouldReport(deviceID: "aa", isConnected: false, at: at(1))
        #expect(result4)
    }

    @Test func devicesAreIndependent() {
        var filter = BluetoothEventFilter()
        _ = filter.shouldReport(deviceID: "aa", isConnected: true, at: at(0))
        let result5 = filter.shouldReport(deviceID: "bb", isConnected: true, at: at(1))
        #expect(result5)
    }
}

@Suite struct BluetoothAlertSettingTests {
    @Test func bluetoothAlertIsOnByDefaultAndRoundTrips() {
        let defaults = InMemoryDefaults()
        let store = AlertSettingsStore(defaults: defaults)
        #expect(store.bluetooth == true)
        store.bluetooth = false
        #expect(AlertSettingsStore(defaults: defaults).bluetooth == false)
    }
}

@Suite struct ConnectedDevicesTests {
    @Test func devicesAreListedByNameWhileConnected() {
        var devices = ConnectedDevices()
        devices.connected(id: "b", name: "Magic Mouse")
        devices.connected(id: "a", name: "AirPods Pro")
        #expect(devices.names == ["AirPods Pro", "Magic Mouse"])
        devices.disconnected(id: "b")
        #expect(devices.names == ["AirPods Pro"])
    }

    @Test func aDeviceWithoutANameIsNotListedAndAReconnectIsListedOnce() {
        var devices = ConnectedDevices()
        devices.connected(id: "x", name: "")
        devices.connected(id: "a", name: "AirPods Pro")
        devices.connected(id: "a", name: "AirPods Pro")
        #expect(devices.names == ["AirPods Pro"])
    }
}
