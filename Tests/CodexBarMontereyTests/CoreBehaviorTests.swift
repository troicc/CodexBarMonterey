import Foundation
import XCTest
@testable import CodexBarMonterey

final class CoreBehaviorTests: XCTestCase {
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
