// TB3 iOS — Data Store (mirrors services/storage.ts)
// SwiftData CRUD operations, local changes for sync, remote change merging.

import Foundation
import SwiftData

@MainActor
final class DataStore {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Profile

    func loadProfile() -> PersistedProfile {
        let descriptor = FetchDescriptor<PersistedProfile>()
        let profiles = (try? modelContext.fetch(descriptor)) ?? []
        if let existing = profiles.first { return existing }
        let newProfile = PersistedProfile()
        modelContext.insert(newProfile)
        try? modelContext.save()
        return newProfile
    }

    func saveProfile(_ profile: PersistedProfile) {
        profile.lastModified = Date.iso8601Now()
        try? modelContext.save()
    }

    // MARK: - Active Program

    func loadActiveProgram() -> PersistedActiveProgram? {
        let descriptor = FetchDescriptor<PersistedActiveProgram>()
        return (try? modelContext.fetch(descriptor))?.first
    }

    func saveActiveProgram(_ program: PersistedActiveProgram) {
        program.lastModified = Date.iso8601Now()
        try? modelContext.save()
    }

    func createActiveProgram(templateId: String, startDate: String, liftSelections: [String: [String]]) -> PersistedActiveProgram {
        // Remove existing program
        if let existing = loadActiveProgram() {
            modelContext.delete(existing)
        }
        let program = PersistedActiveProgram(templateId: templateId, startDate: startDate, liftSelections: liftSelections)
        modelContext.insert(program)
        try? modelContext.save()
        return program
    }

    // MARK: - Session History

    func loadSessionHistory() -> [PersistedSessionLog] {
        let descriptor = FetchDescriptor<PersistedSessionLog>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func addSessionLog(_ session: SyncSessionLog) {
        let persisted = PersistedSessionLog(from: session)
        modelContext.insert(persisted)
        try? modelContext.save()
    }

    // MARK: - Max Test History

    func loadMaxTestHistory() -> [PersistedOneRepMaxTest] {
        let descriptor = FetchDescriptor<PersistedOneRepMaxTest>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func addMaxTest(_ test: SyncOneRepMaxTest) {
        let persisted = PersistedOneRepMaxTest(from: test)
        modelContext.insert(persisted)
        try? modelContext.save()
    }

    // MARK: - Sync Integration: Get Local Changes

    /// Get local changes since a given timestamp for sync push.
    /// Mirrors storage.ts getLocalChanges().
    func getLocalChanges(since: String?) -> SyncPushPayload {
        let sinceDate: Date
        if let since, let date = Date.fromISO8601(since) {
            sinceDate = date
        } else {
            sinceDate = Date.distantPast
        }

        let sinceMs = sinceDate.timeIntervalSince1970 * 1000

        // Profile: push if modified since
        let profile = loadProfile()
        let profileModified = Date.fromISO8601(profile.lastModified)?.timeIntervalSince1970 ?? 0
        let syncProfile = profileModified * 1000 > sinceMs ? profile.toSyncProfile() : nil

        // Active program: push if modified since
        let program = loadActiveProgram()
        var syncProgram: SyncActiveProgram?
        if let program {
            let programModified = Date.fromISO8601(program.lastModified)?.timeIntervalSince1970 ?? 0
            syncProgram = programModified * 1000 > sinceMs ? program.toSyncActiveProgram() : nil
        }

        // Sessions: push if modified since (ISO8601 strings are lexicographically ordered)
        let sinceStr = since ?? ""
        let newSessions = loadSessionsModifiedSince(sinceStr).map { $0.toSyncSessionLog() }

        // Max tests: push if modified since
        let newMaxTests = loadMaxTestsModifiedSince(sinceStr).map { $0.toSyncOneRepMaxTest() }

        return SyncPushPayload(
            profile: syncProfile,
            activeProgram: syncProgram,
            newSessions: newSessions,
            newMaxTests: newMaxTests
        )
    }

    private func loadSessionsModifiedSince(_ since: String) -> [PersistedSessionLog] {
        if since.isEmpty { return loadSessionHistory() }
        let descriptor = FetchDescriptor<PersistedSessionLog>(
            predicate: #Predicate { $0.lastModified > since }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func loadMaxTestsModifiedSince(_ since: String) -> [PersistedOneRepMaxTest] {
        if since.isEmpty { return loadMaxTestHistory() }
        let descriptor = FetchDescriptor<PersistedOneRepMaxTest>(
            predicate: #Predicate { $0.lastModified > since }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Sync Integration: Apply Remote Changes

    /// Merge remote changes into local store.
    /// Mirrors storage.ts applyRemoteChanges().
    func applyRemoteChanges(_ pull: SyncPushPayload) {
        // Profile: last-write-wins
        if let remoteProfile = pull.profile {
            let localProfile = loadProfile()
            let remoteModified = Date.fromISO8601(remoteProfile.lastModified)?.timeIntervalSince1970 ?? 0
            let localModified = Date.fromISO8601(localProfile.lastModified)?.timeIntervalSince1970 ?? 0
            if remoteModified > localModified {
                localProfile.apply(from: remoteProfile)
                try? modelContext.save()
            }
        }

        // Active program: last-write-wins
        if let remoteProgram = pull.activeProgram {
            let localProgram = loadActiveProgram()
            let remoteModified = Date.fromISO8601(remoteProgram.lastModified)?.timeIntervalSince1970 ?? 0
            let localModified = localProgram.flatMap { Date.fromISO8601($0.lastModified)?.timeIntervalSince1970 } ?? 0

            if remoteModified > localModified {
                if let existing = localProgram {
                    existing.apply(from: remoteProgram)
                } else {
                    let newProgram = PersistedActiveProgram()
                    newProgram.apply(from: remoteProgram)
                    modelContext.insert(newProgram)
                }
                try? modelContext.save()
            }
        }

        // Sessions: union by ID
        if !pull.newSessions.isEmpty {
            let existingIds = Set(loadSessionHistory().map { $0.id })
            for session in pull.newSessions {
                if !existingIds.contains(session.id) {
                    modelContext.insert(PersistedSessionLog(from: session))
                }
            }
            try? modelContext.save()
        }

        // Max tests: union by ID
        if !pull.newMaxTests.isEmpty {
            let existingIds = Set(loadMaxTestHistory().map { $0.id })
            for test in pull.newMaxTests {
                if !existingIds.contains(test.id) {
                    modelContext.insert(PersistedOneRepMaxTest(from: test))
                }
            }
            try? modelContext.save()
        }
    }

    // MARK: - Clear All Data

    func clearAllData() {
        try? modelContext.delete(model: PersistedProfile.self)
        try? modelContext.delete(model: PersistedActiveProgram.self)
        try? modelContext.delete(model: PersistedSessionLog.self)
        try? modelContext.delete(model: PersistedOneRepMaxTest.self)
        try? modelContext.save()

        // Clear UserDefaults keys
        UserDefaults.standard.removeObject(forKey: "tb3_last_synced_at")
        ActiveSessionState.clear()

        // Clear Keychain
        Keychain.deleteAll()
    }
}
