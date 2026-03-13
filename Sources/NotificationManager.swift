import Foundation
import UserNotifications

@MainActor
final class NotificationManager {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorizationIfNeeded() {
        center.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    func postQuitSummary(_ summary: QuitSummary) {
        let content = UNMutableNotificationContent()
        content.title = "justQuit finished"
        content.body = summary.count == 0 ? "Nothing needed to quit." : summary.message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        center.add(request)
    }
}
