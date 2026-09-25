import SwiftUI

struct CurrencySettingsView: View {
    @ObservedObject var currency: CurrencySettingsStore = .shared
    @AppStorage("subscriptionDefaultUSD.codex") private var codexFee = ""
    @AppStorage("subscriptionDefaultUSD.claude") private var claudeFee = ""

    var body: some View {
        GroupBox(label: Text("Currency & subscriptions").font(.headline)) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Display currency", selection: Binding(get: { currency.selection }, set: { currency.select($0) })) {
                    ForEach(DisplayCurrency.allCases) { Text($0.title).tag($0) }
                }
                HStack {
                    if let quote = currency.quote {
                        Text("1 USD = \(String(format: "%.4f", quote.rate)) CNY · \(quote.date)")
                            .font(.system(size: 11)).monospacedDigit()
                    } else {
                        Text("No exchange rate yet").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(currency.isRefreshing ? "Updating…" : "Refresh rate") {
                        Task { await currency.refresh(force: true) }
                    }.disabled(currency.isRefreshing)
                }
                if let checked = currency.checkedAt {
                    Text("Last checked: \(checked.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                }
                if let error = currency.error {
                    Text(error).font(.system(size: 11)).foregroundColor(.orange)
                }
                Text("Checks automatically every hour. Frankfurter publishes daily reference rates, not live trading quotes. Converted costs use the latest saved rate; original usage and exports keep their source currency.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                subscriptionField("Codex", value: $codexFee)
                subscriptionField("Claude", value: $claudeFee)
                Text("Enter your actual monthly payment in USD (annual plans: monthly average). These defaults apply unless an account has its own fee set in its Usage value card.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(12)
        }
    }

    private func subscriptionField(_ name: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(name) subscription").font(.system(size: 12))
                Spacer()
                if let fee = SubscriptionComparison.monthlyUSD(value.wrappedValue) {
                    Text(currency.display.format(fee) + " / mo")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                TextField("Monthly USD", text: value)
                    .textFieldStyle(RoundedBorderTextFieldStyle()).frame(width: 110)
                    .accessibilityLabel(Text("\(name) monthly subscription in USD"))
                Text("USD / mo").font(.system(size: 11)).foregroundColor(.secondary)
            }
            if !value.wrappedValue.isEmpty && SubscriptionComparison.monthlyUSD(value.wrappedValue) == nil {
                Text("Enter a nonnegative USD amount with up to 2 decimal places.")
                    .font(.system(size: 10)).foregroundColor(.orange)
            }
        }
    }
}
