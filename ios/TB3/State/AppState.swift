// TB3 iOS — Root App State (mirrors state.ts)

import Foundation
import SwiftData

@Observable
final class AppState {
    // Loading
    var isLoading = true
    var isFirstLaunch = false

    // Auth
    var authState = AuthState()

    // Sync
    var syncState = SyncState()

    // Cast
    var castState = CastState()

    // Strava
    var stravaState = StravaState()

    // Data — populated from SwiftData on init
    var profile: SyncProfile = SyncProfile(
        maxType: "training", roundingIncrement: 2.5, barbellWeight: 45,
        plateInventoryBarbell: DEFAULT_PLATE_INVENTORY_BARBELL,
        plateInventoryBelt: DEFAULT_PLATE_INVENTORY_BELT,
        restTimerDefault: 120, soundMode: "on", voiceAnnouncements: false,
        voiceName: nil, theme: "dark", unit: "lb",
        lastModified: ISO8601DateFormatter().string(from: Date())
    )
    var activeProgram: SyncActiveProgram?
    var computedSchedule: ComputedSchedule?
    var activeSession: ActiveSessionState?
    var sessionHistory: [SyncSessionLog] = []
    var maxTestHistory: [SyncOneRepMaxTest] = []
    var lastBackupDate: String?
    var lastSyncedAt: String?

    // Navigation
    var isSessionPresented = false

    // MARK: - Derived State

    /// Current lifts derived from maxTestHistory (mirrors state.ts currentLifts computed)
    var currentLifts: [DerivedLiftEntry] {
        // Group by liftName, take most recent test per lift
        var latestByLift: [String: SyncOneRepMaxTest] = [:]
        for test in maxTestHistory {
            if let existing = latestByLift[test.liftName] {
                if test.date > existing.date {
                    latestByLift[test.liftName] = test
                }
            } else {
                latestByLift[test.liftName] = test
            }
        }

        return latestByLift.values.map { test in
            let oneRepMax = OneRepMaxCalculator.calculateOneRepMax(weight: test.weight, reps: test.reps)
            let workingMax: Double
            if profile.maxType == "training" {
                workingMax = OneRepMaxCalculator.calculateTrainingMax(oneRepMax: oneRepMax)
            } else {
                workingMax = oneRepMax
            }

            return DerivedLiftEntry(
                name: test.liftName,
                weight: test.weight,
                reps: test.reps,
                oneRepMax: oneRepMax,
                workingMax: workingMax,
                isBodyweight: test.liftName == LiftName.weightedPullUp.rawValue,
                testDate: test.date
            )
        }.sorted { $0.name < $1.name }
    }

    // MARK: - Schedule Staleness

    func isScheduleStale() -> Bool {
        guard let schedule = computedSchedule, let program = activeProgram else { return true }
        let currentHash = ScheduleGenerator.computeSourceHash(
            program: program, lifts: currentLifts, profile: profile
        )
        return schedule.sourceHash != currentHash
    }

    func regenerateScheduleIfNeeded() {
        guard let program = activeProgram else {
            computedSchedule = nil
            return
        }
        if isScheduleStale() {
            computedSchedule = ScheduleGenerator.generateSchedule(
                program: program, lifts: currentLifts, profile: profile
            )
        }
    }

    // MARK: - Reload from Store (after sync merge)

    @MainActor
    func reloadFromStore(_ store: DataStore) {
        let persistedProfile = store.loadProfile()
        profile = persistedProfile.toSyncProfile()

        if let persistedProgram = store.loadActiveProgram() {
            activeProgram = persistedProgram.toSyncActiveProgram()
        }

        sessionHistory = store.loadSessionHistory().map { $0.toSyncSessionLog() }
        maxTestHistory = store.loadMaxTestHistory().map { $0.toSyncOneRepMaxTest() }

        regenerateScheduleIfNeeded()
    }

    @MainActor
    func loadInitialData(_ store: DataStore) {
        let persistedProfile = store.loadProfile()
        profile = persistedProfile.toSyncProfile()

        if let persistedProgram = store.loadActiveProgram() {
            activeProgram = persistedProgram.toSyncActiveProgram()
        } else {
            isFirstLaunch = maxTestHistory.isEmpty
        }

        sessionHistory = store.loadSessionHistory().map { $0.toSyncSessionLog() }
        maxTestHistory = store.loadMaxTestHistory().map { $0.toSyncOneRepMaxTest() }

        activeSession = ActiveSessionState.load()
        lastSyncedAt = UserDefaults.standard.string(forKey: "tb3_last_synced_at")

        regenerateScheduleIfNeeded()
        isLoading = false
    }
}
