// TB3 iOS — Training Day Calculator
// Derives rest/workout/deload status from session history and program state.
// Pure stateless utility — no persistence, fully testable.

import Foundation

enum TrainingDayStatus: Equatable {
    case workoutDay
    case restDay(resumeDate: Date, reason: RestReason)
    case deloadWeek(endsDate: Date)
    case programComplete
    case noProgram
}

enum RestReason: Equatable {
    case betweenSessions  // 1 rest day
    case endOfWeek        // 2 rest days
}

enum TrainingDayCalculator {

    /// Determine today's training status.
    static func status(
        program: SyncActiveProgram?,
        template: TemplateDef?,
        sessionHistory: [SyncSessionLog],
        now: Date = Date()
    ) -> TrainingDayStatus {
        guard let program, let template else { return .noProgram }

        // Check deload / program complete first
        if program.currentWeek > template.durationWeeks {
            if let deloadStart = program.deloadStartDate,
               let startDate = Date.fromISO8601(deloadStart) {
                let calendar = Calendar.current
                let deloadEnd = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: startDate))!
                if calendar.startOfDay(for: now) < deloadEnd {
                    return .deloadWeek(endsDate: deloadEnd)
                } else {
                    return .programComplete
                }
            }
            return .programComplete
        }

        // Find last completed session for this program cycle
        let programStart = Date.fromISO8601(program.startDate)
        let lastCompletedDate = sessionHistory
            .filter { log in
                guard log.templateId == program.templateId && log.status != "skipped",
                      let completedAt = Date.fromISO8601(log.completedAt) else { return false }
                // Only count sessions from the current cycle
                if let start = programStart { return completedAt >= start }
                return true
            }
            .compactMap { Date.fromISO8601($0.completedAt) }
            .max()

        guard let lastCompletedDate else {
            // No session history for this cycle — first session
            return .workoutDay
        }

        // Determine rest days based on program position
        // After completeSession() advances the program:
        //   - currentSession == 1 && currentWeek > 1 means we just crossed a week boundary → 2 rest days
        //   - Otherwise → 1 rest day between sessions
        let isNewWeek = program.currentSession == 1 && program.currentWeek > 1
        let restDaysRequired = isNewWeek ? 2 : 1

        let calendar = Calendar.current
        let lastCompletedDay = calendar.startOfDay(for: lastCompletedDate)
        let resumeDate = calendar.date(byAdding: .day, value: restDaysRequired, to: lastCompletedDay)!
        let today = calendar.startOfDay(for: now)

        if today < resumeDate {
            let reason: RestReason = isNewWeek ? .endOfWeek : .betweenSessions
            return .restDay(resumeDate: resumeDate, reason: reason)
        }

        return .workoutDay
    }

    /// Days remaining until next workout (0 = today is workout day).
    static func daysUntilNextWorkout(resumeDate: Date, now: Date = Date()) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: resumeDate)
        return max(0, calendar.dateComponents([.day], from: today, to: target).day ?? 0)
    }

    /// Days remaining in deload week.
    static func daysRemainingInDeload(endsDate: Date, now: Date = Date()) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: endsDate)
        return max(0, calendar.dateComponents([.day], from: today, to: end).day ?? 0)
    }
}
