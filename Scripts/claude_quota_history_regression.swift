import Foundation

@main
struct ClaudeQuotaHistoryRegression {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let store = ClaudeQuotaHistoryStore(storageDirectory: directory)
        func snapshot(_ percent: Double, time: Date?, account: String? = "a@example.com", reset: Date? = nil,
                      source: String = "oauth", error: Bool = false, minutes: Double? = 300) -> ProviderSnapshot {
            ProviderSnapshot(provider: "claude", version: nil, source: source, status: nil,
                usage: UsageSnapshot(primary: RateWindow(usedPercent: percent, windowMinutes: minutes, resetsAt: reset),
                    secondary: RateWindow(usedPercent: 50, windowMinutes: 10080, resetsAt: nil), tertiary: nil,
                    updatedAt: time, identity: nil, accountEmail: account, accountOrganization: nil, loginMethod: nil),
                credits: nil, account: nil, plan: nil, error: error ? ProviderError(message: "offline") : nil, rawJSON: nil)
        }
        let end = start.addingTimeInterval(7200)
        let first = snapshot(20, time: start, reset: end)
        precondition(store.record(snapshot: first, now: start).count == 2)
        let secondTime = start.addingTimeInterval(600)
        let second = snapshot(30, time: secondTime, reset: end)
        let secondSeries = store.record(snapshot: second, now: secondTime)
        precondition(secondSeries[0].samples.count == 2)
        precondition(ClaudeQuotaSeries.connects(secondSeries[0].samples[0], secondSeries[0].samples[1]))
        precondition(store.record(snapshot: second, now: secondTime)[0].samples.count == 2, "repeat/enrichment must not sample twice")
        precondition(store.record(snapshot: first, now: secondTime)[0].samples.count == 2, "old response ignored")
        precondition(store.record(snapshot: snapshot(80, time: secondTime.addingTimeInterval(60), error: true), now: secondTime.addingTimeInterval(60))[0].samples.count == 2)
        precondition(store.record(snapshot: snapshot(80, time: nil), now: secondTime)[0].samples.count == 2)
        precondition(store.record(snapshot: snapshot(80, time: end), now: secondTime)[0].samples.count == 2, "future measurement ignored")
        precondition(store.record(snapshot: snapshot(80, time: secondTime, account: nil), now: secondTime).isEmpty)
        precondition(store.record(snapshot: snapshot(80, time: secondTime, account: "b@example.com"), now: secondTime)[0].samples.count == 1)
        precondition(store.record(snapshot: snapshot(80, time: secondTime, source: "web"), now: secondTime)[0].samples.count == 2, "same account across sources shares quota history")
        let reloaded = ClaudeQuotaHistoryStore(storageDirectory: directory)
        precondition(reloaded.record(snapshot: second, now: secondTime)[0].samples == secondSeries[0].samples)
        let fractionalTime = secondTime.addingTimeInterval(300.125)
        let fractional = snapshot(40, time: fractionalTime, reset: end.addingTimeInterval(0.125))
        let saved = reloaded.record(snapshot: fractional, now: fractionalTime)
        let again = ClaudeQuotaHistoryStore(storageDirectory: directory).record(snapshot: fractional, now: fractionalTime)
        precondition(saved == again && again[0].samples.count == 3, "fractional measurement deduplicates after reload")
        let file = directory.appendingPathComponent("claude-quota-history-v1.json")
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        precondition((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let data = try Data(contentsOf: file)
        let text = String(decoding: data, as: UTF8.self)
        precondition(!text.contains("example.com") && !text.contains("tokens") && !text.contains("cost"))
        precondition(snapshot(20, time: start, source: "admin-api").claudeSharedQuotaWindows.isEmpty)
        precondition(snapshot(20, time: start, minutes: 10080).claudeSharedQuotaWindows.count == 1, "weekly primary is never labeled 5 hours")
        precondition(snapshot(.infinity, time: start).claudeSharedQuotaWindows.count == 1)
        let before = secondSeries[0].samples.last!
        for after in [
            ClaudeQuotaSample(timestamp: secondTime.addingTimeInterval(60), usedPercent: 1, resetsAt: end),
            ClaudeQuotaSample(timestamp: secondTime.addingTimeInterval(60), usedPercent: 40, resetsAt: end.addingTimeInterval(3600)),
            ClaudeQuotaSample(timestamp: secondTime.addingTimeInterval(4000), usedPercent: 40, resetsAt: end),
            ClaudeQuotaSample(timestamp: end, usedPercent: 40, resetsAt: end),
        ] { precondition(!ClaudeQuotaSeries.connects(before, after), "reset/decrease/missing interval must break chart") }
        precondition(reloaded.record(snapshot: second, now: start.addingTimeInterval(90000)).isEmpty, "24h display excludes stale observations")
        // Corrupt storage must remain recoverable, not overwritten by new observations.
        try Data("broken".utf8).write(to: file)
        let broken = ClaudeQuotaHistoryStore(storageDirectory: directory)
        _ = broken.record(snapshot: first, now: start)
        precondition(broken.persistenceError != nil && (try! Data(contentsOf: file)) == Data("broken".utf8))
        print("PASS | Claude shared quota: identity/source isolation, timestamps, resets, gaps, persistence and token separation")
    }
}
