import Foundation
import Testing
@testable import SystemEventsCore

// Made-up names and no serial numbers or addresses: the shape is the system report's.
private let sample = Data(#"""
{"SPBluetoothDataType":[{"device_connected":[
  {"Tai nghe Lan":{"device_minorType":"Headphones","device_batteryLevelLeft":"80%","device_batteryLevelRight":"65%","device_batteryLevelCase":"40%"}},
  {"Chuột":{"device_minorType":"Mouse","device_batteryLevelMain":"52%"}},
  {"Loa":{"device_minorType":"Hi-Fi Stereo"}}],
 "device_not_connected":[{"Bàn phím cũ":{"device_minorType":"Keyboard","device_batteryLevelMain":"90%"}}]}]}
"""#.utf8)

@Suite struct BluetoothBatteriesTests {
    @Test func connectedDevicesWithTheirLowestBudAndKind() {
        #expect(BluetoothBatteries.parse(sample) == [
            BluetoothBattery(name: "Tai nghe Lan", kind: .headphones, percent: 65),
            BluetoothBattery(name: "Chuột", kind: .mouse, percent: 52),
            BluetoothBattery(name: "Loa", kind: .speaker, percent: nil),
        ])
    }

    @Test func nothingConnectedAndBrokenOutput() {
        #expect(BluetoothBatteries.parse(Data(#"{"SPBluetoothDataType":[{}]}"#.utf8)) == [])
        #expect(BluetoothBatteries.parse(Data("not json".utf8)) == nil)
    }
}
