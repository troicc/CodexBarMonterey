import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Quota trend store regression failed: \(message)\n", stderr)
        exit(1)
    }
}

let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("CodexBarMonterey-quota-trend-\(UUID().uuidString)", isDirectory: true)
defer { try? FileManager.default.removeItem(at: directory) }

let snapshot = ProviderSnapshot(
    provider: "zai",
    version: nil,
    source: "api",
    status: nil,
    usage: UsageSnapshot(
        primary: RateWindow(usedPercent: 0, windowMinutes: 300, resetsAt: nil),
        secondary: RateWindow(usedPercent: 2, windowMinutes: 43200, resetsAt: nil),
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

let start = Date(timeIntervalSince1970: 1_800_000_000)
let store = LocalQuotaTrendStore(storageDirectory: directory)
let first = store.record(snapshot: snapshot, now: start)
let second = store.record(snapshot: snapshot, now: start.addingTimeInterval(600))
require(first?.contains("localQuotaTrend") == true, "first sample was not serialized")
require(second?.components(separatedBy: "tokens").count == 3, "two spaced samples were not retained")

let reloaded = LocalQuotaTrendStore(storageDirectory: directory)
let third = reloaded.record(snapshot: snapshot, now: start.addingTimeInterval(1200))
require(third?.components(separatedBy: "tokens").count == 4, "persisted samples were not reloaded")
print("Local z.ai quota trend regression tests passed.")
