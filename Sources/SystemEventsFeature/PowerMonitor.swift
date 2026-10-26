import Foundation
import IOKit.ps
import SystemEventsCore

/// Reads the battery and charger state and reports changes. Needs no permission.
@MainActor
final class PowerMonitor {
    var onChange: ((PowerSnapshot) -> Void)?

    private var runLoopSource: CFRunLoopSource?

    /// The current state of the internal battery; `hasBattery` is false on a desktop Mac.
    static func read() -> PowerSnapshot {
        let none = PowerSnapshot(hasBattery: false, isOnAC: true, isCharging: false, percent: 0)
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return none }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                    as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = max(description[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            let percent = min(max(Int((Double(current) / Double(maximum) * 100).rounded()), 0), 100)
            var snapshot = PowerSnapshot(
                isOnAC: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                percent: percent)
            // Minutes until empty, or until full while charging; -1 while it is being worked out.
            let key = snapshot.isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            snapshot.minutesLeft = (description[key] as? Int).flatMap { $0 > 0 ? $0 : nil }
            return snapshot
        }
        return none
    }

    func start() {
        guard runLoopSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            // The source is scheduled on the main run loop, so this runs on the main thread.
            MainActor.assumeIsolated { monitor.onChange?(PowerMonitor.read()) }
        }, context)?.takeRetainedValue() else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
    }
}
