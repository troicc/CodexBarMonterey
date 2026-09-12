import AppKit
import SwiftUI

@main
struct ModelAttributionVisualQA {
    @MainActor
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let gapDashboards = historyGapRegression()
        let partialDashboards = partialCostRegression()
        let subscriptionDashboards = subscriptionRegression()
        let dataDirectory = output.appendingPathComponent("fixture-ledger")
        let ledger = LocalTokenHistoryStore(storageDirectory: dataDirectory)
        let date = DateFormatter()
        date.dateFormat = "yyyy-MM-dd"
        let today = date.string(from: Date())
        let yesterday = date.string(from: Date().addingTimeInterval(-86400))
        func fixture(_ provider: String, _ model: String, _ second: String) -> (ProviderSnapshot, String) {
            let raw = """
            {"provider":"\(provider)","usage":{"primary":{"usedPercent":78,"windowMinutes":300},"secondary":{"usedPercent":91,"windowMinutes":10080}}}
            """
            let snap = ProviderSnapshot(provider: provider, version: nil, source: "local", status: nil,
                usage: try! JSONDecoder().decode(ProviderSnapshot.self, from: Data(raw.utf8)).usage,
                credits: nil, account: nil, plan: nil, error: nil, rawJSON: raw)
            let cost = """
            {"provider":"\(provider)","daily":[
              {"date":"\(yesterday)","totalTokens":9200000,"totalCost":6.5,"modelsUsed":["\(model)"],"modelBreakdowns":[{"modelName":"\(model)","totalTokens":9200000,"cost":6.5}]},
              {"date":"\(today)","totalTokens":12300000,"totalCost":12.5,"modelsUsed":["\(model)","\(second)"],"modelBreakdowns":[{"modelName":"\(model)","totalTokens":2300000,"cost":2.5},{"modelName":"\(second)","totalTokens":10000000,"cost":10}]}
            ]}
            """
            if provider == "codex" {
                var object = try! JSONSerialization.jsonObject(with: Data(cost.utf8)) as! [String: Any]
                var daily = object["daily"] as! [[String: Any]]
                var rows = daily[1]["modelBreakdowns"] as! [[String: Any]]
                rows.append(["modelName": "codex-auto-review", "totalTokens": 1000000])
                daily[1]["modelBreakdowns"] = rows
                daily[1]["modelsUsed"] = [model, second, "codex-auto-review"]
                daily[1]["totalTokens"] = 13300000
                object["daily"] = daily
                let data = try! JSONSerialization.data(withJSONObject: object)
                return (snap, String(decoding: data, as: UTF8.self))
            }
            return (snap, cost)
        }
        let claude = fixture("claude", "claude-opus-4-8", "claude-sonnet-4-6")
        let codex = fixture("codex", "gpt-5.6-sol", "gpt-6-astra")
        for item in [claude, codex] { _ = ledger.record(snapshot: item.0, supplementalJSON: item.1) }
        let store = DashboardStore(client: CLIClient(), tokenHistoryStore: ledger)
        let entries = [codex, claude].map {
            AllProviderEntry(id: $0.0.id, dashboard: DashboardParser.dashboard(snapshot: $0.0, supplementalJSON: $0.1))
        }
        let codexDashboard = entries[0].dashboard
        precondition(codexDashboard.metrics.first { $0.id == "today-cost" }?.value == "≥$12.50")
        precondition(codexDashboard.metrics.first { $0.id == "today-cost" }?.subtitle?.contains("codex-auto-review") == true)
        precondition(codexDashboard.topModel10Days == "gpt-5.6-sol")
        precondition(codexDashboard.topModelToday == "gpt-6-astra")
        for mode in ["light", "dark"] {
            let appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)!
            app.appearance = appearance
            for dashboard in subscriptionDashboards {
                try render(ProviderDetailPopoverView(dashboard: dashboard, isRefreshing: false,
                    refresh: {}, openDashboard: {}, openStatus: {}, openSettings: {}),
                    size: NSSize(width: 390, height: 560), appearance: appearance,
                    output: output.appendingPathComponent("subscription-\(dashboard.id)-\(mode).png"))
            }
            for dashboard in gapDashboards + partialDashboards {
                try render(ScrollView {
                    VStack(spacing: 14) {
                        ForEach(dashboardHistorySeries(for: dashboard)) { series in
                            ProviderHistorySeriesView(series: series)
                        }
                    }.padding(14)
                }, size: NSSize(width: 390, height: 340), appearance: appearance,
                    output: output.appendingPathComponent("history-\(dashboard.id)-\(dashboard.history.last?.spendEstimate?.isPartial == true ? "partial-" : "")\(mode).png"))
            }
            for height: CGFloat in [560, 680] {
                try render(AllProvidersContentView(entries: entries, isRefreshing: false, error: nil,
                    refresh: {}, openSettings: {}), size: NSSize(width: 620, height: height),
                    appearance: appearance, output: output.appendingPathComponent("all-providers-\(Int(height))-\(mode).png"))
            }
            try render(ProviderDetailPopoverView(dashboard: codexDashboard, isRefreshing: false,
                refresh: {}, openDashboard: {}, openStatus: {}, openSettings: {}),
                size: NSSize(width: 390, height: 560), appearance: appearance,
                output: output.appendingPathComponent("codex-detail-\(mode).png"))
            for provider in ["claude", "codex"] {
                let account = ledger.accounts().first { $0.providerID == provider }!
                let report = ledger.report(accountID: account.id, range: .thirtyDays)
                precondition(report.modelTotals.count == (provider == "codex" ? 3 : 2))
                precondition(report.modelTotals.reduce(0) { $0 + $1.tokens } == report.totalTokens)
                try render(TokenHistorySettingsView(dashboardStore: store, selectedAccountID: account.id),
                    size: NSSize(width: 760, height: 680), appearance: appearance,
                    output: output.appendingPathComponent("models-\(provider)-\(mode).png"))
            }
        }
        print("PASS | production views; popover 620x560/680; settings 760x680; light/dark; model sums reconciled")
    }

    static func partialCostRegression() -> [ProviderDashboard] {
        return ["codex", "claude"].map { provider in
            let model = provider == "claude" ? "claude-priced" : "gpt-priced"
            let unpriced = provider == "claude" ? "claude-unknown" : "codex-auto-review"
            let json = """
            {"provider":"\(provider)","daily":[
              {"date":"2026-09-08","totalTokens":100,"totalCost":5,"modelsUsed":["\(model)"]},
              {"date":"2026-09-10","totalTokens":100,"totalCost":99,"modelBreakdowns":[
                {"modelName":"\(model)","totalTokens":80,"cost":3.5},
                {"modelName":"\(unpriced)","totalTokens":20}]},
              {"date":"2026-09-11","totalTokens":20,"modelsUsed":["\(unpriced)"]},
              {"date":"2026-09-12","totalTokens":100,"totalCost":7,"modelBreakdowns":[
                {"modelName":"\(model)","totalTokens":80,"cost":7},
                {"modelName":"\(unpriced)","totalTokens":20}]}
            ]}
            """
            let snapshot = ProviderSnapshot(provider: provider, version: nil, source: "test", status: nil,
                usage: nil, credits: nil, account: nil, plan: nil, error: nil, rawJSON: "{}")
            let dashboard = DashboardParser.dashboard(snapshot: snapshot, supplementalJSON: json)
            precondition(dashboard.history.map(\.spend) == [5, 0, 3.5, nil, 7])
            let series = dashboardHistorySeries(for: dashboard).first { $0.id == "daily-cost" }!
            precondition(series.values == [5, 0, 3.5, nil, 7])
            precondition(series.hasPartialEstimates && series.latestText == "≥$7.00")
            precondition(series.valueText(at: 0) == "$5.00" && series.valueText(at: 1) == "$0.00")
            precondition(series.valueText(at: 3) == "—")
            precondition(series.tooltip(at: 2).contains(unpriced) && series.tooltip(at: 2).contains("≥$3.50"))
            precondition(series.tooltip(at: 3).contains("No known prices"))
            let raw = CostHistoryPayloadParser.payload(provider: provider, fromJSON: json)!
            precondition(raw.sortedDaily[1].resolvedCost == nil, "complete totals must remain distinct from chart subtotals")
            print("PASS | \(provider): known/partial/unknown/zero cost history, lower-bound labels and model tooltip")
            return dashboard
        }
    }

    static func subscriptionRegression() -> [ProviderDashboard] {
        let status = """
        {"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty","email":"claude@example.com","subscriptionType":"pro"}
        """
        var dashboards: [ProviderDashboard] = []
        for provider in ["claude", "codex"] {
            let identity = provider == "codex" ? "\"identity\":{\"accountEmail\":\"codex@example.com\",\"loginMethod\":\"prolite\"}," : ""
            let title = provider == "claude" ? "Fable only" : "Codex Spark Weekly"
            let json = """
            {"provider":"\(provider)","source":"\(provider)","usage":{\(identity)
              "primary":{"usedPercent":26,"windowMinutes":300},
              "secondary":{"usedPercent":5,"windowMinutes":10080},
              "extraRateWindows":[{"id":"model-weekly","title":"\(title)","window":{"usedPercent":4,"windowMinutes":10080,"resetsAt":"2026-09-17T23:00:00Z"}},
              {"id":"other-weekly","title":"Weekly","window":{"usedPercent":7,"windowMinutes":10080}}]}}
            """
            let original = try! CLIClient.decodeSnapshots(json)
            let snapshot = ClaudeCLIAccountStatus.enrich(original, json: status)[0]
            precondition(snapshot.id == original[0].id, "display enrichment must preserve ledger/cache identity")
            let dashboard = DashboardParser.dashboard(snapshot: snapshot, supplementalJSON: json)
            precondition(dashboard.quotas.count == 4, "preserve scoped IDs, deduplicate repeated raw roots")
            precondition(dashboard.quotas[2].title == title && dashboard.quotas[2].usedPercent == 4)
            precondition(dashboard.quotas[2].windowMinutes == 10080 && dashboard.quotas[2].resetsAt != nil)
            precondition(dashboard.quotas[3].title == "Weekly" && dashboard.quotas[3].usedPercent == 7)
            precondition(dashboard.accountLabel == "\(provider)@example.com")
            precondition(dashboard.planLabel == (provider == "claude" ? "Pro" : "Pro Lite"))
            dashboards.append(dashboard)
        }
        for source in ["oauth", "web"] {
            let snapshots = try! CLIClient.decodeSnapshots("{\"provider\":\"claude\",\"source\":\"\(source)\",\"usage\":{}}")
            precondition(ClaudeCLIAccountStatus.enrich(snapshots, json: status) == snapshots)
        }
        for method in ["oauth", "api_key", "cli"] {
            let snapshots = try! CLIClient.decodeSnapshots("{\"provider\":\"codex\",\"usage\":{\"loginMethod\":\"\(method)\"}}")
            precondition(snapshots[0].planDisplayName == nil)
        }
        print("PASS | Claude/Codex account/plan; scoped quota identity/reset; source isolation; stable ledger keys")
        return dashboards
    }

    static func historyGapRegression() -> [ProviderDashboard] {
        func dashboard(_ provider: String, _ json: String, supplemental: Bool = true) -> ProviderDashboard {
            let snapshot = ProviderSnapshot(provider: provider, version: nil, source: "test", status: nil,
                usage: nil, credits: nil, account: nil, plan: nil, error: nil, rawJSON: supplemental ? "{}" : json)
            return DashboardParser.dashboard(snapshot: snapshot, supplementalJSON: supplemental ? json : nil)
        }
        var results: [ProviderDashboard] = []
        for provider in ["claude", "codex"] {
            let model = provider == "claude" ? "claude-opus-4-8" : "gpt-test"
            let json = """
            {"provider":"\(provider)","updatedAt":"2026-09-12T02:00:00Z","daily":[
            {"date":"2026-09-11","totalTokens":20,"modelsUsed":["\(model)"]},
            {"date":"2026-09-08","totalTokens":100,"totalCost":5,"modelsUsed":["\(model)"]}
            ]}
            """
            let result = dashboard(provider, json)
            precondition(result.history.map(\.dayKey) == ["2026-09-08", "2026-09-09", "2026-09-10", "2026-09-11", "2026-09-12"])
            precondition(result.history.map(\.tokens) == [100, 0, 0, 20, 0])
            precondition(result.history.map(\.spend) == [5, 0, 0, nil, 0], "unknown price must remain a gap")
            results.append(result)
        }
        let mixed = dashboard("claude", #"{"provider":"claude","daily":[{"date":"2026-09-08","totalTokens":10,"totalCost":1,"modelsUsed":["claude-opus-4-8"]},{"date":"2026-09-09","totalTokens":100,"modelsUsed":["glm-test"]},{"date":"2026-09-10","totalTokens":100,"modelsUsed":["glm-test","claude-opus-4-8"]}]}"#)
        precondition(mixed.history.map(\.tokens) == [10, 0, nil], "other-only and ambiguous days must differ")
        for provider in ["deepseek", "moonshot", "mimo", "openrouter"] {
            let daily = #"[{"date":"2026-09-08","tokens":100,"spend":5},{"date":"2026-09-11","tokens":20,"spend":1}]"#
            let json: String
            if provider == "deepseek" {
                json = "{\"deepseekUsage\":{\"todayTokens\":20,\"currentMonthTokens\":120,\"requestCount\":1,\"currentMonthRequestCount\":2,\"daily\":\(daily)}}"
            } else if provider == "moonshot" || provider == "mimo" {
                json = "{\"localSpend\":{\"currency\":\"USD\",\"todaySpend\":1,\"last30DaysSpend\":6,\"daily\":\(daily)}}"
            } else { json = "{\"daily\":\(daily)}" }
            let result = dashboard(provider, json, supplemental: false)
            precondition(result.history.count == 4 && result.history[1].tokens == nil && result.history[1].spend == nil,
                "\(provider) must retain missing dates as unknown")
        }
        let hourly = [DashboardHistoryPoint(label: "08:00", tokens: 10), DashboardHistoryPoint(label: "10:00", tokens: 20)]
        precondition(DashboardHistoryPoint.continuousDays(hourly) == hourly, "hourly/quota samples are not daily buckets")
        let boundary = DashboardHistoryPoint.continuousDays([
            DashboardHistoryPoint(label: "Dec 31", tokens: 1, dayKey: "2025-12-31"),
            DashboardHistoryPoint(label: "Jan 2", tokens: 1, dayKey: "2026-01-02")])
        precondition(boundary.map(\.dayKey) == ["2025-12-31", "2026-01-01", "2026-01-02"])
        print("PASS | calendar gaps: Claude, Codex, DeepSeek, Moonshot, MiMo, generic; zero/unknown/model attribution/year boundary")
        return results
    }

    @MainActor
    static func render<V: View>(_ view: V, size: NSSize, appearance: NSAppearance, output: URL) throws {
        let host = NSHostingView(rootView: view
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, appearance.name == .darkAqua ? .dark : .light))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        precondition(abs(host.bounds.width - size.width) < 1 && abs(host.bounds.height - size.height) < 1)
        func children(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap { children($0) } }
        let scrolls = children(host).compactMap { $0 as? NSScrollView }
        precondition(scrolls.count == 1, "expected exactly one primary scroll view")
        let scroll = scrolls[0]
        let frame = host.convert(scroll.bounds, from: scroll)
        precondition(frame.width > size.width - 65 && frame.height > size.height - 180)
        precondition(frame.minX >= -1 && frame.maxX <= size.width + 1)
        precondition(frame.minY >= -1 && frame.maxY <= size.height + 1)
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("missing bitmap") }
        appearance.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("missing PNG") }
        try png.write(to: output)
        window.orderOut(nil)
    }
}
