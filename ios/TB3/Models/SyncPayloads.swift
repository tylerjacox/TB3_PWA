// TB3 iOS — Sync Payloads (mirrors sync.ts request/response format)
// These Codable structs produce JSON byte-compatible with the PWA sync protocol.

import Foundation

// MARK: - Sync Profile (mirrors types.ts UserProfile for sync)

struct SyncProfile: Codable, Equatable {
    var maxType: String
    var roundingIncrement: Double
    var barbellWeight: Double
    var plateInventoryBarbell: PlateInventory
    var plateInventoryBelt: PlateInventory
    var restTimerDefault: Int
    var soundMode: String
    var voiceAnnouncements: Bool
    var voiceName: String?
    var theme: String
    var unit: String
    var lastModified: String

    // Device-local notification prefs (not synced to PWA)
    var workoutRemindersEnabled: Bool = false
    var restTimerAlertsEnabled: Bool = false

    private enum CodingKeys: String, CodingKey {
        case maxType, roundingIncrement, barbellWeight
        case plateInventoryBarbell, plateInventoryBelt
        case restTimerDefault, soundMode, voiceAnnouncements, voiceName
        case theme, unit, lastModified
    }
}

// MARK: - Sync Active Program (mirrors types.ts ActiveProgram for sync)

struct SyncActiveProgram: Codable, Equatable {
    var templateId: String
    var startDate: String
    var currentWeek: Int
    var currentSession: Int
    var liftSelections: [String: [String]]
    var lastModified: String
}

// MARK: - Sync Session Log (mirrors types.ts SessionLog for sync)

struct SyncExerciseSet: Codable, Equatable {
    var targetReps: Int
    var actualReps: Int
    var completed: Bool
}

struct SyncExerciseLog: Codable, Equatable {
    var liftName: String
    var targetWeight: Double
    var actualWeight: Double
    var sets: [SyncExerciseSet]
    var durationSeconds: Int?
}

struct SyncSessionLog: Codable, Equatable {
    var id: String
    var date: String
    var templateId: String
    var week: Int
    var sessionNumber: Int
    var status: String
    var startedAt: String
    var completedAt: String
    var exercises: [SyncExerciseLog]
    var notes: String
    var durationSeconds: Int?
    var lastModified: String
    var temperatureF: Double?
}

// MARK: - Sync One Rep Max Test (mirrors types.ts OneRepMaxTest for sync)

struct SyncOneRepMaxTest: Codable, Equatable {
    var id: String
    var date: String
    var liftName: String
    var weight: Double
    var reps: Int
    var calculatedMax: Double
    var maxType: String
    var workingMax: Double
    var lastModified: String
}

// MARK: - Sync Request/Response (mirrors Lambda sync.ts)

struct SyncPushPayload: Codable {
    var profile: SyncProfile?
    var activeProgram: SyncActiveProgram?
    var newSessions: [SyncSessionLog]
    var newMaxTests: [SyncOneRepMaxTest]
}

struct SyncRequest: Codable {
    var lastSyncedAt: String?
    var push: SyncPushPayload
}

struct SyncResponse: Codable {
    var serverTime: String
    var pull: SyncPushPayload
}

// MARK: - Export/Import Format (mirrors exportImport.ts)

struct ExportedAppData: Codable {
    var tb3_export: Bool
    var exportedAt: String
    var appVersion: String
    var schemaVersion: Int
    var profile: SyncProfile
    var activeProgram: SyncActiveProgram?
    var sessionHistory: [SyncSessionLog]
    var maxTestHistory: [SyncOneRepMaxTest]
}
