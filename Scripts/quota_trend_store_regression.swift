import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Quota trend store regression failed: \(message)\n", stderr)
        exit(1)
    }
}

func sampledValues(_ source: String?) -> [Double] {
    guard let source = source,
          let data = source.data(using: String.Encoding.utf8),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let rows = root["localQuotaTrend"] as? [[String: Any]]
    else { return [] }
    return rows.compactMap { ($0["tokens"] as? NSNumber)?.doubleValue }
}

let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("CodexBarMonterey-five-hour-trend-\(UUID().uuidString)", isDirectory: true)
defer { try? FileManager.default.removeItem(at: directory) }

// Put the five-hour window in the secondary slot and give other windows larger
// percentages. The trend must follow the semantic 300-minute window (37%), not
// the maximum percentage (81%) and not the MCP/monthly quota (2%).
let snapshot = ProviderSnapshot(
    provider: "zai",
    version: nil,
    source: "api",
    status: nil,
    usage: UsageSnapshot(
        primary: RateWindow(usedPercent: 2, windowMinutes: 43200, resetsAt: nil),
        secondary: RateWindow(usedPercent: 37, windowMinutes: 300, resetsAt: nil),
        tertiary: RateWindow(usedPercent: 81, windowMinutes: 1440, resetsAt: nil),
        updatedAt: Date(),
        identity: nil,
        accountEmail: nil,
        accountOrganization: nil,
        loginMethod: nil),
    credits: nil,
    account: nil,
    plan: nil,
    error: nil,
    rawJSON: nil)

let start = Date(timeIntervalSince1970: 1_800_000_000)
let store = LocalQuotaTrendStore(storageDirectory: directory)
let first = store.record(snapshot: snapshot, now: start)
let second = store.record(snapshot: snapshot, now: start.addingTimeInterval(600))
require(sampledValues(first) == [37], "first sample did not use the five-hour quota")
require(sampledValues(second) == [37, 37], "spaced five-hour samples were not retained")

let reloaded = LocalQuotaTrendStore(storageDirectory: directory)
let third = reloaded.record(snapshot: snapshot, now: start.addingTimeInterval(1200))
require(sampledValues(third) == [37, 37, 37], "persisted five-hour samples were not reloaded")

// Older payloads can omit windowMinutes. In that case only usage.primary is a
// valid fallback; secondary/MCP percentages must not take over the main trend.
let legacyDirectory = directory.appendingPathComponent("legacy", isDirectory: true)
let legacySnapshot = ProviderSnapshot(
    provider: "zai",
    version: nil,
    source: "api",
    status: nil,
    usage: UsageSnapshot(
        primary: RateWindow(usedPercent: 11, windowMinutes: nil, resetsAt: nil),
        secondary: RateWindow(usedPercent: 72, windowMinutes: nil, resetsAt: nil),
        tertiary: nil,
        updatedAt: Date(),
        identity: nil,
        accountEmail: nil,
        accountOrganization: nil,
        loginMethod: nil),
    credits: nil,
    account: nil,
    plan: nil,
    error: nil,
    rawJSON: nil)
let legacyStore = LocalQuotaTrendStore(storageDirectory: legacyDirectory)
require(sampledValues(legacyStore.record(snapshot: legacySnapshot, now: start)) == [11],
        "legacy payload did not fall back to the primary window")

print("Local z.ai five-hour quota trend regression tests passed.")
