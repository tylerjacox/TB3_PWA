// TB3 iOS — Calendar Integration State

import Foundation

@Observable
final class CalendarState {
    var isConnected = false
    var isLoading = false
    var scheduleFutureWorkouts: Bool = UserDefaults.standard.bool(forKey: "tb3_calendar_schedule_future")
    var lastError: String?
}
