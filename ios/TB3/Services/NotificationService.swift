// TB3 iOS — Notification Service (local notifications for rest timer, reminders, milestones)

import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    private var isAuthorized = false

    // MARK: - Permission

    /// Request notification permission lazily (on first toggle enable).
    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            return granted
        } catch {
            return false
        }
    }

    /// Check current authorization status (called at launch).
    func checkAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Rest Timer Background Alert

    private static let restTimerIdentifier = "tb3_rest_timer_complete"

    /// Schedule a notification for when rest time completes.
    /// Called when scenePhase transitions to .background during rest phase.
    func scheduleRestTimerAlert(restDurationSeconds: Int, timerStartedAtMs: Double) {
        guard isAuthorized else { return }

        let nowMs = Date().timeIntervalSince1970 * 1000
        let elapsedSeconds = (nowMs - timerStartedAtMs) / 1000
        let remainingSeconds = Double(restDurationSeconds) - elapsedSeconds

        // If rest is already complete (overtime), fire in 1 second
        let fireIn = max(1, remainingSeconds)

        let content = UNMutableNotificationContent()
        content.title = "Rest Complete"
        content.body = "Time to start your next set"
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fireIn, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.restTimerIdentifier,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Cancel the rest timer notification (called when returning to foreground).
    func cancelRestTimerAlert() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.restTimerIdentifier])
    }

    // MARK: - Workout Reminders

    private static let workoutReminderIdentifier = "tb3_workout_reminder_daily"

    /// Schedule a daily workout reminder at 8 AM with next session info.
    func scheduleWorkoutReminders(
        templateName: String,
        weekNumber: Int,
        sessionNumber: Int,
        exercises: [String]
    ) {
        guard isAuthorized else { return }

        cancelWorkoutReminders()

        let content = UNMutableNotificationContent()
        content.title = "\(templateName) — Week \(weekNumber)"
        let exerciseList = exercises.prefix(3).joined(separator: ", ")
        content.body = "Session \(sessionNumber): \(exerciseList)"
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = 8
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: Self.workoutReminderIdentifier,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Cancel workout reminders.
    func cancelWorkoutReminders() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.workoutReminderIdentifier])
    }

    // MARK: - Program Milestones

    /// Notify when a training week is completed.
    func notifyWeekComplete(templateName: String, weekNumber: Int, totalWeeks: Int) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Week \(weekNumber) Complete!"
        let remaining = totalWeeks - weekNumber
        content.body = "\(templateName) — \(remaining) \(remaining == 1 ? "week" : "weeks") remaining"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "tb3_milestone_week_\(weekNumber)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Notify when a full program cycle is completed.
    func notifyProgramComplete(templateName: String) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Program Complete!"
        content.body = "\(templateName) cycle finished. Time to retest your maxes!"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "tb3_milestone_program_complete",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }
}
