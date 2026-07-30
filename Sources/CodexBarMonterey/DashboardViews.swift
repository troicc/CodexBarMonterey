@preconcurrency import AppKit
import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

struct DashboardPopoverView: View {
    @ObservedObject var store: DashboardStore

    private let columns = Array(repeating: GridItem(.flexible(minimum: 72), spacing: 8), count: 4)

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                providerSwitcher
                divider
                selectedContent
                divider
                footer
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(width: 590, height: 720)
        .preferredColorScheme(.dark)
    }

    private var providerSwitcher: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 8) {
                overviewButton
                ForEach(store.snapshots) { snapshot in
                    ProviderSwitcherButton(
                        snapshot: snapshot,
                        selected: store.selectedSnapshot?.id == snapshot.id,
                        action: { store.select(snapshot) })
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: 174)
    }

    private var overviewButton: some View {
        Button(action: { store.onOpenAllDetails?() }) {
            VStack(spacing: 5) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 20, weight: .medium))
                Text("Overview")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(.white.opacity(0.82))
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(height: 1)
            .padding(.vertical, 10)
    }

    @ViewBuilder
    private var selectedContent: some View {
        if let dashboard = store.selectedDashboard, let snapshot = store.selectedSnapshot {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    ProviderHeaderView(snapshot: snapshot, dashboard: dashboard)
                    if let error = dashboard.errorMessage {
                        ErrorCard(message: error, providerID: dashboard.id) {
                            store.onOpenSettings?()
                        }
                    }
                    DashboardSummaryCard(dashboard: dashboard) {
                        store.onOpenProviderDetails?(snapshot.provider)
                    }
                    quotaSection(dashboard)
                }
                .padding(.bottom, 4)
            }
        } else if store.isRefreshing {
            VStack(spacing: 12) {
                ProgressView()
                Text("Refreshing providers…")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 30))
                Text(store.lastError ?? "No enabled providers")
                    .multilineTextAlignment(.center)
                Button("Open Settings") { store.onOpenSettings?() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func quotaSection(_ dashboard: ProviderDashboard) -> some View {
        if !dashboard.quotas.isEmpty {
            VStack(spacing: 8) {
                ForEach(dashboard.quotas) { lane in
                    QuotaLaneView(lane: lane, color: ProviderBrand.color(for: dashboard.id))
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 2) {
            DashboardActionRow(
                title: "Usage Dashboard",
                symbol: "chart.bar.xaxis",
                enabled: store.selectedDashboard?.dashboardURL != nil,
                action: store.openDashboardURL)
            DashboardActionRow(
                title: "Status Page",
                symbol: "waveform.path.ecg",
                enabled: store.selectedDashboard?.statusURL != nil,
                action: store.openStatusURL)
            DashboardActionRow(
                title: store.isRefreshing ? "Refreshing…" : "Refresh",
                symbol: "arrow.clockwise",
                shortcut: "⌘R",
                enabled: !store.isRefreshing,
                action: { Task { await store.refresh() } })
            DashboardActionRow(
                title: "Settings…",
                symbol: "gearshape",
                shortcut: "⌘,",
                action: { store.onOpenSettings?() })
            DashboardActionRow(
                title: "About CodexBar",
                symbol: "info.circle",
                action: { NSApp.orderFrontStandardAboutPanel(nil) })
            DashboardActionRow(
                title: "Quit",
                symbol: "power",
                shortcut: "⌘Q",
                action: { store.onQuit?() })
        }
    }
}

private struct ProviderSwitcherButton: View {
    let snapshot: ProviderSnapshot
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: ProviderBrand.symbol(for: snapshot.provider))
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(selected ? .white : ProviderBrand.color(for: snapshot.provider))
                Text(snapshot.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let percent = snapshot.maximumUsedPercent {
                    Capsule()
                        .fill(ProviderBrand.color(for: snapshot.provider).opacity(0.7))
                        .frame(width: 28, height: 3)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.9))
                                .frame(width: max(2, 28 * CGFloat(min(100, percent) / 100)), height: 3)
                        }
                }
            }
            .foregroundColor(.white.opacity(0.78))
            .frame(maxWidth: .infinity, minHeight: 58)
            .padding(.horizontal, 3)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? ProviderBrand.color(for: snapshot.provider).opacity(0.92) : Color.white.opacity(0.03)))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct ProviderHeaderView: View {
    let snapshot: ProviderSnapshot
    let dashboard: ProviderDashboard

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle().fill(ProviderBrand.color(for: snapshot.provider).opacity(0.22))
                Image(systemName: ProviderBrand.symbol(for: snapshot.provider))
                    .foregroundColor(ProviderBrand.color(for: snapshot.provider))
                    .font(.system(size: 19, weight: .semibold))
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(dashboard.title)
                        .font(.system(size: 21, weight: .bold))
                    if let source = dashboard.source {
                        Text(source)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                    }
                }
                Text(dashboard.updatedText)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            if let plan = snapshot.plan, !plan.isEmpty {
                Text(plan)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
            }
        }
    }
}

private struct ErrorCard: View {
    let message: String
    let providerID: String
    let configure: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                Text("Configuration required")
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
            Button(providerID == "zai" ? "Configure z.ai API token" : "Open provider settings", action: configure)
                .buttonStyle(CompactProminentButtonStyle(color: ProviderBrand.color(for: providerID)))
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.20)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.yellow.opacity(0.25), lineWidth: 1))
    }
}

struct DashboardSummaryCard: View {
    let dashboard: ProviderDashboard
    let openDetails: () -> Void

    var body: some View {
        Button(action: openDetails) {
            VStack(alignment: .leading, spacing: 12) {
                if dashboard.metrics.isEmpty {
                    Text("No summary metrics returned")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.70))
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                        ForEach(dashboard.metrics) { metric in
                            MetricView(metric: metric)
                        }
                    }
                }
                if !dashboard.history.isEmpty {
                    MiniHistoryChart(points: dashboard.history, color: ProviderBrand.color(for: dashboard.id))
                        .frame(height: 106)
                } else if !dashboard.quotas.isEmpty {
                    QuotaBarChart(quotas: dashboard.quotas, color: ProviderBrand.color(for: dashboard.id))
                        .frame(height: 76)
                }
                HStack(spacing: 4) {
                    let tokenTotal = dashboard.history.compactMap(\.tokens).reduce(0, +)
                    let requestTotal = dashboard.history.compactMap(\.requests).reduce(0, +)
                    if tokenTotal > 0 {
                        Text("\(compactNumber(tokenTotal)) tokens")
                    }
                    if tokenTotal > 0, requestTotal > 0 { Text("·") }
                    if requestTotal > 0 {
                        Text("\(compactNumber(requestTotal)) requests")
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
                if let topModel = dashboard.topModel {
                    Text("Top model: \(topModel)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.72))
                        .lineLimit(1)
                }
            }
            .padding(15)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        ProviderBrand.color(for: dashboard.id).opacity(0.95),
                        ProviderBrand.color(for: dashboard.id).opacity(0.60),
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct MetricView: View {
    let metric: DashboardMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metric.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.82))
            Text(metric.value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            if let subtitle = metric.subtitle {
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.62))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct QuotaLaneView: View {
    let lane: DashboardQuotaLane
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(lane.title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(String(format: "%.0f%% used", lane.usedPercent))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.78))
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.09))
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(lane.usedPercent / 100))
                }
            }
            .frame(height: 7)
            if let reset = lane.resetText {
                HStack {
                    Text(reset)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.46))
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 2)
    }
}

private struct DashboardActionRow: View {
    let title: String
    let symbol: String
    var shortcut: String? = nil
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .frame(width: 18)
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .foregroundColor(.white.opacity(0.42))
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(enabled ? .white.opacity(0.88) : .white.opacity(0.30))
            .padding(.horizontal, 8)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(DashboardRowButtonStyle())
        .disabled(!enabled)
    }
}

private struct DashboardRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 7).fill(configuration.isPressed ? Color.white.opacity(0.12) : Color.clear))
    }
}

struct MiniHistoryChart: View {
    let points: [DashboardHistoryPoint]
    let color: Color

    private var values: [Double] {
        let spend = points.compactMap(\.spend)
        if spend.contains(where: { $0 > 0 }) { return points.map { $0.spend ?? 0 } }
        let tokens = points.compactMap(\.tokens)
        if tokens.contains(where: { $0 > 0 }) { return points.map { $0.tokens ?? 0 } }
        return points.map { $0.requests ?? 0 }
    }

    var body: some View {
        GeometryReader { geometry in
            let maxValue = max(values.max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: max(2, geometry.size.width / CGFloat(max(values.count, 1)) * 0.22)) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.82))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(2, geometry.size.height * CGFloat(value / maxValue)))
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(color.opacity(0.24)).frame(height: 1)
            }
        }
    }
}

private struct QuotaBarChart: View {
    let quotas: [DashboardQuotaLane]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(quotas) { quota in
                    VStack(spacing: 5) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.84))
                            .frame(height: max(4, geometry.size.height * CGFloat(quota.usedPercent / 100) * 0.78))
                        Text(quota.title)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.64))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct ProviderDetailPanelView: View {
    let dashboard: ProviderDashboard

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dashboard.title)
                            .font(.system(size: 20, weight: .bold))
                        Text(dashboard.updatedText)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    Spacer()
                    Image(systemName: ProviderBrand.symbol(for: dashboard.id))
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(ProviderBrand.color(for: dashboard.id))
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(dashboard.metrics) { metric in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(metric.title).font(.system(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.52))
                            Text(metric.value).font(.system(size: 16, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.05)))
                    }
                }
                if !dashboard.history.isEmpty {
                    DetailedHistoryChart(points: dashboard.history, providerID: dashboard.id)
                        .frame(height: 300)
                } else {
                    VStack(spacing: 10) {
                        ForEach(dashboard.quotas) { lane in
                            QuotaLaneView(lane: lane, color: ProviderBrand.color(for: dashboard.id))
                        }
                    }
                }
                if let topModel = dashboard.topModel {
                    Text("Top model: \(topModel)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.58))
                        .lineLimit(1)
                }
            }
            .padding(20)
        }
        .frame(width: 560, height: 590)
        .preferredColorScheme(.dark)
    }
}

private struct DetailedHistoryChart: View {
    let points: [DashboardHistoryPoint]
    let providerID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MiniHistoryChart(points: points, color: ProviderBrand.color(for: providerID))
                .frame(height: 150)
            LineHistoryChart(values: points.map { $0.tokens ?? $0.requests ?? 0 }, color: ProviderBrand.color(for: providerID))
                .frame(height: 110)
            HStack {
                Text(points.first?.label ?? "")
                Spacer()
                Text(points.last?.label ?? "")
            }
            .font(.system(size: 9))
            .foregroundColor(.white.opacity(0.38))
        }
    }
}

private struct LineHistoryChart: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                Path { path in
                    guard !values.isEmpty else { return }
                    let maximum = max(values.max() ?? 1, 1)
                    for (index, value) in values.enumerated() {
                        let x = values.count == 1 ? 0 : geometry.size.width * CGFloat(index) / CGFloat(values.count - 1)
                        let y = geometry.size.height * (1 - CGFloat(value / maximum))
                        if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineJoin: .round, lineCap: .round))
                LinearGradient(
                    gradient: Gradient(colors: [color.opacity(0.30), color.opacity(0.02)]),
                    startPoint: .top,
                    endPoint: .bottom)
                    .mask(
                        Path { path in
                            guard !values.isEmpty else { return }
                            let maximum = max(values.max() ?? 1, 1)
                            path.move(to: CGPoint(x: 0, y: geometry.size.height))
                            for (index, value) in values.enumerated() {
                                let x = values.count == 1 ? 0 : geometry.size.width * CGFloat(index) / CGFloat(values.count - 1)
                                let y = geometry.size.height * (1 - CGFloat(value / maximum))
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                            path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                            path.closeSubpath()
                        })
            }
        }
    }
}

struct AllProvidersDashboardView: View {
    @ObservedObject var store: DashboardStore
    var selectedProvider: String?

    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 420), spacing: 16)]

    var body: some View {
        ZStack {
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                .ignoresSafeArea()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(filteredSnapshots) { snapshot in
                        VStack(alignment: .leading, spacing: 10) {
                            ProviderHeaderView(snapshot: snapshot, dashboard: store.dashboard(for: snapshot))
                            DashboardSummaryCard(dashboard: store.dashboard(for: snapshot)) {
                                store.onOpenProviderDetails?(snapshot.provider)
                            }
                            ForEach(store.dashboard(for: snapshot).quotas) { lane in
                                QuotaLaneView(lane: lane, color: ProviderBrand.color(for: snapshot.provider))
                            }
                        }
                        .padding(15)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.18)))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.09), lineWidth: 1))
                    }
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 760, minHeight: 560)
        .task {
            if store.snapshots.isEmpty { await store.refresh() }
            for snapshot in filteredSnapshots.prefix(8) {
                await store.enrich(snapshot)
            }
        }
    }

    private var filteredSnapshots: [ProviderSnapshot] {
        guard let selectedProvider else { return store.snapshots }
        return store.snapshots.filter { $0.provider == selectedProvider || $0.id == selectedProvider }
    }
}

private struct CompactProminentButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundColor(.white)
            .background(RoundedRectangle(cornerRadius: 7).fill(color.opacity(configuration.isPressed ? 0.72 : 0.96)))
    }
}

private func compactNumber(_ value: Double) -> String {
    let absolute = abs(value)
    if absolute >= 1_000_000_000 { return String(format: "%.1fB", value / 1_000_000_000) }
    if absolute >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
    if absolute >= 1_000 { return String(format: "%.1fK", value / 1_000) }
    return String(format: "%.0f", value)
}
