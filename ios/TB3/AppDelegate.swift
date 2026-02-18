// TB3 iOS — AppDelegate (GoogleCast SDK initialization + notification delegate)

import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let criteria = GCKDiscoveryCriteria(applicationID: AppConfig.castAppID)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        options.stopReceiverApplicationWhenEndingSession = true
        options.startDiscoveryAfterFirstTapOnCastButton = true
        GCKCastContext.setSharedInstanceWith(options)

        // Disable default Cast notification/mini controller (we handle UI ourselves)
        GCKCastContext.sharedInstance().useDefaultExpandedMediaControls = false

        // Set notification delegate for foreground presentation + tap handling
        UNUserNotificationCenter.current().delegate = self

        return true
    }
}

// MARK: - Notification Handling

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Present milestone notifications as banners even when app is in foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let id = notification.request.identifier
        // Show milestone notifications in foreground
        if id.hasPrefix("tb3_milestone") {
            return [.banner, .sound]
        }
        // Suppress rest timer alerts in foreground (user is already back)
        return []
    }

    /// Handle notification tap — resume workout session.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let id = response.notification.request.identifier
        if id == "tb3_rest_timer_complete" {
            await MainActor.run {
                NotificationCenter.default.post(name: .tb3NotificationTapped, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let tb3NotificationTapped = Notification.Name("tb3NotificationTapped")
}
