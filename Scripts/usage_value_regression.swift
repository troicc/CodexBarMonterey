import Foundation

private final class RateFixtureProtocol: URLProtocol {
    static var body = Data()
    static var status = 200
    static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct UsageValueRegression {
    @MainActor static func main() async throws {
        let json = """
        {"provider":"codex","daily":[
          {"date":"2026-08-15","totalTokens":999,"totalCost":999,"modelsUsed":["excluded"]},
          {"date":"2026-08-16","totalTokens":100,"modelBreakdowns":[{"modelName":"gpt-a","totalTokens":100,"cost":10}]},
          {"date":"2026-09-13","totalTokens":70,"modelBreakdowns":[{"modelName":"gpt-a","totalTokens":20},{"modelName":"gpt-b","totalTokens":50,"cost":15}]},
          {"date":"2026-09-14","totalTokens":30,"modelsUsed":["mixed-a","mixed-b"],"totalCost":2},
          {"date":"2026-09-15","totalTokens":999,"totalCost":999,"modelsUsed":["future"]}
        ]}
        """
        let payload = CostHistoryPayloadParser.payload(provider: "codex", fromJSON: json)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-09-14T12:00:00Z")!
        let rows = payload.modelUsage(now: now, calendar: calendar)
        precondition(rows.map(\.id) == ["gpt-a", "gpt-b", ""])
        precondition(rows.map(\.tokens) == [120, 50, 30])
        precondition(rows[0].cost.knownCost == 10 && rows[0].cost.isPartial)
        precondition(rows[1].cost.knownCost == 15 && !rows[1].cost.isPartial)
        let estimate = payload.costEstimate(dayCount: 30, now: now, calendar: calendar)
        precondition(estimate.knownCost == 27 && estimate.isPartial)
        precondition(SubscriptionComparison.multiple(estimate: estimate, monthlyUSD: 100) == 0.27)
        precondition(SubscriptionComparison.multiple(estimate: estimate, monthlyUSD: 0) == nil)
        precondition(SubscriptionComparison.multiple(estimate: nil, monthlyUSD: 100) == nil)
        let usd = Locale(identifier: "en_US")
        for invalid in ["-1", "nan", "inf", "1e3", "12.345", "", "1,000"] {
            precondition(SubscriptionComparison.monthlyUSD(invalid, locale: usd) == nil)
        }
        precondition(SubscriptionComparison.monthlyUSD("125.00", locale: usd) == 125)
        precondition(SubscriptionComparison.monthlyUSD("125,50", locale: Locale(identifier: "de_DE")) == 125.5)
        let unknown = CostHistoryPayloadParser.payload(provider: "codex", fromJSON:
            "{\"provider\":\"codex\",\"daily\":[{\"date\":\"2026-09-14\",\"totalTokens\":3,\"modelsUsed\":[\"unknown\"]}]}")!
        precondition(unknown.modelUsage(now: now, calendar: calendar).first?.cost.knownCost == nil)
        let claude = CostHistoryPayloadParser.payload(provider: "claude", fromJSON:
            "{\"provider\":\"claude\",\"daily\":[{\"date\":\"2026-09-14\",\"totalTokens\":5,\"modelBreakdowns\":[{\"modelName\":\"claude-a\",\"totalTokens\":3,\"cost\":2},{\"modelName\":\"glm-a\",\"totalTokens\":2,\"cost\":1}]}]}")!
        precondition(claude.claudeModelHistory.modelUsage(now: now, calendar: calendar).map(\.id) == ["claude-a"])

        let quote = ExchangeRateQuote(date: "2026-09-14", base: "USD", quote: "CNY", rate: 7)
        let cny = CurrencyDisplay(selected: .cny, quote: quote)
        precondition(cny.format(125) == "CN¥875.00")
        precondition(cny.converted(12, from: "CNY").value == 12)
        precondition(CurrencyDisplay(selected: .usd, quote: quote).converted(875, from: "CNY").value == 125)
        precondition(CurrencyDisplay(selected: .cny, quote: nil).format(125) == "$125.00")
        precondition(cny.converted(12, from: "EUR").code == "EUR")
        precondition(!ExchangeRateQuote(date: "invalid", base: "USD", quote: "CNY", rate: 7).isValid())
        precondition(!ExchangeRateQuote(date: "2026-09-14", base: "CNY", quote: "USD", rate: 7).isValid())
        precondition(!ExchangeRateQuote(date: "2026-09-14", base: "USD", quote: "CNY", rate: 0).isValid())

        let suite = "usage-value-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RateFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let store = CurrencySettingsStore(defaults: defaults, session: session)
        RateFixtureProtocol.body = try JSONEncoder().encode(quote)
        await store.refresh(force: true)
        precondition(store.quote == quote && store.error == nil && store.checkedAt != nil)
        await store.refresh()
        precondition(RateFixtureProtocol.requests == 1, "cached refresh must not refetch within an hour")
        RateFixtureProtocol.status = 503
        await store.refresh(force: true)
        precondition(store.quote == quote && store.error != nil)
        RateFixtureProtocol.status = 200
        RateFixtureProtocol.body = Data("{\"base\":\"USD\",\"quote\":\"CNY\",\"date\":\"2026-09-14\",\"rate\":0}".utf8)
        await store.refresh(force: true)
        precondition(store.quote == quote && store.error != nil)
        let reloaded = CurrencySettingsStore(defaults: defaults, session: session)
        precondition(reloaded.quote == quote)
        if ProcessInfo.processInfo.environment["CODEXBAR_TEST_LIVE_FX"] == "1" {
            defaults.removeObject(forKey: CurrencyDisplay.quoteKey)
            defaults.removeObject(forKey: CurrencyDisplay.checkedKey)
            let live = CurrencySettingsStore(defaults: defaults)
            await live.refresh(force: true)
            precondition(live.quote != nil && live.error == nil, "live exchange-rate request failed")
            print("PASS | live URLSession USD/CNY \(live.quote!.rate), published \(live.quote!.date)")
        }
        print("PASS | model aggregation, partial/unknown costs, attribution, 30d boundaries, subscription ratio, currency conversion, network cache and failure recovery")
    }
}
