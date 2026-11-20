import Foundation
import UserNotifications

struct ReminderSyncResult {
    /// Notifications that were scheduled.
    var scheduled: Int = 0
    /// Whether the system currently allows Lifelog to post notifications.
    var authorized: Bool = false
    /// "Once" reminders whose time has passed; the caller should switch them off.
    var expiredOnceIds: [String] = []
}

/// Local notifications only. Nothing is sent to a server.
enum NotificationService {
    private static let identifierPrefix = "lifelog.reminder."
    private static let onceKeyPrefix = "lifelog.reminder.once."

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Forgets the stored fire date for a one-time reminder (call after editing it).
    static func forgetOnce(_ id: String) {
        UserDefaults.standard.removeObject(forKey: onceKeyPrefix + id)
    }

    /// Re-schedules every reminder. The system prompt is shown only when
    /// `requestIfNeeded` is true, at least one reminder is on, and the person has
    /// not been asked yet.
    static func sync(_ reminders: [ReminderItem], requestIfNeeded: Bool = false) async -> ReminderSyncResult {
        let center = UNUserNotificationCenter.current()
        var status = await authorizationStatus()
        let anyEnabled = reminders.contains { $0.enabled }
        if status == .notDetermined, anyEnabled, requestIfNeeded {
            _ = await requestAuthorization()
            status = await authorizationStatus()
        }

        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        if !ours.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ours) }

        var result = ReminderSyncResult()
        result.authorized = status == .authorized || status == .provisional || status == .ephemeral

        let defaults = UserDefaults.standard
        let calendar = Calendar.current
        let now = Date()

        for reminder in reminders {
            let onceKey = onceKeyPrefix + reminder.id
            guard reminder.enabled else {
                defaults.removeObject(forKey: onceKey)
                continue
            }

            var fireDate: Date?
            if reminder.repeatMode == .once {
                if let stored = defaults.object(forKey: onceKey) as? Date {
                    let parts = calendar.dateComponents([.hour, .minute], from: stored)
                    if parts.hour == reminder.hour, parts.minute == reminder.minute {
                        if stored <= now {
                            result.expiredOnceIds.append(reminder.id)
                            defaults.removeObject(forKey: onceKey)
                            continue
                        }
                        fireDate = stored
                    }
                }
                if fireDate == nil {
                    var target = DateComponents()
                    target.hour = reminder.hour
                    target.minute = reminder.minute
                    fireDate = calendar.nextDate(
                        after: now,
                        matching: target,
                        matchingPolicy: .nextTime
                    )
                }
            }

            guard result.authorized else { continue }

            let trigger: UNCalendarNotificationTrigger
            if reminder.repeatMode == .once, let fireDate {
                defaults.set(fireDate, forKey: onceKey)
                let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            } else {
                var parts = DateComponents()
                parts.hour = reminder.hour
                parts.minute = reminder.minute
                trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
            }

            let content = UNMutableNotificationContent()
            content.title = reminder.title.isEmpty ? "Lifelog" : reminder.title
            content.body = reminder.note.isEmpty ? "A quiet moment to record your day." : reminder.note
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: identifierPrefix + reminder.id,
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(request)
                result.scheduled += 1
            } catch {
                continue
            }
        }
        return result
    }
}
