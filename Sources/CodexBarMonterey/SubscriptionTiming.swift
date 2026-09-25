import Foundation

struct SubscriptionTiming: Hashable {
    enum Kind: String, CaseIterable {
        case expires, renews
        var title: String { self == .expires ? "Subscription expires" : "Subscription renews" }
    }

    let date: Date
    let kind: Kind
    let isManual: Bool

    static func preferenceKey(for snapshot: ProviderSnapshot) -> String {
        // Claude CLI metadata may identify an account without changing its history ID.
        let identity = snapshot.id + "::" + (snapshot.accountDisplayName?.lowercased() ?? "")
        return "subscriptionDate.\(snapshot.provider).\(StableIdentifier.hash(identity))"
    }

    static func resolve(expires: Date?, renews: Date?, manual: String) -> Self? {
        if let date = expires { return Self(date: date, kind: .expires, isManual: false) }
        if let date = renews { return Self(date: date, kind: .renews, isManual: false) }
        let parts = manual.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 2, let kind = Kind(rawValue: String(parts[0])),
              let date = dayFormatter.date(from: String(parts[1])),
              dayFormatter.string(from: date) == parts[1] else { return nil }
        return Self(date: date, kind: kind, isManual: true)
    }

    static func encode(date: Date, kind: Kind) -> String {
        kind.rawValue + "|" + dayFormatter.string(from: date)
    }

    private static var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }

    var dateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = isManual ? .none : .short
        return formatter.string(from: date)
    }

    func status(now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                          to: calendar.startOfDay(for: date)).day ?? 0
        if days < 0 || (!isManual && date <= now) {
            return kind == .expires ? "Expiry date passed" : "Renewal date passed"
        }
        return days == 0 ? "Today" : days == 1 ? "1 day left" : "\(days) days left"
    }
}
