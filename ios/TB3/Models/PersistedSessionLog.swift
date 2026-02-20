// TB3 iOS — Persisted Session Log (SwiftData, mirrors types.ts SessionLog)

import Foundation
import SwiftData

@Model
final class PersistedSessionLog {
    @Attribute(.unique) var id: String = ""
    var date: String = ""
    var templateId: String = ""
    var week: Int = 0
    var sessionNumber: Int = 0
    var status: String = ""
    var startedAt: String = ""
    var completedAt: String = ""
    var exercisesData: Data = Data()
    var notes: String = ""
    var durationSeconds: Int?
    var lastModified: String = ""
    var temperatureF: Double?

    init() {}

    init(from sync: SyncSessionLog) {
        self.id = sync.id
        self.date = sync.date
        self.templateId = sync.templateId
        self.week = sync.week
        self.sessionNumber = sync.sessionNumber
        self.status = sync.status
        self.startedAt = sync.startedAt
        self.completedAt = sync.completedAt
        self.exercisesData = (try? JSONEncoder().encode(sync.exercises)) ?? Data()
        self.notes = sync.notes
        self.durationSeconds = sync.durationSeconds
        self.lastModified = sync.lastModified
        self.temperatureF = sync.temperatureF
    }

    // MARK: - Exercises accessor

    var exercises: [SyncExerciseLog] {
        get { (try? JSONDecoder().decode([SyncExerciseLog].self, from: exercisesData)) ?? [] }
        set { exercisesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    // MARK: - Conversion to sync payload

    func toSyncSessionLog() -> SyncSessionLog {
        SyncSessionLog(
            id: id,
            date: date,
            templateId: templateId,
            week: week,
            sessionNumber: sessionNumber,
            status: status,
            startedAt: startedAt,
            completedAt: completedAt,
            exercises: exercises,
            notes: notes,
            durationSeconds: durationSeconds,
            lastModified: lastModified,
            temperatureF: temperatureF
        )
    }

    var statusEnum: SessionStatus? {
        SessionStatus(rawValue: status)
    }
}
