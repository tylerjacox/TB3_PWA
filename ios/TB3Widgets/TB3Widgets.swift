// TB3 iOS — Widget Bundle Entry Point
// Provides home screen and lock screen widgets for workout info at a glance.

import WidgetKit
import SwiftUI

@main
struct TB3WidgetBundle: WidgetBundle {
    var body: some Widget {
        NextWorkoutWidget()
        LiftPRsWidget()
        ProgressWidget()
        StrengthTrendWidget()
    }
}
