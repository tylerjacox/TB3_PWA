// TB3 iOS — Shared App Group Container
// Provides a shared SwiftData ModelContainer accessible by the main app, widgets, and intents.

import Foundation
import SwiftData

enum SharedContainer {
    static let appGroupID = "group.com.tb3.app"

    static var sharedURL: URL {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        )!
    }

    static var storeURL: URL {
        sharedURL.appending(path: "TB3.store")
    }

    static func makeModelContainer() throws -> ModelContainer {
        let config = ModelConfiguration(url: storeURL)
        return try ModelContainer(
            for: PersistedProfile.self,
                 PersistedActiveProgram.self,
                 PersistedSessionLog.self,
                 PersistedOneRepMaxTest.self,
            configurations: config
        )
    }

    // MARK: - Migration

    /// One-time migration: copy data from default SwiftData store to shared App Group container.
    /// Call this on first launch after the update that adds App Groups.
    @MainActor
    static func migrateIfNeeded() {
        let migrationKey = "tb3_shared_container_migrated_v2"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        do {
            // Open the default SwiftData container (wherever the OS put it)
            let oldContainer = try ModelContainer(
                for: PersistedProfile.self,
                     PersistedActiveProgram.self,
                     PersistedSessionLog.self,
                     PersistedOneRepMaxTest.self
            )

            // Check if old store has any data worth migrating
            let oldProfiles = try oldContainer.mainContext.fetch(FetchDescriptor<PersistedProfile>())
            let oldPrograms = try oldContainer.mainContext.fetch(FetchDescriptor<PersistedActiveProgram>())
            let oldSessions = try oldContainer.mainContext.fetch(FetchDescriptor<PersistedSessionLog>())
            let oldMaxTests = try oldContainer.mainContext.fetch(FetchDescriptor<PersistedOneRepMaxTest>())

            let hasOldData = !oldProfiles.isEmpty || !oldPrograms.isEmpty || !oldSessions.isEmpty || !oldMaxTests.isEmpty
            guard hasOldData else {
                UserDefaults.standard.set(true, forKey: migrationKey)
                return
            }

            // Open shared container
            let newContainer = try makeModelContainer()

            // Check if shared store already has data (e.g. from sync)
            let existingPrograms = try newContainer.mainContext.fetch(FetchDescriptor<PersistedActiveProgram>())
            let existingMaxTests = try newContainer.mainContext.fetch(FetchDescriptor<PersistedOneRepMaxTest>())

            // Copy profile (always overwrite — old store has the original)
            if let profile = oldProfiles.first {
                let existing = try newContainer.mainContext.fetch(FetchDescriptor<PersistedProfile>())
                if existing.isEmpty {
                    let newProfile = PersistedProfile()
                    newProfile.apply(from: profile.toSyncProfile())
                    newContainer.mainContext.insert(newProfile)
                }
            }

            // Copy active program if shared store doesn't have one
            if existingPrograms.isEmpty, let program = oldPrograms.first {
                let newProgram = PersistedActiveProgram()
                newProgram.apply(from: program.toSyncActiveProgram())
                newContainer.mainContext.insert(newProgram)
            }

            // Copy session logs (union by ID)
            if !oldSessions.isEmpty {
                let existingSessions = try newContainer.mainContext.fetch(FetchDescriptor<PersistedSessionLog>())
                let existingIds = Set(existingSessions.map { $0.id })
                for session in oldSessions {
                    if !existingIds.contains(session.id) {
                        newContainer.mainContext.insert(PersistedSessionLog(from: session.toSyncSessionLog()))
                    }
                }
            }

            // Copy max tests (union by ID)
            if !oldMaxTests.isEmpty {
                let existingIds = Set(existingMaxTests.map { $0.id })
                for test in oldMaxTests {
                    if !existingIds.contains(test.id) {
                        newContainer.mainContext.insert(PersistedOneRepMaxTest(from: test.toSyncOneRepMaxTest()))
                    }
                }
            }

            try newContainer.mainContext.save()
            UserDefaults.standard.set(true, forKey: migrationKey)
        } catch {
            // Migration failed — will retry next launch. Don't mark as migrated.
            print("SharedContainer migration failed: \(error)")
        }
    }
}
