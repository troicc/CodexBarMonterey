import Foundation

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("Local spend regression failed: \(message)\n").utf8))
    exit(1)
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fail(message) }
}

private func balanceJSON(_ amount: Double) -> String {
    "{\"availableBalance\":\(amount),\"currency\":\"USD\"}"
}

private func localSpend(_ source: String?) -> [String: Any] {
    guard let source = source,
          let data = source.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let payload = root["localSpend"] as? [String: Any]
    else { fail("could not decode localSpend payload") }
    return payload
}

private func number(_ payload: [String: Any], _ key: String) -> Double {
    guard let value = payload[key] as? NSNumber else { fail("missing numeric field \(key)") }
    return value.doubleValue
}

private func integer(_ payload: [String: Any], _ key: String) -> Int {
    guard let value = payload[key] as? NSNumber else { fail("missing integer field \(key)") }
    return value.intValue
}

var calendar = Calendar(identifier: .gregorian)
calendar.locale = Locale(identifier: "en_US_POSIX")
calendar.timeZone = TimeZone(secondsFromGMT: 0)!

let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("CodexBarMonterey-local-spend-\(UUID().uuidString)", isDirectory: true)
defer { try? FileManager.default.removeItem(at: directory) }

let start = calendar.date(from: DateComponents(
    calendar: calendar,
    timeZone: calendar.timeZone,
    year: 2026,
    month: 8,
    day: 1,
    hour: 12))!
let store = LocalSpendHistoryStore(directoryURL: directory, calendar: calendar)

_ = store.record(
    provider: "moonshot",
    accountKey: "moonshot::first@example.com",
    rawJSON: balanceJSON(100),
    now: start)

// A refresh inside the five-minute sampling window must not replace the
// original baseline and erase the first observed balance decrease.
let rapid = localSpend(store.record(
    provider: "moonshot",
    accountKey: "moonshot::first@example.com",
    rawJSON: balanceJSON(90),
    now: start.addingTimeInterval(60)))
require(number(rapid, "last30DaysSpend") == 0, "rapid refresh was treated as a complete interval")

let sampled = localSpend(store.record(
    provider: "moonshot",
    accountKey: "moonshot::first@example.com",
    rawJSON: balanceJSON(80),
    now: start.addingTimeInterval(301)))
require(number(sampled, "todaySpend") == 20, "original baseline was not retained")
require(number(sampled, "last30DaysSpend") == 20, "sampled spend total is incorrect")
require(integer(sampled, "intervalCount") == 1, "sampled interval count is incorrect")

// A long offline gap is real balance movement, but cannot be assigned honestly
// to the day on which the next refresh happened.
let afterGap = localSpend(store.record(
    provider: "moonshot",
    accountKey: "moonshot::first@example.com",
    rawJSON: balanceJSON(70),
    now: start.addingTimeInterval(3 * 60 * 60)))
require(number(afterGap, "last30DaysSpend") == 20, "long-gap spend was assigned to a day")
require(integer(afterGap, "unattributedIntervals") == 1, "long gap was not disclosed")

// A second account for the same provider must use an independent ledger.
_ = store.record(
    provider: "moonshot",
    accountKey: "moonshot::second@example.com",
    rawJSON: balanceJSON(50),
    now: start)
let secondAccount = localSpend(store.record(
    provider: "moonshot",
    accountKey: "moonshot::second@example.com",
    rawJSON: balanceJSON(45),
    now: start.addingTimeInterval(301)))
require(number(secondAccount, "last30DaysSpend") == 5, "provider accounts shared one spend ledger")
require(integer(secondAccount, "unattributedIntervals") == 0, "account isolation leaked uncertainty state")

let fileURL = directory.appendingPathComponent("local-spend-history.json")
let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
if let permissions = attributes[.posixPermissions] as? NSNumber {
    require(permissions.intValue & 0o777 == 0o600, "history file permissions are not 0600")
}

// Even a short interval spanning midnight is intentionally unassigned because
// the balance API does not reveal which side of midnight incurred the spend.
let midnightDirectory = directory.appendingPathComponent("midnight", isDirectory: true)
let midnightStore = LocalSpendHistoryStore(
    directoryURL: midnightDirectory,
    calendar: calendar,
    minimumSampleInterval: 0)
let beforeMidnight = calendar.date(from: DateComponents(
    calendar: calendar,
    timeZone: calendar.timeZone,
    year: 2026,
    month: 8,
    day: 1,
    hour: 23,
    minute: 59))!
_ = midnightStore.record(
    provider: "moonshot",
    accountKey: "moonshot::midnight@example.com",
    rawJSON: balanceJSON(100),
    now: beforeMidnight)
let crossMidnight = localSpend(midnightStore.record(
    provider: "moonshot",
    accountKey: "moonshot::midnight@example.com",
    rawJSON: balanceJSON(90),
    now: beforeMidnight.addingTimeInterval(120)))
require(number(crossMidnight, "todaySpend") == 0, "cross-midnight spend was assigned to the next day")
require(number(crossMidnight, "last30DaysSpend") == 0, "cross-midnight spend entered the 30-day total")
require(integer(crossMidnight, "unattributedIntervals") == 1, "cross-midnight uncertainty was not disclosed")

print("Local spend history regression tests passed.")
