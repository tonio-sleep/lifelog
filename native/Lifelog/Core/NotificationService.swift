import Foundation
import UserNotifications

enum NotificationService {
    static func sync(_ reminders: [ReminderItem]) async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { $0.hasPrefix("lifelog.reminder.") }
        if !identifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
        guard granted else { return }

        for reminder in reminders where reminder.enabled {
            var components = DateComponents()
            components.hour = reminder.hour
            components.minute = reminder.minute
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: reminder.repeatMode == .daily
            )
            let content = UNMutableNotificationContent()
            content.title = reminder.title.isEmpty ? "Lifelog" : reminder.title
            content.body = reminder.note.isEmpty ? "A quiet moment to record your day." : reminder.note
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "lifelog.reminder.\(reminder.id)",
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }
}
