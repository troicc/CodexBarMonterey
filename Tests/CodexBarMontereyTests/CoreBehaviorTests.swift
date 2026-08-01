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

    private func credential(_ secret: String) -> ProviderCredentialInput {
        ProviderCredentialInput(
            secret: secret,
            accountLabel: "Default",
            enterpriseHost: "",
            workspaceID: "",
            region: "")
    }

    private func temporaryDirectory(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBarMontereyTests-\(name)-\(UUID().uuidString)", isDirectory: true)
    }
}
