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

    func postUpdateAvailable(version: String) {
        let content = UNMutableNotificationContent()
        content.title = "justQuit update available"
        content.body = "Version \(version) is ready to install."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "justquit-update-\(version)",
            content: content,
            trigger: nil
        )

        center.add(request)
    }
}
