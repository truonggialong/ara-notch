import Foundation
import os
import SystemEventsCore

/// The battery levels of the Bluetooth devices connected now, from the system report. The
/// report takes a moment, so it runs in the background, at most once every two minutes, and
/// is given up after five seconds; until a new one arrives the last one stays.
@MainActor
final class BluetoothBatteryReader: ObservableObject {
    @Published private(set) var devices: [BluetoothBattery] = []

    private static let interval: TimeInterval = 120
    nonisolated private static let timeout: TimeInterval = 5
    private var lastRun: Date?
    private var isRunning = false

    /// Reads the report again unless it was read in the last two minutes or is being read.
    func refreshIfStale(now: Date = Date()) {
        guard !isRunning, lastRun.map({ now.timeIntervalSince($0) >= Self.interval }) ?? true else { return }
        isRunning = true
        lastRun = now
        Task.detached(priority: .utility) {
            let data = Self.runReport()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isRunning = false
                if let data, let devices = BluetoothBatteries.parse(data) {
                    self.devices = devices
                }
            }
        }
    }

    /// Runs `system_profiler` and returns what it printed; nil when it failed or took too long.
    nonisolated private static func runReport() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let deadline = DispatchTime.now() + timeout
        let done = DispatchSemaphore(value: 0)
        // Read while it runs: a full pipe would otherwise stall the report.
        nonisolated(unsafe) var output = Data()
        let reader = Thread {
            output = pipe.fileHandleForReading.readDataToEndOfFile()
            done.signal()
        }
        reader.start()
        if done.wait(timeout: deadline) == .timedOut {
            process.terminate()
            return nil
        }
        process.waitUntilExit()
        return process.terminationStatus == 0 ? output : nil
    }
}
