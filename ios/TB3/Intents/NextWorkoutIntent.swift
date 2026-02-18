// TB3 iOS — Next Workout App Intent
// Returns inline Siri dialog with upcoming session details (no app open needed).

import AppIntents

struct NextWorkoutIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Check Next TB3 Workout"
    nonisolated static let description = IntentDescription("See what's coming up in your TB3 training program.")

    nonisolated static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let info = try IntentDataProvider.getNextWorkoutInfo() else {
            throw IntentError.noProgramConfigured
        }

        // Format sets label
        let setsLabel: String
        if info.setsRange.count == 2, info.setsRange[0] != info.setsRange[1] {
            setsLabel = "\(info.setsRange[0]) to \(info.setsRange[1])"
        } else {
            setsLabel = "\(info.setsRange.last ?? 3)"
        }

        // Format reps label
        let repsLabel: String
        switch info.repsPerSet {
        case .single(let r): repsLabel = "\(r)"
        case .array(let arr): repsLabel = arr.map(String.init).joined(separator: ", ")
        }

        // Build exercise lines
        let exerciseLines = info.exercises.map { ex in
            "\(ex.liftName) at \(Int(ex.targetWeight)) \(info.unit)"
        }.joined(separator: ". ")

        let summary = "\(info.templateName), Week \(info.weekNumber) of \(info.totalWeeks), Session \(info.sessionNumber). \(setsLabel) sets of \(repsLabel) reps at \(info.percentage) percent. \(exerciseLines)."

        return .result(dialog: "\(summary)")
    }
}
