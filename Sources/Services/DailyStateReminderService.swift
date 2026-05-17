import Foundation
import UIKit
import UserNotifications

enum DailyStateReminderService {
    static let enabledKey = "daily.stateReminder.enabled"
    static let hourKey = "daily.stateReminder.hour"
    static let minuteKey = "daily.stateReminder.minute"
    static let pendingOpenKey = "daily.stateReminder.pendingOpen"
    static let notificationName = Notification.Name("LifeOSDailyStateReminderOpenCapture")

    private static let requestIdentifier = "lifeos.daily-state-reminder"

    static var defaultHour: Int { 21 }
    static var defaultMinute: Int { 30 }

    static func schedule(hour: Int, minute: Int) async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else {
                cancel()
                return false
            }

            var dateComponents = DateComponents()
            dateComponents.hour = hour
            dateComponents.minute = minute

            let content = UNMutableNotificationContent()
            content.title = "留一点时间记录今天的状态吗？"
            content.body = "今天的状态、想法、感受，都可以先放这里。"
            content.sound = .default
            content.userInfo = ["lifeosRoute": "capture"]

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: trigger)

            center.removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
            try await center.add(request)
            return true
        } catch {
            cancel()
            return false
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
    }

    static func markPendingOpen() {
        UserDefaults.standard.set(true, forKey: pendingOpenKey)
        NotificationCenter.default.post(name: notificationName, object: nil)
    }

    static func consumePendingOpen() -> Bool {
        let pending = UserDefaults.standard.bool(forKey: pendingOpenKey)
        if pending {
            UserDefaults.standard.set(false, forKey: pendingOpenKey)
        }
        return pending
    }

    static func reminderDate(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }

    static func hourAndMinute(from date: Date) -> (hour: Int, minute: Int) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? defaultHour, components.minute ?? defaultMinute)
    }
}

final class DailyStateReminderNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let route = response.notification.request.content.userInfo["lifeosRoute"] as? String
        if route == "capture" {
            DailyStateReminderService.markPendingOpen()
        } else if route == "dream" {
            WakeDreamReminderService.markPendingOpen()
        }
        completionHandler()
    }
}
