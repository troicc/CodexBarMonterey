import Foundation

@main
struct SubscriptionTimingRegression {
    static func main() throws {
        func snapshot(_ usage: String, account: String = "a@example.com") throws -> ProviderSnapshot {
            try JSONCoding.decoder.decode(ProviderSnapshot.self,
                from: Data("{\"provider\":\"codex\",\"account\":\"\(account)\",\"usage\":\(usage)}".utf8))
        }
        let expiry = try snapshot(#"{"subscriptionExpiresAt":"2026-10-24T10:30:00Z","subscriptionRenewsAt":"2026-10-25T10:30:00.123Z"}"#)
        precondition(expiry.usage?.subscriptionExpiresAt != nil)
        precondition(expiry.usage?.subscriptionRenewsAt != nil)
        let automatic = SubscriptionTiming.resolve(expires: expiry.usage?.subscriptionExpiresAt,
            renews: expiry.usage?.subscriptionRenewsAt, manual: "expires|2026-11-01")!
        precondition(!automatic.isManual && automatic.kind == .expires)
        let bad = try snapshot(#"{"primary":{"usedPercent":42,"resetsAt":"2026-10-24T10:30:00Z"},"subscriptionExpiresAt":"invalid","subscriptionRenewsAt":123}"#)
        precondition(bad.usage?.primary?.usedPercent == 42)
        precondition(bad.usage?.subscriptionExpiresAt == nil && bad.usage?.subscriptionRenewsAt == nil)
        precondition(SubscriptionTiming.resolve(expires: nil, renews: nil, manual: "") == nil)
        for value in ["expires|2026-02-30", "expires|2026-1-1", "other|2026-10-24", "garbage"] {
            precondition(SubscriptionTiming.resolve(expires: nil, renews: nil, manual: value) == nil)
        }
        let manual = SubscriptionTiming.resolve(expires: nil, renews: nil, manual: "expires|2026-10-24")!
        precondition(manual.isManual)
        precondition(SubscriptionTiming.encode(date: manual.date, kind: manual.kind) == "expires|2026-10-24")
        precondition(manual.status(now: manual.date.addingTimeInterval(3600)) == "Today")
        precondition(manual.status(now: manual.date.addingTimeInterval(86400)) == "Expiry date passed")
        precondition(manual.status(now: manual.date.addingTimeInterval(-86400)) == "1 day left")
        let renewal = SubscriptionTiming.resolve(expires: nil, renews: manual.date, manual: "")!
        precondition(renewal.kind == .renews && !renewal.isManual)
        precondition(renewal.status(now: manual.date.addingTimeInterval(1)) == "Renewal date passed")
        let other = try snapshot("{}", account: "b@example.com")
        precondition(SubscriptionTiming.preferenceKey(for: expiry) != SubscriptionTiming.preferenceKey(for: other))
        let suite = "subscription-regression.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = SubscriptionTiming.preferenceKey(for: expiry)
        defaults.set("expires|2026-10-24", forKey: key)
        precondition(UserDefaults(suiteName: suite)!.string(forKey: key) == "expires|2026-10-24")
        precondition(defaults.string(forKey: SubscriptionTiming.preferenceKey(for: other)) == nil)
        defaults.removeObject(forKey: key)
        precondition(defaults.string(forKey: key) == nil)
        print("PASS | subscription dates: contract, malformed metadata, precedence, calendar days, account isolation, persistence/clear")
    }
}
