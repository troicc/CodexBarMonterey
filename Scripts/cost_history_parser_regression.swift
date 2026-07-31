import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Cost history parser regression failed: \(message)\n", stderr)
        exit(1)
    }
}

let todayFormatter = DateFormatter()
todayFormatter.calendar = Calendar(identifier: .gregorian)
todayFormatter.locale = Locale(identifier: "en_US_POSIX")
todayFormatter.timeZone = TimeZone.current
todayFormatter.dateFormat = "yyyy-MM-dd"
let todayKey = todayFormatter.string(from: Date())

let payload = """
[
  {
    "provider": "codex",
    "source": "local",
    "last30DaysTokens": 1100000000,
    "last30DaysCostUSD": 42.5,
    "daily": [
      {
        "date": "\(todayKey)",
        "totalTokens": 674800,
        "totalCost": 1.5,
        "modelsUsed": ["gpt-5.6-sol"],
        "modelBreakdowns": [{"modelName": "gpt-5.6-sol", "cost": 1.5}]
      },
      {
        "date": "2026-07-29",
        "totalTokens": 505100000,
        "totalCost": 41.0,
        "modelsUsed": ["gpt-5.6-sol"]
      }
    ],
    "totals": {"totalTokens": 1100000000, "totalCost": 42.5}
  },
  {
    "provider": "codex",
    "source": "oauth",
    "usage": {"secondary": {"usedPercent": 69}}
  }
]
"""

for _ in 0..<100 {
    guard let parsed = CostHistoryPayloadParser.payload(provider: "codex", fromJSON: payload) else {
        require(false, "typed Codex payload was not found")
        fatalError()
    }
    require(parsed.resolvedLast30DaysTokens == 1_100_000_000, "aggregate token count selected a daily row")
    require(parsed.resolvedLast30DaysCostUSD == 42.5, "aggregate cost was not stable")
    require(parsed.resolvedTodayTokens == 674_800, "today token count did not use today's daily row")
    require(parsed.resolvedTodayCostUSD == 1.5, "today cost did not use today's daily row")
    require(parsed.sortedDaily.last?.date == todayKey, "daily history was not sorted")
    require(parsed.topModel == "gpt-5.6-sol", "top model derivation was not deterministic")
}

let wrapped = #"""
{"data":[{"provider":"codex","last30DaysTokens":1234,"last30DaysCostUSD":0,"daily":[]}]}
"""#
let wrappedPayload = CostHistoryPayloadParser.payload(provider: "codex", fromJSON: wrapped)
require(wrappedPayload?.resolvedLast30DaysTokens == 1234, "wrapped payload was not discovered")
require(CostHistoryPayloadParser.payload(provider: "claude", fromJSON: payload) == nil, "wrong provider payload was selected")

print("Typed cost-history parser regression tests passed.")
