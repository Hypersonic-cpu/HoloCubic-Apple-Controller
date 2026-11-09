import Foundation

public protocol TokenStore {
    func load() throws -> String?
    func save(_ token: String) throws
    func clear()
}

/// Stores the token in this app's standard preferences domain.
public struct UserDefaultsTokenStore: TokenStore {
    private let defaults: UserDefaults
    private let key: String
    private let migratesLegacyValue: Bool

    public init(defaults: UserDefaults? = nil, key: String = "actionCtrlToken") {
        self.defaults = defaults ?? AppSharedPreferences.defaults
        self.key = key
        self.migratesLegacyValue = defaults == nil
    }

    public func load() throws -> String? {
        if migratesLegacyValue {
            return AppSharedPreferences.value(forKey: key) as? String
        }
        return defaults.object(forKey: key) as? String
    }

    public func save(_ token: String) throws {
        if token.isEmpty {
            clear()
        } else {
            if migratesLegacyValue {
                AppSharedPreferences.save(token, forKey: key)
            } else {
                defaults.set(token, forKey: key)
            }
        }
    }

    public func clear() {
        if migratesLegacyValue {
            AppSharedPreferences.removeValue(forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

public protocol DeviceAddressStore {
    func load() throws -> String?
    func save(_ address: String) throws
}

/// Stores the device address in this app's standard preferences domain.
public struct UserDefaultsDeviceAddressStore: DeviceAddressStore {
    private let defaults: UserDefaults
    private let key: String
    private let migratesLegacyValue: Bool

    public init(defaults: UserDefaults? = nil, key: String = "deviceAddress") {
        self.defaults = defaults ?? AppSharedPreferences.defaults
        self.key = key
        self.migratesLegacyValue = defaults == nil
    }

    public func load() throws -> String? {
        if migratesLegacyValue {
            return AppSharedPreferences.value(forKey: key) as? String
        }
        return defaults.object(forKey: key) as? String
    }

    public func save(_ address: String) throws {
        if address.isEmpty {
            if migratesLegacyValue {
                AppSharedPreferences.removeValue(forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        } else {
            if migratesLegacyValue {
                AppSharedPreferences.save(address, forKey: key)
            } else {
                defaults.set(address, forKey: key)
            }
        }
    }
}
