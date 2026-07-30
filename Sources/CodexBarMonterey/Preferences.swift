import Foundation

@MainActor
final class Preferences {
    static let shared = Preferences()

    private enum Key {
        static let refreshInterval = "refreshInterval"
        static let mergeIcons = "mergeIcons"
        static let showPercentage = "showPercentage"
        static let launchAtLogin = "launchAtLogin"
        static let automaticUpdates = "automaticUpdates"
    }

    private let defaults = UserDefaults.standard

    var refreshInterval: TimeInterval {
        get {
            let value = defaults.double(forKey: Key.refreshInterval)
            return value > 0 ? value : 300
        }
        set { defaults.set(newValue, forKey: Key.refreshInterval) }
    }

    var mergeIcons: Bool {
        get { defaults.object(forKey: Key.mergeIcons) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.mergeIcons) }
    }

    var showPercentage: Bool {
        get { defaults.object(forKey: Key.showPercentage) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.showPercentage) }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set {
            defaults.set(newValue, forKey: Key.launchAtLogin)
            LaunchAtLoginController.setEnabled(newValue)
        }
    }

    var automaticUpdates: Bool {
        get { defaults.object(forKey: Key.automaticUpdates) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.automaticUpdates) }
    }
}
