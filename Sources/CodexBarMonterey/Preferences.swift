import Foundation

enum RefreshMode: String, CaseIterable, Identifiable {
    case manual
    case fixed
    case adaptive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: return "Manual"
        case .fixed: return "Fixed interval"
        case .adaptive: return "Adaptive"
        }
    }
}

enum MenuBarDisplayStyle: String, CaseIterable, Identifiable {
    case meter
    case usedPercentage
    case remainingPercentage
    case providerIcon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meter: return "Usage meter"
        case .usedPercentage: return "Used percentage"
        case .remainingPercentage: return "Remaining percentage"
        case .providerIcon: return "Provider icon"
        }
    }
}

enum MenuQuotaPresentation: String, CaseIterable, Identifiable {
    case used
    case remaining

    var id: String { rawValue }
    var title: String { self == .used ? "Used" : "Remaining" }
}

@MainActor
final class Preferences {
    static let shared = Preferences()

    private enum Key {
        static let refreshMode = "refreshMode"
        static let refreshInterval = "refreshInterval"
        static let refreshOnMenuOpen = "refreshOnMenuOpen"
        static let mergeIcons = "mergeIcons"
        static let showPercentage = "showPercentage"
        static let menuBarDisplayStyle = "menuBarDisplayStyle"
        static let showAccountInMenu = "showAccountInMenu"
        static let showMenuMetrics = "showMenuMetrics"
        static let showResetTime = "showResetTime"
        static let showServiceStatus = "showServiceStatus"
        static let menuQuotaPresentation = "menuQuotaPresentation"
        static let overviewProviderLimit = "overviewProviderLimit"
        static let notifyOnServiceIncidents = "notifyOnServiceIncidents"
        static let notifyOnRecovery = "notifyOnRecovery"
        static let notifyOnQuotaThreshold = "notifyOnQuotaThreshold"
        static let quotaWarningThreshold = "quotaWarningThreshold"
        static let launchAtLogin = "launchAtLogin"
        static let automaticUpdates = "automaticUpdates"
    }

    private let defaults = UserDefaults.standard

    var refreshMode: RefreshMode {
        get {
            guard let value = defaults.string(forKey: Key.refreshMode),
                  let mode = RefreshMode(rawValue: value)
            else { return .adaptive }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: Key.refreshMode) }
    }

    var refreshInterval: TimeInterval {
        get {
            let value = defaults.double(forKey: Key.refreshInterval)
            return value > 0 ? value : 300
        }
        set { defaults.set(max(60, newValue), forKey: Key.refreshInterval) }
    }

    var refreshOnMenuOpen: Bool {
        get { defaults.object(forKey: Key.refreshOnMenuOpen) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.refreshOnMenuOpen) }
    }

    var mergeIcons: Bool {
        get { defaults.object(forKey: Key.mergeIcons) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.mergeIcons) }
    }

    var menuBarDisplayStyle: MenuBarDisplayStyle {
        get {
            if let value = defaults.string(forKey: Key.menuBarDisplayStyle),
               let style = MenuBarDisplayStyle(rawValue: value)
            {
                return style
            }
            // Preserve the pre-v0.8 preference when migrating existing installs.
            return defaults.bool(forKey: Key.showPercentage) ? .usedPercentage : .meter
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.menuBarDisplayStyle)
            defaults.set(newValue == .usedPercentage, forKey: Key.showPercentage)
        }
    }

    /// Compatibility shim for older settings code and preferences.
    var showPercentage: Bool {
        get { menuBarDisplayStyle == .usedPercentage }
        set { menuBarDisplayStyle = newValue ? .usedPercentage : .meter }
    }

    var showAccountInMenu: Bool {
        get { defaults.object(forKey: Key.showAccountInMenu) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showAccountInMenu) }
    }

    var showMenuMetrics: Bool {
        get { defaults.object(forKey: Key.showMenuMetrics) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showMenuMetrics) }
    }

    var showResetTime: Bool {
        get { defaults.object(forKey: Key.showResetTime) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showResetTime) }
    }

    var showServiceStatus: Bool {
        get { defaults.object(forKey: Key.showServiceStatus) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showServiceStatus) }
    }

    var menuQuotaPresentation: MenuQuotaPresentation {
        get {
            guard let value = defaults.string(forKey: Key.menuQuotaPresentation),
                  let presentation = MenuQuotaPresentation(rawValue: value)
            else { return .used }
            return presentation
        }
        set { defaults.set(newValue.rawValue, forKey: Key.menuQuotaPresentation) }
    }

    var overviewProviderLimit: Int {
        get {
            let value = defaults.integer(forKey: Key.overviewProviderLimit)
            return value > 0 ? min(12, value) : 6
        }
        set { defaults.set(max(3, min(12, newValue)), forKey: Key.overviewProviderLimit) }
    }

    var notifyOnServiceIncidents: Bool {
        get { defaults.bool(forKey: Key.notifyOnServiceIncidents) }
        set { defaults.set(newValue, forKey: Key.notifyOnServiceIncidents) }
    }

    var notifyOnRecovery: Bool {
        get { defaults.object(forKey: Key.notifyOnRecovery) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.notifyOnRecovery) }
    }

    var notifyOnQuotaThreshold: Bool {
        get { defaults.bool(forKey: Key.notifyOnQuotaThreshold) }
        set { defaults.set(newValue, forKey: Key.notifyOnQuotaThreshold) }
    }

    var quotaWarningThreshold: Double {
        get {
            let value = defaults.double(forKey: Key.quotaWarningThreshold)
            return value > 0 ? max(50, min(100, value)) : 80
        }
        set { defaults.set(max(50, min(100, newValue)), forKey: Key.quotaWarningThreshold) }
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
