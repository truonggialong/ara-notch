import Foundation

/// A `UserDefaults` that keeps everything in memory, so tests never touch ~/Library/Preferences.
/// Values are boxed the way the real store returns them (`NSNumber`, `NSString`).
final class InMemoryDefaults: UserDefaults {
    private var storage: [String: Any] = [:]

    init() {
        super.init(suiteName: nil)!
    }

    override func object(forKey defaultName: String) -> Any? {
        storage[defaultName]
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        storage[defaultName] = value
    }

    override func set(_ value: Bool, forKey defaultName: String) {
        storage[defaultName] = NSNumber(value: value)
    }

    override func set(_ value: Int, forKey defaultName: String) {
        storage[defaultName] = NSNumber(value: value)
    }

    override func set(_ value: Double, forKey defaultName: String) {
        storage[defaultName] = NSNumber(value: value)
    }

    override func removeObject(forKey defaultName: String) {
        storage[defaultName] = nil
    }

    override func double(forKey defaultName: String) -> Double {
        (storage[defaultName] as? NSNumber)?.doubleValue ?? 0
    }
}
