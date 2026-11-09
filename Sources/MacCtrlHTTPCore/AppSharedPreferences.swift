import Foundation

/// Preferences shared by the macOS app and its WidgetKit extension.
public enum AppSharedPreferences {
    public static let appGroupIdentifier = "group.com.clocteck.MacCtrlHTTP"
    public static let defaults: UserDefaults = {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) != nil else {
            return .standard
        }
        return UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }()

    /// Reads the shared container first, then migrates values from the app's former standard domain.
    public static func value(forKey key: String, migrateLegacyValue: Bool = true) -> Any? {
        if let value = defaults.object(forKey: key) {
            return value
        }
        guard migrateLegacyValue, defaults !== UserDefaults.standard,
              let legacyValue = UserDefaults.standard.object(forKey: key) else {
            return nil
        }
        defaults.set(legacyValue, forKey: key)
        return legacyValue
    }

    public static func save(_ value: Any, forKey key: String) {
        defaults.set(value, forKey: key)
        if defaults !== UserDefaults.standard {
            UserDefaults.standard.set(value, forKey: key)
        }
        defaults.synchronize()
        if defaults !== UserDefaults.standard {
            UserDefaults.standard.synchronize()
        }
    }

    public static func removeValue(forKey key: String) {
        defaults.removeObject(forKey: key)
        if defaults !== UserDefaults.standard {
            UserDefaults.standard.removeObject(forKey: key)
        }
        defaults.synchronize()
        if defaults !== UserDefaults.standard {
            UserDefaults.standard.synchronize()
        }
    }
}
