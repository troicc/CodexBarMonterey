import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Token history regression failed: \(message)\n", stderr)
        exit(1)
    }
}

private func snapshot(provider: String, account: String, rawJSON: String) -> ProviderSnapshot {
    ProviderSnapshot(
        provider: provider,
        version: nil,
        source: "regression",
        status: nil,
        usage: nil,
        credits: nil,
        account: account,
        plan: nil,
        error: nil,
        rawJSON: rawJSON)
}

private func isoDate(_ value: String) -> Date {
    guard let result = ISO8601DateFormatter().date(from: value) else {
        fatalError("Invalid test date: \(value)")
    }
    return result
}

let fixtureOverride = ProcessInfo.processInfo.environment["CODEXBAR_TOKEN_HISTORY_FIXTURE_DIRECTORY"]
let directory = fixtureOverride.map { URL(fileURLWithPath: $0, isDirectory: true) } ??
    FileManager.default.temporaryDirectory
        .appendingPathComponent("codexbar-token-history-regression-\(UUID().uuidString)", isDirectory: true)
defer {
    if fixtureOverride == nil { try? FileManager.default.removeItem(at: directory) }
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!
let now = isoDate("2026-08-29T08:30:00Z")
let store = LocalTokenHistoryStore(storageDirectory: directory, calendar: calendar)

// The chart must keep absent calendar buckets without adding synthetic ledger
// records or claiming that an unobserved API interval had zero usage.
let gapDirectory = directory.appendingPathComponent("calendar-gaps")
let gapStore = LocalTokenHistoryStore(storageDirectory: gapDirectory, calendar: calendar)
let gapSnapshot = snapshot(provider: "zai", account: "gaps", rawJSON: #"{"zaiUsage":{"modelUsage":{"xTime":["2026-08-26T06:00:00Z","2026-08-29T06:00:00Z"],"modelDataList":[{"modelName":"glm-test","tokensUsage":[100,20]}]}}}"#)
let gapPayload = gapStore.record(snapshot: gapSnapshot, supplementalJSON: nil, now: now)!
let gapAccount = gapStore.accounts()[0]
let gapReport = gapStore.report(accountID: gapAccount.id, range: .week, now: now)
require(gapReport.chart.count == 4, "z.ai missing days compressed the calendar")
require(gapReport.chart.map(\.tokens) == [100, 0, 0, 20], "gap filling altered totals")
require(gapReport.chart.map(\.hasRecords) == [true, false, false, true], "unknown days became observed zeroes")
require(gapReport.recordCount == 2 && gapReport.totalTokens == 120, "chart placeholders entered the ledger")
let gapObject = try JSONSerialization.jsonObject(with: Data(gapPayload.utf8)) as! [String: Any]
let gapDays = (gapObject["localTokenHistory"] as! [String: Any])["daily"] as! [[String: Any]]
require(gapDays.count == 4 && gapDays[1]["tokens"] == nil, "z.ai dashboard lost the missing-data distinction")
let monthReport = gapStore.report(accountID: gapAccount.id, range: .year, now: now)
require(monthReport.chart.count == 1 && monthReport.chart[0].tokens == 120, "month aggregation changed")

let initialZai = snapshot(
    provider: "zai",
    account: "zhipu@example.com",
    rawJSON: """
    {
      "usage": {
        "zaiUsage": {
          "modelUsage": {
            "xTime": ["2026-08-28T08:00:00Z", "2026-08-29T06:00:00Z"],
            "modelDataList": [
              {"modelName": "glm-4.5", "tokensUsage": [100, 200]},
              {"modelName": "glm-4", "tokensUsage": [50, 75]}
            ]
          }
        }
      }
    }
    """)

let firstPayload = store.record(snapshot: initialZai, supplementalJSON: nil, now: now)
require(firstPayload?.contains("last30DaysTokens") == true, "z.ai dashboard supplement was not generated")
let firstRevision = store.revision
_ = store.record(snapshot: initialZai, supplementalJSON: nil, now: now)
require(store.revision == firstRevision, "overlapping z.ai hours were not de-duplicated")

let updatedZai = snapshot(
    provider: "zai",
    account: "zhipu@example.com",
    rawJSON: """
    {
      "zaiUsage": {
        "modelUsage": {
          "xTime": ["2026-08-28T08:00:00Z", "2026-08-29T06:00:00Z", "2026-08-29T07:00:00Z"],
          "modelDataList": [
            {"modelName": "glm-4.5", "tokensUsage": [100, 220, 300]},
            {"modelName": "glm-4", "tokensUsage": [50, 75, 25]}
          ]
        }
      }
    }
    """)

_ = store.record(snapshot: updatedZai, supplementalJSON: nil, now: now)
let zaiAccount = store.accounts().first(where: { $0.providerID == "zai" })
require(zaiAccount != nil, "z.ai account was not indexed")
let zaiReport = store.report(accountID: zaiAccount?.id, range: .thirtyDays, now: now)
require(zaiReport.recordCount == 6, "z.ai model/hour bucket count was not preserved")
require(zaiReport.last30DaysTokens == 770, "z.ai corrected 30-day total was not merged")
require(zaiReport.todayTokens == 620, "z.ai current-day total was incorrect")
require(zaiReport.modelTotals.first?.name == "glm-4.5", "z.ai model totals were not retained")
require(zaiReport.modelTotals.first?.tokens == 620, "z.ai leading-model total was incorrect")

let codex = snapshot(
    provider: "codex",
    account: "codex@example.com",
    rawJSON: "{}")
let codexCost = """
{
  "provider": "codex",
  "daily": [
    {
      "date": "2025-01-01",
      "inputTokens": 100,
      "outputTokens": 200,
      "cacheReadTokens": 300,
      "cacheCreationTokens": 400,
      "totalTokens": 1000,
      "totalCost": 1.25,
      "modelsUsed": ["gpt-5"]
    },
    {
      "date": "2026-08-29",
      "inputTokens": 500,
      "outputTokens": 600,
      "cacheReadTokens": 700,
      "cacheCreationTokens": 200,
      "totalTokens": 2000,
      "totalCost": 2.50,
      "modelsUsed": ["gpt-5", "gpt-5-codex"]
    }
  ]
}
"""

_ = store.record(snapshot: codex, supplementalJSON: codexCost, now: now)
let codexAccount = store.accounts().first(where: { $0.providerID == "codex" })
require(codexAccount != nil, "Codex account was not indexed")
let codexAll = store.report(accountID: codexAccount?.id, range: .all, now: now)
require(codexAll.allTimeTokens == 3000, "old Codex records were pruned or omitted")
require(codexAll.components.input == 600, "Codex input tokens were not retained")
require(codexAll.components.output == 800, "Codex output tokens were not retained")
require(codexAll.components.cacheRead == 1000, "Codex cache-read tokens were not retained")
require(codexAll.components.cacheCreation == 600, "Codex cache-creation tokens were not retained")

let persisted = LocalTokenHistoryStore(storageDirectory: directory, calendar: calendar)
require(persisted.accounts().count == 2, "ledger did not survive reload")
require(persisted.report(accountID: nil, range: .all, now: now).allTimeTokens == 3770, "reloaded all-provider total was incorrect")

let csv = persisted.exportCSV(accountID: nil, range: nil, now: now)
require(csv.contains("input_tokens"), "CSV component columns are missing")
require(csv.contains("zai.modelUsage"), "CSV did not include z.ai source rows")
let json = try persisted.exportJSON(accountID: nil, range: nil, now: now)
let exportedRoot = try JSONSerialization.jsonObject(with: json) as? [String: Any]
require(exportedRoot?["records"] != nil, "JSON export records are missing")

let historyURL = directory.appendingPathComponent("token-history-v1.json")
let attributes = try FileManager.default.attributesOfItem(atPath: historyURL.path)
if let permissions = attributes[.posixPermissions] as? NSNumber {
    require(permissions.intValue & 0o777 == 0o600, "token history file permissions are not 0600")
}

print("Local token history regression tests passed.")
