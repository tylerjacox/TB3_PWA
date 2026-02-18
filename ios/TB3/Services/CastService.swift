// TB3 iOS — Cast Service (GoogleCast SDK integration)
// Sends workout session JSON to Cast receiver via custom namespace.
//
// NOTE: Requires GoogleCast SDK added via CocoaPods.
// Build will fail without `pod install` — this is expected until
// the Xcode workspace is set up.

import Foundation

// Protocol to abstract GoogleCast SDK for testability and to compile without SDK
protocol CastSessionProtocol: AnyObject {
    func sendMessage(_ message: String, namespace: String) throws
}

@MainActor
final class CastService {
    private let castState: CastState
    private let namespace = AppConfig.castNamespace

    // GoogleCast session reference (set when connected)
    private var castSession: CastSessionProtocol?

    // Debounce timer for rapid state updates
    private var debounceTimer: Timer?

    init(castState: CastState) {
        self.castState = castState
    }

    // MARK: - Setup (called after GoogleCast SDK initialized)

    /// Connect to a Cast session. Called when GCKSessionManager reports connection.
    func onSessionConnected(_ session: CastSessionProtocol) {
        castSession = session
        castState.connected = true
    }

    /// Disconnect. Called when GCKSessionManager reports disconnection.
    func onSessionDisconnected() {
        castSession = nil
        castState.connected = false
        castState.deviceName = nil
    }

    func updateDeviceName(_ name: String?) {
        castState.deviceName = name
    }

    func setAvailable(_ available: Bool) {
        castState.available = available
    }

    // MARK: - Send Session State

    /// Send current workout state to Cast receiver.
    /// Debounced to prevent rapid message flooding during set completion.
    func sendSessionState(_ state: ActiveSessionState?) {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendMessageImmediate(state)
            }
        }
    }

    /// Send immediately (for initial connection, no debounce)
    func sendSessionStateImmediate(_ state: ActiveSessionState?) {
        sendMessageImmediate(state)
    }

    private func sendMessageImmediate(_ state: ActiveSessionState?) {
        guard let castSession, castState.connected else { return }

        let payload: [String: Any]

        if let state {
            let exercise = state.currentExerciseIndex < state.exercises.count
                ? state.exercises[state.currentExerciseIndex]
                : nil

            let exerciseSets = state.sets.filter { $0.exerciseIndex == state.currentExerciseIndex }
            let completedSets = exerciseSets.filter(\.completed).count
            let totalSets = exerciseSets.count
            let nextSet = exerciseSets.first { !$0.completed }

            // Exercise summaries
            let exerciseSummaries: [[String: Any]] = state.exercises.enumerated().map { i, ex in
                let exSets = state.sets.filter { $0.exerciseIndex == i }
                return [
                    "name": LiftName(rawValue: ex.liftName)?.displayName ?? ex.liftName,
                    "completedSets": exSets.filter(\.completed).count,
                    "totalSets": exSets.count,
                ]
            }

            // Timer — send elapsedMs so Cast receiver doesn't need clock sync
            let serverTimeNow = Date().timeIntervalSince1970 * 1000
            var timerDict: [String: Any]
            if let timer = state.timerState {
                timerDict = [
                    "phase": timer.phase.rawValue,
                    "startedAt": timer.startedAt,
                    "restDurationSeconds": timer.restDurationSeconds as Any,
                    "elapsedMs": max(0, serverTimeNow - timer.startedAt),
                    "serverTimeNow": serverTimeNow,
                ]
            } else {
                timerDict = ["phase": NSNull(), "startedAt": 0, "restDurationSeconds": NSNull(), "serverTimeNow": serverTimeNow]
            }

            payload = [
                "exerciseName": LiftName(rawValue: exercise?.liftName ?? "")?.displayName ?? (exercise?.liftName ?? ""),
                "weight": exercise?.targetWeight ?? 0,
                "unit": "lb",
                "plates": exercise?.plates.map { ["weight": $0.weight, "count": $0.count] } ?? [],
                "isBodyweight": exercise?.isBodyweight ?? false,
                "currentSetNumber": (nextSet?.setNumber ?? totalSets + 1),
                "totalSets": totalSets,
                "completedSets": completedSets,
                "targetReps": nextSet?.targetReps ?? 0,
                "timer": timerDict,
                "exercises": exerciseSummaries,
                "currentExerciseIndex": state.currentExerciseIndex,
                "week": state.week,
                "session": state.session,
                "templateId": state.templateId,
                "startedAt": state.startedAt,
            ]
        } else {
            payload = ["idle": true]
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        try? castSession.sendMessage(jsonString, namespace: namespace)
    }
}
