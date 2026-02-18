// TB3 iOS — Start Workout App Intent
// Opens the app and starts the next scheduled workout session.

import AppIntents

struct StartWorkoutIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Start TB3 Workout"
    nonisolated static let description = IntentDescription("Start your next scheduled TB3 workout session.")

    nonisolated static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // If there's already a session in progress, resume it
        if ActiveSessionState.load() != nil {
            UserDefaults.standard.set(true, forKey: "tb3_intent_resume_session")
            NotificationCenter.default.post(name: .tb3IntentFired, object: nil)
            return .result(dialog: "Resuming your workout in progress.")
        }

        // Validate next workout exists
        guard let info = try IntentDataProvider.getNextWorkoutInfo() else {
            throw IntentError.noProgramConfigured
        }

        // Signal the app to start the workout when it opens
        UserDefaults.standard.set(true, forKey: "tb3_intent_start_workout")

        // Notify the app to check intent flags (handles timing race with openAppWhenRun)
        NotificationCenter.default.post(name: .tb3IntentFired, object: nil)

        let exerciseNames = info.exercises.map { $0.liftName }.joined(separator: ", ")
        return .result(dialog: "Starting \(info.templateName) Week \(info.weekNumber) Session \(info.sessionNumber): \(exerciseNames)")
    }
}

// MARK: - Notification Name

extension Notification.Name {
    /// Posted by App Intents after setting UserDefaults flags,
    /// so the app can react even if scenePhase already fired.
    nonisolated(unsafe) static let tb3IntentFired = Notification.Name("tb3IntentFired")
}

// MARK: - Intent Errors

enum IntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case noProgramConfigured
    case programComplete
    case dataUnavailable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noProgramConfigured:
            "No active program. Open TB3 and choose a template first."
        case .programComplete:
            "Your current program is complete. Start a new cycle in TB3."
        case .dataUnavailable:
            "Unable to load workout data. Please open TB3 first."
        }
    }
}
