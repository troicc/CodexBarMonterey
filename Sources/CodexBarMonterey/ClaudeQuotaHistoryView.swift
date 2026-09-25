import SwiftUI

struct ClaudeQuotaCoverageView: View {
    let dashboard: ProviderDashboard

    var body: some View {
        Text(dashboard.hasClaudeSharedQuota
            ? "Shared by web, desktop and Claude Code on this account. Web chat has no separate token or cost breakdown here."
            : "Shared quota unavailable. Local logs do not include web chat tokens or costs.")
            .font(.system(size: 10)).foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ClaudeQuotaHistoryView: View {
    let dashboard: ProviderDashboard
    @State private var expanded: Bool
    @State private var selected = "five-hour"
    let now: Date

    init(dashboard: ProviderDashboard, expanded: Bool = false, now: Date = Date()) {
        self.dashboard = dashboard
        self.now = now
        _expanded = State(initialValue: expanded)
    }

    private var series: ClaudeQuotaSeries? {
        dashboard.claudeQuotaHistory.first { $0.id == selected } ?? dashboard.claudeQuotaHistory.first
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                if dashboard.claudeQuotaHistory.count > 1 {
                    Picker("Quota window", selection: $selected) {
                        ForEach(dashboard.claudeQuotaHistory) { lane in Text(lane.title).tag(lane.id) }
                    }.pickerStyle(SegmentedPickerStyle())
                }
                if let series = series, let last = series.samples.last {
                    HStack {
                        Text(series.title + " · used")
                        Spacer()
                        Text(String(format: "%.0f%%", last.usedPercent)).monospacedDigit()
                    }.font(.system(size: 11, weight: .medium))
                    ClaudeQuotaPlot(series: series, now: now)
                        .frame(height: 84)
                    HStack {
                        Text("24h ago")
                        Spacer()
                        Text("Now")
                    }.font(.system(size: 9)).foregroundColor(.secondary)
                    Text("Last sample: \(last.timestamp.formatted(date: .abbreviated, time: .shortened)) · \(series.samples.count) observations")
                        .font(.system(size: 9)).foregroundColor(.secondary)
                    Text("Sampled account quota, including web chat. Breaks mark resets, decreases or gaps over 1 hour. Not tokens or cost.")
                        .font(.system(size: 9)).foregroundColor(.secondary)
                } else {
                    Text(dashboard.claudeQuotaHistoryNotice ?? "History begins with successful refreshes. No samples in the last 24 hours.")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                }
                if series != nil, let notice = dashboard.claudeQuotaHistoryNotice {
                    Text(notice).font(.system(size: 9)).foregroundColor(.secondary)
                }
            }.fixedSize(horizontal: false, vertical: true).padding(.top, 8)
        } label: {
            Label("Quota trend · 24h", systemImage: "chart.xyaxis.line")
                .font(.system(size: 11, weight: .medium))
        }
    }
}

private struct ClaudeQuotaPlot: View {
    let series: ClaudeQuotaSeries
    let now: Date

    private func point(_ sample: ClaudeQuotaSample, size: CGSize) -> CGPoint {
        let fraction = max(0, min(1, sample.timestamp.timeIntervalSince(now.addingTimeInterval(-86400)) / 86400))
        return CGPoint(x: 3 + fraction * max(0, size.width - 6),
            y: 3 + (1 - sample.usedPercent / 100) * max(0, size.height - 6))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Path { path in
                    for percent in [0.0, 0.5, 1.0] {
                        let y = 3 + percent * (geometry.size.height - 6)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                }.stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                Path { path in
                    for (index, sample) in series.samples.enumerated() {
                        let position = point(sample, size: geometry.size)
                        if index > 0, ClaudeQuotaSeries.connects(series.samples[index - 1], sample) {
                            path.addLine(to: position)
                        } else { path.move(to: position) }
                    }
                }.stroke(ProviderBrand.color(for: "claude"), lineWidth: 1.8)
                ForEach(series.samples) { sample in
                    Circle().fill(ProviderBrand.color(for: "claude")).frame(width: 5, height: 5)
                        .position(point(sample, size: geometry.size))
                        .help("\(sample.timestamp.formatted(date: .abbreviated, time: .shortened)): \(String(format: "%.1f%% used", sample.usedPercent))")
                }
                VStack { Text("100%"); Spacer(); Text("0%") }
                    .font(.system(size: 8)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(series.title) shared quota trend, 0 to 100 percent, last 24 hours"))
        .accessibilityValue(Text("\(series.samples.count) observations"))
    }
}
