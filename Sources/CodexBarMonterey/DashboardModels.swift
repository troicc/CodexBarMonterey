@preconcurrency import AppKit
import Foundation
import SwiftUI

struct DashboardMetric: Identifiable, Hashable {
    let id: String
    let title: String
    let value: String
    let subtitle: String?

    init(id: String? = nil, title: String, value: String, subtitle: String? = nil) {
        self.id = id ?? title
        self.title = title
        self.value = value
        self.subtitle = subtitle
    }
}
struct DashboardHistoryPoint: Identifiable, Hashable {
    let id: String
    let label: String
    let spend: Double?
    let tokens: Double?
    let requests: Double?

    init(label: String, spend: Double? = nil, tokens: Double? = nil, requests: Double? = nil) {
        self.id = label
        self.label = label
        self.spend = spend
        self.tokens = tokens
        self.requests = requests
    }
}
struct DashboardQuotaLane: Identifiable, Hashable {
    let id: String
    let title: String
    let usedPercent: Double
    let resetText: String?
    let resetsAt: Date?
    let windowMinutes: Double?

    init(
        id: String,
        title: String,
        usedPercent: Double,
        resetText: String?,
        resetsAt: Date? = nil,
        windowMinutes: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.usedPercent = max(0, min(100, usedPercent))
        self.resetText = resetText
        self.resetsAt = resetsAt
        self.windowMinutes = windowMinutes
    }

    var remainingPercent: Double { max(0, 100 - usedPercent) }

    /// Mirrors the useful part of upstream's pace display without relying on
    /// newer macOS-only APIs. A window is on pace when consumption is no faster
    /// than elapsed time; otherwise an estimated run-out is shown when possible.
    func paceDescription(now: Date = Date()) -> String? {
        guard let resetsAt = resetsAt,
              let windowMinutes = windowMinutes,
              windowMinutes > 0,
              resetsAt > now
        else { return nil }

        if usedPercent >= 100 { return "Quota depleted" }
        let duration = windowMinutes * 60
        let startedAt = resetsAt.addingTimeInterval(-duration)
        let elapsed = max(0, now.timeIntervalSince(startedAt))
        guard elapsed > 60 else { return "Window just started" }

        let expectedUsed = max(0, min(100, elapsed / duration * 100))
        let reserve = expectedUsed - usedPercent
        if reserve >= 5 {
            return String(format: "%.0f%% reserve", reserve)
        }

        let rate = usedPercent / elapsed
        if rate > 0 {
            let secondsToEmpty = remainingPercent / rate
            if now.addingTimeInterval(secondsToEmpty) < resetsAt {
                return "Runs out in \(Self.compactDuration(secondsToEmpty))"
            }
        }
        return reserve >= -5 ? "On pace" : String(format: "%.0f%% over pace", abs(reserve))
    }

    private static func compactDuration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = interval >= 86_400 ? [.day, .hour] : [.hour, .minute]
        formatter.maximumUnitCount = 2
        return formatter.string(from: max(60, interval)) ?? "soon"
    }
}

struct DashboardHistorySummary: Hashable {
    let spend: Double?
    let tokens: Double?
    let requests: Double?
    let currencyCode: String?
    let spendIsEstimated: Bool

    init(
        spend: Double?,
        tokens: Double?,
        requests: Double?,
        currencyCode: String? = nil,
        spendIsEstimated: Bool = false
    ) {
        self.spend = spend
        self.tokens = tokens
        self.requests = requests
        self.currencyCode = currencyCode
        self.spendIsEstimated = spendIsEstimated
    }
}

enum DashboardHistoryContext: Hashable {
    case dailyUsage
    case hourlyUsage
    case dailySpend
    case fiveHourQuotaSamples
    case generic
}

struct ProviderDashboard: Identifiable, Hashable {
    let id: String
    let title: String
    let accountLabel: String?
    let source: String?
    let updatedText: String
    let metrics: [DashboardMetric]
    let quotas: [DashboardQuotaLane]
    let history: [DashboardHistoryPoint]
    let historyContext: DashboardHistoryContext
    let historySummary: DashboardHistorySummary?
    let topModel: String?
    let errorMessage: String?
    let serviceStatus: ProviderStatus?
    let dashboardURL: URL?
    let statusURL: URL?
    static func loading(providerID: String, title: String) -> ProviderDashboard {
        ProviderDashboard(
            id: providerID,
            title: title,
            accountLabel: nil,
            source: nil,
            updatedText: "Refreshing…",
            metrics: [],
            quotas: [],
            history: [],
            historyContext: .generic,
            historySummary: nil,
            topModel: nil,
            errorMessage: nil,
            serviceStatus: nil,
            dashboardURL: ProviderCatalog.dashboardURL(for: providerID),
            statusURL: ProviderCatalog.statusURL(for: providerID))
    }
}
enum ProviderBrand {
    static func symbol(for id: String) -> String {
        switch id {
        case "codex": return "terminal.fill"
        case "openai": return "sparkles"
        case "claude": return "sun.max.fill"
        case "cursor": return "cursorarrow.rays"
        case "gemini": return "diamond.fill"
        case "antigravity": return "asterisk"
        case "factory": return "shippingbox.fill"
        case "copilot": return "person.crop.circle.badge.checkmark"
        case "zai": return "z.circle.fill"
        case "minimax": return "waveform.path.ecg"
        case "openrouter": return "arrow.triangle.branch"
        case "kiro": return "k.circle.fill"
        case "grok": return "x.circle.fill"
        case "deepseek": return "scope"
        case "moonshot", "kimi": return "moon.stars.fill"
        case "mimo": return "m.circle.fill"
        case "mistral": return "wind"
        case "bedrock": return "cloud.fill"
        default: return "circle.grid.2x2.fill"
        }
    }
    static func nsColor(for id: String) -> NSColor {
        let fixed: [String: NSColor] = [
            "codex": NSColor(calibratedRed: 0.84, green: 0.32, blue: 0.93, alpha: 1),
            "openai": NSColor(calibratedRed: 0.35, green: 0.48, blue: 0.98, alpha: 1),
            "claude": NSColor(calibratedRed: 0.91, green: 0.50, blue: 0.29, alpha: 1),
            "cursor": NSColor(calibratedWhite: 0.88, alpha: 1),
            "gemini": NSColor(calibratedRed: 0.32, green: 0.64, blue: 0.98, alpha: 1),
            "factory": NSColor(calibratedRed: 0.58, green: 0.49, blue: 0.95, alpha: 1),
            "zai": NSColor(calibratedRed: 0.73, green: 0.35, blue: 0.94, alpha: 1),
            "minimax": NSColor(calibratedRed: 0.38, green: 0.82, blue: 0.94, alpha: 1),
            "moonshot": NSColor(calibratedRed: 0.13, green: 0.36, blue: 0.92, alpha: 1),
            "kimi": NSColor(calibratedRed: 0.13, green: 0.36, blue: 0.92, alpha: 1),
            "mimo": NSColor(calibratedRed: 0.98, green: 0.42, blue: 0.18, alpha: 1),
        ]
        return fixed[id] ?? NSColor.providerColor(id: id)
    }
    static func color(for id: String) -> Color {
        Color(nsColor: nsColor(for: id))
    }
}
