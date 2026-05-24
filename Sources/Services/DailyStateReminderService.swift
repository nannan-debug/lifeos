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
            UserDefaults.standard.set(hour, forKey: hourKey)
            UserDefaults.standard.set(minute, forKey: minuteKey)
            rescheduleIfNeeded()
            return true
        } catch {
            cancel()
            return false
        }
    }

    static func rescheduleIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: enabledKey) else { return }
        let hour = defaults.integer(forKey: hourKey)
        let minute = defaults.integer(forKey: minuteKey)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestIdentifier])

        guard let smart = generateSmartContent() else { return }

        var fireDate = DateComponents()
        fireDate.hour = hour == 0 && minute == 0 ? defaultHour : hour
        fireDate.minute = hour == 0 && minute == 0 ? defaultMinute : minute

        let now = Date()
        let todayTarget = reminderDate(hour: fireDate.hour!, minute: fireDate.minute!)
        if now > todayTarget {
            guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) else { return }
            let c = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
            fireDate.year = c.year
            fireDate.month = c.month
            fireDate.day = c.day
        }

        let content = UNMutableNotificationContent()
        content.title = smart.title
        content.body = smart.body
        content.sound = .default
        content.userInfo = ["lifeosRoute": "capture"]

        let trigger = UNCalendarNotificationTrigger(dateMatching: fireDate, repeats: false)
        let request = UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: trigger)
        center.add(request)
    }

    static func generateSmartContent() -> (title: String, body: String)? {
        let defaults = UserDefaults.standard
        let uid = defaults.string(forKey: "auth.userId") ?? ""
        let suffix = uid.isEmpty ? "" : ".\(uid)"

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let todayKey = f.string(from: Date())

        let tasks = defaults.array(forKey: "ps.tasks\(suffix)") as? [[String: String]] ?? []
        let incompleteTasks = tasks.filter { ($0["status"] ?? "") != "已完成" }.count

        let timeMap = defaults.dictionary(forKey: "ps.time.byDate\(suffix)") as? [String: [[String: String]]] ?? [:]
        let todayTimeCount = timeMap[todayKey]?.count ?? 0

        let turns = defaults.array(forKey: "ps.turns\(suffix)") as? [[String: String]] ?? []
        let startOfDay = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let todayTurnCount = turns.filter {
            guard let ts = Double($0["createdAt"] ?? "") else { return false }
            return ts >= startOfDay
        }.count

        let checksMap = defaults.dictionary(forKey: "ps.checks.byDate\(suffix)") as? [String: [String: Bool]] ?? [:]
        let todayChecks = checksMap[todayKey] ?? [:]
        let checksDone = todayChecks.values.filter { $0 }.count
        let checksTotal = todayChecks.count

        if todayTurnCount >= 3 && todayTimeCount >= 2 { return nil }

        let daysAbsent: Int = {
            let sortedKeys = timeMap.keys.sorted().reversed()
            guard let latest = sortedKeys.first(where: { $0 <= todayKey && !(timeMap[$0] ?? []).isEmpty }),
                  let latestDate = f.date(from: latest) else { return 0 }
            return Calendar.current.dateComponents([.day], from: latestDate, to: Date()).day ?? 0
        }()

        if daysAbsent >= 3 {
            return ("好几天没来了，还好吗？", "不用整理好，随便说一句也行。")
        }
        if incompleteTasks > 0 {
            return ("你今天有\(incompleteTasks)个待办还没完成哦", "想聊聊今天的状态吗？")
        }
        if todayTurnCount == 0 && todayTimeCount == 0 {
            return ("今天还没有记录呢", "状态怎么样？")
        }
        if checksTotal > 0 && checksDone < checksTotal {
            let remaining = checksTotal - checksDone
            return ("打卡还差\(remaining)个", "留一点时间记录今天吗？")
        }
        return ("留一点时间记录今天的状态吗？", "今天的想法、感受，都可以先放这里。")
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
