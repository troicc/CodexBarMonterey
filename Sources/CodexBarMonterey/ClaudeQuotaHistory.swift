import Foundation

struct ClaudeQuotaSample: Codable, Hashable, Identifiable {
    let timestamp: Date
    let usedPercent: Double
    let resetsAt: Date?
    var id: Date { timestamp }
}

struct ClaudeQuotaSeries: Hashable, Identifiable {
    let id: String
    let title: String
    let samples: [ClaudeQuotaSample]

    /// Do not draw consumption through resets, corrections or an unobserved interval.
    static func connects(_ previous: ClaudeQuotaSample, _ next: ClaudeQuotaSample) -> Bool {
        next.timestamp > previous.timestamp &&
            next.timestamp.timeIntervalSince(previous.timestamp) <= 3600 &&
            previous.resetsAt == next.resetsAt &&
            !(previous.resetsAt.map { $0 <= next.timestamp } ?? false) &&
            next.usedPercent >= previous.usedPercent
    }
}

extension ProviderSnapshot {
    var claudeSharedQuotaWindows: [(id: String, title: String, window: RateWindow)] {
        guard provider == "claude", source?.lowercased().contains("admin") != true else { return [] }
        let windows = [usage?.primary, usage?.secondary, usage?.tertiary].compactMap { $0 }
        var result: [(id: String, title: String, window: RateWindow)] = []
        for (id, title, minutes, fallback) in [
            ("five-hour", "5 hours", 300.0, usage?.primary),
            ("weekly", "Weekly", 10080.0, usage?.secondary),
        ] {
            let window = windows.first { $0.windowMinutes == minutes }
                ?? (fallback?.windowMinutes == nil ? fallback : nil)
            if let window = window, let percent = window.usedPercent, percent.isFinite, (0...100).contains(percent) {
                result.append((id, title, window))
            }
        }
        return result
    }

    // New quota history can use the CLI display identity without migrating token/cost ledgers.
    var claudeQuotaAccountKey: String? {
        let email = [usage?.identity?.accountEmail, usage?.accountEmail, account, cliAccountStatus?.email]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .first { !$0.isEmpty }
        guard provider == "claude", let email = email else { return nil }
        let org = (usage?.identity?.accountOrganization ?? usage?.accountOrganization ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return StableIdentifier.hash("claude::\(email)::\(org)")
    }
}

/// Account quota percentages stay separate from token and estimated-cost history.
final class ClaudeQuotaHistoryStore {
    private let fileURL: URL
    private var accounts: [String: [String: [ClaudeQuotaSample]]] = [:]
    private var canSave = true
    private(set) var persistenceError: String?

    init(storageDirectory: URL? = nil) {
        let root = storageDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexBarMonterey", isDirectory: true)
        fileURL = root.appendingPathComponent("claude-quota-history-v1.json")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                accounts = try decoder.decode([String: [String: [ClaudeQuotaSample]]].self, from: Data(contentsOf: fileURL))
            } catch {
                canSave = false
                persistenceError = "Quota history could not be read; the original file is preserved."
            }
        }
    }

    func record(snapshot: ProviderSnapshot, now: Date = Date()) -> [ClaudeQuotaSeries] {
        guard let key = snapshot.claudeQuotaAccountKey else { return [] }
        let cutoff = now.addingTimeInterval(-30 * 86400)
        // Only upstream measurement times can create samples. Enrichment, currency changes,
        // errors and repeated cached responses must never fabricate fresh observations.
        if snapshot.error == nil, let reportedTime = snapshot.usage?.updatedAt,
           reportedTime <= now, reportedTime >= cutoff {
            // ISO-8601 persistence uses seconds; keep in-memory identity at the same precision.
            let measured = Date(timeIntervalSince1970: floor(reportedTime.timeIntervalSince1970))
            var changed = false
            for lane in snapshot.claudeSharedQuotaWindows {
                var samples = accounts[key]?[lane.id] ?? []
                guard samples.last.map({ measured > $0.timestamp }) ?? true else { continue }
                samples.append(ClaudeQuotaSample(timestamp: measured, usedPercent: lane.window.usedPercent!,
                    resetsAt: lane.window.resetsAt.map { Date(timeIntervalSince1970: floor($0.timeIntervalSince1970)) }))
                accounts[key, default: [:]][lane.id] = Array(samples.suffix(10000))
                changed = true
            }
            if changed {
                for account in Array(accounts.keys) {
                    var lanes = accounts[account] ?? [:]
                    for (lane, samples) in lanes {
                        lanes[lane] = samples.filter {
                            $0.timestamp >= cutoff && $0.timestamp <= now && $0.usedPercent.isFinite && (0...100).contains($0.usedPercent)
                        }.sorted { $0.timestamp < $1.timestamp }
                    }
                    accounts[account] = lanes.values.allSatisfy({ $0.isEmpty }) ? nil : lanes
                }
                save()
            }
        }
        let displayCutoff = now.addingTimeInterval(-86400)
        return [("five-hour", "5 hours"), ("weekly", "Weekly")].compactMap { id, title in
            let samples = (accounts[key]?[id] ?? []).filter {
                $0.timestamp >= displayCutoff && $0.timestamp <= now && $0.usedPercent.isFinite && (0...100).contains($0.usedPercent)
            }.sorted { $0.timestamp < $1.timestamp }
            return samples.isEmpty ? nil : ClaudeQuotaSeries(id: id, title: title, samples: samples)
        }
    }

    private func save() {
        guard canSave else { return }
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(accounts).write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            persistenceError = nil
        } catch {
            persistenceError = "Quota history could not be saved. Current quotas are still available."
        }
    }
}
