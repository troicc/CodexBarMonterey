import SwiftUI

/// Shared by the provider detail and All Providers, with an account-scoped fee.
struct ProviderUsageValueView: View {
    let dashboard: ProviderDashboard

    var body: some View {
        if let key = dashboard.subscriptionPreferenceKey {
            ProviderUsageValueCard(dashboard: dashboard, preferenceKey: key)
                .id(key)
        }
    }
}

struct ProviderUsageValueCard: View {
    let dashboard: ProviderDashboard
    @AppStorage private var monthlyFee: String
    @AppStorage private var providerFee: String
    @ObservedObject private var currency: CurrencySettingsStore
    @State private var modelsExpanded: Bool
    @State private var editingFee = false

    init(dashboard: ProviderDashboard, preferenceKey: String,
         defaults: UserDefaults = .standard, modelsExpanded: Bool = false,
         currency: CurrencySettingsStore = .shared) {
        self.dashboard = dashboard
        _monthlyFee = AppStorage(wrappedValue: "", preferenceKey, store: defaults)
        _providerFee = AppStorage(wrappedValue: "", "subscriptionDefaultUSD.\(dashboard.id)", store: defaults)
        self.currency = currency
        _modelsExpanded = State(initialValue: modelsExpanded)
    }

    private var feeText: String { monthlyFee.isEmpty ? providerFee : monthlyFee }
    private var fee: Double? { SubscriptionComparison.monthlyUSD(feeText) }
    private var multiple: Double? {
        SubscriptionComparison.multiple(estimate: dashboard.usageCostEstimate, monthlyUSD: fee)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProviderDetailSectionTitle(title: dashboard.id == "claude" ? "Local usage value · 30d" : "Usage value · 30d", symbol: "dollarsign.circle")
            comparison
            subscriptionEditor
            Text(dashboard.id == "claude"
                ? "Local Claude Code logs only; web chats are excluded. API equivalent ÷ monthly fee, not total subscription value or a bill. Logs cannot verify the billing account."
                : "API equivalent from local logs ÷ monthly fee. Not a bill or quota; logs cannot verify the billing account.")
                .font(.system(size: 9)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if dashboard.usageCostEstimate?.isPartial == true {
                Text("Partial estimate · known costs only")
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
            if currency.selection == .cny {
                Text(currency.quote.map { "USD/CNY \(String(format: "%.4f", $0.rate)) · \($0.date) · reference rate" }
                    ?? "Exchange rate unavailable · showing USD")
                    .font(.system(size: 9)).foregroundColor(.secondary)
            }
            Divider()
            DisclosureGroup(isExpanded: $modelsExpanded) {
                modelRows.padding(.top, 8)
            } label: {
                Text("Models · 30d (\(dashboard.modelUsage.count))")
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }

    private var comparison: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(usageCostText(dashboard.usageCostEstimate, display: currency.display))
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                Text("API equivalent")
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                if let multiple = multiple {
                    Text((dashboard.usageCostEstimate?.isPartial == true ? "≥" : "")
                         + String(format: "%.2f×", multiple))
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                        .foregroundColor(ProviderBrand.color(for: dashboard.id))
                    Text("of monthly fee")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                } else {
                    Text(fee == 0 ? "No paid subscription" : fee == nil ? "Set monthly fee" : "Cost unavailable")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
        }
    }

    private var subscriptionEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Subscription")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                Spacer(minLength: 4)
                Text(fee.map { currency.display.format($0) } ?? "Not set")
                    .font(.system(size: 11, weight: .medium)).monospacedDigit()
                Text("/ mo").font(.system(size: 10)).foregroundColor(.secondary)
                Button(editingFee ? "Done" : "Edit") { editingFee.toggle() }
                    .font(.system(size: 10)).buttonStyle(BorderlessButtonStyle())
                    .disabled(editingFee && fee == nil && !feeText.isEmpty)
            }
            if editingFee || fee == nil {
                HStack {
                    Text("Monthly fee · USD").font(.system(size: 10)).foregroundColor(.secondary)
                    Spacer()
                    if !monthlyFee.isEmpty {
                        Button("Use default") { monthlyFee = ""; editingFee = false }
                            .font(.system(size: 10)).buttonStyle(BorderlessButtonStyle())
                    }
                    TextField("Monthly fee", text: Binding(get: { feeText }, set: { monthlyFee = $0 }))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: 11)).multilineTextAlignment(.trailing)
                    .frame(width: 90)
                    .accessibilityLabel(Text("Monthly subscription in US dollars"))
                    .help("Enter what you pay in USD per month. For annual billing, use the monthly average. Saved for this account.")
                }
            }
            if !feeText.isEmpty && fee == nil {
                Text("Enter a nonnegative USD amount with up to 2 decimal places.")
                    .font(.system(size: 9)).foregroundColor(.orange)
            }
        }
    }

    @ViewBuilder
    private var modelRows: some View {
        if dashboard.modelUsage.isEmpty {
            Text("No model breakdown available for the last 30 days.")
                .font(.system(size: 11)).foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(dashboard.modelUsage) { row in
                    ModelUsageValueRow(row: row, display: currency.display)
                }
                Text("Total tokens include cached tokens when reported. Costs use the prices available in local usage data.")
                    .font(.system(size: 9)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ModelUsageValueRow: View {
    let row: ModelUsageSummary
    let display: CurrencyDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.name)
                .font(.system(size: 11, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline) {
                Text(row.tokens.map { usageTokenText($0) + " tokens" } ?? "Tokens unavailable")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                    .help(row.tokens.map { String(format: "%.0f total tokens", $0) } ?? "Tokens unavailable")
                Spacer(minLength: 8)
                Text(usageCostText(row.cost, display: display))
                    .font(.system(size: 11, weight: .medium)).monospacedDigit()
                    .fixedSize()
                    .help(row.cost.knownCost.map { String(format: "%.6f USD", $0)
                        + (row.cost.isPartial ? " · partial estimate" : " · API equivalent") } ?? "No price available")
            }
        }
    }
}

private func usageCostText(_ estimate: CostEstimateSummary?, display: CurrencyDisplay) -> String {
    guard let cost = estimate?.knownCost else { return "Unavailable" }
    return (estimate?.isPartial == true ? "≥" : "") + display.format(cost)
}

private func usageTokenText(_ value: Double) -> String {
    if value >= 1_000_000_000 { return String(format: "%.2fB", value / 1_000_000_000) }
    if value >= 1_000_000 { return String(format: "%.2fM", value / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }
    return String(format: "%.0f", value)
}
