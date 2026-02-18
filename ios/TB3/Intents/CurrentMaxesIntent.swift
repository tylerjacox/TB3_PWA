// TB3 iOS — Current Maxes App Intent
// Returns inline Siri dialog with the user's current one-rep maxes.

import AppIntents

struct CurrentMaxesIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Check TB3 Lift Maxes"
    nonisolated static let description = IntentDescription("See your current one-rep max and working max for each lift.")

    nonisolated static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let maxTests = try IntentDataProvider.loadMaxTestHistory()
        let profile = try IntentDataProvider.loadProfile()
        let lifts = IntentDataProvider.deriveCurrentLifts(from: maxTests, profile: profile)

        guard !lifts.isEmpty else {
            throw IntentError.noProgramConfigured
        }
        let unit = profile.unit

        let lines = lifts.map { lift in
            "\(lift.name): \(Int(lift.oneRepMax)) \(unit) max, \(Int(lift.workingMax)) \(unit) working"
        }.joined(separator: ". ")

        return .result(dialog: "Your current maxes. \(lines).")
    }
}
