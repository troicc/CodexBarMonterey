import SwiftUI

struct SubscriptionTimingView: View {
    let dashboard: ProviderDashboard
    var compact = false

    var body: some View {
        if let key = dashboard.subscriptionDatePreferenceKey {
            SubscriptionTimingCard(dashboard: dashboard, preferenceKey: key, compact: compact)
                .id(key)
        }
    }
}

struct SubscriptionTimingCard: View {
    let dashboard: ProviderDashboard
    let compact: Bool
    @AppStorage private var manual: String
    @State private var editing: Bool
    @State private var draftDate = Date()
    @State private var draftKind = SubscriptionTiming.Kind.expires

    init(dashboard: ProviderDashboard, preferenceKey: String, compact: Bool = false,
         defaults: UserDefaults = .standard, editing: Bool = false) {
        self.dashboard = dashboard
        self.compact = compact
        _manual = AppStorage(wrappedValue: "", preferenceKey, store: defaults)
        _editing = State(initialValue: editing)
    }

    private var timing: SubscriptionTiming? {
        SubscriptionTiming.resolve(expires: dashboard.subscriptionExpiresAt,
                                   renews: dashboard.subscriptionRenewsAt, manual: manual)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(timing?.kind.title ?? "Subscription date", systemImage: "calendar")
                    .font(.system(size: compact ? 10 : 11, weight: .medium))
                Spacer(minLength: 4)
                if !compact && (timing == nil || timing?.isManual == true) {
                    Button(timing == nil ? "Set date" : "Edit") {
                        draftDate = timing?.date ?? Date()
                        draftKind = timing?.kind ?? .expires
                        editing = true
                    }.buttonStyle(BorderlessButtonStyle()).font(.system(size: 10))
                }
            }
            if let timing = timing {
                Text(timing.dateText).font(.system(size: compact ? 10 : 12, weight: .medium))
                TimelineView(.periodic(from: Date(), by: 60)) { context in
                    Text(timing.status(now: context.date) + " · " + (timing.isManual ? "Manual" : "Provider"))
                        .font(.system(size: 10)).foregroundColor(.secondary)
                }
            } else {
                Text(compact ? "Not provided · set in details" : "Not provided by this source. You can set a date for this account.")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if editing && !compact {
                editor
            }
        }
        .padding(compact ? 0 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(compact ? 0 : 0.035)))
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Date type", selection: $draftKind) {
                Text("Expires").tag(SubscriptionTiming.Kind.expires)
                Text("Renews").tag(SubscriptionTiming.Kind.renews)
            }.pickerStyle(SegmentedPickerStyle())
            DatePicker("Date", selection: $draftDate, displayedComponents: .date)
                .datePickerStyle(FieldDatePickerStyle())
            Text("Saved for this account. Update after renewal.")
                .font(.system(size: 10)).foregroundColor(.secondary)
            HStack {
                if !manual.isEmpty {
                    Button("Clear") { manual = ""; editing = false }
                }
                Spacer()
                Button("Cancel") { editing = false }
                Button("Save") {
                    manual = SubscriptionTiming.encode(date: draftDate, kind: draftKind)
                    editing = false
                }
            }.font(.system(size: 11))
        }
    }
}
