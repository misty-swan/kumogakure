import Foundation
import UserNotifications

@MainActor
protocol NotificationScheduling: AnyObject {
    func requestAuthorizationIfNeeded() async -> Bool
    func authorizationStatus() async -> UNAuthorizationStatus
    func scheduleCompletionNotification(sessionID: UUID, endsAt: Date)
    func cancelCompletionNotification(sessionID: UUID)
    func scheduleGraceWarningNotification()
    func cancelGraceWarningNotification()
}

/// Schedules completion and 10-second grace-period warning local notifications.
@MainActor
final class NotificationScheduler: NotificationScheduling {
    private static let graceWarningIdentifier = "kumogakure.session.grace_warning"

    private let center: UNUserNotificationCenter
    private let preferences: UserPreferencesStore
    private let clock: any ClockProviding

    init(
        center: UNUserNotificationCenter = .current(),
        preferences: UserPreferencesStore,
        clock: any ClockProviding = SystemClock()
    ) {
        self.center = center
        self.preferences = preferences
        self.clock = clock
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        let currentStatus = await authorizationStatus()
        switch currentStatus {
        case .authorized, .provisional, .ephemeral:
            preferences.hasRequestedNotificationPermission = true
            return true
        case .denied:
            preferences.hasRequestedNotificationPermission = true
            return false
        case .notDetermined:
            preferences.hasRequestedNotificationPermission = true
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    func scheduleCompletionNotification(sessionID: UUID, endsAt: Date) {
        let interval = max(1.0, endsAt.timeIntervalSince(clock.now))
        let content = UNMutableNotificationContent()
        content.title = "雲隠れ"
        content.body = "霧が晴れました。おかえりなさい。"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.completionIdentifier(for: sessionID),
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    func cancelCompletionNotification(sessionID: UUID) {
        let identifier = Self.completionIdentifier(for: sessionID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func scheduleGraceWarningNotification() {
        let content = UNMutableNotificationContent()
        content.title = "雲隠れ"
        content.body = "霧が濃くなり始めています。10秒以内に戻ると続けられます。"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.0, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.graceWarningIdentifier,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    func cancelGraceWarningNotification() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.graceWarningIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.graceWarningIdentifier])
    }

    private static func completionIdentifier(for sessionID: UUID) -> String {
        "kumogakure.session.complete.\(sessionID.uuidString)"
    }
}
