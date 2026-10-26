import Combine
import SystemEventsCore

/// Observable alert switches; every change is written through to the store.
@MainActor
public final class AlertSettings: ObservableObject {
    private let store: AlertSettingsStore

    @Published public var power: Bool {
        didSet { store.power = power }
    }

    @Published public var capsLock: Bool {
        didSet { store.capsLock = capsLock }
    }

    @Published public var network: Bool {
        didSet { store.network = network }
    }

    @Published public var bluetooth: Bool {
        didSet { store.bluetooth = bluetooth }
    }

    @Published public var replacesHUD: Bool {
        didSet { store.replacesHUD = replacesHUD }
    }

    public init(store: AlertSettingsStore) {
        self.store = store
        power = store.power
        capsLock = store.capsLock
        network = store.network
        bluetooth = store.bluetooth
        replacesHUD = store.replacesHUD
    }
}
