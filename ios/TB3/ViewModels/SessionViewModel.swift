// TB3 iOS — Session ViewModel (workout engine)

import Foundation
import WidgetKit

@MainActor @Observable
final class SessionViewModel {
    // Timer display
    var timerElapsed: TimeInterval = 0
    var timerPhase: TimerPhase?
    var isOvertime = false

    // Undo
    var undoSetNumber: Int?
    private var undoTimer: Timer?

    // Actions menu
    var showActionsMenu = false
    var showEndConfirm = false

    // Voice tracking
    private var lastAnnouncedSecond: Int?
    private var restCompleteFired = false

    // Live Activity overtime transition tracking
    private var lastPushedOvertime = false

    private let appState: AppState
    private let dataStore: DataStore
    private let feedback: FeedbackService
    private let castService: CastService?
    private let stravaService: StravaService?
    private let liveActivityService: LiveActivityService?

    init(appState: AppState, dataStore: DataStore, feedback: FeedbackService, castService: CastService? = nil, stravaService: StravaService? = nil, liveActivityService: LiveActivityService? = nil) {
        self.appState = appState
        self.dataStore = dataStore
        self.feedback = feedback
        self.castService = castService
        self.stravaService = stravaService
        self.liveActivityService = liveActivityService
    }

    private func sendCastUpdate() {
        castService?.sendSessionState(appState.activeSession)
    }

    private func sendLiveActivityUpdate() {
        guard let session = appState.activeSession else { return }
        liveActivityService?.updateActivity(session: session)
    }

    // MARK: - Convenience Accessors

    var session: ActiveSessionState? { appState.activeSession }

    var currentExercise: ActiveSessionExercise? {
        guard let session, session.currentExerciseIndex < session.exercises.count else { return nil }
        return session.exercises[session.currentExerciseIndex]
    }

    var currentSets: [SessionSet] {
        guard let session else { return [] }
        return session.sets.filter { $0.exerciseIndex == session.currentExerciseIndex }
    }

    var completedSetsCount: Int {
        currentSets.filter(\.completed).count
    }

    var nextSetNumber: Int {
        completedSetsCount + 1
    }

    var allSetsComplete: Bool {
        !currentSets.isEmpty && currentSets.allSatisfy(\.completed)
    }

    var allExercisesComplete: Bool {
        guard let session else { return false }
        return session.sets.allSatisfy(\.completed)
    }

    // MARK: - Timer Tick (called at 250ms intervals from TimelineView)

    func timerTick() {
        guard let session, let timer = session.timerState else {
            if timerPhase != nil { timerPhase = nil }
            if timerElapsed != 0 { timerElapsed = 0 }
            if isOvertime { isOvertime = false }
            return
        }

        let now = Date().timeIntervalSince1970 * 1000
        let elapsed = max(0, now - timer.startedAt)
        let newElapsed = elapsed / 1000 // convert to seconds

        // Only update if changed (avoids unnecessary view invalidation)
        if abs(timerElapsed - newElapsed) >= 0.1 {
            timerElapsed = newElapsed
        }

        if timer.phase == .rest {
            if timerPhase != .rest { timerPhase = .rest }

            if let restDuration = timer.restDurationSeconds, restDuration > 0 {
                let restMs = Double(restDuration) * 1000
                let newOvertime = elapsed >= restMs
                if isOvertime != newOvertime { isOvertime = newOvertime }

                // Push Live Activity update on overtime transition
                if isOvertime != lastPushedOvertime {
                    lastPushedOvertime = isOvertime
                    sendLiveActivityUpdate()
                }

                let remainingMs = restMs - elapsed

                // Voice milestones (countdown to overtime)
                if remainingMs > 0 {
                    let sec = Int(ceil(remainingMs / 1000))
                    if sec != lastAnnouncedSecond, let label = feedback.voiceMilestoneLabel(secondsRemaining: sec) {
                        lastAnnouncedSecond = sec
                        feedback.speakMilestone(label)
                    }
                }

                // "Go" feedback at overtime threshold
                if newOvertime && !restCompleteFired {
                    restCompleteFired = true
                    feedback.restComplete()
                }
            } else {
                if isOvertime { isOvertime = false }
            }
        } else {
            if timerPhase != .exercise { timerPhase = .exercise }
            if isOvertime { isOvertime = false }
        }
    }

    // MARK: - Complete Set / Begin Set

    func completeSet() {
        guard var session = appState.activeSession else { return }

        // If in rest phase → transition to exercise phase
        if let timer = session.timerState, timer.phase == .rest {
            session.timerState = TimerState(
                phase: .exercise,
                startedAt: Date().timeIntervalSince1970 * 1000,
                restDurationSeconds: nil
            )
            lastAnnouncedSecond = nil
            restCompleteFired = false
            lastPushedOvertime = false
            appState.activeSession = session
            session.save()
            sendCastUpdate()
            sendLiveActivityUpdate()
            return
        }

        // Record set completion
        guard let nextIndex = session.sets.firstIndex(where: {
            $0.exerciseIndex == session.currentExerciseIndex && !$0.completed
        }) else { return }

        let now = Date().timeIntervalSince1970 * 1000
        session.sets[nextIndex].completed = true
        session.sets[nextIndex].actualReps = session.sets[nextIndex].targetReps
        session.sets[nextIndex].completedAt = now

        feedback.setComplete()

        // Show undo toast
        undoSetNumber = session.sets[nextIndex].setNumber
        undoTimer?.invalidate()
        undoTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.undoSetNumber = nil
            }
        }

        // Start rest timer
        let restDuration = getRestDuration()
        if restDuration > 0 {
            session.timerState = TimerState(
                phase: .rest,
                startedAt: now,
                restDurationSeconds: restDuration
            )
            lastAnnouncedSecond = nil
            restCompleteFired = false
            lastPushedOvertime = false
        } else {
            session.timerState = nil
        }

        // Check if exercise complete
        let exerciseSets = session.sets.filter { $0.exerciseIndex == session.currentExerciseIndex }
        if exerciseSets.allSatisfy(\.completed) {
            feedback.exerciseComplete()

            // Auto-advance to next exercise
            let nextExerciseIndex = session.currentExerciseIndex + 1
            if nextExerciseIndex < session.exercises.count {
                appState.activeSession = session
                session.save()
                sendCastUpdate()
                sendLiveActivityUpdate()

                // Delay auto-advance 1.5 seconds
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    guard var s = appState.activeSession else { return }
                    s.currentExerciseIndex = nextExerciseIndex
                    if s.exerciseStartTimes[nextExerciseIndex] == nil {
                        s.exerciseStartTimes[nextExerciseIndex] = Date.iso8601Now()
                    }
                    s.timerState = nil
                    appState.activeSession = s
                    s.save()
                    sendCastUpdate()
                    sendLiveActivityUpdate()
                }
                return
            }
        }

        appState.activeSession = session
        session.save()
        sendCastUpdate()
        sendLiveActivityUpdate()

        // Check if all exercises complete
        if session.sets.allSatisfy(\.completed) {
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                completeSession()
            }
        }
    }

    // MARK: - Undo

    func handleUndo() {
        guard var session = appState.activeSession, let undoSetNum = undoSetNumber else { return }

        feedback.undo()

        if let index = session.sets.firstIndex(where: {
            $0.exerciseIndex == session.currentExerciseIndex && $0.setNumber == undoSetNum
        }) {
            session.sets[index].completed = false
            session.sets[index].actualReps = nil
            session.sets[index].completedAt = nil
        }

        session.timerState = nil
        undoSetNumber = nil
        undoTimer?.invalidate()

        appState.activeSession = session
        session.save()
        sendCastUpdate()
        sendLiveActivityUpdate()
    }

    // MARK: - Exercise Navigation

    func goToExercise(_ index: Int) {
        guard var session = appState.activeSession,
              index >= 0, index < session.exercises.count else { return }

        session.currentExerciseIndex = index
        if session.exerciseStartTimes[index] == nil {
            session.exerciseStartTimes[index] = Date.iso8601Now()
        }
        session.timerState = nil
        lastAnnouncedSecond = nil
        restCompleteFired = false
        lastPushedOvertime = false

        appState.activeSession = session
        session.save()
        sendCastUpdate()
        sendLiveActivityUpdate()
    }

    // MARK: - Start Session

    func startSession(exercises: [ComputedExercise], week: ComputedWeek, program: SyncActiveProgram) {
        let now = Date.iso8601Now()

        // Build exercises
        var sessionExercises: [ActiveSessionExercise] = []
        var sets: [SessionSet] = []

        let totalSets = week.setsRange.last ?? 3

        for (i, exercise) in exercises.enumerated() {
            sessionExercises.append(ActiveSessionExercise(
                liftName: exercise.liftName,
                targetWeight: exercise.targetWeight,
                plates: exercise.plates,
                repsPerSet: week.repsPerSet,
                isBodyweight: exercise.isBodyweight
            ))

            for s in 1...totalSets {
                let targetReps: Int
                switch week.repsPerSet {
                case .single(let r): targetReps = r
                case .array(let arr): targetReps = s <= arr.count ? arr[s - 1] : (arr.last ?? 1)
                }

                sets.append(SessionSet(
                    exerciseIndex: i,
                    setNumber: s,
                    targetReps: targetReps,
                    actualReps: nil,
                    completed: false,
                    completedAt: nil
                ))
            }
        }

        let session = ActiveSessionState(
            status: .inProgress,
            templateId: program.templateId,
            week: program.currentWeek,
            session: program.currentSession,
            exercises: sessionExercises,
            sets: sets,
            currentExerciseIndex: 0,
            timerState: nil,
            startedAt: now,
            exerciseStartTimes: [0: now],
            weekPercentage: Double(week.percentage),
            minSets: week.minSets,
            maxSets: week.maxSets
        )

        appState.activeSession = session
        session.save()
        appState.isSessionPresented = true
        castService?.sendSessionStateImmediate(appState.activeSession)
        liveActivityService?.startActivity(session: session)
    }

    // MARK: - Complete Session

    func completeSession() {
        guard let session = appState.activeSession else { return }

        feedback.sessionComplete()

        // Build exercise logs
        var exerciseLogs: [SyncExerciseLog] = []
        for (i, exercise) in session.exercises.enumerated() {
            let exerciseSets = session.sets.filter { $0.exerciseIndex == i && $0.completed }
            let setLogs = exerciseSets.map { set in
                SyncExerciseSet(
                    targetReps: set.targetReps,
                    actualReps: set.actualReps ?? set.targetReps,
                    completed: set.completed
                )
            }

            // Calculate duration
            let startTime = session.exerciseStartTimes[i]
            let nextStartTime = session.exerciseStartTimes[i + 1]
            var duration: TimeInterval?
            if let start = startTime.flatMap({ Date.fromISO8601($0) }) {
                let end = nextStartTime.flatMap({ Date.fromISO8601($0) }) ?? Date()
                duration = end.timeIntervalSince(start)
            }

            exerciseLogs.append(SyncExerciseLog(
                liftName: exercise.liftName,
                targetWeight: exercise.targetWeight,
                actualWeight: exercise.targetWeight,
                sets: setLogs,
                durationSeconds: duration.map { Int($0) }
            ))
        }

        // Determine status
        let completedCount = session.sets.filter(\.completed).count
        let totalCount = session.sets.count
        let status: String
        if completedCount == totalCount {
            status = "completed"
        } else if completedCount > 0 {
            status = "partial"
        } else {
            status = "skipped"
        }

        let now = Date.iso8601Now()
        let log = SyncSessionLog(
            id: Date.generateId(),
            date: session.startedAt,
            templateId: session.templateId,
            week: session.week,
            sessionNumber: session.session,
            status: status,
            startedAt: session.startedAt,
            completedAt: now,
            exercises: exerciseLogs,
            notes: "",
            durationSeconds: nil,
            lastModified: now
        )

        // Save to history
        appState.sessionHistory.append(log)
        dataStore.addSessionLog(log)

        // Advance program
        if var program = appState.activeProgram, let template = Templates.get(id: program.templateId) {
            program.currentSession += 1
            if program.currentSession > template.sessionsPerWeek {
                program.currentSession = 1
                program.currentWeek += 1
            }
            program.lastModified = now
            appState.activeProgram = program

            if let persisted = dataStore.loadActiveProgram() {
                persisted.currentWeek = program.currentWeek
                persisted.currentSession = program.currentSession
                persisted.lastModified = now
                dataStore.saveActiveProgram(persisted)
            }
        }

        // Auto-share to Strava
        if appState.stravaState.isConnected && appState.stravaState.autoShare {
            Task { await stravaService?.shareActivity(session: log) }
        }

        // End Live Activity before clearing session
        liveActivityService?.endActivity()

        // Clear active session
        appState.activeSession = nil
        ActiveSessionState.clear()
        appState.isSessionPresented = false

        // Refresh widgets (Next Workout advances, Progress updates)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - End Workout Early

    func endWorkoutEarly() {
        completeSession()
    }

    // MARK: - Stop Timer

    func stopTimer() {
        guard var session = appState.activeSession else { return }
        session.timerState = nil
        appState.activeSession = session
        session.save()
        sendCastUpdate()
        sendLiveActivityUpdate()
    }

    // MARK: - Rest Duration

    private func getRestDuration() -> Int {
        let defaultRest = appState.profile.restTimerDefault
        if defaultRest > 0 { return defaultRest }

        // Auto-detect from intensity
        guard let session = appState.activeSession else { return 120 }
        let percentage = session.weekPercentage
        if percentage >= 0.9 { return 180 }
        if percentage >= 0.7 { return 120 }
        return 90
    }
}
