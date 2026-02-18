// TB3 iOS — Widget Data Helper
// Provides non-MainActor data loading for widget timeline providers.
// Mirrors IntentDataProvider.deriveCurrentLifts() without MainActor isolation.

import Foundation
import SwiftData

enum WidgetDataHelper {

    /// Derive current lifts from max test history (non-MainActor version for widgets)
    static func deriveCurrentLifts(from maxTests: [SyncOneRepMaxTest], profile: SyncProfile) -> [DerivedLiftEntry] {
        var latestByLift: [String: SyncOneRepMaxTest] = [:]
        for test in maxTests {
            if let existing = latestByLift[test.liftName] {
                if test.date > existing.date {
                    latestByLift[test.liftName] = test
                }
            } else {
                latestByLift[test.liftName] = test
            }
        }

        let maxType = profile.maxType

        return latestByLift.values.map { test in
            let oneRepMax = OneRepMaxCalculator.calculateOneRepMax(weight: test.weight, reps: test.reps)
            let workingMax: Double
            if maxType == "training" {
                workingMax = OneRepMaxCalculator.calculateTrainingMax(oneRepMax: oneRepMax)
            } else {
                workingMax = oneRepMax
            }
            return DerivedLiftEntry(
                name: test.liftName,
                weight: test.weight,
                reps: test.reps,
                oneRepMax: oneRepMax,
                workingMax: workingMax,
                isBodyweight: test.liftName == LiftName.weightedPullUp.rawValue,
                testDate: test.date
            )
        }.sorted { $0.name < $1.name }
    }
}
