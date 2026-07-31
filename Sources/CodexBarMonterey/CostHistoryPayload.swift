import Foundation

/// Typed representation of `codexbar cost --format json`.
///
/// Dashboard code must not discover aggregate values by recursively searching
/// for names such as `totalTokens`: that key also occurs in every daily row and
/// dictionary iteration order is not a stable data contract. This type keeps
/// the selected-window aggregate, daily history, and model summary separate.
struct CostHistoryPayload: Decodable, Hashable {
    let provider: String
    let source: String?
    let updatedAt: String?
    let sessionTokens: Double?
    let sessionCostUSD: Double?
    let last30DaysTokens: Double?
    let last30DaysCostUSD: Double?
    let daily: [CostHistoryDay]?
    let totals: CostHistoryTotals?

    var resolvedLast30DaysTokens: Double? {
        positiveOrZero(last30DaysTokens) ??
            positiveOrZero(totals?.totalTokens) ??
            summedDaily(\.totalTokens)
    }

    var resolvedLast30DaysCostUSD: Double? {
        positiveOrZero(last30DaysCostUSD) ??
            positiveOrZero(totals?.totalCost) ??
            summedDaily(\.totalCost)
    }

    /// Tokens recorded for the current local calendar day. The cost scanner's
    /// `daily[].date` contract is `yyyy-MM-dd`; if no row exists but a daily
    /// collection was returned, the correct current-day value is zero.
    var resolvedTodayTokens: Double? {
        resolvedToday(\.totalTokens)
    }

    var resolvedTodayCostUSD: Double? {
        resolvedToday(\.totalCost)
    }

    var sortedDaily: [CostHistoryDay] {
        (daily ?? []).sorted {
            if $0.date == $1.date { return ($0.totalTokens ?? 0) < ($1.totalTokens ?? 0) }
            return $0.date < $1.date
        }
    }

    var topModel: String? {
        var costs: [String: Double] = [:]
        var appearances: [String: Int] = [:]
        for day in daily ?? [] {
            for breakdown in day.modelBreakdowns ?? [] {
                let name = breakdown.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                costs[name, default: 0] += max(0, breakdown.cost ?? 0)
                appearances[name, default: 0] += 1
            }
            for rawName in day.modelsUsed ?? [] {
                let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                appearances[name, default: 0] += 1
            }
        }
        if let highestCost = costs
            .filter({ $0.value > 0 })
            .sorted(by: { lhs, rhs in
                lhs.value == rhs.value ? lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending : lhs.value > rhs.value
            })
            .first
        {
            return highestCost.key
        }
        return appearances.sorted(by: { lhs, rhs in
            lhs.value == rhs.value ? lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending : lhs.value > rhs.value
        }).first?.key
    }

    private func summedDaily(_ keyPath: KeyPath<CostHistoryDay, Double?>) -> Double? {
        let values = (daily ?? []).compactMap { $0[keyPath: keyPath] }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    private func resolvedToday(_ keyPath: KeyPath<CostHistoryDay, Double?>) -> Double? {
        guard daily != nil else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        let todayKey = formatter.string(from: Date())
        guard let row = sortedDaily.last(where: { String($0.date.prefix(10)) == todayKey }) else {
            return 0
        }
        return positiveOrZero(row[keyPath: keyPath]) ?? 0
    }

    private func positiveOrZero(_ value: Double?) -> Double? {
        guard let value = value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}

struct CostHistoryDay: Decodable, Hashable {
    let date: String
    let inputTokens: Double?
    let outputTokens: Double?
    let cacheReadTokens: Double?
    let cacheCreationTokens: Double?
    let totalTokens: Double?
    let totalCost: Double?
    let modelsUsed: [String]?
    let modelBreakdowns: [CostModelBreakdown]?
}

struct CostModelBreakdown: Decodable, Hashable {
    let modelName: String
    let cost: Double?
}

struct CostHistoryTotals: Decodable, Hashable {
    let inputTokens: Double?
    let outputTokens: Double?
    let cacheReadTokens: Double?
    let cacheCreationTokens: Double?
    let totalTokens: Double?
    let totalCost: Double?
}

enum CostHistoryPayloadParser {
    static func payload(provider: String, fromJSON source: String?) -> CostHistoryPayload? {
        guard let source = source, let data = source.data(using: String.Encoding.utf8),
              let root = try? JSONSerialization.jsonObject(with: data)
        else { return nil }

        var candidates: [[String: Any]] = []
        collectCandidates(in: root, provider: provider, output: &candidates)
        guard let candidate = candidates.sorted(by: { lhs, rhs in
            let left = score(lhs)
            let right = score(rhs)
            if left == right {
                return canonicalDescription(lhs) < canonicalDescription(rhs)
            }
            return left > right
        }).first,
        let candidateData = try? JSONSerialization.data(withJSONObject: candidate, options: [.sortedKeys])
        else { return nil }

        return try? JSONDecoder().decode(CostHistoryPayload.self, from: candidateData)
    }

    private static func collectCandidates(in value: Any, provider: String, output: inout [[String: Any]]) {
        if let dictionary = value as? [String: Any] {
            if let candidateProvider = dictionary["provider"] as? String,
               candidateProvider.caseInsensitiveCompare(provider) == .orderedSame,
               isCostPayload(dictionary)
            {
                output.append(dictionary)
            }
            for key in dictionary.keys.sorted() {
                if let nested = dictionary[key] {
                    collectCandidates(in: nested, provider: provider, output: &output)
                }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                collectCandidates(in: nested, provider: provider, output: &output)
            }
        }
    }

    private static func isCostPayload(_ dictionary: [String: Any]) -> Bool {
        dictionary["last30DaysTokens"] != nil ||
            dictionary["last30DaysCostUSD"] != nil ||
            dictionary["daily"] != nil ||
            dictionary["totals"] != nil
    }

    private static func score(_ dictionary: [String: Any]) -> Int {
        var result = 0
        if dictionary["last30DaysTokens"] != nil { result += 100 }
        if dictionary["last30DaysCostUSD"] != nil { result += 100 }
        if let daily = dictionary["daily"] as? [Any] { result += min(daily.count, 60) * 2 }
        if dictionary["totals"] != nil { result += 20 }
        if dictionary["sessionTokens"] != nil { result += 5 }
        return result
    }

    private static func canonicalDescription(_ dictionary: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
