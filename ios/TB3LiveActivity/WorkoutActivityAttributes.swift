// TB3 iOS — Live Activity Attributes (shared between main app + widget extension)

import ActivityKit
import Foundation

struct WorkoutActivityAttributes: ActivityAttributes {
    // Static context — set once when activity starts
    var templateId: String
    var week: Int
    var sessionNumber: Int
    var totalExercises: Int

    // Dynamic state — updated on every significant change
    struct ContentState: Codable, Hashable {
        var exerciseName: String
        var exerciseIndex: Int
        var weight: Int
        var isBodyweight: Bool
        var completedSets: Int
        var totalSets: Int
        var timerPhase: String?          // "rest" | "exercise" | nil
        var timerStartedAt: Double?      // ms since epoch
        var restDurationSeconds: Int?
        var isOvertime: Bool
    }
}
