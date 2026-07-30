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
}

struct ProviderDashboard: Identifiable, Hashable {
    let id: String
    let title: String
    let source: String?
    let updatedText: String
    let metrics: [DashboardMetric]
    let quotas: [DashboardQuotaLane]
    let history: [DashboardHistoryPoint]
    let topModel: String?
    let errorMessage: String?
    let dashboardURL: URL?
    let statusURL: URL?

    static func loading(providerID: String, title: String) -> ProviderDashboard {
        ProviderDashboard(
            id: providerID,
            title: title,
            source: nil,
            updatedText: "Refreshing…",
            metrics: [],
            quotas: [],
            history: [],
            topModel: nil,
            errorMessage: nil,
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
        ]
        return fixed[id] ?? NSColor.providerColor(id: id)
    }

    static func color(for id: String) -> Color {
        Color(nsColor: nsColor(for: id))
    }
}
