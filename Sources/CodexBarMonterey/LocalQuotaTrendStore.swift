import Foundation

/// Persists a small, account-isolated history of the z.ai five-hour quota window.
/// The upstream API exposes current quota windows but no dated history array,
/// so the Monterey UI samples the 300-minute window locally. MCP/monthly quota
/// windows are intentionally excluded from this trend.
final class LocalQuotaTrendStore {
    private struct Sample: Codable, Hashable {
        let timestamp: Date
        let usedPercent: Double
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private var samplesByAccount: [String: [Sample]]

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
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        self.fileManager = fileManager
        self.fileURL = directory.appendingPathComponent("zai-five-hour-trend-v3.json")
        self.samplesByAccount = Self.load(from: self.fileURL)
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
        let accountKey = Self.storageKey(for: snapshot)
        for key in Array(samplesByAccount.keys) {
            let retained = (samplesByAccount[key] ?? [])
                .filter { $0.timestamp >= cutoff }
                .sorted { $0.timestamp < $1.timestamp }
            samplesByAccount[key] = retained.isEmpty ? nil : Array(retained.suffix(240))
        }
        var samples = samplesByAccount[accountKey] ?? []

        if let last = samples.last {
            let interval = now.timeIntervalSince(last.timestamp)
            if interval > 0, interval < 5 * 60 {
                samples[samples.count - 1] = Sample(timestamp: now, usedPercent: clamped)
            } else if interval >= 5 * 60 {
                samples.append(Sample(timestamp: now, usedPercent: clamped))
            }
            // Ignore duplicate/out-of-order timestamps so a clock adjustment
            // cannot move the end of the persisted series backwards.
        } else {
            samples.append(Sample(timestamp: now, usedPercent: clamped))
        }
        samples = Array(samples.suffix(240))
        samplesByAccount[accountKey] = samples
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
        snapshot.headlineUsedPercent
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(samplesByAccount) else { return }
        do {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try data.write(to: fileURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            // Quota history is an optional cache and must never break refresh.
        }
    }

    private static func storageKey(for snapshot: ProviderSnapshot) -> String {
        "\(snapshot.provider)::\(StableIdentifier.hash(snapshot.id))"
    }

    private static func load(from url: URL) -> [String: [Sample]] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: [Sample]].self, from: data)) ?? [:]
    }
}
