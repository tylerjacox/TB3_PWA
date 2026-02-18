// TB3 iOS — Sync Coordinator (mirrors periodic sync in sync.ts)
// Manages 5-minute timer, app foreground trigger, and network reconnect.

import Foundation
import Network
import SwiftData
import WidgetKit

@MainActor
final class SyncCoordinator {
    private let syncService: SyncService
    private let dataStore: DataStore
    private let authState: AuthState
    private let syncState: SyncState
    private let appState: AppState

    private var timer: Timer?
    private var networkMonitor: NWPathMonitor?
    private var wasOffline = false

    private let syncIntervalSeconds: TimeInterval = 300 // 5 minutes

    init(
        syncService: SyncService,
        dataStore: DataStore,
        authState: AuthState,
        syncState: SyncState,
        appState: AppState
    ) {
        self.syncService = syncService
        self.dataStore = dataStore
        self.authState = authState
        self.syncState = syncState
        self.appState = appState
    }

    // MARK: - Start / Stop

    func start() {
        stop()

        // Periodic 5-minute timer
        timer = Timer.scheduledTimer(withTimeInterval: syncIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performSync()
            }
        }

        // Network path monitor for reconnect trigger
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if path.status == .satisfied && self.wasOffline {
                    self.wasOffline = false
                    await self.performSync()
                } else if path.status != .satisfied {
                    self.wasOffline = true
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.tb3.networkMonitor"))
        networkMonitor = monitor
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        networkMonitor?.cancel()
        networkMonitor = nil
    }

    // MARK: - App Lifecycle Triggers

    /// Call when app returns to foreground (scenePhase → .active)
    func onForeground() {
        Task {
            await performSync()
        }
    }

    /// Call for manual sync (user taps sync button in profile)
    func syncNow() {
        Task {
            await performSync()
        }
    }

    // MARK: - Core Sync

    func performSync() async {
        // Skip conditions (matching PWA sync.ts lines 63-66)
        guard authState.isAuthenticated else { return }
        guard syncState.isSyncing == false else { return }
        guard appState.activeSession == nil else { return } // Skip during workout

        syncState.isSyncing = true
        syncState.error = nil

        do {
            let localChanges = dataStore.getLocalChanges(since: syncState.lastSyncedAt)

            let response = try await syncService.performSync(
                localChanges: localChanges,
                lastSyncedAt: syncState.lastSyncedAt
            )

            // Apply remote changes to local SwiftData
            dataStore.applyRemoteChanges(response.pull)

            // Update last synced timestamp
            syncState.lastSyncedAt = response.serverTime
            UserDefaults.standard.set(response.serverTime, forKey: "tb3_last_synced_at")
            syncState.isSyncing = false

            // Reload app state from store after merge
            appState.reloadFromStore(dataStore)

            // Refresh widgets after sync merge (data may have changed from another device)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            syncState.isSyncing = false
            syncState.error = error.localizedDescription
        }
    }
}
