import Foundation

/// Persists a small, privacy-safe history of quota percentages for providers
/// whose upstream API only returns the current snapshot. z.ai v0.46 exposes
/// quota windows but no dated history array, so the Monterey UI samples the
/// highest used percentage locally and labels it as a local trend.
final class LocalQuotaTrendStore {
    private struct Sample: Codable, Hashable {
        let timestamp: Date
        let usedPercent: Double
    }

    private let fileURL: URL
    private var samplesByProvider: [String: [Sample]]

    init(fileManager: FileManager = .default, storageDirectory: URL? = nil) {
        let directory: URL
        if let storageDirectory = storageDirectory {
            directory = storageDirectory
        } else {
            let cacheRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ??
                fileManager.temporaryDirectory
            directory = cacheRoot.appendingPathComponent("CodexBarMonterey", isDirectory: true)
        }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("quota-trends-v1.json")
        self.samplesByProvider = Self.load(from: self.fileURL)
    }

    /// Records one sample and returns synthetic provider JSON understood by the
    /// existing tolerant dashboard history parser. The numeric value is stored
    /// in the internal `tokens` slot solely as a generic chart ordinate; UI
    /// labels always call it quota usage, never tokens.
    func record(snapshot: ProviderSnapshot, now: Date = Date()) -> String? {
        guard snapshot.provider == "zai",
              let usedPercent = Self.preferredUsedPercent(snapshot),
              usedPercent.isFinite
        else { return nil }

        let clamped = max(0, min(100, usedPercent))
        let cutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        var samples = (samplesByProvider[snapshot.provider] ?? []).filter { $0.timestamp >= cutoff }

        if let last = samples.last, now.timeIntervalSince(last.timestamp) < 5 * 60 {
            samples[samples.count - 1] = Sample(timestamp: now, usedPercent: clamped)
        } else {
            samples.append(Sample(timestamp: now, usedPercent: clamped))
        }
        samples = Array(samples.suffix(240))
        samplesByProvider[snapshot.provider] = samples
        save()

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "MMM d HH:mm"

        let rows: [[String: Any]] = samples.map { sample in
            [
                "label": formatter.string(from: sample.timestamp),
                "tokens": sample.usedPercent,
            ]
        }
        let root: [String: Any] = [
            "provider": snapshot.provider,
            "localQuotaTrend": rows,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func preferredUsedPercent(_ snapshot: ProviderSnapshot) -> Double? {
        let values = [
            snapshot.usage?.primary?.usedPercent,
            snapshot.usage?.secondary?.usedPercent,
            snapshot.usage?.tertiary?.usedPercent,
        ].compactMap { $0 }
        return values.max()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(samplesByProvider) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> [String: [Sample]] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: [Sample]].self, from: data)) ?? [:]
    }
}
