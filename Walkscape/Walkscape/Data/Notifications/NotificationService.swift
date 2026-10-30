import Foundation
import Observation
import UIKit
import UserNotifications
import WalkscapeBackend
import WalkscapeDomain

/// Local notifications for game events (chests, zones, companion growth,
/// referral chests, the daily reminder) and the APNs registration that lets
/// the server push friend requests and team invites.
///
/// A single shared instance, so the app delegate can install it as the
/// notification delegate before launch finishes (a tap that launches the
/// app is only delivered to a delegate set by then).
@MainActor
@Observable
final class NotificationService: NSObject {
    static let shared = NotificationService()

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    /// This device's APNs token (hex), once iOS hands it over.
    private(set) var deviceToken: String?
    /// Set when a notification is tapped; the app moves to that tab.
    private(set) var pendingDestination: GameNotification.Destination?

    @ObservationIgnored var onDeviceToken: ((String) -> Void)?
    @ObservationIgnored var onOpen: ((GameNotification.Destination) -> Void)?
    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    static let reminderID = "daily-reminder"

    /// Debug builds talk to the APNs sandbox; TestFlight and App Store builds to production.
    static var pushEnvironment: PushRegistry.Environment {
        #if DEBUG
        return .sandbox
        #else
        return .production
        #endif
    }

    var isAuthorized: Bool { authorization == .authorized || authorization == .provisional || authorization == .ephemeral }

    func install() {
        center.delegate = self
    }

    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
        if isAuthorized { UIApplication.shared.registerForRemoteNotifications() }
    }

    /// Shows the iOS permission prompt. Returns whether notifications are allowed.
    func requestPermission() async -> Bool {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        await refreshAuthorization()
        return isAuthorized
    }

    func didRegister(deviceToken data: Data) {
        let token = PushRegistry.hex(data)
        deviceToken = token
        onDeviceToken?(token)
    }

    /// Posts right away. Callers decide what is worth posting.
    func post(_ notifications: [GameNotification]) {
        guard isAuthorized else { return }
        for notification in notifications {
            center.add(UNNotificationRequest(identifier: notification.id, content: content(for: notification), trigger: nil))
        }
    }

    /// Repeats every day at `hour`, or removes the reminder when `notification` is nil.
    func scheduleDailyReminder(_ notification: GameNotification?, hour: Int) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.reminderID])
        guard let notification, isAuthorized else { return }
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: 0), repeats: true)
        center.add(UNNotificationRequest(identifier: Self.reminderID, content: content(for: notification), trigger: trigger))
    }

    func takePendingDestination() -> GameNotification.Destination? {
        defer { pendingDestination = nil }
        return pendingDestination
    }

    private func content(for notification: GameNotification) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.threadIdentifier = notification.category.rawValue
        content.userInfo = ["destination": notification.destination.rawValue, "notificationID": notification.id]
        return content
    }

    fileprivate func opened(_ destination: GameNotification.Destination) {
        if let onOpen { onOpen(destination) } else { pendingDestination = destination }
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    /// While the app is open, still show the banner: social pushes are the
    /// only ones that arrive then (game events are only posted in the background).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let raw = response.notification.request.content.userInfo["destination"] as? String
        guard let destination = raw.flatMap(GameNotification.Destination.init(rawValue:)) else { return }
        await MainActor.run { self.opened(destination) }
    }
}

/// Hands APNs callbacks to `NotificationService`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MainActor.assumeIsolated { NotificationService.shared.install() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { NotificationService.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Simulators and builds without the push entitlement land here; local notifications still work.
    }
}
