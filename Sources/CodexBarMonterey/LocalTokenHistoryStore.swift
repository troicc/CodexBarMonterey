import Foundation

enum TokenHistoryRange: String, CaseIterable, Identifiable, Codable {
    case day
    case week
    case thirtyDays
    case ninetyDays
    case year
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "24h"
        case .week: return "7d"
        case .thirtyDays: return "30d"
        case .ninetyDays: return "90d"
        case .year: return "1y"
        case .all: return "All"
        }
    }

    fileprivate func cutoff(now: Date, calendar: Calendar) -> Date? {
        switch self {
        case .day:
            return now.addingTimeInterval(-24 * 60 * 60)
        case .week:
            return calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))
        case .thirtyDays:
            return calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now))
        case .ninetyDays:
            return calendar.date(byAdding: .day, value: -89, to: calendar.startOfDay(for: now))
        case .year:
            return calendar.date(byAdding: .day, value: -364, to: calendar.startOfDay(for: now))
        case .all:
            return nil
        }
    }
}

enum TokenHistoryBucket: String, Codable, Hashable {
    case hour
    case day
}

struct TokenHistoryRecord: Codable, Hashable, Identifiable {
    let providerID: String
    let providerName: String
    let accountID: String
    let accountLabel: String?
    let timestamp: Date
    let bucket: TokenHistoryBucket
    let model: String?
    let modelsUsed: [String]?
    let inputTokens: Double?
    let outputTokens: Double?
    let cacheReadTokens: Double?
    let cacheCreationTokens: Double?
    let totalTokens: Double
    let requests: Double?
    let cost: Double?
    let currencyCode: String?
    let source: String
    var modelBreakdowns: [CostModelBreakdown]? = nil

    var id: String {
        let modelKey = model?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "_all"
        let timeKey = Int64(timestamp.timeIntervalSince1970.rounded())
        return "\(accountID)::\(bucket.rawValue)::\(timeKey)::\(source.lowercased())::\(modelKey)"
    }
}

struct TokenHistoryAccount: Identifiable, Hashable {
    let id: String
    let providerID: String
    let providerName: String
    let accountLabel: String?
    let firstRecordedAt: Date
    let lastRecordedAt: Date
    let recordCount: Int

    var displayName: String {
        guard let accountLabel = accountLabel, !accountLabel.isEmpty else { return providerName }
        return "\(providerName) — \(accountLabel)"
    }
}

struct TokenHistoryChartPoint: Identifiable, Hashable {
    let timestamp: Date
    let label: String
    let tokens: Double
    var hasRecords: Bool = true

    var id: Date { timestamp }
}

struct TokenHistoryNamedTotal: Identifiable, Hashable {
    let name: String
    let tokens: Double

    var id: String { name }
}

struct TokenHistoryComponentTotals: Hashable {
    let input: Double?
    let output: Double?
    let cacheRead: Double?
    let cacheCreation: Double?

    var hasData: Bool {
        input != nil || output != nil || cacheRead != nil || cacheCreation != nil
    }
}

struct TokenHistoryReport: Hashable {
    let range: TokenHistoryRange
    let totalTokens: Double
    let todayTokens: Double
    let last30DaysTokens: Double
    let allTimeTokens: Double
    let firstRecordedAt: Date?
    let lastRecordedAt: Date?
    let recordCount: Int
    let chart: [TokenHistoryChartPoint]
    let components: TokenHistoryComponentTotals
    let modelTotals: [TokenHistoryNamedTotal]
    let providerTotals: [TokenHistoryNamedTotal]
}

/// Durable, account-isolated token ledger used by the settings history page.
///
/// Provider APIs expose different rolling windows. The store merges every
/// dated bucket it can prove is token usage and never automatically deletes a
/// record. In particular, z.ai's rolling hourly/model response is de-duplicated
/// by account, timestamp, and model so it grows into an honest 30-day and
/// all-time local history without treating quota percentages as tokens.
final class LocalTokenHistoryStore {
    private struct Ledger: Codable {
        let schemaVersion: Int
        let records: [TokenHistoryRecord]
    }

    private struct ExportEnvelope: Codable {
        let schemaVersion: Int
        let generatedAt: Date
        let range: TokenHistoryRange?
        let accountID: String?
        let records: [TokenHistoryRecord]
    }

    private enum Aggregation {
        case hour
        case day
        case month
    }

    private let fileManager: FileManager
    private let calendar: Calendar
    private(set) var fileURL: URL
    private var recordsByID: [String: TokenHistoryRecord]
    private var writesEnabled: Bool
    private(set) var persistenceError: String?
    private(set) var revision = 0

    init(
        fileManager: FileManager = .default,
        storageDirectory: URL? = nil,
        calendar: Calendar = .current
    ) {
        let directory: URL
        if let storageDirectory = storageDirectory {
            directory = storageDirectory
        } else if let override = ProcessInfo.processInfo.environment["CODEXBAR_MONTEREY_TOKEN_HISTORY_DIRECTORY"],
                  !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
                fileManager.temporaryDirectory
            directory = applicationSupport.appendingPathComponent("CodexBarMonterey", isDirectory: true)
        }

        self.fileManager = fileManager
        self.calendar = calendar
        self.fileURL = directory.appendingPathComponent("token-history-v1.json")

        switch Self.load(from: self.fileURL) {
        case let .success(records):
            var loaded: [String: TokenHistoryRecord] = [:]
            for record in records { loaded[record.id] = record }
            self.recordsByID = loaded
            self.writesEnabled = true
            self.persistenceError = nil
        case let .failure(error):
            // Never overwrite an unreadable ledger. It may be recoverable, and
            // preserving token history is more important than silently starting
            // over with an empty file.
            self.recordsByID = [:]
            self.writesEnabled = false
            self.persistenceError = "Token history could not be read and was left untouched: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func record(
        snapshot: ProviderSnapshot,
        supplementalJSON: String?,
        now: Date = Date()
    ) -> String? {
        let accountID = Self.accountID(for: snapshot)
        var incoming: [TokenHistoryRecord] = []
        var replacementDates = Set<Date>()

        if snapshot.provider == "zai" {
            incoming.append(contentsOf: Self.zaiRecords(
                snapshot: snapshot,
                accountID: accountID))
        } else if snapshot.provider == "deepseek" {
            incoming.append(contentsOf: Self.deepSeekRecords(
                snapshot: snapshot,
                accountID: accountID))
        }

        if let payload = CostHistoryPayloadParser.payload(
            provider: snapshot.provider,
            fromJSON: supplementalJSON)
        {
            replacementDates = Set(payload.sortedDaily.compactMap { Self.parseDate($0.date) }
                .map { Calendar.current.startOfDay(for: $0) })
            incoming.append(contentsOf: Self.costHistoryRecords(
                snapshot: snapshot,
                accountID: accountID,
                payload: payload))
        }

        // For providers without a typed contract, accept only explicitly dated
        // arrays named as usage/token history and containing a token field.
        // Quota windows are not arrays with those names, so percentages cannot
        // leak into this ledger.
        if incoming.isEmpty {
            incoming.append(contentsOf: Self.genericHistoryRecords(
                snapshot: snapshot,
                accountID: accountID))
        }

        var changed = false
        // Replace corrected day buckets atomically, including an older all-model
        // bucket. Keep a byte-for-byte backup before the first schema enrichment.
        let replaced = recordsByID.values.filter {
            ($0.accountID == accountID || $0.accountID.hasPrefix(accountID + "::")) &&
                $0.source == "\(snapshot.provider).costHistory" && replacementDates.contains($0.timestamp)
        }
        let incomingIDs = Set(incoming.map(\.id))
        let obsolete = replaced.filter { !incomingIDs.contains($0.id) }
        if !obsolete.isEmpty {
            let backup = fileURL.deletingLastPathComponent().appendingPathComponent("token-history-before-model-attribution.json")
            if fileManager.fileExists(atPath: fileURL.path) && !fileManager.fileExists(atPath: backup.path) {
                do { try fileManager.copyItem(at: fileURL, to: backup) }
                catch {
                    persistenceError = "History correction could not preserve its backup: \(error.localizedDescription)"
                    return nil
                }
            }
            for old in obsolete { recordsByID[old.id] = nil }
            changed = true
        }
        for candidate in incoming where candidate.totalTokens.isFinite && candidate.totalTokens >= 0 {
            if recordsByID[candidate.id] != candidate {
                recordsByID[candidate.id] = candidate
                changed = true
            }
        }

        if changed {
            revision &+= 1
            save()
        }
        return dashboardPayload(accountID: accountID, now: now)
    }

    func accounts() -> [TokenHistoryAccount] {
        Dictionary(grouping: recordsByID.values.map(Self.attributedRecord), by: \.accountID)
            .compactMap { accountID, records -> TokenHistoryAccount? in
                guard let first = records.min(by: { $0.timestamp < $1.timestamp }),
                      let last = records.max(by: { $0.timestamp < $1.timestamp })
                else { return nil }
                let latestLabel = records
                    .sorted(by: { $0.timestamp > $1.timestamp })
                    .compactMap(\.accountLabel)
                    .first
                return TokenHistoryAccount(
                    id: accountID,
                    providerID: last.providerID,
                    providerName: last.providerName,
                    accountLabel: latestLabel,
                    firstRecordedAt: first.timestamp,
                    lastRecordedAt: last.timestamp,
                    recordCount: records.count)
            }
            .sorted {
                let providerOrder = $0.providerName.localizedCaseInsensitiveCompare($1.providerName)
                if providerOrder != .orderedSame { return providerOrder == .orderedAscending }
                return ($0.accountLabel ?? "").localizedCaseInsensitiveCompare($1.accountLabel ?? "") == .orderedAscending
            }
    }

    func report(
        accountID: String?,
        range: TokenHistoryRange,
        now: Date = Date()
    ) -> TokenHistoryReport {
        let accountRecords = sortedRecords(accountID: accountID).filter {
            accountID != nil || !$0.providerID.hasPrefix("claude-code-")
        }
        let cutoff = range.cutoff(now: now, calendar: calendar)
        let visible = accountRecords.filter { record in
            guard let cutoff = cutoff else { return true }
            return record.timestamp >= cutoff && record.timestamp <= now
        }
        let thirtyDayCutoff = TokenHistoryRange.thirtyDays.cutoff(now: now, calendar: calendar)
        let today = accountRecords.filter { calendar.isDate($0.timestamp, inSameDayAs: now) }
        let last30 = accountRecords.filter { record in
            guard let thirtyDayCutoff = thirtyDayCutoff else { return true }
            return record.timestamp >= thirtyDayCutoff && record.timestamp <= now
        }

        return TokenHistoryReport(
            range: range,
            totalTokens: visible.reduce(0) { $0 + $1.totalTokens },
            todayTokens: today.reduce(0) { $0 + $1.totalTokens },
            last30DaysTokens: last30.reduce(0) { $0 + $1.totalTokens },
            allTimeTokens: accountRecords.reduce(0) { $0 + $1.totalTokens },
            firstRecordedAt: accountRecords.first?.timestamp,
            lastRecordedAt: accountRecords.last?.timestamp,
            recordCount: visible.count,
            chart: chartPoints(records: visible, range: range, now: now),
            components: TokenHistoryComponentTotals(
                input: Self.sumOptional(visible.map(\.inputTokens)),
                output: Self.sumOptional(visible.map(\.outputTokens)),
                cacheRead: Self.sumOptional(visible.map(\.cacheReadTokens)),
                cacheCreation: Self.sumOptional(visible.map(\.cacheCreationTokens))),
            modelTotals: Self.namedTotals(
                records: visible.flatMap(Self.modelTotals)),
            providerTotals: Self.namedTotals(records: visible.map { ($0.providerName, $0.totalTokens) }))
    }

    func exportCSV(
        accountID: String?,
        range: TokenHistoryRange?,
        now: Date = Date()
    ) -> String {
        let records = exportRecords(accountID: accountID, range: range, now: now)
        var rows = [
            "timestamp,provider_id,provider_name,account_id,account_label,bucket,model,models_used,input_tokens,output_tokens,cache_read_tokens,cache_creation_tokens,total_tokens,requests,cost,currency,source,model_tokens",
        ]
        let formatter = ISO8601DateFormatter()
        rows.append(contentsOf: records.map { record in
            [
                formatter.string(from: record.timestamp),
                record.providerID,
                record.providerName,
                record.accountID,
                record.accountLabel ?? "",
                record.bucket.rawValue,
                record.model ?? "",
                (record.modelsUsed ?? []).joined(separator: " | "),
                Self.exportNumber(record.inputTokens),
                Self.exportNumber(record.outputTokens),
                Self.exportNumber(record.cacheReadTokens),
                Self.exportNumber(record.cacheCreationTokens),
                Self.exportNumber(record.totalTokens),
                Self.exportNumber(record.requests),
                Self.exportNumber(record.cost),
                record.currencyCode ?? "",
                record.source,
                Self.modelTotals(record).map { "\($0.0): \(Self.exportNumber($0.1))" }.joined(separator: " | "),
            ].map(Self.csvField).joined(separator: ",")
        })
        return rows.joined(separator: "\n") + "\n"
    }

    func exportJSON(
        accountID: String?,
        range: TokenHistoryRange?,
        now: Date = Date()
    ) throws -> Data {
        let envelope = ExportEnvelope(
            schemaVersion: 1,
            generatedAt: now,
            range: range,
            accountID: accountID,
            records: exportRecords(accountID: accountID, range: range, now: now))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }

    private func dashboardPayload(accountID: String, now: Date) -> String? {
        let allRecords = sortedRecords(accountID: accountID)
        guard !allRecords.isEmpty else { return nil }
        let report = report(accountID: accountID, range: .thirtyDays, now: now)
        let modelTotals = Self.namedTotals(records: allRecords.flatMap(Self.modelTotals))
        func topModel(dayCount: Int) -> String? {
            let start = calendar.startOfDay(for: now)
            guard let cutoff = calendar.date(byAdding: .day, value: 1 - dayCount, to: start) else { return nil }
            let scoped = allRecords.filter { $0.timestamp >= cutoff && $0.timestamp <= now }
            let totals = Self.namedTotals(records: scoped.flatMap(Self.modelTotals))
            guard !totals.contains(where: { $0.name == "Unattributed models" && $0.tokens > 0 }) else { return nil }
            return totals.first(where: { $0.tokens > 0 })?.name
        }
        let cutoff = TokenHistoryRange.thirtyDays.cutoff(now: now, calendar: calendar) ?? .distantPast
        var payload: [String: Any] = [
            "todayTokens": report.todayTokens,
            "last30DaysTokens": report.last30DaysTokens,
            "allTimeTokens": report.allTimeTokens,
            "coverageStartedAt": Self.isoString(allRecords[0].timestamp),
            "coverageEndedAt": Self.isoString(allRecords[allRecords.count - 1].timestamp),
            "hasFull30DayCoverage": allRecords[0].timestamp <= cutoff,
            "recordCount": allRecords.count,
            "modelCount": modelTotals.count,
            "daily": report.chart.map { point -> [String: Any] in
                var row: [String: Any] = ["date": Self.dayString(point.timestamp)]
                if point.hasRecords { row["tokens"] = point.tokens }
                return row
            },
        ]
        if let model = topModel(dayCount: 10) {
            payload["topModel"] = model
            payload["topModel10Days"] = model
        }
        if let model = topModel(dayCount: 1) { payload["topModelToday"] = model }
        let root: [String: Any] = ["localTokenHistory": payload]
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func sortedRecords(accountID: String?) -> [TokenHistoryRecord] {
        recordsByID.values.map(Self.attributedRecord)
            .filter { accountID == nil || $0.accountID == accountID }
            .sorted {
                if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
                return $0.id < $1.id
            }
    }

    private func exportRecords(
        accountID: String?,
        range: TokenHistoryRange?,
        now: Date
    ) -> [TokenHistoryRecord] {
        let records = sortedRecords(accountID: accountID).filter {
            range == nil || accountID != nil || !$0.providerID.hasPrefix("claude-code-")
        }
        guard let range = range,
              let cutoff = range.cutoff(now: now, calendar: calendar)
        else { return records }
        return records.filter { $0.timestamp >= cutoff && $0.timestamp <= now }
    }

    private func chartPoints(
        records: [TokenHistoryRecord],
        range: TokenHistoryRange,
        now: Date
    ) -> [TokenHistoryChartPoint] {
        let aggregation: Aggregation
        switch range {
        case .day: aggregation = .hour
        case .week, .thirtyDays, .ninetyDays: aggregation = .day
        case .year: aggregation = .month
        case .all:
            if let first = records.first?.timestamp,
               now.timeIntervalSince(first) <= 90 * 24 * 60 * 60
            {
                aggregation = .day
            } else {
                aggregation = .month
            }
        }

        var totals: [Date: Double] = [:]
        for record in records {
            let date: Date
            switch aggregation {
            case .hour:
                let parts = calendar.dateComponents([.year, .month, .day, .hour], from: record.timestamp)
                date = calendar.date(from: parts) ?? record.timestamp
            case .day:
                date = calendar.startOfDay(for: record.timestamp)
            case .month:
                let parts = calendar.dateComponents([.year, .month], from: record.timestamp)
                date = calendar.date(from: parts) ?? calendar.startOfDay(for: record.timestamp)
            }
            totals[date, default: 0] += record.totalTokens
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        let component: Calendar.Component
        switch aggregation {
        case .hour: formatter.dateFormat = "MMM d HH:mm"; component = .hour
        case .day: formatter.dateFormat = "MMM d"; component = .day
        case .month: formatter.dateFormat = "MMM yy"; component = .month
        }
        guard var date = totals.keys.min(), let last = totals.keys.max() else { return [] }
        let end = max(last, calendar.dateInterval(of: component, for: now)?.start ?? last)
        var points: [TokenHistoryChartPoint] = []
        while date <= end {
            points.append(TokenHistoryChartPoint(timestamp: date, label: formatter.string(from: date),
                tokens: totals[date] ?? 0, hasRecords: totals[date] != nil))
            guard let next = calendar.date(byAdding: component, value: 1, to: date), next > date else { break }
            date = next
        }
        return points
    }

    private func save() {
        guard writesEnabled else { return }
        let ledger = Ledger(schemaVersion: 1, records: sortedRecords(accountID: nil))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(ledger)
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try data.write(to: fileURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            persistenceError = nil
        } catch {
            persistenceError = "Token history could not be saved: \(error.localizedDescription)"
        }
    }

    private static func load(from url: URL) -> Result<[TokenHistoryRecord], Error> {
        guard FileManager.default.fileExists(atPath: url.path) else { return .success([]) }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let ledger = try decoder.decode(Ledger.self, from: data)
            guard ledger.schemaVersion == 1 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return .success(ledger.records)
        } catch {
            return .failure(error)
        }
    }

    private static func accountID(for snapshot: ProviderSnapshot) -> String {
        "\(snapshot.provider)::\(StableIdentifier.hash(snapshot.id))"
    }

    private static func zaiRecords(
        snapshot: ProviderSnapshot,
        accountID: String
    ) -> [TokenHistoryRecord] {
        guard let root = jsonObject(snapshot.rawJSON),
              let usage = dictionary(named: "zaiUsage", in: root),
              let modelUsage = normalizedDictionary(usage)["modelusage"] as? [String: Any]
        else { return [] }
        let normalized = normalizedDictionary(modelUsage)
        let times = normalized["xtime"] as? [String] ?? []
        let rows = normalized["modeldatalist"] as? [[String: Any]] ?? []
        guard !times.isEmpty, !rows.isEmpty else { return [] }

        var records: [TokenHistoryRecord] = []
        for row in rows {
            let item = normalizedDictionary(row)
            let model = (item["modelname"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let values = item["tokensusage"] as? [Any] ?? []
            for index in times.indices where index < values.count {
                guard let timestamp = parseDate(times[index]),
                      let tokens = number(values[index]),
                      tokens.isFinite,
                      tokens >= 0
                else { continue }
                records.append(TokenHistoryRecord(
                    providerID: snapshot.provider,
                    providerName: snapshot.displayName,
                    accountID: accountID,
                    accountLabel: snapshot.accountDisplayName,
                    timestamp: startOfHour(timestamp),
                    bucket: .hour,
                    model: model?.isEmpty == false ? model : "Unknown",
                    modelsUsed: nil,
                    inputTokens: nil,
                    outputTokens: nil,
                    cacheReadTokens: nil,
                    cacheCreationTokens: nil,
                    totalTokens: tokens,
                    requests: nil,
                    cost: nil,
                    currencyCode: nil,
                    source: "zai.modelUsage"))
            }
        }
        return records
    }

    private static func deepSeekRecords(
        snapshot: ProviderSnapshot,
        accountID: String
    ) -> [TokenHistoryRecord] {
        guard let root = jsonObject(snapshot.rawJSON),
              let usage = dictionary(named: "deepseekUsage", in: root)
        else { return [] }
        let normalized = normalizedDictionary(usage)
        let currency = (normalized["currency"] as? String)?.uppercased()
        let rows = normalized["daily"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            let item = normalizedDictionary(row)
            guard let timestampValue = firstValue(item, keys: ["date", "day", "timestamp"]),
                  let timestamp = parseDate(timestampValue),
                  let tokens = firstNumber(item, keys: ["totaltokens", "tokens", "tokenusage"]),
                  tokens.isFinite,
                  tokens >= 0
            else { return nil }
            return TokenHistoryRecord(
                providerID: snapshot.provider,
                providerName: snapshot.displayName,
                accountID: accountID,
                accountLabel: snapshot.accountDisplayName,
                timestamp: Calendar.current.startOfDay(for: timestamp),
                bucket: .day,
                model: nil,
                modelsUsed: nil,
                inputTokens: nil,
                outputTokens: nil,
                cacheReadTokens: nil,
                cacheCreationTokens: nil,
                totalTokens: tokens,
                requests: firstNumber(item, keys: ["requestcount", "requests"]),
                cost: firstNumber(item, keys: ["cost", "totalcost"]),
                currencyCode: currency,
                source: "deepseek.daily")
        }
    }

    private static func costHistoryRecords(
        snapshot: ProviderSnapshot,
        accountID: String,
        payload: CostHistoryPayload
    ) -> [TokenHistoryRecord] {
        payload.sortedDaily.flatMap { day -> [TokenHistoryRecord] in
            let days: [CostHistoryDay]
            if snapshot.provider == "claude" {
                let known = [day.selectingModels(CostHistoryPayload.isClaudeModel),
                    day.selectingModels { !CostHistoryPayload.isClaudeModel($0) }].compactMap { $0 }
                days = known.isEmpty ? [day] : known
            } else { days = [day] }
            return days.compactMap { day in
                guard let timestamp = parseDate(day.date) else { return nil }
                let components = [day.inputTokens, day.outputTokens, day.cacheReadTokens, day.cacheCreationTokens].compactMap { $0 }
                guard let total = day.totalTokens ?? (components.isEmpty ? nil : components.reduce(0, +)),
                      total.isFinite, total >= 0 else { return nil }
                let models = day.reconciledModels?.map(\.modelName) ?? day.modelsUsed
                return attributedRecord(TokenHistoryRecord(
                    providerID: snapshot.provider, providerName: snapshot.displayName,
                    accountID: accountID, accountLabel: snapshot.accountDisplayName,
                    timestamp: Calendar.current.startOfDay(for: timestamp), bucket: .day,
                    model: models?.count == 1 ? models?.first : nil, modelsUsed: models,
                    inputTokens: finiteNonnegative(day.inputTokens), outputTokens: finiteNonnegative(day.outputTokens),
                    cacheReadTokens: finiteNonnegative(day.cacheReadTokens), cacheCreationTokens: finiteNonnegative(day.cacheCreationTokens),
                    totalTokens: total, requests: nil, cost: finiteNonnegative(day.resolvedCost), currencyCode: "USD",
                    source: "\(snapshot.provider).costHistory", modelBreakdowns: day.reconciledModels))
            }
        }
    }

    private static func modelTotals(_ record: TokenHistoryRecord) -> [(String, Double)] {
        if let rows = record.modelBreakdowns,
           let sum = CostHistoryPayload.completeSum(rows.map(\.totalTokens)), abs(sum - record.totalTokens) < 0.5 {
            return rows.compactMap { row in row.totalTokens.map { (row.modelName, $0) } }
        }
        if let model = record.model ?? (record.modelsUsed?.count == 1 ? record.modelsUsed?.first : nil) {
            return [(model, record.totalTokens)]
        }
        return [("Unattributed models", record.totalTokens)]
    }

    /// A GLM model name proves this is not Claude model usage, but does not
    /// prove which GLM endpoint/account billed it. Keep client logs separate
    /// from z.ai API data so they cannot silently double-count that account.
    private static func attributedRecord(_ record: TokenHistoryRecord) -> TokenHistoryRecord {
        guard record.providerID == "claude" else { return record }
        let names = record.modelsUsed ?? record.model.map { [$0] } ?? []
        if !names.isEmpty && names.allSatisfy(CostHistoryPayload.isClaudeModel) { return record }
        let other = !names.isEmpty && names.allSatisfy { !CostHistoryPayload.isClaudeModel($0) }
        return TokenHistoryRecord(
            providerID: other ? "claude-code-other" : "claude-code-unattributed",
            providerName: other ? "Claude Code · Other models" : "Claude Code · Unattributed",
            accountID: record.accountID + (other ? "::other" : "::unattributed"), accountLabel: nil,
            timestamp: record.timestamp, bucket: record.bucket, model: record.model, modelsUsed: record.modelsUsed,
            inputTokens: record.inputTokens, outputTokens: record.outputTokens,
            cacheReadTokens: record.cacheReadTokens, cacheCreationTokens: record.cacheCreationTokens,
            totalTokens: record.totalTokens, requests: record.requests, cost: record.cost,
            currencyCode: record.currencyCode, source: record.source, modelBreakdowns: record.modelBreakdowns)
    }

    private static func genericHistoryRecords(
        snapshot: ProviderSnapshot,
        accountID: String
    ) -> [TokenHistoryRecord] {
        guard let root = jsonObject(snapshot.rawJSON) else { return [] }
        let acceptedNames: Set<String> = [
            "daily", "hourly", "history", "usagehistory", "tokenhistory", "dailyusage", "hourlyusage",
        ]
        var records: [TokenHistoryRecord] = []

        func visit(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                for key in dictionary.keys.sorted() {
                    guard let nested = dictionary[key] else { continue }
                    let normalizedKey = normalize(key)
                    if acceptedNames.contains(normalizedKey), let rows = nested as? [[String: Any]] {
                        for row in rows {
                            let item = normalizedDictionary(row)
                            guard let rawDate = firstValue(item, keys: ["date", "day", "timestamp", "hour", "period", "startdate"]),
                                  let timestamp = parseDate(rawDate),
                                  let tokens = firstNumber(item, keys: ["tokens", "totaltokens", "tokenusage"]),
                                  tokens.isFinite,
                                  tokens >= 0
                            else { continue }
                            let isHourly = normalizedKey.contains("hour") || String(describing: rawDate).contains(":")
                            let model = (firstValue(item, keys: ["model", "modelname"]) as? String)?
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            records.append(TokenHistoryRecord(
                                providerID: snapshot.provider,
                                providerName: snapshot.displayName,
                                accountID: accountID,
                                accountLabel: snapshot.accountDisplayName,
                                timestamp: isHourly ? startOfHour(timestamp) : Calendar.current.startOfDay(for: timestamp),
                                bucket: isHourly ? .hour : .day,
                                model: model?.isEmpty == false ? model : nil,
                                modelsUsed: nil,
                                inputTokens: finiteNonnegative(firstNumber(item, keys: ["inputtokens"])),
                                outputTokens: finiteNonnegative(firstNumber(item, keys: ["outputtokens"])),
                                cacheReadTokens: finiteNonnegative(firstNumber(item, keys: ["cachereadtokens"])),
                                cacheCreationTokens: finiteNonnegative(firstNumber(item, keys: ["cachecreationtokens"])),
                                totalTokens: tokens,
                                requests: finiteNonnegative(firstNumber(item, keys: ["requests", "requestcount"])),
                                cost: finiteNonnegative(firstNumber(item, keys: ["cost", "totalcost"])),
                                currencyCode: nil,
                                source: "\(snapshot.provider).\(normalizedKey)"))
                        }
                    } else {
                        visit(nested)
                    }
                }
            } else if let array = value as? [Any] {
                for nested in array { visit(nested) }
            }
        }
        visit(root)
        return records
    }

    private static func jsonObject(_ source: String?) -> Any? {
        guard let source = source,
              let data = source.data(using: .utf8)
        else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func dictionary(named name: String, in root: Any) -> [String: Any]? {
        let target = normalize(name)
        if let object = root as? [String: Any] {
            for key in object.keys.sorted() where normalize(key) == target {
                if let result = object[key] as? [String: Any] { return result }
            }
            for key in object.keys.sorted() {
                if let nested = object[key], let result = dictionary(named: name, in: nested) {
                    return result
                }
            }
        } else if let array = root as? [Any] {
            for value in array {
                if let result = dictionary(named: name, in: value) { return result }
            }
        }
        return nil
    }

    private static func normalizedDictionary(_ dictionary: [String: Any]) -> [String: Any] {
        Dictionary(uniqueKeysWithValues: dictionary.map { (normalize($0.key), $0.value) })
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func firstValue(_ dictionary: [String: Any], keys: [String]) -> Any? {
        for key in keys.map(normalize) {
            if let value = dictionary[key] { return value }
        }
        return nil
    }

    private static func firstNumber(_ dictionary: [String: Any], keys: [String]) -> Double? {
        for key in keys.map(normalize) {
            if let value = dictionary[key], let result = number(value) { return result }
        }
        return nil
    }

    private static func number(_ value: Any) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String {
            return Double(value.replacingOccurrences(of: ",", with: ""))
        }
        return nil
    }

    private static func parseDate(_ value: Any) -> Date? {
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1000 : raw)
        }
        let text = String(describing: value)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        if let date = ISO8601DateFormatter().date(from: text) { return date }
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    private static func startOfHour(_ date: Date) -> Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        return calendar.date(from: parts) ?? date
    }

    private static func finiteNonnegative(_ value: Double?) -> Double? {
        guard let value = value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func sumOptional(_ values: [Double?]) -> Double? {
        let present = values.compactMap { finiteNonnegative($0) }
        return present.isEmpty || present.count != values.count ? nil : present.reduce(0, +)
    }

    private static func namedTotals(records: [(String, Double)]) -> [TokenHistoryNamedTotal] {
        var totals: [String: Double] = [:]
        for (name, value) in records where value.isFinite && value >= 0 {
            totals[name, default: 0] += value
        }
        return totals.map { TokenHistoryNamedTotal(name: $0.key, tokens: $0.value) }
            .sorted {
                if $0.tokens != $1.tokens { return $0.tokens > $1.tokens }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private static func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func exportNumber(_ value: Double?) -> String {
        guard let value = value else { return "" }
        return exportNumber(value)
    }

    private static func exportNumber(_ value: Double) -> String {
        if value.rounded() == value { return String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), value) }
        return String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }

    private static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
