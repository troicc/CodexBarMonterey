import Foundation

enum SpendTrackingMode: String, Codable {
    case officialHistory
    case prepaidBalanceDelta
    case quotaOnly
    case unavailable
}

struct ProviderFinanceProfile: Hashable {
    let trackingMode: SpendTrackingMode
    let supportsBalanceBreakdown: Bool

    static func profile(for provider: String) -> ProviderFinanceProfile {
        switch provider.lowercased() {
        case "deepseek", "moonshot", "mimo":
            return ProviderFinanceProfile(
                trackingMode: .prepaidBalanceDelta,
                supportsBalanceBreakdown: true)
        case "kimi", "zai", "qwen", "qwencloud", "alibaba", "alibabatokenplan":
            return ProviderFinanceProfile(
                trackingMode: .quotaOnly,
                supportsBalanceBreakdown: false)
        case "codex", "claude":
            return ProviderFinanceProfile(
                trackingMode: .officialHistory,
                supportsBalanceBreakdown: false)
        default:
            return ProviderFinanceProfile(
                trackingMode: .unavailable,
                supportsBalanceBreakdown: false)
        }
    }
}

struct ProviderBalanceObservation: Codable, Hashable {
    let total: Double
    let paid: Double?
    let granted: Double?
    let currencyCode: String

    init?(total: Double, paid: Double?, granted: Double?, currencyCode: String) {
        let normalizedCurrency = ProviderFinanceParsing.normalizedCurrencyCode(currencyCode)
        guard total.isFinite,
              total >= 0,
              let normalizedCurrency = normalizedCurrency,
              !normalizedCurrency.isEmpty
        else { return nil }

        self.total = total
        self.paid = paid.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.granted = granted.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.currencyCode = normalizedCurrency
    }
}

enum ProviderFinanceObservationExtractor {
    static func observation(
        provider: String,
        rawJSON: String?,
        supplementalJSON: String? = nil
    ) -> ProviderBalanceObservation? {
        let profile = ProviderFinanceProfile.profile(for: provider)
        guard profile.trackingMode == .prepaidBalanceDelta else { return nil }

        let roots = [rawJSON, supplementalJSON]
            .compactMap { $0 }
            .compactMap(ProviderFinanceParsing.parseJSON)

        switch provider.lowercased() {
        case "mimo":
            if let observation = mimoObservation(in: roots) { return observation }
        case "deepseek":
            if let observation = deepSeekObservation(in: roots) { return observation }
        case "moonshot":
            if let observation = moonshotObservation(in: roots) { return observation }
        default:
            break
        }

        return standardizedBalanceObservation(in: roots)
    }

    private static func mimoObservation(in roots: [Any]) -> ProviderBalanceObservation? {
        guard let usage = ProviderFinanceParsing.dictionary(named: "mimoUsage", in: roots) else {
            return nil
        }
        let normalized = ProviderFinanceParsing.normalizedDictionary(usage)
        guard let total = ProviderFinanceParsing.firstNumber(normalized, keys: ["balance", "totalbalance", "availablebalance"]),
              let currency = ProviderFinanceParsing.firstString(normalized, keys: ["currency", "currencycode"])
        else { return nil }

        return ProviderBalanceObservation(
            total: total,
            paid: ProviderFinanceParsing.firstNumber(normalized, keys: ["cashbalance", "paidbalance", "toppedupbalance"]),
            granted: ProviderFinanceParsing.firstNumber(normalized, keys: ["giftbalance", "grantedbalance", "voucherbalance"]),
            currencyCode: currency)
    }

    private static func deepSeekObservation(in roots: [Any]) -> ProviderBalanceObservation? {
        // Prefer the provider's normalized display string when present. A raw
        // /user/balance response can contain multiple currencies and must never
        // be summed or silently converted.
        if let standardized = standardizedBalanceObservation(in: roots) {
            return standardized
        }
        if let direct = ProviderFinanceParsing.findDictionary(
            in: roots,
            requiringAnyKey: ["total_balance", "totalBalance"],
            currencyKeys: ["currency"])
        {
            let normalized = ProviderFinanceParsing.normalizedDictionary(direct)
            if let total = ProviderFinanceParsing.firstNumber(normalized, keys: ["totalbalance"]),
               let currency = ProviderFinanceParsing.firstString(normalized, keys: ["currency"])
            {
                return ProviderBalanceObservation(
                    total: total,
                    paid: ProviderFinanceParsing.firstNumber(normalized, keys: ["toppedupbalance", "paidbalance"]),
                    granted: ProviderFinanceParsing.firstNumber(normalized, keys: ["grantedbalance", "giftbalance"]),
                    currencyCode: currency)
            }
        }
        return nil
    }

    private static func moonshotObservation(in roots: [Any]) -> ProviderBalanceObservation? {
        if let direct = ProviderFinanceParsing.findDictionary(
            in: roots,
            requiringAnyKey: ["availableBalance", "available_balance"],
            currencyKeys: ["currency", "currencyCode"])
        {
            let normalized = ProviderFinanceParsing.normalizedDictionary(direct)
            if let total = ProviderFinanceParsing.firstNumber(normalized, keys: ["availablebalance"]),
               let currency = ProviderFinanceParsing.firstString(normalized, keys: ["currency", "currencycode"])
            {
                return ProviderBalanceObservation(
                    total: total,
                    paid: ProviderFinanceParsing.firstNumber(normalized, keys: ["cashbalance", "paidbalance"]),
                    granted: ProviderFinanceParsing.firstNumber(normalized, keys: ["voucherbalance", "grantedbalance"]),
                    currencyCode: currency)
            }
        }
        return standardizedBalanceObservation(in: roots)
    }

    private static func standardizedBalanceObservation(in roots: [Any]) -> ProviderBalanceObservation? {
        let candidates = ProviderFinanceParsing.strings(in: roots)
            .filter { value in
                let lower = value.lowercased()
                return lower.contains("balance") ||
                    lower.contains("paid:") ||
                    lower.contains("granted:") ||
                    lower.contains("cash:") ||
                    lower.contains("voucher:")
            }

        for candidate in candidates {
            if let observation = ProviderFinanceParsing.balanceObservation(from: candidate) {
                return observation
            }
        }
        return nil
    }
}

enum ProviderFinanceParsing {
    static func parseJSON(_ source: String) -> Any? {
        guard let data = source.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    static func normalize(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func normalizedDictionary(_ dictionary: [String: Any]) -> [String: Any] {
        var output: [String: Any] = [:]
        for (key, value) in dictionary { output[normalize(key)] = value }
        return output
    }

    static func dictionary(named name: String, in roots: [Any]) -> [String: Any]? {
        let target = normalize(name)
        func visit(_ value: Any) -> [String: Any]? {
            if let dictionary = value as? [String: Any] {
                for (key, nested) in dictionary where normalize(key) == target {
                    if let match = nested as? [String: Any] { return match }
                }
                for nested in dictionary.values {
                    if let match = visit(nested) { return match }
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

    static func findDictionary(
        in roots: [Any],
        requiringAnyKey keys: [String],
        currencyKeys: [String]
    ) -> [String: Any]? {
        let required = Set(keys.map(normalize))
        let currencies = Set(currencyKeys.map(normalize))

        func visit(_ value: Any) -> [String: Any]? {
            if let dictionary = value as? [String: Any] {
                let normalizedKeys = Set(dictionary.keys.map(normalize))
                if !required.isDisjoint(with: normalizedKeys),
                   !currencies.isDisjoint(with: normalizedKeys)
                {
                    return dictionary
                }
                for nested in dictionary.values {
                    if let match = visit(nested) { return match }
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

    static func strings(in roots: [Any]) -> [String] {
        var output: [String] = []
        func visit(_ value: Any) {
            if let string = value as? String {
                output.append(string)
            } else if let dictionary = value as? [String: Any] {
                for nested in dictionary.values { visit(nested) }
            } else if let array = value as? [Any] {
                for nested in array { visit(nested) }
            }
        }
        for root in roots { visit(root) }
        return output
    }

    static func firstNumber(_ dictionary: [String: Any], keys: [String]) -> Double? {
        for key in keys.map(normalize) {
            if let value = dictionary[key], let number = numberValue(value) { return number }
        }
        return nil
    }

    static func firstString(_ dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys.map(normalize) {
            guard let value = dictionary[key] else { continue }
            if let string = value as? String, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return string
            }
        }
        return nil
    }

    static func numberValue(_ value: Any) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String {
            return firstDecimal(in: string)
        }
        if let dictionary = value as? [String: Any] {
            let normalized = normalizedDictionary(dictionary)
            return firstNumber(normalized, keys: ["value", "amount", "total", "balance"])
        }
        return nil
    }

    static func normalizedCurrencyCode(_ raw: String?) -> String? {
        guard let raw = raw else { return nil }
        let upper = raw.uppercased().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if upper.contains("CNY") || upper.contains("RMB") || upper.contains("CN¥") || upper == "¥" || upper == "￥" {
            return "CNY"
        }
        if upper.contains("USD") || upper.contains("US$") || upper == "$" {
            return "USD"
        }
        let letters = upper.filter { $0.isLetter }
        return letters.count == 3 ? letters : nil
    }

    static func currencyCode(in text: String) -> String? {
        let upper = text.uppercased()
        if upper.contains("CNY") || upper.contains("RMB") || text.contains("¥") || text.contains("￥") {
            return "CNY"
        }
        if upper.contains("USD") || upper.contains("US$") || text.contains("$") {
            return "USD"
        }
        return nil
    }

    static func balanceObservation(from text: String) -> ProviderBalanceObservation? {
        guard let currency = currencyCode(in: text) else { return nil }

        let total = labeledDecimal(
            in: text,
            labels: ["balance", "total", "available"],
            fallbackToFirst: true)
        guard let total = total else { return nil }

        let paid = labeledDecimal(
            in: text,
            labels: ["paid", "cash", "topped up", "topped_up", "top up"],
            fallbackToFirst: false)
        let granted = labeledDecimal(
            in: text,
            labels: ["granted", "gift", "voucher", "bonus"],
            fallbackToFirst: false)
        return ProviderBalanceObservation(
            total: total,
            paid: paid,
            granted: granted,
            currencyCode: currency)
    }

    private static func labeledDecimal(
        in text: String,
        labels: [String],
        fallbackToFirst: Bool
    ) -> Double? {
        for label in labels {
            let escaped = NSRegularExpression.escapedPattern(for: label)
            let pattern = "(?i)\\b\(escaped)\\b\\s*[:=]?\\s*(?:CNY|RMB|USD|US\\$|CN¥|[¥￥$])?\\s*([-+]?[0-9][0-9,]*(?:\\.[0-9]+)?)"
            if let value = firstCapture(pattern: pattern, in: text).flatMap(decimalValue) {
                return value
            }
        }
        return fallbackToFirst ? firstDecimal(in: text) : nil
    }

    static func firstDecimal(in text: String) -> Double? {
        let pattern = "[-+]?[0-9][0-9,]*(?:\\.[0-9]+)?"
        guard let match = firstCapture(pattern: pattern, in: text, captureGroup: 0) else { return nil }
        return decimalValue(match)
    }

    private static func decimalValue(_ raw: String) -> Double? {
        Double(raw.replacingOccurrences(of: ",", with: ""))
    }

    private static func firstCapture(
        pattern: String,
        in text: String,
        captureGroup: Int = 1
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              captureGroup < match.numberOfRanges,
              let captureRange = Range(match.range(at: captureGroup), in: text)
        else { return nil }
        return String(text[captureRange])
    }
}
