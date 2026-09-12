import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("model-attribution-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: directory) }
let snapshot = ProviderSnapshot(provider: "claude", version: nil, source: "local", status: nil,
    usage: nil, credits: nil, account: nil, plan: nil, error: nil, rawJSON: "{}")
let legacy = #"""
{"provider":"claude","daily":[
 {"date":"2026-09-02","totalTokens":100,"modelsUsed":["glm-5.3"]},
 {"date":"2026-09-03","inputTokens":80,"outputTokens":20,"totalTokens":100,"totalCost":2,"modelsUsed":["glm-5.3","claude-opus-4-8"]}
]}
"""#
let current = #"""
{"provider":"claude","last30DaysTokens":240,"last30DaysCostUSD":3,"daily":[
 {"date":"2026-09-02","totalTokens":100,"modelsUsed":["glm-5.3"],"modelBreakdowns":[{"modelName":"glm-5.3","totalTokens":100}]},
 {"date":"2026-09-03","inputTokens":80,"outputTokens":20,"totalTokens":100,"totalCost":2,"modelsUsed":["glm-5.3","claude-opus-4-8"],"modelBreakdowns":[{"modelName":"glm-5.3","totalTokens":60},{"modelName":"claude-opus-4-8","totalTokens":40,"cost":2}]},
 {"date":"2026-09-04","totalTokens":40,"totalCost":1,"modelsUsed":["claude-opus-4-8","claude-unknown"],"modelBreakdowns":[{"modelName":"claude-opus-4-8","totalTokens":30,"cost":1},{"modelName":"claude-unknown","totalTokens":10}]}
]}
"""#
let now = ISO8601DateFormatter().date(from: "2026-09-08T12:00:00Z")!
let raw = CostHistoryPayloadParser.payload(provider: "claude", fromJSON: current)!
let filtered = raw.claudeModelHistory
require(filtered.resolvedLast30DaysTokens == 80, "mixed-day GLM tokens leaked into Claude")
require(filtered.sortedDaily.first?.date == "2026-09-03", "GLM-only day remained in Claude")
require(filtered.sortedDaily.first?.totalCost == 2, "known Claude cost was lost")
require(filtered.resolvedLast30DaysCostUSD == nil, "partial estimated price became a complete total")
require(filtered.sortedDaily.last?.resolvedCost == nil, "unknown price became zero in history")
require(filtered.sortedDaily.first?.inputTokens == nil, "mixed components were fabricated")
let store = LocalTokenHistoryStore(storageDirectory: directory)
_ = store.record(snapshot: snapshot, supplementalJSON: legacy, now: now)
require(store.accounts().contains { $0.providerID == "claude-code-unattributed" }, "ambiguous legacy day was attributed to Claude")
_ = store.record(snapshot: snapshot, supplementalJSON: current, now: now)
let accounts = store.accounts()
let claude = accounts.first { $0.providerID == "claude" }!
let other = accounts.first { $0.providerID == "claude-code-other" }!
require(!accounts.contains { $0.providerID == "claude-code-unattributed" }, "superseded aggregate remained")
let report = store.report(accountID: claude.id, range: .all, now: now)
require(report.allTimeTokens == 80, "migration double counted the old aggregate")
require(report.modelTotals.first?.tokens == 70, "Claude per-model token total wrong")
require(report.modelTotals.reduce(0) { $0 + $1.tokens } == report.totalTokens, "model totals do not reconcile")
require(store.report(accountID: other.id, range: .all, now: now).allTimeTokens == 160, "third-party tokens were lost")
require(store.report(accountID: nil, range: .all, now: now).allTimeTokens == 80, "client logs overlap provider totals")
let revision = store.revision
_ = store.record(snapshot: snapshot, supplementalJSON: current, now: now)
require(store.revision == revision, "identical refresh was not idempotent")
let reloaded = LocalTokenHistoryStore(storageDirectory: directory)
require(reloaded.report(accountID: claude.id, range: .all, now: now).allTimeTokens == 80, "migration did not survive reload")
require(FileManager.default.fileExists(atPath: directory.appendingPathComponent("token-history-before-model-attribution.json").path), "migration backup missing")
let exported = try JSONSerialization.jsonObject(with: reloaded.exportJSON(accountID: nil, range: nil, now: now)) as! [String: Any]
let rows = exported["records"] as! [[String: Any]]
require(rows.reduce(0) { $0 + ($1["totalTokens"] as! Double) } == 240, "full export must retain all sources")
let codexJSON = current.replacingOccurrences(of: "\"provider\":\"claude\"", with: "\"provider\":\"codex\"")
let codex = ProviderSnapshot(provider: "codex", version: nil, source: "local", status: nil,
    usage: nil, credits: nil, account: nil, plan: nil, error: nil, rawJSON: "{}")
_ = store.record(snapshot: codex, supplementalJSON: codexJSON, now: now)
let codexAccount = store.accounts().first { $0.providerID == "codex" }!
require(store.report(accountID: codexAccount.id, range: .all, now: now).modelTotals.count == 3, "Codex per-model breakdown omitted")
print("Model attribution, unknown prices, migration, deduplication and exports passed.")

let scopedJSON = #"""
{"provider":"codex","daily":[
 {"date":"2026-08-29","totalTokens":10000,"totalCost":900,"modelsUsed":["old-model"]},
 {"date":"2026-08-30","totalTokens":300,"totalCost":1,"modelsUsed":["gpt-5.6-sol"]},
 {"date":"2026-09-08","totalTokens":100,"totalCost":4,"modelsUsed":["gpt-6-astra","codex-auto-review"],"modelBreakdowns":[{"modelName":"gpt-6-astra","totalTokens":80,"cost":4},{"modelName":"codex-auto-review","totalTokens":20}]},
 {"date":"2026-09-09","totalTokens":20000,"totalCost":500,"modelsUsed":["future-model"]}
]}
"""#
let scoped = CostHistoryPayloadParser.payload(provider: "codex", fromJSON: scopedJSON)!
var localCalendar = Calendar(identifier: .gregorian)
localCalendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
let localNow = ISO8601DateFormatter().date(from: "2026-09-08T00:15:00Z")!
let estimate = scoped.costEstimate(dayCount: 1, now: localNow, calendar: localCalendar)
require(estimate.knownCost == 4 && estimate.isPartial, "known GPT-6 cost must remain visible as partial")
require(estimate.unpricedModels == ["codex-auto-review"], "unpriced model reason missing")
require(scoped.topModel(dayCount: 10, now: localNow, calendar: localCalendar) == "gpt-5.6-sol", "10d must include the ninth prior day and exclude the tenth/future")
require(scoped.topModel(dayCount: 1, now: localNow, calendar: localCalendar) == "gpt-6-astra", "today ranking used prices or old days")
let beforeLocalMidnight = localNow.addingTimeInterval(-9 * 3600)
require(scoped.topModel(dayCount: 1, now: beforeLocalMidnight, calendar: localCalendar) == nil, "today ignored local midnight")
let unknownDay = raw.sortedDaily[0]
let unknownEstimate = CostEstimateSummary(days: [unknownDay])
require(unknownEstimate.knownCost == nil && unknownEstimate.isPartial, "all-unpriced usage became a zero estimate")
let completeDay = filtered.sortedDaily[0]
let completeEstimate = CostEstimateSummary(days: [completeDay])
require(completeEstimate.knownCost == 2 && !completeEstimate.isPartial, "complete estimate marked partial")
let noUsage = scoped.costEstimate(dayCount: 1, now: beforeLocalMidnight, calendar: localCalendar)
require(noUsage.knownCost == 0 && !noUsage.isPartial, "empty day should have a known zero")
let ambiguous = CostHistoryPayloadParser.payload(provider: "claude", fromJSON: legacy)!
require(ambiguous.topModel(dayCount: 10, now: localNow, calendar: localCalendar) == nil, "mixed unknown model distribution produced a guessed winner")
let tieJSON = #"{"provider":"codex","daily":[{"date":"2026-09-08","totalTokens":20,"modelBreakdowns":[{"modelName":"z-model","totalTokens":10,"cost":900},{"modelName":"a-model","totalTokens":10}]}]}"#
let tie = CostHistoryPayloadParser.payload(provider: "codex", fromJSON: tieJSON)!
require(tie.topModel(dayCount: 1, now: localNow, calendar: localCalendar) == "a-model", "token tie order is not deterministic")
let zaiSnapshot = ProviderSnapshot(provider: "zai", version: nil, source: "api", status: nil, usage: nil,
    credits: nil, account: nil, plan: nil, error: nil, rawJSON: #"""
{"zaiUsage":{"modelUsage":{"xTime":["2026-08-30T06:00:00Z","2026-09-08T00:00:00Z"],"modelDataList":[{"modelName":"glm-a","tokensUsage":[300,0]},{"modelName":"glm-b","tokensUsage":[0,80]}]}}}
"""#)
let zaiStore = LocalTokenHistoryStore(storageDirectory: directory.appendingPathComponent("zai"), calendar: localCalendar)
let zaiPayload = zaiStore.record(snapshot: zaiSnapshot, supplementalJSON: nil, now: localNow)!
let zaiRoot = try JSONSerialization.jsonObject(with: Data(zaiPayload.utf8)) as! [String: Any]
let zaiHistory = zaiRoot["localTokenHistory"] as! [String: Any]
require(zaiHistory["topModel10Days"] as? String == "glm-a", "ledger 10d ranking incorrect")
require(zaiHistory["topModelToday"] as? String == "glm-b", "ledger today ranking incorrect")
print("Partial estimates and 10d/today token rankings passed, including local midnight and ledger providers.")
