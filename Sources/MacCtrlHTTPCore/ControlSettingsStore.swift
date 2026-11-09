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
    private let migratesLegacyValue: Bool

    public init(
        defaults: UserDefaults? = nil,
        bufferSizeKey: String = "bufferSize",
        keyDelayKey: String = "keyDelayMilliseconds"
    ) {
        self.defaults = defaults ?? AppSharedPreferences.defaults
        self.bufferSizeKey = bufferSizeKey
        self.keyDelayKey = keyDelayKey
        self.migratesLegacyValue = defaults == nil
    }

    public func loadBufferSize() -> Int? {
        if migratesLegacyValue {
            return AppSharedPreferences.value(forKey: bufferSizeKey) as? Int
        }
        return defaults.object(forKey: bufferSizeKey) as? Int
    }

    public func saveBufferSize(_ value: Int) {
        if migratesLegacyValue {
            AppSharedPreferences.save(value, forKey: bufferSizeKey)
        } else {
            defaults.set(value, forKey: bufferSizeKey)
        }
    }

    public func loadKeyDelayMilliseconds() -> Int? {
        if migratesLegacyValue {
            return AppSharedPreferences.value(forKey: keyDelayKey) as? Int
        }
        return defaults.object(forKey: keyDelayKey) as? Int
    }

    public func saveKeyDelayMilliseconds(_ value: Int) {
        if migratesLegacyValue {
            AppSharedPreferences.save(value, forKey: keyDelayKey)
        } else {
            defaults.set(value, forKey: keyDelayKey)
        }
    }
}
