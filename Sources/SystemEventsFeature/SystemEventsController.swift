import Combine
import Foundation
import NotchShell
import os
import SwiftUI
import SystemEventsCore

/// Events that can be injected for automated checks, without touching the real system state.
public enum SimulatedSystemEvent: String, CaseIterable, Sendable {
    case plug
    case unplug
    case low
    case full
    case capsOn = "caps-on"
    case capsOff = "caps-off"
    case offline
    case online
    case bluetooth
    /// Press the volume-up key once, as the notch's own display would handle it.
    case volumeUp = "volume-up"
    case volumeDown = "volume-down"
    case brightnessUp = "brightness-up"
    case brightnessDown = "brightness-down"
    case keyboardLightUp = "keyboard-light-up"
    case keyboardLightDown = "keyboard-light-down"
}

/// Watches power, Caps Lock and the network, and shows what happens as live activities.
@MainActor
public final class SystemEventsController {
    private let settings: AlertSettings
    private let notch: NotchController
    private let powerMonitor = PowerMonitor()
    private let batteryModel = BatteryModel()
    private let batteryReader = BluetoothBatteryReader()
    private let capsLockMonitor = CapsLockMonitor()
    private let networkMonitor = NetworkMonitor()
    private let bluetoothMonitor = BluetoothMonitor()
    private var bluetoothFilter = BluetoothEventFilter()
    private let log = Logger(subsystem: "com.aranotch.app", category: "alerts")

    private var powerDetector = PowerEventDetector()
    private var capsLockDetector = CapsLockDetector()
    private var connectivity = ConnectivityDebouncer()
    private var connectivityTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let mediaKeys = MediaKeyTap()

    public init(settings: AlertSettings, notch: NotchController) {
        self.settings = settings
        self.notch = notch
    }

    public func start() {
        let power = PowerMonitor.read()
        if power.hasBattery {
            log.notice("power at launch: \(power.percent)% on \(power.isOnAC ? "AC" : "battery", privacy: .public), charging \(power.isCharging)")
        } else {
            log.notice("power at launch: no battery")
        }
        handle(power)
        batteryModel.snapshot = power
        powerMonitor.onChange = { [weak self] snapshot in
            self?.batteryModel.snapshot = snapshot
            self?.handle(snapshot)
        }
        powerMonitor.start()

        capsLockMonitor.onRead = { [weak self] isOn in
            guard let self else { return }
            self.showCapsLockResting(isOn && self.settings.capsLock)
            guard let event = self.capsLockDetector.update(isOn: isOn), self.settings.capsLock else { return }
            self.notch.present(SystemActivities.capsLock(event))
        }
        capsLockMonitor.start()
        settings.$capsLock
            .dropFirst()
            .sink { [weak self] isOn in self?.showCapsLockResting(isOn && CapsLockMonitor.isOn) }
            .store(in: &cancellables)

        settings.$replacesHUD
            .sink { [weak self] isOn in self?.setReplacesHUD(isOn) }
            .store(in: &cancellables)

        var hasLoggedNetwork = false
        networkMonitor.onChange = { [weak self] isOnline in
            guard let self else { return }
            if !hasLoggedNetwork {
                hasLoggedNetwork = true
                self.log.notice("network at launch: \(isOnline ? "online" : "offline", privacy: .public)")
            }
            self.present(self.connectivity.update(isOnline: isOnline, at: Date()))
            self.scheduleConnectivityCheck()
        }
        networkMonitor.start()

        bluetoothMonitor.onEvent = { [weak self] identifier, name, isConnected in
            guard let self, self.settings.bluetooth,
                  self.bluetoothFilter.shouldReport(deviceID: identifier, isConnected: isConnected, at: Date())
            else { return }
            self.notch.present(SystemActivities.bluetooth(name: name, isConnected: isConnected))
        }
        // Bluetooth is only touched while its alert is on: the first use asks for permission.
        settings.$bluetooth
            .sink { [weak self] isOn in
                if isOn {
                    self?.bluetoothMonitor.start()
                } else {
                    self?.bluetoothMonitor.stop()
                    self?.notch.dismissActivity(id: SystemActivities.ID.bluetooth)
                }
            }
            .store(in: &cancellables)

        // Switching an alert off also removes one that is showing right now.
        settings.$power.filter { !$0 }
            .sink { [weak self] _ in self?.notch.dismissActivity(id: SystemActivities.ID.power) }
            .store(in: &cancellables)
        settings.$capsLock.filter { !$0 }
            .sink { [weak self] _ in self?.notch.dismissActivity(id: SystemActivities.ID.capsLock) }
            .store(in: &cancellables)
        settings.$network.filter { !$0 }
            .sink { [weak self] _ in self?.notch.dismissActivity(id: SystemActivities.ID.network) }
            .store(in: &cancellables)
    }

    /// The battery, the Bluetooth devices and the volume (the music feature's row), as a widget of the overview.
    public func makeOverviewTile(volume: AnyView) -> AnyView {
        // The time left changes without the system announcing it: read again when shown.
        AnyView(DeviceWidget(battery: batteryModel, reader: batteryReader, volume: volume).onAppear { [batteryModel] in
            batteryModel.snapshot = PowerMonitor.read()
        })
    }

    private var showsCapsLockResting = false

    /// While Caps Lock is on, a small mark rests beside the closed notch: the notice that it
    /// went on lasts a moment, the state lasts until it is turned off.
    private func showCapsLockResting(_ shows: Bool) {
        guard shows != showsCapsLockResting else { return }
        showsCapsLockResting = shows
        notch.setRestingActivity(shows ? SystemActivities.capsLockResting() : nil, id: SystemActivities.ID.capsLockResting)
    }

    public func makeSettingsSection() -> AnyView {
        AnyView(AlertSettingsSection(settings: settings))
    }

    // MARK: - Volume and brightness

    /// Whether the volume and brightness keys are currently handled by the notch.
    public private(set) var isReplacingHUD = false

    private func setReplacesHUD(_ isOn: Bool) {
        mediaKeys.stop()
        isReplacingHUD = false
        guard isOn else { return }
        mediaKeys.onKey = { [weak self] key, fine in self?.handle(key, fine: fine) ?? false }
        // Without Accessibility the tap cannot be made; the keys then stay with the system.
        isReplacingHUD = mediaKeys.start()
        if !isReplacingHUD {
            log.notice("volume and brightness keys stay with the system: no Accessibility permission")
        }
    }

    /// Applies a key press and shows the new level. Returns false when the level cannot be
    /// controlled from here, so the key goes on to the system.
    @discardableResult
    private func handle(_ key: MediaKeyEvent, fine: Bool) -> Bool {
        switch key.key {
        case .volumeUp, .volumeDown:
            guard let level = VolumeControl.level else { return false }
            let next = LevelStepper.step(level, up: key.key == .volumeUp, fine: fine)
            VolumeControl.level = next
            // Raising the volume unmutes, as the system does.
            if key.key == .volumeUp, VolumeControl.isMuted {
                VolumeControl.isMuted = false
            }
            notch.present(SystemActivities.level(
                "sign.volume", symbol: SystemActivities.volumeSymbol(level: next, isMuted: VolumeControl.isMuted),
                value: next))
        case .mute:
            guard !key.isRepeat, let level = VolumeControl.level else { return VolumeControl.level != nil }
            VolumeControl.isMuted.toggle()
            let isMuted = VolumeControl.isMuted
            notch.present(SystemActivities.level(
                "sign.volume", symbol: SystemActivities.volumeSymbol(level: level, isMuted: isMuted),
                value: isMuted ? 0 : level))
        case .brightnessUp, .brightnessDown:
            guard let level = BrightnessControl.level else { return false }
            let next = LevelStepper.step(level, up: key.key == .brightnessUp, fine: fine)
            BrightnessControl.level = next
            notch.present(SystemActivities.level(
                "sign.brightness", symbol: next > 0.5 ? "sun.max.fill" : "sun.min.fill", value: next))
        case .keyboardLightUp, .keyboardLightDown:
            guard let level = KeyboardLightControl.level else { return false }
            let next = LevelStepper.step(level, up: key.key == .keyboardLightUp, fine: fine)
            KeyboardLightControl.level = next
            notch.present(SystemActivities.level(
                "sign.keyboardLight", symbol: next > 0 ? "light.max" : "light.min", value: next))
        }
        return true
    }

    /// Shows the activity for an event as if it had happened. Honours the settings switches.
    public func simulate(_ event: SimulatedSystemEvent) {
        switch event {
        case .plug: present(PowerEvent.pluggedIn(percent: 64))
        case .unplug: present(PowerEvent.unplugged(percent: 64))
        case .low: present(PowerEvent.low(percent: 18))
        case .full: present(PowerEvent.full)
        case .capsOn: present(CapsLockEvent.on)
        case .capsOff: present(CapsLockEvent.off)
        case .offline: present(ConnectivityEvent.offline)
        case .online: present(ConnectivityEvent.online)
        case .bluetooth:
            if settings.bluetooth {
                notch.present(SystemActivities.bluetooth(name: "AirPods Pro", isConnected: true))
            }
        case .volumeUp, .volumeDown, .brightnessUp, .brightnessDown, .keyboardLightUp, .keyboardLightDown:
            // These change the real volume, brightness or keyboard light by one step, like a key press.
            let data1: [SimulatedSystemEvent: Int] = [
                .volumeUp: 0, .volumeDown: 1, .brightnessUp: 2, .brightnessDown: 3,
                .keyboardLightUp: 21, .keyboardLightDown: 22,
            ]
            if let code = data1[event], let key = MediaKeyEvent(data1: (code << 16) | (0xA << 8)) {
                handle(key, fine: false)
            }
        }
    }

    // MARK: - Events

    private func handle(_ snapshot: PowerSnapshot) {
        powerDetector.update(snapshot).forEach(present)
    }

    private func present(_ event: PowerEvent) {
        guard settings.power else { return }
        notch.present(SystemActivities.power(event))
    }

    private func present(_ event: CapsLockEvent) {
        guard settings.capsLock else { return }
        notch.present(SystemActivities.capsLock(event))
    }

    private func present(_ event: ConnectivityEvent?) {
        guard let event, settings.network else { return }
        notch.present(SystemActivities.network(event))
    }

    /// Wakes up when a lost connection has lasted long enough to be worth reporting.
    private func scheduleConnectivityCheck() {
        connectivityTimer?.invalidate()
        connectivityTimer = nil
        guard let deadline = connectivity.nextDeadline else { return }
        let timer = Timer(timeInterval: max(deadline.timeIntervalSinceNow, 0), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.present(self.connectivity.advance(to: Date()))
                self.scheduleConnectivityCheck()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        connectivityTimer = timer
    }
}
