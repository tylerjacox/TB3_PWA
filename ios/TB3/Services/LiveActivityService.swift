// TB3 iOS — Live Activity Service (manages ActivityKit lifecycle)

import ActivityKit
import Foundation

@MainActor
final class LiveActivityService {
    private var currentActivity: Activity<WorkoutActivityAttributes>?

    // MARK: - Start

    func startActivity(session: ActiveSessionState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // End any existing activity first
        endActivity()

        let attributes = WorkoutActivityAttributes(
            templateId: session.templateId,
            week: session.week,
            sessionNumber: session.session,
            totalExercises: session.exercises.count
        )

        let state = buildContentState(from: session)
        let content = ActivityContent(state: state, staleDate: nil)

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            print("[LiveActivity] Failed to start: \(error)")
        }
    }

    // MARK: - Update

    func updateActivity(session: ActiveSessionState) {
        guard let activity = currentActivity else { return }

        let state = buildContentState(from: session)
        let content = ActivityContent(state: state, staleDate: nil)

        Task {
            await activity.update(content)
        }
    }

    // MARK: - End

    func endActivity() {
        guard let activity = currentActivity else { return }

        let finalState = WorkoutActivityAttributes.ContentState(
            exerciseName: "Complete",
            exerciseIndex: 0,
            weight: 0,
            isBodyweight: false,
            completedSets: 0,
            totalSets: 0,
            timerPhase: nil,
            timerStartedAt: nil,
            restDurationSeconds: nil,
            isOvertime: false
        )

        let content = ActivityContent(state: finalState, staleDate: nil)

        Task {
            await activity.end(content, dismissalPolicy: .immediate)
        }

        currentActivity = nil
    }

    // MARK: - Build State

    private func buildContentState(from session: ActiveSessionState) -> WorkoutActivityAttributes.ContentState {
        let exercise = session.exercises[session.currentExerciseIndex]
        let exerciseSets = session.sets.filter { $0.exerciseIndex == session.currentExerciseIndex }
        let completedSets = exerciseSets.filter(\.completed).count

        // Compute overtime
        var isOvertime = false
        if let timer = session.timerState, timer.phase == .rest,
           let restDuration = timer.restDurationSeconds, restDuration > 0 {
            let elapsed = Date().timeIntervalSince1970 * 1000 - timer.startedAt
            isOvertime = elapsed >= Double(restDuration) * 1000
        }

        return WorkoutActivityAttributes.ContentState(
            exerciseName: LiftName(rawValue: exercise.liftName)?.displayName ?? exercise.liftName,
            exerciseIndex: session.currentExerciseIndex,
            weight: Int(exercise.targetWeight),
            isBodyweight: exercise.isBodyweight,
            completedSets: completedSets,
            totalSets: exerciseSets.count,
            timerPhase: session.timerState?.phase.rawValue,
            timerStartedAt: session.timerState?.startedAt,
            restDurationSeconds: session.timerState?.restDurationSeconds,
            isOvertime: isOvertime
        )
    }
}
