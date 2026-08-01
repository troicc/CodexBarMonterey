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
    @Published private(set) var lastSuccessfulRefresh: Date?

    private let client: CLIClient
    var onOpenSettings: (() -> Void)?
    var onOpenAllDetails: (() -> Void)?
    var onOpenProviderDetails: ((String) -> Void)?
    var onQuit: (() -> Void)?
    var onRefreshStateChanged: (() -> Void)?

    private var loadingProviders: [String: Int] = [:]
    private var supplementalJSONBySnapshot: [String: String] = [:]
    private var supplementalJSONByProvider: [String: String] = [:]
    private var refreshPending = false
    private var snapshotGeneration = 0
    private let quotaTrendStore = LocalQuotaTrendStore()
    private let spendHistoryStore = LocalSpendHistoryStore()

    init(client: CLIClient) {
        self.client = client
    }
    var selectedSnapshot: ProviderSnapshot? {
        guard let selectedProviderID = selectedProviderID else { return snapshots.first }
        return snapshots.first(where: { $0.id == selectedProviderID || $0.provider == selectedProviderID })
    }

    var selectedDashboard: ProviderDashboard? {
        guard let snapshot = selectedSnapshot else { return nil }
        return dashboards[snapshot.id]
    }
    func refresh() async {
        if isRefreshing {
            refreshPending = true
            return
        }
        isRefreshing = true
        onRefreshStateChanged?()
        repeat {
            refreshPending = false
            await performRefresh()
        } while refreshPending
        isRefreshing = false
        onRefreshStateChanged?()
    }

    private func performRefresh() async {
        do {
            let loaded = try await client.fetchEnabled(status: true)
            snapshots = loaded.sorted { left, right in
                let providerOrder = left.displayName.localizedCaseInsensitiveCompare(right.displayName)
                if providerOrder != .orderedSame { return providerOrder == .orderedAscending }
                let accountOrder = (left.accountDisplayName ?? "")
                    .localizedCaseInsensitiveCompare(right.accountDisplayName ?? "")
                if accountOrder != .orderedSame { return accountOrder == .orderedAscending }
                return left.id < right.id
            }
            snapshotGeneration &+= 1
            let currentSnapshotIDs = Set(snapshots.map(\.id))
            let currentProviderIDs = Set(snapshots.map(\.provider))
            supplementalJSONBySnapshot = supplementalJSONBySnapshot.filter {
                currentSnapshotIDs.contains($0.key)
            }
            supplementalJSONByProvider = supplementalJSONByProvider.filter {
                currentProviderIDs.contains($0.key)
            }
            var rebuilt: [String: ProviderDashboard] = [:]
            for snapshot in snapshots {
                let cachedSupplement = cachedSupplement(for: snapshot)
                let localQuota = quotaTrendStore.record(snapshot: snapshot)
                let localSpend = spendHistoryStore.record(
                    snapshot: snapshot,
                    supplementalJSON: cachedSupplement)
                let combinedSupplement = Self.combinedSupplementalJSON(
                    cachedSupplement,
                    localQuota,
                    localSpend)
                let dashboard = DashboardParser.dashboard(
                    snapshot: snapshot,
                    supplementalJSON: combinedSupplement)
                rebuilt[snapshot.id] = dashboard
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
            lastError = nil
            lastSuccessfulRefresh = Date()
        } catch {
            lastError = error.localizedDescription
            NSLog("Dashboard refresh failed: %@", error.localizedDescription)
        }
        onRefreshStateChanged?()
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
    private func enrichDashboard(for requestedSnapshot: ProviderSnapshot) async {
        let key = requestedSnapshot.id
        let generation = snapshotGeneration
        guard let snapshot = snapshots.first(where: { $0.id == key }),
              loadingProviders[key] != generation
        else { return }
        loadingProviders[key] = generation
        defer {
            if loadingProviders[key] == generation { loadingProviders[key] = nil }
        }
        let providerAccountCount = snapshots.filter { $0.provider == snapshot.provider }.count
        // The upstream cost command accepts a provider ID but no account ID.
        // Showing that aggregate under every account would be misleading, so
        // suppress provider-level enrichment when multiple accounts are visible.
        let fetchedSupplement: String?
        if providerAccountCount <= 1 {
            fetchedSupplement = await client.dashboardSupplementJSON(provider: snapshot.provider)
        } else {
            fetchedSupplement = nil
        }
        guard generation == snapshotGeneration,
              snapshots.contains(where: { $0.id == key })
        else { return }
        if let fetchedSupplement = fetchedSupplement {
            supplementalJSONBySnapshot[key] = fetchedSupplement
            supplementalJSONByProvider[snapshot.provider] = fetchedSupplement
        } else if providerAccountCount > 1 {
            supplementalJSONBySnapshot[key] = nil
            supplementalJSONByProvider[snapshot.provider] = nil
        }
        let cachedSupplement = fetchedSupplement ?? cachedSupplement(for: snapshot)
        let localQuota = quotaTrendStore.record(snapshot: snapshot)
        let localSpend = spendHistoryStore.record(
            snapshot: snapshot,
            supplementalJSON: cachedSupplement)
        let resolvedSupplement = Self.combinedSupplementalJSON(
            cachedSupplement,
            localQuota,
            localSpend)
        let dashboard = DashboardParser.dashboard(
            snapshot: snapshot,
            supplementalJSON: resolvedSupplement)
        dashboards[key] = dashboard
    }
    func dashboard(for snapshot: ProviderSnapshot) -> ProviderDashboard {
        dashboards[snapshot.id] ?? DashboardParser.dashboard(snapshot: snapshot)
    }

    func openDashboardURL() {
        guard let url = selectedDashboard?.dashboardURL else { return }
        NSWorkspace.shared.open(url)
    }

    func openStatusURL() {
        guard let url = selectedDashboard?.statusURL else { return }
        NSWorkspace.shared.open(url)
    }
    private func cachedSupplement(for snapshot: ProviderSnapshot) -> String? {
        // Provider-level fallback is safe only when that provider has a single
        // account. This prevents one account's supplemental history from being
        // displayed under another account with the same provider ID.
        let accountCount = snapshots.filter { $0.provider == snapshot.provider }.count
        guard accountCount <= 1 else { return nil }
        if let exact = supplementalJSONBySnapshot[snapshot.id] { return exact }
        return supplementalJSONByProvider[snapshot.provider]
    }

    private static func combinedSupplementalJSON(_ sources: String?...) -> String? {
        let sources = sources.compactMap { $0 }.filter { !$0.isEmpty }
        guard !sources.isEmpty else { return nil }
        if sources.count == 1 { return sources[0] }
        let objects = sources.compactMap { source -> Any? in
            guard let data = source.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        }
        guard !objects.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: objects, options: [.sortedKeys])
        else { return sources[0] }
        return String(decoding: data, as: UTF8.self)
    }
}
