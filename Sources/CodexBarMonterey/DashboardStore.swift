@preconcurrency import AppKit
import Foundation
import SwiftUI

@MainActor
final class DashboardStore: ObservableObject {
    @Published private(set) var snapshots: [ProviderSnapshot] = []
    @Published private(set) var dashboards: [String: ProviderDashboard] = [:]
    @Published var selectedProviderID: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    let client: CLIClient

    var onOpenSettings: (() -> Void)?
    var onOpenAllDetails: (() -> Void)?
    var onOpenProviderDetails: ((String) -> Void)?
    var onCheckUpdates: (() -> Void)?
    var onQuit: (() -> Void)?

    private var loadingProviders: Set<String> = []
    private var supplementalJSONBySnapshot: [String: String] = [:]
    private var supplementalJSONByProvider: [String: String] = [:]
    private let quotaTrendStore = LocalQuotaTrendStore()

    init(client: CLIClient) {
        self.client = client
    }

    var selectedSnapshot: ProviderSnapshot? {
        guard let selectedProviderID = selectedProviderID else { return snapshots.first }
        return snapshots.first(where: { $0.id == selectedProviderID || $0.provider == selectedProviderID })
    }

    var selectedDashboard: ProviderDashboard? {
        guard let snapshot = selectedSnapshot else { return nil }
        return dashboards[snapshot.id] ?? dashboards[snapshot.provider]
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil
        do {
            let loaded = try await client.fetchEnabled(status: true)
            snapshots = loaded.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            var rebuilt: [String: ProviderDashboard] = [:]
            for snapshot in snapshots {
                let cachedSupplement = supplementalJSONBySnapshot[snapshot.id] ?? supplementalJSONByProvider[snapshot.provider]
                let localTrend = quotaTrendStore.record(snapshot: snapshot)
                let combinedSupplement = Self.combinedSupplementalJSON(cachedSupplement, localTrend)
                let dashboard = DashboardParser.dashboard(
                    snapshot: snapshot,
                    supplementalJSON: combinedSupplement)
                rebuilt[snapshot.id] = dashboard
                if rebuilt[snapshot.provider] == nil { rebuilt[snapshot.provider] = dashboard }
            }
            dashboards = rebuilt
            if let selectedProviderID = selectedProviderID,
               snapshots.contains(where: { $0.id == selectedProviderID || $0.provider == selectedProviderID }) == false
            {
                self.selectedProviderID = snapshots.first?.id
            } else if self.selectedProviderID == nil {
                self.selectedProviderID = snapshots.first?.id
            }
            if let snapshot = selectedSnapshot {
                await enrichDashboard(for: snapshot)
            }
        } catch {
            lastError = error.localizedDescription
        }
        isRefreshing = false
    }

    func select(_ snapshot: ProviderSnapshot) {
        selectedProviderID = snapshot.id
        Task { await enrichDashboard(for: snapshot) }
    }

    func selectProviderID(_ id: String) {
        guard let snapshot = snapshots.first(where: { $0.id == id || $0.provider == id }) else { return }
        select(snapshot)
    }

    func enrichSelectedDashboard() async {
        guard let snapshot = selectedSnapshot else { return }
        await enrichDashboard(for: snapshot)
    }

    func enrich(_ snapshot: ProviderSnapshot) async {
        await enrichDashboard(for: snapshot)
    }

    private func enrichDashboard(for snapshot: ProviderSnapshot) async {
        let key = snapshot.id
        guard !loadingProviders.contains(key) else { return }
        loadingProviders.insert(key)
        defer { loadingProviders.remove(key) }
        let fetchedSupplement = await client.dashboardSupplementJSON(provider: snapshot.provider)
        if let fetchedSupplement = fetchedSupplement {
            supplementalJSONBySnapshot[key] = fetchedSupplement
            supplementalJSONByProvider[snapshot.provider] = fetchedSupplement
        }
        let cachedSupplement = fetchedSupplement ??
            supplementalJSONBySnapshot[key] ??
            supplementalJSONByProvider[snapshot.provider]
        let localTrend = quotaTrendStore.record(snapshot: snapshot)
        let resolvedSupplement = Self.combinedSupplementalJSON(cachedSupplement, localTrend)
        let dashboard = DashboardParser.dashboard(
            snapshot: snapshot,
            supplementalJSON: resolvedSupplement)
        dashboards[key] = dashboard
        dashboards[snapshot.provider] = dashboard
    }

    func dashboard(for snapshot: ProviderSnapshot) -> ProviderDashboard {
        dashboards[snapshot.id] ?? dashboards[snapshot.provider] ?? DashboardParser.dashboard(snapshot: snapshot)
    }

    func openDashboardURL() {
        guard let url = selectedDashboard?.dashboardURL else { return }
        NSWorkspace.shared.open(url)
    }

    func openStatusURL() {
        guard let url = selectedDashboard?.statusURL else { return }
        NSWorkspace.shared.open(url)
    }

    func copySelectedJSON() {
        guard let json = selectedSnapshot?.rawJSON else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
    }

    private static func combinedSupplementalJSON(_ first: String?, _ second: String?) -> String? {
        let sources = [first, second].compactMap { $0 }.filter { !$0.isEmpty }
        guard !sources.isEmpty else { return nil }
        if sources.count == 1 { return sources[0] }
        let objects = sources.compactMap { source -> Any? in
            guard let data = source.data(using: String.Encoding.utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        }
        guard !objects.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: objects, options: [.sortedKeys])
        else { return sources[0] }
        return String(decoding: data, as: UTF8.self)
    }
}
