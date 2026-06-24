import Foundation
import UIKit
import UserNotifications

/// Local notifications for "a job beeped while I was backgrounded" — the babysit-an-agent-run case.
final class NotificationManager {
    static let shared = NotificationManager()
    private var requested = false

    /// Ask once (call when the user opts into bell→notify, in the foreground).
    func requestAuth() {
        guard !requested else { return }
        requested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Post "a job beeped" — only when the app isn't active. Safe to call from the main thread.
    func notifyBell() {
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = "iosTerminal"
        content.body = "A terminal bell fired — a job may have finished."
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
