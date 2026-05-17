import Foundation
import UserNotifications

enum WakeDreamReminderService {
    static let enabledKey = "wakeDreamReminder.enabled"
    static let lastScheduledDateKey = "wakeDreamReminder.lastScheduledDate"
    static let pendingOpenPromptKey = "wakeDreamReminder.pendingOpenPrompt"

    private static let requestIdentifierPrefix = "lifeos.wake-dream-reminder"
    private static let calendar = Calendar.current
    private static let minimumNightSleepDuration: TimeInterval = 3 * 60 * 60
    private static let reminderDelay: TimeInterval = 2 * 60

    static let composerPrompt = "做梦："

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        if !enabled {
            cancelPending()
            UserDefaults.standard.removeObject(forKey: lastScheduledDateKey)
            UserDefaults.standard.removeObject(forKey: pendingOpenPromptKey)
        }
    }

    static func scheduleIfNeeded(from blocks: [HealthKitTimeBlock], now: Date = Date()) async -> Bool {
        guard UserDefaults.standard.bool(forKey: enabledKey),
              let wakeDate = mainNightSleepWakeDate(from: blocks, now: now) else {
            return false
        }

        let dayKey = dateKey(for: wakeDate)
        guard UserDefaults.standard.string(forKey: lastScheduledDateKey) != dayKey else {
            return false
        }

        let reminderDate = wakeDate.addingTimeInterval(reminderDelay)
        guard reminderDate > now else {
            return false
        }

        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { return false }

            let content = UNMutableNotificationContent()
            content.title = "还记得昨晚的梦吗？"
            content.body = "如果愿意，可以先记下几个片段。"
            content.sound = .default
            content.userInfo = ["lifeosRoute": "dream"]

            let request = UNNotificationRequest(
                identifier: requestIdentifier(for: dayKey),
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: reminderDate.timeIntervalSince(now), repeats: false)
            )

            cancelPending()
            try await center.add(request)
            UserDefaults.standard.set(dayKey, forKey: lastScheduledDateKey)
            return true
        } catch {
            return false
        }
    }

    static func cancelPending() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let identifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(requestIdentifierPrefix) }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    static func markPendingOpen() {
        UserDefaults.standard.set(composerPrompt, forKey: pendingOpenPromptKey)
        NotificationCenter.default.post(name: DailyStateReminderService.notificationName, object: composerPrompt)
    }

    static func consumePendingOpenPrompt() -> String? {
        let prompt = UserDefaults.standard.string(forKey: pendingOpenPromptKey)
        if prompt != nil {
            UserDefaults.standard.removeObject(forKey: pendingOpenPromptKey)
        }
        return prompt
    }

    static func mainNightSleepWakeDate(from blocks: [HealthKitTimeBlock], now: Date = Date()) -> Date? {
        let candidates = blocks.filter { block in
            guard block.extra[HealthKitTimeEntryKey.kind] == HealthKitTimeEntryKey.kindSleep else { return false }
            guard calendar.isDate(block.endDate, inSameDayAs: now) else { return false }
            guard block.endDate.timeIntervalSince(block.startDate) >= minimumNightSleepDuration else { return false }

            let hour = calendar.component(.hour, from: block.endDate)
            return hour >= 4 && hour < 12
        }

        return candidates
            .sorted {
                let lhsDuration = $0.endDate.timeIntervalSince($0.startDate)
                let rhsDuration = $1.endDate.timeIntervalSince($1.startDate)
                if lhsDuration == rhsDuration { return $0.endDate > $1.endDate }
                return lhsDuration > rhsDuration
            }
            .first?
            .endDate
    }

    private static func requestIdentifier(for dayKey: String) -> String {
        "\(requestIdentifierPrefix).\(dayKey)"
    }

    private static func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
