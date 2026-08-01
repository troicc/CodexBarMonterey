@preconcurrency import UserNotifications
import Foundation

@MainActor
final class ProviderAlertController: NSObject, UNUserNotificationCenterDelegate {
    private struct AlertState: Equatable {
        let health: ProviderServiceHealth
        let hasError: Bool
        let maximumUsedPercent: Double?
    }

    private let center: UNUserNotificationCenter
    private var previousStates: [String: AlertState]?

    override init() {
        self.center = .current()
        super.init()
        center.delegate = self
    }

    func prepareAuthorizationIfNeeded() {
        if Preferences.shared.notifyOnServiceIncidents || Preferences.shared.notifyOnQuotaThreshold {
            Self.requestAuthorization()
        }
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                NSLog("Notification authorization failed: %@", error.localizedDescription)
            } else if !granted {
                NSLog("CodexBar Monterey notifications were not authorized")
            }
        }
    }

    func evaluate(
        snapshots: [ProviderSnapshot],
        dashboards: [String: ProviderDashboard] = [:]
    ) {
        let current = Dictionary(uniqueKeysWithValues: snapshots.map { snapshot in
            (snapshot.id, AlertState(
                health: snapshot.serviceHealth,
                hasError: snapshot.error != nil,
                maximumUsedPercent: dashboards[snapshot.id]?.quotas.map(\.usedPercent).max()
                    ?? snapshot.maximumUsedPercent))
        })

        // The first successful refresh establishes a baseline. It must not flood
        // Notification Center simply because the application has just launched.
        guard let previousStates = previousStates else {
            self.previousStates = current
            return
        }

        for snapshot in snapshots {
            guard let prior = previousStates[snapshot.id],
                  let next = current[snapshot.id]
            else { continue }

            if Preferences.shared.notifyOnServiceIncidents {
                if (!prior.health.isIncident && next.health.isIncident) || (!prior.hasError && next.hasError) {
                    let detail = snapshot.error?.message ?? snapshot.status?.displayText ?? next.health.title
                    notify(
                        title: "\(snapshot.displayName) needs attention",
                        body: detail,
                        identifier: "incident-\(StableIdentifier.hash(snapshot.id))-\(next.health.rawValue)")
                } else if Preferences.shared.notifyOnRecovery,
                          (prior.health.isIncident || prior.hasError),
                          !next.health.isIncident,
                          !next.hasError
                {
                    notify(
                        title: "\(snapshot.displayName) recovered",
                        body: snapshot.status?.displayText ?? "Provider access is available again.",
                        identifier: "recovery-\(StableIdentifier.hash(snapshot.id))")
                }
            }

            if Preferences.shared.notifyOnQuotaThreshold,
               let used = next.maximumUsedPercent
            {
                let priorUsed = prior.maximumUsedPercent ?? 0
                let threshold = Preferences.shared.quotaWarningThreshold
                if priorUsed < threshold, used >= threshold {
                    let title = used >= 100
                        ? "\(snapshot.displayName) quota depleted"
                        : "\(snapshot.displayName) quota warning"
                    notify(
                        title: title,
                        body: String(format: "Usage reached %.0f%%.", used),
                        identifier: "quota-\(StableIdentifier.hash(snapshot.id))-\(Int(threshold))")
                }
            }
        }

        self.previousStates = current
    }

    private func notify(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(
            identifier: "\(identifier)-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil))
        { error in
            if let error = error {
                NSLog("Could not deliver provider notification: %@", error.localizedDescription)
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
