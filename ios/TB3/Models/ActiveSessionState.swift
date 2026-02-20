// TB3 iOS — Active Session State (mirrors types.ts ActiveSessionState)
// Stored in UserDefaults for crash recovery. Not synced.

import Foundation

struct ActiveSessionExercise: Codable, Equatable {
    var liftName: String
    var targetWeight: Double
    var plates: [PlateCount]
    var repsPerSet: RepsPerSet
    var isBodyweight: Bool
}

struct SessionSet: Codable, Equatable {
    var exerciseIndex: Int
    var setNumber: Int
    var targetReps: Int
    var actualReps: Int?
    var completed: Bool
    var completedAt: Double? // milliseconds since epoch
}

struct TimerState: Codable, Equatable {
    var phase: TimerPhase
    var startedAt: Double // Date.now() milliseconds
    var restDurationSeconds: Int?
}

struct ActiveSessionState: Codable, Equatable {
    var status: WorkoutStatus
    var templateId: String
    var week: Int
    var session: Int
    var exercises: [ActiveSessionExercise]
    var sets: [SessionSet]
    var currentExerciseIndex: Int
    var timerState: TimerState?
    var startedAt: String
    var exerciseStartTimes: [Int: String]
    var weekPercentage: Double
    var minSets: Int?
    var maxSets: Int?
    var temperatureF: Double? // Ambient temperature at session start (°F)

    // MARK: - Persistence via UserDefaults

    private static let storageKey = "tb3_active_session"

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    static func load() -> ActiveSessionState? {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return nil }
        return try? JSONDecoder().decode(ActiveSessionState.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }
}
