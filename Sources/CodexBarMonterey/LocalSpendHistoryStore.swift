import Foundation

/// Persists an account-scoped balance ledger and derives conservative local
/// spend estimates from observed balance decreases. The store never treats a
/// recharge, gift-credit increase, refund, or currency change as negative spend.
final class LocalSpendHistoryStore {
    private struct Sample: Codable, Hashable {
        let timestamp: Date
        let total: Double
        let paid: Double?
        let granted: Double?
    }

    private struct Ledger: Codable {
        let provider: String
        let accountHash: String
        let currencyCode: String
        var samples: [Sample]
    }

    private struct StoreFile: Codable {
        var version: Int
        var ledgers: [String: Ledger]

        static let empty = StoreFile(version: 1, ledgers: [:])
    }

    private struct DailySpend: Encodable {
        let date: String
        let spend: Double
    }

    private struct BalancePayload: Encodable {
        let total: Double
        let paid: Double?
        let granted: Double?
    }

    private struct LocalSpendPayload: Encodable {
        let provider: String
        let currency: String
        let estimated: Bool
        let coverageStartedAt: String
        let balance: BalancePayload
        let todaySpend: Double
        let last30DaysSpend: Double
        let intervalCount: Int
        let adjustmentIntervals: Int
        let daily: [DailySpend]
    }

    private struct Envelope: Encodable {
        let localSpend: LocalSpendPayload
    }

    private let fileURL: URL
    private let calendar: Calendar
    private let minimumSampleInterval: TimeInterval
    private let retentionInterval: TimeInterval
    private let lock = NSLock()

    init(
        directoryURL: URL? = nil,
        calendar: Calendar = .current,
        minimumSampleInterval: TimeInterval = 5 * 60,
        retentionInterval: TimeInterval = 180 * 24 * 60 * 60
    ) {
        let baseURL: URL
        if let directoryURL = directoryURL {
            baseURL = directoryURL
        } else {
            baseURL = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask).first!
                .appendingPathComponent("CodexBarMonterey", isDirectory: true)
        }
        self.fileURL = baseURL.appendingPathComponent("local-spend-history.json")
        self.calendar = calendar
        self.minimumSampleInterval = max(0, minimumSampleInterval)
        self.retentionInterval = max(24 * 60 * 60, retentionInterval)
    }

    func record(
        snapshot: ProviderSnapshot,
        supplementalJSON: String? = nil,
        now: Date = Date()
    ) -> String? {
        record(
            provider: snapshot.provider,
            accountKey: snapshot.id,
            rawJSON: snapshot.rawJSON,
            supplementalJSON: supplementalJSON,
            now: now)
    }

    func record(
        provider: String,
        accountKey: String,
        rawJSON: String?,
        supplementalJSON: String? = nil,
        now: Date = Date()
    ) -> String? {
        guard ProviderFinanceProfile.profile(for: provider).trackingMode == .prepaidBalanceDelta,
              let observation = ProviderFinanceObservationExtractor.observation(
                provider: provider,
                rawJSON: rawJSON,
                supplementalJSON: supplementalJSON)
        else { return nil }

        lock.lock()
        defer { lock.unlock() }

        var store = loadStore()
        let accountHash = Self.stableHash(accountKey)
        let ledgerKey = [provider.lowercased(), accountHash, observation.currencyCode].joined(separator: "::")
        var ledger = store.ledgers[ledgerKey] ?? Ledger(
            provider: provider.lowercased(),
            accountHash: accountHash,
            currencyCode: observation.currencyCode,
            samples: [])

        let cutoff = now.addingTimeInterval(-retentionInterval)
        ledger.samples.removeAll { $0.timestamp < cutoff }
        let sample = Sample(
            timestamp: now,
            total: observation.total,
            paid: observation.paid,
            granted: observation.granted)
        insert(sample, into: &ledger.samples)

        store.ledgers[ledgerKey] = ledger
        store.ledgers = store.ledgers.filter { _, value in
            value.samples.contains { $0.timestamp >= cutoff }
        }
        saveStore(store)
        return encodedPayload(for: ledger, current: observation, now: now)
    }

    private func insert(_ sample: Sample, into samples: inout [Sample]) {
        samples.sort { $0.timestamp < $1.timestamp }
        guard let last = samples.last else {
            samples.append(sample)
            return
        }

        if sample.timestamp.timeIntervalSince(last.timestamp) < minimumSampleInterval {
            if sample.timestamp >= last.timestamp {
                samples[samples.count - 1] = sample
            }
            return
        }
        samples.append(sample)
    }

    private func encodedPayload(
        for ledger: Ledger,
        current: ProviderBalanceObservation,
        now: Date
    ) -> String? {
        let samples = ledger.samples.sorted { $0.timestamp < $1.timestamp }
        guard let first = samples.first else { return nil }

        var daily: [Date: Double] = [:]
        var adjustmentIntervals = 0
        var spendIntervals = 0

        for pair in zip(samples, samples.dropFirst()) {
            let previous = pair.0
            let next = pair.1
            let totalDelta = previous.total - next.total
            let paidIncreased = componentIncreased(previous.paid, next.paid)
            let grantedIncreased = componentIncreased(previous.granted, next.granted)
            let hasAdjustment = totalDelta < -0.000_001 || paidIncreased || grantedIncreased

            if hasAdjustment {
                adjustmentIntervals += 1
                continue
            }
            guard totalDelta > 0.000_001 else { continue }
            let day = calendar.startOfDay(for: next.timestamp)
            daily[day, default: 0] += totalDelta
            spendIntervals += 1
        }

        let today = calendar.startOfDay(for: now)
        let thirtyDayStart = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        let todaySpend = daily[today, default: 0]
        let last30DaysSpend = daily.reduce(0.0) { partial, entry in
            entry.key >= thirtyDayStart && entry.key <= today ? partial + entry.value : partial
        }

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let dailyPayload = daily.keys.sorted().suffix(180).map { day in
            DailySpend(date: dateFormatter.string(from: day), spend: daily[day, default: 0])
        }
        let envelope = Envelope(localSpend: LocalSpendPayload(
            provider: ledger.provider,
            currency: ledger.currencyCode,
            estimated: true,
            coverageStartedAt: isoFormatter.string(from: first.timestamp),
            balance: BalancePayload(
                total: current.total,
                paid: current.paid,
                granted: current.granted),
            todaySpend: todaySpend,
            last30DaysSpend: last30DaysSpend,
            intervalCount: spendIntervals,
            adjustmentIntervals: adjustmentIntervals,
            daily: dailyPayload))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(envelope) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func componentIncreased(_ previous: Double?, _ next: Double?) -> Bool {
        guard let previous = previous, let next = next else { return false }
        return next - previous > 0.000_001
    }

    private func loadStore() -> StoreFile {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(StoreFile.self, from: data),
              decoded.version == 1
        else { return .empty }
        return decoded
    }

    private func saveStore(_ store: StoreFile) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(store)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Dashboard refresh must remain non-fatal if persistence is denied.
        }
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}
