import Foundation
import Combine

enum DisplayCurrency: String, CaseIterable, Identifiable {
    case usd = "USD"
    case cny = "CNY"
    var id: String { rawValue }
    var title: String { self == .usd ? "US dollar (USD)" : "人民币 (CNY / RMB)" }
}

struct ExchangeRateQuote: Codable, Equatable {
    let date: String
    let base: String
    let quote: String
    let rate: Double

    func isValid(now: Date = Date()) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard base == "USD", quote == "CNY", rate.isFinite, rate > 0,
              let day = formatter.date(from: date), formatter.string(from: day) == date else { return false }
        return day.timeIntervalSince(now) < 86_400
    }
}

struct CurrencyDisplay {
    static let selectionKey = "displayCurrency"
    static let quoteKey = "usdCnyExchangeRate.v1"
    static let checkedKey = "usdCnyExchangeRate.checkedAt"
    let selected: DisplayCurrency
    let quote: ExchangeRateQuote?

    init(defaults: UserDefaults = .standard) {
        selected = DisplayCurrency(rawValue: defaults.string(forKey: Self.selectionKey) ?? "") ?? .usd
        let decoded = defaults.data(forKey: Self.quoteKey).flatMap { try? JSONDecoder().decode(ExchangeRateQuote.self, from: $0) }
        quote = decoded?.isValid() == true ? decoded : nil
    }

    init(selected: DisplayCurrency, quote: ExchangeRateQuote?) {
        self.selected = selected
        self.quote = quote?.isValid() == true ? quote : nil
    }

    func converted(_ value: Double, from source: String) -> (value: Double, code: String) {
        let source = source.uppercased()
        guard source != selected.rawValue, let quote = quote else { return (value, source) }
        let converted: Double
        if source == "USD" && selected == .cny { converted = value * quote.rate }
        else if source == "CNY" && selected == .usd { converted = value / quote.rate }
        else { return (value, source) }
        return converted.isFinite ? (converted, selected.rawValue) : (value, source)
    }

    func format(_ value: Double, source: String = "USD") -> String {
        let amount = converted(value, from: source)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.currencyCode = amount.code
        formatter.currencySymbol = amount.code == "CNY" ? "CN¥" : amount.code == "USD" ? "$" : amount.code + " "
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount.value)) ?? "\(amount.code) \(amount.value)"
    }
}

extension Notification.Name {
    static let currencyDisplayChanged = Notification.Name("CodexBarMonterey.currencyDisplayChanged")
}

@MainActor
final class CurrencySettingsStore: ObservableObject {
    static let shared = CurrencySettingsStore()
    @Published private(set) var selection: DisplayCurrency
    @Published private(set) var quote: ExchangeRateQuote?
    @Published private(set) var checkedAt: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var error: String?
    private let defaults: UserDefaults
    private let session: URLSession
    private var timer: Timer?

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
        let display = CurrencyDisplay(defaults: defaults)
        selection = display.selected
        quote = display.quote
        checkedAt = defaults.object(forKey: CurrencyDisplay.checkedKey) as? Date
    }

    var display: CurrencyDisplay { CurrencyDisplay(selected: selection, quote: quote) }

    func select(_ currency: DisplayCurrency) {
        defaults.set(currency.rawValue, forKey: CurrencyDisplay.selectionKey)
        selection = currency
        NotificationCenter.default.post(name: .currencyDisplayChanged, object: nil)
        Task { await refresh() }
    }

    func start() {
        guard timer == nil else { return }
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        if !force, quote != nil, let checkedAt = checkedAt,
           Date().timeIntervalSince(checkedAt) >= 0, Date().timeIntervalSince(checkedAt) < 3600 { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let url = URL(string: "https://api.frankfurter.dev/v2/rate/USD/CNY")!
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
            let fetched = try JSONDecoder().decode(ExchangeRateQuote.self, from: data)
            guard fetched.isValid(), quote.map({ fetched.date >= $0.date }) ?? true else { throw URLError(.cannotParseResponse) }
            let checked = Date()
            defaults.set(try JSONEncoder().encode(fetched), forKey: CurrencyDisplay.quoteKey)
            defaults.set(checked, forKey: CurrencyDisplay.checkedKey)
            quote = fetched
            checkedAt = checked
            error = nil
            NotificationCenter.default.post(name: .currencyDisplayChanged, object: nil)
        } catch {
            self.error = quote == nil
                ? "Rate unavailable. Amounts remain in their original currency."
                : "Could not refresh. Using the saved rate dated \(quote!.date)."
        }
    }
}
