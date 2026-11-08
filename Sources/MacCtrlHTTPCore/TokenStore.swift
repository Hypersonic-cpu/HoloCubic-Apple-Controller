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

    public init(defaults: UserDefaults = .standard, key: String = "actionCtrlToken") {
        self.defaults = defaults
        self.key = key
    }

    public func load() throws -> String? {
        defaults.string(forKey: key)
    }

    public func save(_ token: String) throws {
        if token.isEmpty {
            clear()
        } else {
            defaults.set(token, forKey: key)
        }
    }

    public func clear() {
        defaults.removeObject(forKey: key)
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

    public init(defaults: UserDefaults = .standard, key: String = "deviceAddress") {
        self.defaults = defaults
        self.key = key
    }

    public func load() throws -> String? {
        defaults.string(forKey: key)
    }

    public func save(_ address: String) throws {
        if address.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(address, forKey: key)
        }
    }
}
