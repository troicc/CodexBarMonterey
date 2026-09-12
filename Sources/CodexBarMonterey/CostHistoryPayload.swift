import Foundation

/// Typed representation of `codexbar cost --format json`.
///
/// Dashboard code must not discover aggregate values by recursively searching
/// for names such as `totalTokens`: that key also occurs in every daily row and
/// dictionary iteration order is not a stable data contract. This type keeps
/// the selected-window aggregate, daily history, and model summary separate.
struct CostHistoryPayload: Codable, Hashable {
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
        if let daily = daily {
            return Self.completeSum(daily.map(\.resolvedCost))
        }
        return positiveOrZero(last30DaysCostUSD) ?? positiveOrZero(totals?.totalCost)
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

    var todayCostEstimate: CostEstimateSummary { costEstimate(dayCount: 1) }
    var last30DaysCostEstimate: CostEstimateSummary { costEstimate(dayCount: 30) }

    func costEstimate(dayCount: Int, now: Date = Date(), calendar: Calendar = .current) -> CostEstimateSummary {
        guard daily != nil else {
            return CostEstimateSummary(knownCost: dayCount == 30 ? resolvedLast30DaysCostUSD : nil,
                unpricedModels: [], hasUnattributedCost: true)
        }
        return CostEstimateSummary(days: days(inLast: dayCount, now: now, calendar: calendar))
    }

    /// Ranking is by token volume, independent of price availability.
    var topModel: String? { topModel(dayCount: 10) }

    func topModel(dayCount: Int, now: Date = Date(), calendar: Calendar = .current) -> String? {
        var totals: [String: Double] = [:]
        for day in days(inLast: dayCount, now: now, calendar: calendar) {
            guard let rows = day.reconciledModels else {
                if day.totalTokens != 0 { return nil }
                continue
            }
            for row in rows {
                let name = row.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, let tokens = row.totalTokens, tokens.isFinite, tokens >= 0 else { return nil }
                totals[name, default: 0] += tokens
            }
        }
        return totals.filter { $0.value > 0 }.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }.first?.key
    }

    private func days(inLast count: Int, now: Date, calendar: Calendar) -> [CostHistoryDay] {
        guard count > 0,
              let cutoff = calendar.date(byAdding: .day, value: 1 - count, to: calendar.startOfDay(for: now))
        else { return [] }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return sortedDaily.filter { day in
            guard let date = formatter.date(from: day.date) else { return false }
            return date >= cutoff && date <= now
        }
    }

    /// Local client logs identify models, not the billing endpoint or account.
    /// Exclude third-party/ambiguous rows from the Claude model view.
    var claudeModelHistory: CostHistoryPayload {
        guard provider == "claude" else { return self }
        let days = sortedDaily.compactMap { $0.selectingModels { Self.isClaudeModel($0) } }
        return CostHistoryPayload(provider: provider, source: source, updatedAt: updatedAt,
            sessionTokens: nil, sessionCostUSD: nil,
            last30DaysTokens: days.reduce(0) { $0 + ($1.totalTokens ?? 0) },
            last30DaysCostUSD: Self.completeSum(days.map(\.totalCost)), daily: days, totals: nil)
    }

    static func isClaudeModel(_ model: String) -> Bool {
        model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("claude-")
    }

    static func completeSum(_ values: [Double?]) -> Double? {
        guard values.allSatisfy({ $0 != nil && $0!.isFinite && $0! >= 0 }) else { return nil }
        return values.compactMap { $0 }.reduce(0, +)
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
        if keyPath == \CostHistoryDay.totalCost { return row.resolvedCost }
        return positiveOrZero(row[keyPath: keyPath])
    }

    private func positiveOrZero(_ value: Double?) -> Double? {
        guard let value = value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}

struct CostHistoryDay: Codable, Hashable {
    let date: String
    let inputTokens: Double?
    let outputTokens: Double?
    let cacheReadTokens: Double?
    let cacheCreationTokens: Double?
    let totalTokens: Double?
    let totalCost: Double?
    let modelsUsed: [String]?
    let modelBreakdowns: [CostModelBreakdown]?

    var resolvedCost: Double? {
        if let rows = reconciledModels, modelBreakdowns?.isEmpty == false {
            return CostHistoryPayload.completeSum(rows.map(\.cost))
        }
        return totalCost
    }

    /// Only use a breakdown when it reconciles with the daily total. A model
    /// name list alone cannot partition a mixed day.
    var reconciledModels: [CostModelBreakdown]? {
        if let rows = modelBreakdowns, !rows.isEmpty,
           let sum = CostHistoryPayload.completeSum(rows.map(\.totalTokens)),
           let total = totalTokens, abs(sum - total) < 0.5 {
            return rows
        }
        if let names = modelsUsed, names.count == 1, let total = totalTokens {
            return [CostModelBreakdown(modelName: names[0], cost: totalCost, totalTokens: total)]
        }
        return nil
    }

    func selectingModels(_ include: (String) -> Bool) -> CostHistoryDay? {
        guard let rows = reconciledModels else {
            let names = modelsUsed ?? []
            return !names.isEmpty && names.allSatisfy(include) ? self : nil
        }
        let selected = rows.filter { include($0.modelName) }
        guard !selected.isEmpty else { return nil }
        if selected.count == rows.count { return self }
        return CostHistoryDay(date: date, inputTokens: nil, outputTokens: nil,
            cacheReadTokens: nil, cacheCreationTokens: nil,
            totalTokens: selected.compactMap(\.totalTokens).reduce(0, +),
            totalCost: CostHistoryPayload.completeSum(selected.map(\.cost)),
            modelsUsed: selected.map(\.modelName), modelBreakdowns: selected)
    }
}

struct CostModelBreakdown: Codable, Hashable {
    let modelName: String
    let cost: Double?
    var totalTokens: Double? = nil
}

struct CostHistoryTotals: Codable, Hashable {
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

/// A lower-bound estimate preserves known prices without treating unpriced
/// models as free. Complete cost accessors remain nil for incomplete periods.
struct CostEstimateSummary: Hashable {
    let knownCost: Double?
    let unpricedModels: [String]
    let hasUnattributedCost: Bool

    var isPartial: Bool { !unpricedModels.isEmpty || hasUnattributedCost }

    init(knownCost: Double?, unpricedModels: [String], hasUnattributedCost: Bool) {
        self.knownCost = knownCost
        self.unpricedModels = unpricedModels
        self.hasUnattributedCost = hasUnattributedCost
    }

    init(days: [CostHistoryDay]) {
        var sum: Double = 0
        var known = days.isEmpty
        var missing = Set<String>()
        var unattributed = false
        for day in days {
            if let cost = day.resolvedCost, cost.isFinite, cost >= 0 {
                sum += cost
                known = true
            } else if let rows = day.reconciledModels {
                for row in rows {
                    if let cost = row.cost, cost.isFinite, cost >= 0 {
                        sum += cost
                        known = true
                    } else if row.totalTokens != 0 {
                        missing.insert(row.modelName)
                    }
                }
            } else {
                unattributed = true
                missing.formUnion(day.modelsUsed ?? [])
            }
        }
        knownCost = known ? sum : nil
        unpricedModels = missing.sorted()
        hasUnattributedCost = unattributed
    }
}
