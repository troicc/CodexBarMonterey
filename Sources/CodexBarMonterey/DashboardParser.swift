import Foundation

/// Converts the upstream provider JSON into the compact dashboard model used by
/// the Monterey UI. The upstream payload intentionally remains the source of
/// truth; this parser is tolerant of provider-specific fields and newer engines.
enum DashboardParser {
    static func dashboard(snapshot: ProviderSnapshot, supplementalJSON: String? = nil) -> ProviderDashboard {
        let roots = [snapshot.rawJSON, supplementalJSON]
            .compactMap { $0 }
            .compactMap(parseJSON)
        let flattened = roots.flatMap(flatten)
        let costPayload = CostHistoryPayloadParser.payload(
            provider: snapshot.provider,
            fromJSON: supplementalJSON)
        let deepSeek = snapshot.provider == "deepseek" ? deepSeekPayload(from: roots) : nil
        let zai = snapshot.provider == "zai" ? zaiPayload(from: roots) : nil
        let mimo = snapshot.provider == "mimo" ? mimoPayload(from: roots) : nil
        let localSpend = localSpendPayload(from: roots)
        let financeObservation = ProviderFinanceObservationExtractor.observation(
            provider: snapshot.provider,
            rawJSON: snapshot.rawJSON,
            supplementalJSON: supplementalJSON)
        let financeProfile = ProviderFinanceProfile.profile(for: snapshot.provider)
        let costBackedProvider = snapshot.provider == "codex" || snapshot.provider == "claude"
        let providerSpecific = snapshot.provider == "deepseek" ||
            snapshot.provider == "zai" ||
            snapshot.provider == "moonshot" ||
            snapshot.provider == "mimo"
        let genericCurrencyCode = findCurrencyCode(flattened)

        var metrics: [DashboardMetric] = []
        if let deepSeek = deepSeek {
            metrics.append(DashboardMetric(
                id: "today-tokens",
                title: "Today tokens",
                value: compact(deepSeek.todayTokens) ?? "0",
                subtitle: requestSubtitle(deepSeek.todayRequests)))
            appendCurrencyMetric(
                &metrics,
                id: "today-cost",
                title: "Today cost",
                value: deepSeek.todayCost,
                currencyCode: deepSeek.currencyCode,
                unavailableSubtitle: "DeepSeek did not return cost data")
            metrics.append(DashboardMetric(
                id: "month-tokens",
                title: "Month tokens",
                value: compact(deepSeek.monthTokens) ?? "0",
                subtitle: requestSubtitle(deepSeek.monthRequests)))
            appendCurrencyMetric(
                &metrics,
                id: "month-cost",
                title: "Month cost",
                value: deepSeek.monthCost,
                currencyCode: deepSeek.currencyCode,
                unavailableSubtitle: "DeepSeek did not return cost data")
        } else if snapshot.provider == "deepseek" {
            appendBalanceMetric(&metrics, observation: financeObservation)
            appendLocalSpendMetrics(&metrics, payload: localSpend)
            metrics.append(DashboardMetric(
                id: "deepseek-details",
                title: "Tokens & cost",
                value: "Platform only",
                subtitle: "Official details require a DeepSeek Platform session"))
        }

        if snapshot.provider == "moonshot" || snapshot.provider == "mimo" {
            appendBalanceMetric(&metrics, observation: financeObservation)
            appendLocalSpendMetrics(&metrics, payload: localSpend)
            if let mimo = mimo {
                if let tokenUsed = mimo.tokenUsed, let tokenLimit = mimo.tokenLimit, tokenLimit > 0 {
                    metrics.append(DashboardMetric(
                        id: "token-plan",
                        title: "Token plan",
                        value: "\(compact(tokenUsed) ?? decimal(tokenUsed)) / \(compact(tokenLimit) ?? decimal(tokenLimit))",
                        subtitle: mimo.planCode))
                } else if let plan = mimo.planCode, !plan.isEmpty {
                    metrics.append(DashboardMetric(id: "plan", title: "Plan", value: plan))
                }
            }
        }

        if let zai = zai {
            metrics.append(DashboardMetric(
                id: "today-tokens",
                title: "Today tokens",
                value: compact(zai.todayTokens) ?? "0"))
            metrics.append(DashboardMetric(
                id: "24h-tokens",
                title: "24h tokens",
                value: compact(zai.totalTokens) ?? "0"))
            metrics.append(DashboardMetric(
                id: "models",
                title: "Models",
                value: String(zai.modelCount)))
            metrics.append(DashboardMetric(
                id: "cost",
                title: "Cost",
                value: "Not exposed",
                subtitle: "z.ai has no monetary cost summary"))
        } else if snapshot.provider == "zai" {
            metrics.append(DashboardMetric(
                id: "hourly-tokens",
                title: "Hourly tokens",
                value: "Unavailable",
                subtitle: "No model-usage history was returned"))
            metrics.append(DashboardMetric(
                id: "cost",
                title: "Cost",
                value: "Not exposed",
                subtitle: "Quota usage cannot be converted into money"))
        }

        if let costPayload = costPayload {
            appendMetric(
                &metrics,
                id: "today-tokens",
                title: "Today tokens",
                value: compact(costPayload.resolvedTodayTokens))
            appendCostMetric(
                &metrics,
                id: "today-cost",
                title: "Today cost",
                tokens: costPayload.resolvedTodayTokens,
                cost: costPayload.resolvedTodayCostUSD)
            appendMetric(
                &metrics,
                id: "30d-tokens",
                title: "30d tokens",
                value: compact(costPayload.resolvedLast30DaysTokens))
            appendCostMetric(
                &metrics,
                id: "30d-cost",
                title: "30d cost",
                tokens: costPayload.resolvedLast30DaysTokens,
                cost: costPayload.resolvedLast30DaysCostUSD)
        }

        // Typed payloads and registered finance providers are parsed explicitly.
        // This avoids accidentally treating daily rows, quotas, or token-plan
        // credits as monetary aggregate fields.
        if !costBackedProvider && !providerSpecific {
            appendMetric(&metrics, id: "today-spend", title: "Today", value: currency(
                findNumber(flattened, aliases: [
                    "todayspend", "todaycost", "costtoday", "dailyspend", "currentdayspend"
                ]),
                code: genericCurrencyCode))
            appendMetric(&metrics, id: "7d-spend", title: "7d spend", value: currency(
                findNumber(flattened, aliases: [
                    "7dspend", "sevendayspend", "weekspend", "weeklyspend", "last7daysspend"
                ]),
                code: genericCurrencyCode))
            appendMetric(&metrics, id: "30d-spend", title: "30d spend", value: currency(
                findNumber(flattened, aliases: [
                    "30dspend", "thirtydayspend", "monthlyspend", "periodspend", "totalspend"
                ]),
                code: genericCurrencyCode))
            appendMetric(&metrics, id: "today-requests", title: "Today req", value: compact(findNumber(flattened, aliases: [
                "todayrequests", "requeststoday", "dailyrequests"
            ])))
            appendMetric(&metrics, id: "30d-tokens", title: "30d tokens", value: compact(findNumber(flattened, aliases: [
                "30dtokens", "thirtydaytokens", "periodtokens"
            ])))
            appendMetric(&metrics, id: "30d-requests", title: "30d requests", value: compact(findNumber(flattened, aliases: [
                "30drequests", "thirtydayrequests", "periodrequests"
            ])))
        }

        let quotas = mergedQuotaLanes(snapshot: snapshot, roots: roots, mimo: mimo)
        if metrics.count < 4, !providerSpecific {
            if snapshot.provider == "codex" {
                if let remaining = snapshot.credits?.remaining,
                   remaining > 0 || snapshot.credits?.hasCredits == true
                {
                    appendMetric(&metrics, id: "credits", title: "Credits", value: decimal(remaining))
                }
            } else {
                appendMetric(&metrics, id: "balance", title: "Balance", value: currency(
                    findNumber(flattened, aliases: [
                        "balance", "creditbalance", "remainingbalance", "remainingcredits", "creditsremaining"
                    ]),
                    code: genericCurrencyCode))
                appendMetric(&metrics, id: "tokens", title: "Tokens", value: compact(findNumber(flattened, aliases: [
                    "usedtokens", "tokencount", "tokenusage"
                ])))
                appendMetric(&metrics, id: "requests", title: "Requests", value: compact(findNumber(flattened, aliases: [
                    "usedrequests", "requestcount", "requestsused"
                ])))
            }
        }
        if metrics.isEmpty, let credits = snapshot.credits?.remaining, credits > 0 {
            metrics.append(DashboardMetric(title: "Credits", value: decimal(credits)))
        }
        if metrics.isEmpty, let plan = snapshot.plan, !plan.isEmpty {
            metrics.append(DashboardMetric(title: "Plan", value: plan))
        }
        if metrics.isEmpty, financeProfile.trackingMode == .quotaOnly {
            metrics.append(DashboardMetric(
                id: "quota-only",
                title: "Usage type",
                value: "Quota only",
                subtitle: "No monetary balance is exposed"))
        }

        let history: [DashboardHistoryPoint]
        let historySummary: DashboardHistorySummary?
        let topModel: String?
        if let deepSeek = deepSeek {
            history = deepSeek.history
            historySummary = DashboardHistorySummary(
                spend: deepSeek.monthCost,
                tokens: deepSeek.monthTokens,
                requests: deepSeek.monthRequests,
                currencyCode: deepSeek.currencyCode,
                spendIsEstimated: false)
            topModel = deepSeek.topModel
        } else if let zai = zai {
            history = zai.history
            historySummary = DashboardHistorySummary(
                spend: nil,
                tokens: zai.totalTokens,
                requests: nil)
            topModel = zai.topModel
        } else if let costPayload = costPayload {
            history = costHistory(costPayload)
            historySummary = DashboardHistorySummary(
                spend: costPayload.resolvedLast30DaysCostUSD,
                tokens: costPayload.resolvedLast30DaysTokens,
                requests: nil,
                currencyCode: "USD",
                spendIsEstimated: false)
            topModel = costPayload.topModel
        } else if let localSpend = localSpend {
            history = localSpend.history
            historySummary = DashboardHistorySummary(
                spend: localSpend.last30DaysSpend,
                tokens: nil,
                requests: nil,
                currencyCode: localSpend.currencyCode,
                spendIsEstimated: true)
            topModel = nil
        } else if providerSpecific {
            history = extractHistory(from: roots)
            historySummary = genericHistorySummary(history)
            topModel = nil
        } else {
            history = extractHistory(from: roots)
            historySummary = genericHistorySummary(history, currencyCode: genericCurrencyCode)
            topModel = findString(flattened, aliases: [
                "topmodel", "mostusedmodel", "leadingmodel"
            ])
        }

        let updated = snapshot.usage?.updatedAt ?? snapshot.credits?.updatedAt
        let updatedText = updated.map(relativeDate) ?? "Updated just now"
        let error = normalizedError(snapshot)

        return ProviderDashboard(
            id: snapshot.provider,
            title: snapshot.displayName,
            source: snapshot.source,
            updatedText: updatedText,
            metrics: Array(metrics.prefix(4)),
            quotas: quotas,
            history: history,
            historySummary: historySummary,
            topModel: topModel,
            errorMessage: error,
            dashboardURL: ProviderCatalog.dashboardURL(for: snapshot.provider),
            statusURL: snapshot.status?.url ?? ProviderCatalog.statusURL(for: snapshot.provider))
    }

    private struct DeepSeekPayload {
        let todayTokens: Double
        let monthTokens: Double
        let todayCost: Double?
        let monthCost: Double?
        let todayRequests: Double
        let monthRequests: Double
        let currencyCode: String?
        let topModel: String?
        let history: [DashboardHistoryPoint]
    }

    private struct ZaiPayload {
        let todayTokens: Double
        let totalTokens: Double
        let modelCount: Int
        let topModel: String?
        let history: [DashboardHistoryPoint]
    }


    private struct MiMoPayload {
        let planCode: String?
        let tokenUsed: Double?
        let tokenLimit: Double?
        let tokenPercent: Double?
    }

    private struct LocalSpendPayload {
        let currencyCode: String
        let todaySpend: Double
        let last30DaysSpend: Double
        let coverageStartedAt: Date?
        let adjustmentIntervals: Int
        let history: [DashboardHistoryPoint]
    }

    private static func deepSeekPayload(from roots: [Any]) -> DeepSeekPayload? {
        guard let usage = dictionary(named: "deepseekUsage", in: roots) else { return nil }
        let normalized = normalizedDictionary(usage)
        guard let todayTokens = firstNumber(normalized, keys: ["todaytokens"]),
              let monthTokens = firstNumber(normalized, keys: ["currentmonthtokens"]),
              let todayRequests = firstNumber(normalized, keys: ["requestcount"]),
              let monthRequests = firstNumber(normalized, keys: ["currentmonthrequestcount"])
        else { return nil }

        let rows = (normalized["daily"] as? [[String: Any]]) ?? []
        let history = rows.compactMap(historyPoint)
        return DeepSeekPayload(
            todayTokens: todayTokens,
            monthTokens: monthTokens,
            todayCost: firstNumber(normalized, keys: ["todaycost"]),
            monthCost: firstNumber(normalized, keys: ["currentmonthcost"]),
            todayRequests: todayRequests,
            monthRequests: monthRequests,
            currencyCode: ProviderFinanceParsing.normalizedCurrencyCode(normalized["currency"] as? String),
            topModel: normalized["topmodel"] as? String,
            history: Array(history.suffix(60)))
    }

    private static func mimoPayload(from roots: [Any]) -> MiMoPayload? {
        guard let usage = dictionary(named: "mimoUsage", in: roots) else { return nil }
        let normalized = normalizedDictionary(usage)
        return MiMoPayload(
            planCode: firstString(normalized, keys: ["plancode", "planname"]),
            tokenUsed: firstNumber(normalized, keys: ["tokenused", "usedtokens"]),
            tokenLimit: firstNumber(normalized, keys: ["tokenlimit", "limittokens"]),
            tokenPercent: firstNumber(normalized, keys: ["tokenpercent", "usedpercent"]))
    }

    private static func localSpendPayload(from roots: [Any]) -> LocalSpendPayload? {
        guard let payload = dictionary(named: "localSpend", in: roots) else { return nil }
        let normalized = normalizedDictionary(payload)
        guard let currency = firstString(normalized, keys: ["currency", "currencycode"])
            .flatMap(ProviderFinanceParsing.normalizedCurrencyCode),
              let today = firstNumber(normalized, keys: ["todayspend"]),
              let last30Days = firstNumber(normalized, keys: ["last30daysspend"])
        else { return nil }

        let dailyRows = normalized["daily"] as? [[String: Any]] ?? []
        let history = dailyRows.compactMap(historyPoint)
        let coverage = firstString(normalized, keys: ["coveragestartedat"])
            .flatMap(isoDate)
        let adjustments = Int(firstNumber(normalized, keys: ["adjustmentintervals"]) ?? 0)
        return LocalSpendPayload(
            currencyCode: currency,
            todaySpend: today,
            last30DaysSpend: last30Days,
            coverageStartedAt: coverage,
            adjustmentIntervals: adjustments,
            history: Array(history.suffix(180)))
    }

    private static func zaiPayload(from roots: [Any]) -> ZaiPayload? {
        guard let usage = dictionary(named: "zaiUsage", in: roots),
              let modelUsage = normalizedDictionary(usage)["modelusage"] as? [String: Any]
        else { return nil }
        let normalized = normalizedDictionary(modelUsage)
        let times = normalized["xtime"] as? [String] ?? []
        let rows = normalized["modeldatalist"] as? [[String: Any]] ?? []
        guard !times.isEmpty, !rows.isEmpty else { return nil }

        var hourly = Array(repeating: 0.0, count: times.count)
        var totalsByModel: [String: Double] = [:]
        for row in rows {
            let item = normalizedDictionary(row)
            let name = (item["modelname"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let model = (name?.isEmpty == false ? name : nil) ?? "Unknown"
            let values = item["tokensusage"] as? [Any] ?? []
            var modelTotal = 0.0
            for index in times.indices where index < values.count {
                guard let value = numberValue(values[index]), value > 0 else { continue }
                hourly[index] += value
                modelTotal += value
            }
            totalsByModel[model, default: 0] += modelTotal
        }

        let history = times.indices.map { index in
            DashboardHistoryPoint(label: zaiHistoryLabel(times[index]), tokens: hourly[index])
        }
        let todayTokens = zip(times, hourly).reduce(0.0) { partial, pair in
            guard let date = zaiHourDate(pair.0), Calendar.current.isDateInToday(date) else { return partial }
            return partial + pair.1
        }
        let totalTokens = hourly.reduce(0, +)
        let topModel = totalsByModel.max(by: { $0.value < $1.value })?.key
        return ZaiPayload(
            todayTokens: todayTokens,
            totalTokens: totalTokens,
            modelCount: totalsByModel.keys.filter { $0 != "Unknown" }.count,
            topModel: topModel,
            history: Array(history.suffix(48)))
    }

    private static func dictionary(named name: String, in roots: [Any]) -> [String: Any]? {
        let target = normalize(name)
        func visit(_ value: Any) -> [String: Any]? {
            if let dictionary = value as? [String: Any] {
                for key in dictionary.keys.sorted() where normalize(key) == target {
                    if let match = dictionary[key] as? [String: Any] { return match }
                }
                for key in dictionary.keys.sorted() {
                    if let nested = dictionary[key], let match = visit(nested) { return match }
                }
            } else if let array = value as? [Any] {
                for nested in array {
                    if let match = visit(nested) { return match }
                }
            }
            return nil
        }
        for root in roots {
            if let match = visit(root) { return match }
        }
        return nil
    }

    private static func normalizedDictionary(_ dictionary: [String: Any]) -> [String: Any] {
        var normalized: [String: Any] = [:]
        for (key, value) in dictionary { normalized[normalize(key)] = value }
        return normalized
    }

    private static func firstString(_ dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys.map(normalize) {
            if let value = dictionary[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return value
            }
        }
        return nil
    }

    private static func isoDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func zaiHourDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)
    }

    private static func zaiHistoryLabel(_ value: String) -> String {
        guard let date = zaiHourDate(value) else { return String(value.suffix(5)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "MMM d HH:mm"
        return formatter.string(from: date)
    }

    private static func requestSubtitle(_ value: Double) -> String? {
        guard value > 0, let formatted = compact(value) else { return nil }
        return "\(formatted) requests"
    }

    private struct FlatValue {
        let path: String
        let value: Any
    }

    private static func parseJSON(_ source: String) -> Any? {
        guard let data = source.data(using: String.Encoding.utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func flatten(_ root: Any) -> [FlatValue] {
        var output: [FlatValue] = []
        func visit(_ value: Any, path: String) {
            if let dictionary = value as? [String: Any] {
                for key in dictionary.keys.sorted() {
                    guard let nested = dictionary[key] else { continue }
                    visit(nested, path: path.isEmpty ? key : "\(path).\(key)")
                }
            } else if let array = value as? [Any] {
                for (index, nested) in array.enumerated() {
                    visit(nested, path: "\(path)[\(index)]")
                }
            } else {
                output.append(FlatValue(path: normalize(path), value: value))
            }
        }
        visit(root, path: "")
        return output
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func findNumber(_ values: [FlatValue], aliases: [String]) -> Double? {
        for alias in aliases.map(normalize) {
            let matches = values
                .filter { $0.path.hasSuffix(alias) || $0.path.contains(alias) }
                .sorted { lhs, rhs in
                    let leftRank = lhs.path.hasSuffix(alias) ? 0 : 1
                    let rightRank = rhs.path.hasSuffix(alias) ? 0 : 1
                    if leftRank == rightRank {
                        if lhs.path.count == rhs.path.count { return lhs.path < rhs.path }
                        return lhs.path.count < rhs.path.count
                    }
                    return leftRank < rightRank
                }
            for match in matches {
                if let number = numberValue(match.value) { return number }
            }
        }
        return nil
    }

    private static func findString(_ values: [FlatValue], aliases: [String]) -> String? {
        for alias in aliases.map(normalize) {
            let matches = values
                .filter { $0.path.hasSuffix(alias) || $0.path.contains(alias) }
                .sorted { lhs, rhs in
                    let leftRank = lhs.path.hasSuffix(alias) ? 0 : 1
                    let rightRank = rhs.path.hasSuffix(alias) ? 0 : 1
                    if leftRank == rightRank {
                        if lhs.path.count == rhs.path.count { return lhs.path < rhs.path }
                        return lhs.path.count < rhs.path.count
                    }
                    return leftRank < rightRank
                }
            for match in matches {
                if let string = match.value as? String, !string.isEmpty { return string }
            }
        }
        return nil
    }

    private static func findCurrencyCode(_ values: [FlatValue]) -> String? {
        let currencyPaths = ["currency", "currencycode", "billingcurrency"]
        for path in currencyPaths {
            if let raw = findString(values, aliases: [path]),
               let code = ProviderFinanceParsing.normalizedCurrencyCode(raw)
            {
                return code
            }
        }
        for value in values {
            if let text = value.value as? String,
               let code = ProviderFinanceParsing.currencyCode(in: text)
            {
                return code
            }
        }
        return nil
    }

    private static func numberValue(_ value: Any) -> Double? {
        ProviderFinanceParsing.numberValue(value)
    }

    private static func costHistory(_ payload: CostHistoryPayload) -> [DashboardHistoryPoint] {
        payload.sortedDaily.suffix(60).map { day in
            DashboardHistoryPoint(
                label: formatHistoryLabel(day.date),
                spend: day.totalCost,
                tokens: day.totalTokens,
                requests: nil)
        }
    }

    private static func genericHistorySummary(
        _ history: [DashboardHistoryPoint],
        currencyCode: String? = nil
    ) -> DashboardHistorySummary? {
        guard !history.isEmpty else { return nil }
        let spendValues = history.compactMap { $0.spend }
        let tokenValues = history.compactMap { $0.tokens }
        let requestValues = history.compactMap { $0.requests }
        return DashboardHistorySummary(
            spend: spendValues.isEmpty ? nil : spendValues.reduce(0, +),
            tokens: tokenValues.isEmpty ? nil : tokenValues.reduce(0, +),
            requests: requestValues.isEmpty ? nil : requestValues.reduce(0, +),
            currencyCode: currencyCode,
            spendIsEstimated: false)
    }

    private static func extractHistory(from roots: [Any]) -> [DashboardHistoryPoint] {
        var candidates: [[DashboardHistoryPoint]] = []
        func visit(_ value: Any) {
            if let array = value as? [[String: Any]], !array.isEmpty {
                let points = array.compactMap(historyPoint)
                if !points.isEmpty { candidates.append(points) }
                for item in array { visit(item) }
            } else if let dictionary = value as? [String: Any] {
                for key in dictionary.keys.sorted() {
                    if let nested = dictionary[key] { visit(nested) }
                }
            } else if let array = value as? [Any] {
                for nested in array { visit(nested) }
            }
        }
        for root in roots { visit(root) }
        return candidates.max(by: { score($0) < score($1) }).map { Array($0.suffix(60)) } ?? []
    }

    private static func score(_ points: [DashboardHistoryPoint]) -> Int {
        points.count * 10 + points.reduce(0) { partial, point in
            partial + (point.spend == nil ? 0 : 3) + (point.tokens == nil ? 0 : 2) + (point.requests == nil ? 0 : 1)
        }
    }

    private static func historyPoint(_ row: [String: Any]) -> DashboardHistoryPoint? {
        var normalized: [String: Any] = [:]
        for (key, value) in row { normalized[normalize(key)] = value }
        let dateValue = firstValue(normalized, keys: ["date", "day", "label", "startdate", "timestamp", "hour", "period"])
        guard let dateValue = dateValue else { return nil }
        let label = formatHistoryLabel(dateValue)
        let spend = firstNumber(normalized, keys: ["spend", "cost", "amount", "totalcost", "usd"])
        let tokens = firstNumber(normalized, keys: ["tokens", "totaltokens", "tokenusage"])
        let requests = firstNumber(normalized, keys: ["requests", "requestcount", "totalrequests"])
        guard spend != nil || tokens != nil || requests != nil else { return nil }
        return DashboardHistoryPoint(label: label, spend: spend, tokens: tokens, requests: requests)
    }

    private static func firstValue(_ row: [String: Any], keys: [String]) -> Any? {
        for key in keys {
            if let value = row[key] { return value }
        }
        return nil
    }

    private static func firstNumber(_ row: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = row[key], let number = numberValue(value) { return number }
        }
        return nil
    }

    private static func formatHistoryLabel(_ value: Any) -> String {
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            let seconds = raw > 10_000_000_000 ? raw / 1000 : raw
            return shortDate(Date(timeIntervalSince1970: seconds))
        }
        let string = String(describing: value)
        for formatter in JSONCoding.historyDateFormatters {
            if let date = formatter.date(from: string) { return shortDate(date) }
        }
        return String(string.prefix(12))
    }

    private static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private static func relativeDate(_ date: Date) -> String {
        let interval = abs(date.timeIntervalSinceNow)
        if interval < 60 { return "Updated just now" }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = interval >= 3600 ? [.hour] : [.minute]
        return formatter.string(from: interval).map { "Updated \($0) ago" } ?? "Updated recently"
    }

    private static func mergedQuotaLanes(
        snapshot: ProviderSnapshot,
        roots: [Any],
        mimo: MiMoPayload?
    ) -> [DashboardQuotaLane] {
        if snapshot.provider == "deepseek" { return [] }
        var lanes = quotaLanes(snapshot)
        var seen = Set(lanes.map { normalize($0.title) })

        if let percent = mimo?.tokenPercent {
            let title = "Token plan"
            lanes.append(DashboardQuotaLane(
                id: "mimo-token-plan",
                title: title,
                usedPercent: max(0, min(100, percent)),
                resetText: mimo?.planCode))
            seen.insert(normalize(title))
        }

        for root in roots {
            for lane in extractQuotaLanes(root) where !seen.contains(normalize(lane.title)) {
                lanes.append(lane)
                seen.insert(normalize(lane.title))
            }
        }
        return Array(lanes.prefix(8))
    }

    private static func quotaLanes(_ snapshot: ProviderSnapshot) -> [DashboardQuotaLane] {
        let windows = [snapshot.usage?.primary, snapshot.usage?.secondary, snapshot.usage?.tertiary].compactMap { $0 }
        return windows.enumerated().map { index, window in
            DashboardQuotaLane(
                id: "\(index)-\(window.displayLabel)",
                title: window.displayLabel,
                usedPercent: max(0, min(100, window.usedPercent ?? 0)),
                resetText: window.resetText)
        }
    }

    private static func extractQuotaLanes(_ root: Any) -> [DashboardQuotaLane] {
        var lanes: [DashboardQuotaLane] = []
        func visit(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                var normalized: [String: Any] = [:]
                for (key, nested) in dictionary { normalized[normalize(key)] = nested }
                if let used = firstNumber(normalized, keys: ["usedpercent", "percentused", "usagepercent", "tokenpercent"]) {
                    let titleValue = firstValue(normalized, keys: ["title", "label", "name", "windowlabel", "metric"])
                    let minutes = firstNumber(normalized, keys: ["windowminutes", "minutes", "durationminutes"])
                    let title: String
                    if let titleValue = titleValue {
                        title = String(describing: titleValue)
                    } else if let minutes = minutes {
                        title = windowLabel(minutes: minutes)
                    } else {
                        title = "Quota"
                    }
                    let resetValue = firstValue(normalized, keys: ["resetdescription", "resettext", "resetsat", "resetat"])
                    let reset = resetValue.map { String(describing: $0) }
                    lanes.append(DashboardQuotaLane(
                        id: "raw-\(lanes.count)-\(normalize(title))",
                        title: title,
                        usedPercent: max(0, min(100, used)),
                        resetText: reset))
                }
                for key in dictionary.keys.sorted() {
                    if let nested = dictionary[key] { visit(nested) }
                }
            } else if let array = value as? [Any] {
                for nested in array { visit(nested) }
            }
        }
        visit(root)
        return lanes
    }

    private static func windowLabel(minutes: Double) -> String {
        if abs(minutes - 300) < 1 { return "5 hours" }
        if abs(minutes - 1440) < 1 { return "Daily" }
        if abs(minutes - 10080) < 1 { return "Weekly" }
        if abs(minutes - 43200) < 60 { return "Monthly" }
        if minutes >= 1440 { return "\(Int(minutes / 1440)) days" }
        if minutes >= 60 { return "\(Int(minutes / 60)) hours" }
        return "\(Int(minutes)) minutes"
    }

    private static func normalizedError(_ snapshot: ProviderSnapshot) -> String? {
        guard let message = snapshot.error?.message else { return nil }
        if snapshot.provider == "zai", message.localizedCaseInsensitiveContains("No available fetch strategy") {
            return "z.ai needs an API token. Open Settings, select z.ai, paste the token, then save and verify."
        }
        return message
    }

    private static func appendBalanceMetric(
        _ metrics: inout [DashboardMetric],
        observation: ProviderBalanceObservation?
    ) {
        guard let observation = observation else { return }
        var breakdown: [String] = []
        if let paid = observation.paid,
           let formatted = currency(paid, code: observation.currencyCode)
        {
            breakdown.append("Paid \(formatted)")
        }
        if let granted = observation.granted,
           let formatted = currency(granted, code: observation.currencyCode)
        {
            breakdown.append("Granted \(formatted)")
        }
        metrics.append(DashboardMetric(
            id: "balance",
            title: "Balance",
            value: currency(observation.total, code: observation.currencyCode) ?? decimal(observation.total),
            subtitle: breakdown.isEmpty ? nil : breakdown.joined(separator: " · ")))
    }

    private static func appendLocalSpendMetrics(
        _ metrics: inout [DashboardMetric],
        payload: LocalSpendPayload?
    ) {
        guard let payload = payload else { return }
        var subtitle = payload.coverageStartedAt.map { "Estimated locally since \(shortDate($0))" }
            ?? "Estimated locally"
        if payload.adjustmentIntervals > 0 {
            subtitle += " · \(payload.adjustmentIntervals) adjustment interval"
            if payload.adjustmentIntervals != 1 { subtitle += "s" }
            subtitle += " excluded"
        }
        metrics.append(DashboardMetric(
            id: "today-spend-estimate",
            title: "Today est.",
            value: currency(payload.todaySpend, code: payload.currencyCode) ?? decimal(payload.todaySpend),
            subtitle: subtitle))
        metrics.append(DashboardMetric(
            id: "30d-spend-estimate",
            title: "30d est.",
            value: currency(payload.last30DaysSpend, code: payload.currencyCode) ?? decimal(payload.last30DaysSpend),
            subtitle: "Balance-delta estimate"))
    }

    private static func appendCostMetric(
        _ metrics: inout [DashboardMetric],
        id: String,
        title: String,
        tokens: Double?,
        cost: Double?,
        currencyCode: String = "USD")
    {
        guard let tokens = tokens, tokens > 0 else { return }
        if let cost = cost, cost > 0 {
            appendMetric(&metrics, id: id, title: title, value: currency(cost, code: currencyCode))
        } else {
            metrics.append(DashboardMetric(
                id: id,
                title: title,
                value: "—",
                subtitle: "Pricing unavailable"))
        }
    }

    private static func appendCurrencyMetric(
        _ metrics: inout [DashboardMetric],
        id: String,
        title: String,
        value: Double?,
        currencyCode: String?,
        unavailableSubtitle: String)
    {
        if let value = value {
            metrics.append(DashboardMetric(
                id: id,
                title: title,
                value: currency(value, code: currencyCode) ?? decimal(value)))
        } else {
            metrics.append(DashboardMetric(
                id: id,
                title: title,
                value: "—",
                subtitle: unavailableSubtitle))
        }
    }

    private static func appendMetric(_ metrics: inout [DashboardMetric], id: String, title: String, value: String?) {
        guard let value = value, !value.isEmpty else { return }
        metrics.append(DashboardMetric(id: id, title: title, value: value))
    }

    private static func currency(_ value: Double?, code: String?) -> String? {
        guard let value = value else { return nil }
        guard let code = ProviderFinanceParsing.normalizedCurrencyCode(code) else {
            return decimal(value)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value))
            ?? "\(code) \(String(format: "%.2f", value))"
    }

    private static func compact(_ value: Double?) -> String? {
        guard let value = value else { return nil }
        let absolute = abs(value)
        if absolute >= 1_000_000_000 { return String(format: "%.1fB", value / 1_000_000_000) }
        if absolute >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if absolute >= 1_000 { return String(format: "%.1fK", value / 1_000) }
        return String(format: value.rounded() == value ? "%.0f" : "%.1f", value)
    }

    private static func decimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

extension JSONCoding {
    static let historyDateFormatters: [DateFormatter] = {
        let formats = ["yyyy-MM-dd", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZ", "MMM d"]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return formatter
        }
    }()
}
