import Foundation
import XCTest
@testable import CodexBarMonterey

final class CoreBehaviorTests: XCTestCase {
    func testScopedQuotaWindowsPreserveIdentityAndReset() throws {
        for provider in ["claude", "codex"] {
            let json = """
            {"provider":"\(provider)","usage":{"secondary":{"usedPercent":5,"windowMinutes":10080},
            "extraRateWindows":[{"id":"fable","title":"Fable only","window":{"usedPercent":4,"windowMinutes":10080,"resetsAt":"2026-09-17T23:00:00Z"}},
            {"id":"spark","title":"Weekly","window":{"usedPercent":7,"windowMinutes":10080}}]}}
            """
            let snapshot = try XCTUnwrap(CLIClient.decodeSnapshots(json).first)
            let dashboard = DashboardParser.dashboard(snapshot: snapshot, supplementalJSON: json)
            XCTAssertEqual(dashboard.quotas.map(\.title), ["Weekly", "Fable only", "Weekly"])
            XCTAssertEqual(dashboard.quotas.map(\.usedPercent), [5, 4, 7])
            XCTAssertEqual(Set(dashboard.quotas.map(\.id)).count, 3)
            XCTAssertNotNil(dashboard.quotas[1].resetsAt)
            XCTAssertEqual(dashboard.quotas[1].windowMinutes, 10080)
        }
    }

    func testPlanAndClaudeCLIIdentityFallbackIsolation() throws {
        func snapshots(_ source: String = "claude", _ usage: String = "{}") throws -> [ProviderSnapshot] {
            try CLIClient.decodeSnapshots("{\"provider\":\"claude\",\"source\":\"\(source)\",\"usage\":\(usage)}")
        }
        let status = """
        {"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty","email":"test@example.com","subscriptionType":"pro"}
        """
        let original = try snapshots()
        let enriched = ClaudeCLIAccountStatus.enrich(original, json: status)[0]
        XCTAssertEqual(enriched.accountDisplayName, "test@example.com")
        XCTAssertEqual(enriched.planDisplayName, "Pro")
        XCTAssertEqual(enriched.id, original[0].id)
        for input in [try snapshots("oauth"), try snapshots("web"), original + original,
                      try snapshots("claude", "{\"accountEmail\":\"other@example.com\"}")] {
            XCTAssertEqual(ClaudeCLIAccountStatus.enrich(input, json: status), input)
        }
        for invalid in ["{}", status.replacingOccurrences(of: "true", with: "false"),
                        status.replacingOccurrences(of: "firstParty", with: "thirdParty")] {
            XCTAssertEqual(ClaudeCLIAccountStatus.enrich(original, json: invalid), original)
        }
        let plans: [(String, String?)] = [("prolite", "Pro Lite"), ("plus", "Plus"), ("pro", "Pro"), ("oauth", nil)]
        for (method, expected) in plans {
            let codex = try CLIClient.decodeSnapshots("{\"provider\":\"codex\",\"usage\":{\"identity\":{\"loginMethod\":\"\(method)\"}}}")[0]
            XCTAssertEqual(codex.planDisplayName, expected)
        }
        let explicit = try CLIClient.decodeSnapshots("{\"provider\":\"codex\",\"plan\":\"Enterprise\",\"usage\":{\"loginMethod\":\"pro\"}}")[0]
        XCTAssertEqual(explicit.planDisplayName, "Enterprise")
    }

    func testCostHistoryKeepsKnownSubtotalAndLabelsPartialEstimates() {
        for provider in ["codex", "claude"] {
            let model = provider == "claude" ? "claude-priced" : "gpt-priced"
            let unpriced = provider == "claude" ? "claude-unknown" : "codex-auto-review"
            let json = """
            {"provider":"\(provider)","daily":[
              {"date":"2026-09-08","totalTokens":100,"totalCost":99,"modelBreakdowns":[
                {"modelName":"\(model)","totalTokens":80,"cost":3.5},
                {"modelName":"\(unpriced)","totalTokens":20}]},
              {"date":"2026-09-10","totalTokens":20,"modelsUsed":["\(unpriced)"],"modelBreakdowns":[
                {"modelName":"\(unpriced)","totalTokens":20}]},
              {"date":"2026-09-11","totalTokens":50,"totalCost":2,"modelsUsed":["\(model)"]}
            ]}
            """
            let snapshot = ProviderSnapshot(provider: provider, version: nil, source: "test", status: nil,
                usage: nil, credits: nil, account: nil, plan: nil, error: nil, rawJSON: "{}")
            let history = DashboardParser.dashboard(snapshot: snapshot, supplementalJSON: json).history
            XCTAssertEqual(history.map(\.spend), [3.5, 0, nil, 2])
            XCTAssertEqual(history[0].spendEstimate?.isPartial, true)
            XCTAssertEqual(history[0].spendEstimate?.unpricedModels, [unpriced])
            XCTAssertNil(history[1].spendEstimate)
            XCTAssertNil(history[2].spendEstimate?.knownCost)
            XCTAssertEqual(history[3].spendEstimate?.isPartial, false)
        }
    }

    func testCostChartsKeepInactiveDaysAndUnknownPrices() {
        for provider in ["claude", "codex"] {
            let snapshot = ProviderSnapshot(provider: provider, version: nil, source: "test", status: nil,
                usage: nil, credits: nil, account: nil, plan: nil, error: nil, rawJSON: "{}")
            let json = """
            {"provider":"\(provider)","daily":[
              {"date":"2026-09-08","totalTokens":100,"totalCost":5,"modelsUsed":["claude-test"]},
              {"date":"2026-09-11","totalTokens":20,"modelsUsed":["claude-test"]}
            ]}
            """
            let history = DashboardParser.dashboard(snapshot: snapshot, supplementalJSON: json).history
            XCTAssertEqual(history.map(\.dayKey), ["2026-09-08", "2026-09-09", "2026-09-10", "2026-09-11"])
            XCTAssertEqual(history.map(\.tokens), [100, 0, 0, 20])
            XCTAssertEqual(history.map(\.spend), [5, 0, 0, nil])
        }
    }

    func testDailyAPIGapsStayUnknownAcrossYearBoundary() {
        let points = [
            DashboardHistoryPoint(label: "Jan 2", tokens: 20, dayKey: "2026-01-02"),
            DashboardHistoryPoint(label: "Dec 31", tokens: 100, dayKey: "2025-12-31"),
        ]
        let history = DashboardHistoryPoint.continuousDays(points)
        XCTAssertEqual(history.map(\.dayKey), ["2025-12-31", "2026-01-01", "2026-01-02"])
        XCTAssertEqual(history.map(\.tokens), [100, nil, 20])
        XCTAssertEqual(Set(history.map(\.id)).count, 3)
        let hourly = [DashboardHistoryPoint(label: "08:00", tokens: 5), DashboardHistoryPoint(label: "10:00", tokens: 8)]
        XCTAssertEqual(DashboardHistoryPoint.continuousDays(hourly), hourly)
    }

    func testSnapshotIdentityIncludesUsageAccount() {
        let first = snapshot(email: "first@example.com", organization: "Example")
        let second = snapshot(email: "second@example.com", organization: "Example")

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.id, snapshot(email: "FIRST@EXAMPLE.COM", organization: "EXAMPLE").id)
        XCTAssertEqual(first.accountDisplayName, "first@example.com · Example")
    }

    func testSpendSamplingRetainsBaselineAndDisclosesLongGap() throws {
        let directory = temporaryDirectory(named: "spend")
        defer { try? FileManager.default.removeItem(at: directory) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let store = LocalSpendHistoryStore(directoryURL: directory, calendar: calendar)

        _ = store.record(
            provider: "moonshot",
            accountKey: "moonshot::first@example.com",
            rawJSON: balanceJSON(100),
            now: start)
        _ = store.record(
            provider: "moonshot",
            accountKey: "moonshot::first@example.com",
            rawJSON: balanceJSON(90),
            now: start.addingTimeInterval(60))

        let sampled = try payload(store.record(
            provider: "moonshot",
            accountKey: "moonshot::first@example.com",
            rawJSON: balanceJSON(80),
            now: start.addingTimeInterval(301)))
        XCTAssertEqual(number(sampled, "last30DaysSpend"), 20, accuracy: 0.000_001)

        let longGap = try payload(store.record(
            provider: "moonshot",
            accountKey: "moonshot::first@example.com",
            rawJSON: balanceJSON(70),
            now: start.addingTimeInterval(3 * 60 * 60)))
        XCTAssertEqual(number(longGap, "last30DaysSpend"), 20, accuracy: 0.000_001)
        XCTAssertEqual((longGap["unattributedIntervals"] as? NSNumber)?.intValue, 1)
    }

    func testConfigBackupRestoresPreviousCredential() throws {
        let directory = temporaryDirectory(named: "config")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configURL = directory.appendingPathComponent("config.json")
        let store = CodexBarConfigStore(
            environment: ["CODEXBAR_CONFIG": configURL.path],
            homeDirectory: directory)
        let profile = ProviderAuthenticationCatalog.profile(for: "openrouter")

        _ = try store.save(
            providerID: "openrouter",
            profile: profile,
            input: credential("original"))
        let backup = try store.makeBackup()
        _ = try store.save(
            providerID: "openrouter",
            profile: profile,
            input: credential("replacement"))
        try store.restore(backup)

        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any])
        let providers = try XCTUnwrap(root["providers"] as? [[String: Any]])
        let openRouter = try XCTUnwrap(providers.first { ($0["id"] as? String) == "openrouter" })
        XCTAssertEqual(openRouter["apiKey"] as? String, "original")
    }

    func testProviderStatusClassification() {
        XCTAssertEqual(
            ProviderStatus(
                indicator: "none",
                description: "All Systems Operational",
                updatedAt: nil,
                url: nil).health,
            .operational)
        XCTAssertEqual(
            ProviderStatus(
                indicator: "minor",
                description: "Degraded performance",
                updatedAt: nil,
                url: nil).health,
            .degraded)
        XCTAssertEqual(
            ProviderStatus(
                indicator: "critical",
                description: "Major outage",
                updatedAt: nil,
                url: nil).health,
            .outage)
    }

    func testQuotaPaceShowsReserveAndEarlyRunOut() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = now.addingTimeInterval(50 * 60)
        let reserve = DashboardQuotaLane(
            id: "reserve",
            title: "100 minutes",
            usedPercent: 25,
            resetText: nil,
            resetsAt: reset,
            windowMinutes: 100)
        XCTAssertEqual(reserve.paceDescription(now: now), "25% reserve")

        let overPace = DashboardQuotaLane(
            id: "over",
            title: "100 minutes",
            usedPercent: 80,
            resetText: nil,
            resetsAt: reset,
            windowMinutes: 100)
        XCTAssertTrue(overPace.paceDescription(now: now)?.hasPrefix("Runs out in ") == true)
    }

    func testZaiHeadlineQuotaPrefersFiveHourWindowOverMCP() {
        let snapshot = quotaSnapshot(
            primary: RateWindow(usedPercent: 72, windowMinutes: 43_200, resetsAt: nil),
            secondary: RateWindow(usedPercent: 11, windowMinutes: 300, resetsAt: nil))

        XCTAssertEqual(snapshot.maximumUsedPercent, 72)
        XCTAssertEqual(snapshot.headlineUsedPercent, 11)
        XCTAssertEqual(snapshot.headlineQuotaLabel, "5h")

        let legacy = quotaSnapshot(
            primary: RateWindow(usedPercent: 9, windowMinutes: nil, resetsAt: nil),
            secondary: RateWindow(usedPercent: 80, windowMinutes: nil, resetsAt: nil))
        XCTAssertEqual(legacy.headlineUsedPercent, 9)
    }

    func testZaiTokenHistoryBuildsThirtyDayMetricWithoutQuotaSamples() throws {
        let directory = temporaryDirectory(named: "tokens")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-29T08:30:00Z"))
        let rawJSON = """
        {
          "zaiUsage": {
            "modelUsage": {
              "xTime": ["2026-08-29T06:00:00Z", "2026-08-29T07:00:00Z"],
              "modelDataList": [
                {"modelName": "glm-4.5", "tokensUsage": [120, 180]},
                {"modelName": "glm-4", "tokensUsage": [40, 60]}
              ]
            }
          }
        }
        """
        let zai = ProviderSnapshot(
            provider: "zai",
            version: nil,
            source: "api",
            status: nil,
            usage: nil,
            credits: nil,
            account: "zhipu@example.com",
            plan: nil,
            error: nil,
            rawJSON: rawJSON)
        let ledger = LocalTokenHistoryStore(storageDirectory: directory)
        let supplement = try XCTUnwrap(ledger.record(
            snapshot: zai,
            supplementalJSON: nil,
            now: now))
        let revision = ledger.revision
        _ = ledger.record(snapshot: zai, supplementalJSON: nil, now: now)
        XCTAssertEqual(ledger.revision, revision)

        let report = ledger.report(
            accountID: try XCTUnwrap(ledger.accounts().first?.id),
            range: .thirtyDays,
            now: now)
        XCTAssertEqual(report.last30DaysTokens, 400)
        XCTAssertEqual(report.modelTotals.first?.name, "glm-4.5")

        let dashboard = DashboardParser.dashboard(snapshot: zai, supplementalJSON: supplement)
        XCTAssertEqual(dashboard.metrics.first(where: { $0.id == "30d-tokens" })?.value, "400")
        XCTAssertEqual(dashboard.historyContext, .dailyUsage)
        XCTAssertFalse(dashboard.history.isEmpty)
    }

    func testTokenAccountActivationAndRemovalPreservesOtherAccounts() throws {
        let directory = temporaryDirectory(named: "accounts")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CodexBarConfigStore(
            environment: ["CODEXBAR_CONFIG": directory.appendingPathComponent("config.json").path],
            homeDirectory: directory)
        let profile = ProviderAuthenticationCatalog.profile(for: "deepseek")

        _ = try store.save(
            providerID: "deepseek",
            profile: profile,
            input: credential("first", label: "Work"))
        _ = try store.save(
            providerID: "deepseek",
            profile: profile,
            input: credential("second", label: "Personal"))

        var accounts = try store.configuredTokenAccounts(providerID: "deepseek")
        XCTAssertEqual(accounts.map(\.label), ["Work", "Personal"])
        XCTAssertEqual(accounts.first(where: \.isActive)?.label, "Personal")

        let work = try XCTUnwrap(accounts.first(where: { $0.label == "Work" }))
        try store.activateTokenAccount(providerID: "deepseek", accountID: work.id)
        accounts = try store.configuredTokenAccounts(providerID: "deepseek")
        XCTAssertEqual(accounts.first(where: \.isActive)?.label, "Work")

        let personal = try XCTUnwrap(accounts.first(where: { $0.label == "Personal" }))
        try store.removeTokenAccount(providerID: "deepseek", accountID: personal.id)
        accounts = try store.configuredTokenAccounts(providerID: "deepseek")
        XCTAssertEqual(accounts.map(\.label), ["Work"])
        XCTAssertTrue(accounts[0].isActive)
    }

    private func snapshot(email: String, organization: String) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: "zai",
            version: nil,
            source: "api",
            status: nil,
            usage: UsageSnapshot(
                primary: nil,
                secondary: nil,
                tertiary: nil,
                updatedAt: nil,
                identity: nil,
                accountEmail: email,
                accountOrganization: organization,
                loginMethod: nil),
            credits: nil,
            account: nil,
            plan: nil,
            error: nil,
            rawJSON: nil)
    }

    private func quotaSnapshot(primary: RateWindow?, secondary: RateWindow?) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: "zai",
            version: nil,
            source: "api",
            status: nil,
            usage: UsageSnapshot(
                primary: primary,
                secondary: secondary,
                tertiary: nil,
                updatedAt: nil,
                identity: nil,
                accountEmail: nil,
                accountOrganization: nil,
                loginMethod: nil),
            credits: nil,
            account: nil,
            plan: nil,
            error: nil,
            rawJSON: nil)
    }

    private func balanceJSON(_ value: Double) -> String {
        "{\"availableBalance\":\(value),\"currency\":\"USD\"}"
    }

    private func payload(_ source: String?) throws -> [String: Any] {
        let data = try XCTUnwrap(source?.data(using: .utf8))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(root["localSpend"] as? [String: Any])
    }

    private func number(_ payload: [String: Any], _ key: String) -> Double {
        (payload[key] as? NSNumber)?.doubleValue ?? .nan
    }

    private func credential(_ secret: String, label: String = "Default") -> ProviderCredentialInput {
        ProviderCredentialInput(
            secret: secret,
            accountLabel: label,
            enterpriseHost: "",
            workspaceID: "",
            region: "")
    }

    private func temporaryDirectory(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBarMontereyTests-\(name)-\(UUID().uuidString)", isDirectory: true)
    }
}
