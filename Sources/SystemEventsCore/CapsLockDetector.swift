public enum CapsLockEvent: Equatable, Sendable {
    case on
    case off
}

/// Reports Caps Lock changes. The state at launch is not a change.
public struct CapsLockDetector: Sendable {
    private var isOn: Bool?

    public init() {}

    public mutating func update(isOn newValue: Bool) -> CapsLockEvent? {
        defer { isOn = newValue }
        guard let isOn, isOn != newValue else { return nil }
        return newValue ? .on : .off
    }
}
