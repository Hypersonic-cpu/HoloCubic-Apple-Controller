import Foundation

public protocol ControlSettingsStore {
    func loadBufferSize() -> Int?
    func saveBufferSize(_ value: Int)
    func loadKeyDelayMilliseconds() -> Int?
    func saveKeyDelayMilliseconds(_ value: Int)
}

/// Stores the Mac-only controller settings in this app's preferences domain.
public struct UserDefaultsControlSettingsStore: ControlSettingsStore {
    private let defaults: UserDefaults
    private let bufferSizeKey: String
    private let keyDelayKey: String

    public init(
        defaults: UserDefaults = .standard,
        bufferSizeKey: String = "bufferSize",
        keyDelayKey: String = "keyDelayMilliseconds"
    ) {
        self.defaults = defaults
        self.bufferSizeKey = bufferSizeKey
        self.keyDelayKey = keyDelayKey
    }

    public func loadBufferSize() -> Int? {
        defaults.object(forKey: bufferSizeKey) as? Int
    }

    public func saveBufferSize(_ value: Int) {
        defaults.set(value, forKey: bufferSizeKey)
    }

    public func loadKeyDelayMilliseconds() -> Int? {
        defaults.object(forKey: keyDelayKey) as? Int
    }

    public func saveKeyDelayMilliseconds(_ value: Int) {
        defaults.set(value, forKey: keyDelayKey)
    }
}
