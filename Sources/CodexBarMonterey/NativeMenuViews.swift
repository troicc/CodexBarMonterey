@preconcurrency import AppKit
import SwiftUI

struct NativeMenuOverviewRow: Identifiable, Hashable {
    let id: String
    let providerID: String
    let title: String
    let account: String?
    let usedPercent: Double?
    let quotaLabel: String?
    let health: ProviderServiceHealth
    let hasError: Bool
}

struct NativeMenuHeaderView: View {
    let title: String
    let subtitle: String
    let providerID: String?
    let health: ProviderServiceHealth?
    let refreshing: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(providerColor.opacity(0.14))
                Image(systemName: providerID.map(ProviderBrand.symbol(for:)) ?? "chart.bar.xaxis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(providerColor)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if let health = health, health != .unknown {
                        Circle()
                            .fill(nativeMenuHealthColor(health))
                            .frame(width: 7, height: 7)
                            .accessibilityLabel(Text(health.title))
                    }
                }
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if refreshing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.72)
                    .accessibilityLabel(Text("Refreshing providers"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: 310)
    }

    private var providerColor: Color {
        providerID.map(ProviderBrand.color(for:)) ?? Color.accentColor
    }
}

struct NativeMenuOverviewView: View {
    let rows: [NativeMenuOverviewRow]
    let totalCount: Int
    let quotaPresentation: MenuQuotaPresentation
    let showAccount: Bool
    let showStatus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("OVERVIEW")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(totalCount) enabled")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            if rows.isEmpty {
                Text("No enabled providers")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(rows) { row in
                    HStack(spacing: 9) {
                        Image(systemName: ProviderBrand.symbol(for: row.providerID))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(ProviderBrand.color(for: row.providerID))
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Text(row.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                if showStatus {
                                    NativeMenuStatusDot(
                                        health: row.hasError ? .outage : row.health,
                                        accessibilityText: row.hasError ? "Connection error" : row.health.title)
                                }
                                Spacer(minLength: 4)
                                Text(percentText(row))
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            if showAccount, let account = row.account {
                                Text(account)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            NativeMenuProgressBar(
                                usedPercent: row.usedPercent,
                                color: ProviderBrand.color(for: row.providerID))
                        }
                    }
                }
            }

            if totalCount > rows.count {
                Text("\(totalCount - rows.count) more in Providers")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: 310)
    }

    private func percentText(_ row: NativeMenuOverviewRow) -> String {
        guard let used = row.usedPercent else { return "—" }
        let value = quotaPresentation == .used ? used : 100 - used
        let percentage = String(
            format: "%.0f%% %@",
            max(0, min(100, value)),
            quotaPresentation.title.lowercased())
        return [row.quotaLabel, percentage]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

struct NativeMenuProviderCardView: View {
    let snapshot: ProviderSnapshot
    let dashboard: ProviderDashboard
    let showAccount: Bool
    let showMetrics: Bool
    let showResetTime: Bool
    let showStatus: Bool
    let quotaPresentation: MenuQuotaPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showStatus, let status = dashboard.serviceStatus, status.health != .unknown {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: status.health.symbolName)
                        .foregroundColor(nativeMenuHealthColor(status.health))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(status.health.title)
                            .font(.system(size: 10, weight: .semibold))
                        if status.health.isIncident {
                            Text(status.displayText)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }

            if let error = dashboard.errorMessage {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(3)
                }
            }

            if showAccount, let account = snapshot.accountDisplayName {
                Label(account, systemImage: "person.crop.circle")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            if showMetrics, !dashboard.metrics.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: 8)
                {
                    ForEach(Array(dashboard.metrics.prefix(4))) { metric in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(metric.title)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            Text(metric.value)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            ForEach(Array(dashboard.quotas.prefix(4))) { lane in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(lane.title)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        Text(quotaText(lane))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    }
                    NativeMenuProgressBar(
                        usedPercent: lane.usedPercent,
                        color: ProviderBrand.color(for: snapshot.provider))
                    if showResetTime {
                        let details = [lane.resetText, lane.paceDescription()].compactMap { $0 }
                        if !details.isEmpty {
                            Text(details.joined(separator: " · "))
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            if dashboard.metrics.count > 4 || dashboard.quotas.count > 4 {
                Text("More information is available in Detailed Dashboard")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: 310)
    }

    private func quotaText(_ lane: DashboardQuotaLane) -> String {
        let value = quotaPresentation == .used ? lane.usedPercent : lane.remainingPercent
        return String(format: "%.0f%% %@", value, quotaPresentation.title.lowercased())
    }
}

private struct NativeMenuProgressBar: View {
    let usedPercent: Double?
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.16))
                if let usedPercent = usedPercent {
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(max(0, min(100, usedPercent)) / 100))
                }
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

private struct NativeMenuStatusDot: View {
    let health: ProviderServiceHealth
    let accessibilityText: String

    var body: some View {
        Circle()
            .fill(nativeMenuHealthColor(health))
            .frame(width: 6, height: 6)
            .accessibilityLabel(Text(accessibilityText))
    }
}

private func nativeMenuHealthColor(_ health: ProviderServiceHealth) -> Color {
    switch health {
    case .unknown: return .secondary
    case .operational: return .green
    case .degraded: return .orange
    case .outage: return .red
    }
}
