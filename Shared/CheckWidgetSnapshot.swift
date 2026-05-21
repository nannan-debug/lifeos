import AppIntents
import Foundation
import WidgetKit

struct CheckWidgetItemSnapshot: Codable, Equatable, Identifiable {
    var id: String { title }
    let title: String
    let done: Bool
    let tag: String
}

struct CheckWidgetSnapshot: Codable, Equatable {
    static let storageKey = "lifeos.checkWidget.snapshot.v1"

    let dateKey: String
    let updatedAt: Date
    let items: [CheckWidgetItemSnapshot]

    var completedCount: Int {
        items.filter(\.done).count
    }

    var pendingItems: [CheckWidgetItemSnapshot] {
        items.filter { !$0.done }
    }

    var displayItems: [CheckWidgetItemSnapshot] {
        let pending = pendingItems
        return pending.isEmpty ? Array(items.prefix(6)) : pending + items.filter(\.done)
    }

    static var emptyToday: CheckWidgetSnapshot {
        empty(for: Date())
    }

    static func empty(for date: Date) -> CheckWidgetSnapshot {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return CheckWidgetSnapshot(dateKey: formatter.string(from: date), updatedAt: date, items: [])
    }
}

enum CheckWidgetSnapshotStore {
    static let appGroupID = "group.ai.anna.personalsystem"
    static let activeUserIDKey = "lifeos.checkWidget.activeUserId.v1"
    static let checksKeyBase = "ps.checks.byDate"

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func checksKey(for userID: String?) -> String {
        guard let userID, !userID.isEmpty else { return checksKeyBase }
        return "\(checksKeyBase).\(userID)"
    }

    static func save(_ snapshot: CheckWidgetSnapshot, defaults: UserDefaults = sharedDefaults) {
        guard let data = try? JSONEncoder.widgetSnapshotEncoder.encode(snapshot) else { return }
        defaults.set(data, forKey: CheckWidgetSnapshot.storageKey)
    }

    static func load(defaults: UserDefaults = sharedDefaults, today: Date = Date()) -> CheckWidgetSnapshot {
        guard let data = defaults.data(forKey: CheckWidgetSnapshot.storageKey),
              let snapshot = try? JSONDecoder.widgetSnapshotDecoder.decode(CheckWidgetSnapshot.self, from: data) else {
            return .empty(for: today)
        }
        return refreshSnapshotForTodayIfNeeded(snapshot, today: today, defaults: defaults)
    }

    static func refreshSnapshotForTodayIfNeeded(
        _ snapshot: CheckWidgetSnapshot,
        today: Date = Date(),
        defaults: UserDefaults = sharedDefaults
    ) -> CheckWidgetSnapshot {
        let todayKey = dateKey(for: today)
        guard snapshot.dateKey != todayKey else {
            return snapshot
        }
        let refreshed = snapshotForDate(todayKey, basedOn: snapshot, updatedAt: today, defaults: defaults)
        save(refreshed, defaults: defaults)
        return refreshed
    }

    static func saveAppContext(
        userID: String?,
        checksByDate: [String: [String: Bool]],
        snapshot: CheckWidgetSnapshot,
        defaults: UserDefaults = sharedDefaults
    ) {
        defaults.set(userID ?? "", forKey: activeUserIDKey)
        defaults.set(checksByDate, forKey: checksKey(for: userID))
        save(snapshot, defaults: defaults)
    }

    static func loadSharedChecks(userID: String?, defaults: UserDefaults = sharedDefaults) -> [String: [String: Bool]]? {
        defaults.dictionary(forKey: checksKey(for: userID)) as? [String: [String: Bool]]
    }

    @discardableResult
    static func toggleItem(
        title: String,
        dateKey requestedDateKey: String?,
        defaults: UserDefaults = sharedDefaults,
        today: Date = Date()
    ) -> CheckWidgetSnapshot {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = load(defaults: defaults, today: today)
        guard !cleanTitle.isEmpty else { return snapshot }

        let requestedDateKey = requestedDateKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetDateKey = requestedDateKey == snapshot.dateKey ? snapshot.dateKey : dateKey(for: today)
        let userID = defaults.string(forKey: activeUserIDKey) ?? ""
        let key = checksKey(for: userID)
        var checksByDate = defaults.dictionary(forKey: key) as? [String: [String: Bool]] ?? [:]
        var day = checksByDate[targetDateKey] ?? [:]
        let currentValue = day[cleanTitle] ?? snapshot.items.first(where: { $0.title == cleanTitle })?.done ?? false
        day[cleanTitle] = !currentValue
        checksByDate[targetDateKey] = day
        defaults.set(checksByDate, forKey: key)

        let updatedItems = snapshot.items.map { item in
            guard item.title == cleanTitle else { return item }
            return CheckWidgetItemSnapshot(title: item.title, done: !currentValue, tag: item.tag)
        }
        let updatedSnapshot = CheckWidgetSnapshot(
            dateKey: snapshot.dateKey,
            updatedAt: Date(),
            items: updatedItems
        )
        save(updatedSnapshot, defaults: defaults)
        return updatedSnapshot
    }

    private static func snapshotForDate(
        _ dateKey: String,
        basedOn snapshot: CheckWidgetSnapshot,
        updatedAt: Date,
        defaults: UserDefaults
    ) -> CheckWidgetSnapshot {
        let userID = defaults.string(forKey: activeUserIDKey) ?? ""
        let key = checksKey(for: userID)
        let checksByDate = defaults.dictionary(forKey: key) as? [String: [String: Bool]] ?? [:]
        let day = checksByDate[dateKey] ?? [:]
        let items = snapshot.items.map { item in
            CheckWidgetItemSnapshot(title: item.title, done: day[item.title] ?? false, tag: item.tag)
        }
        return CheckWidgetSnapshot(dateKey: dateKey, updatedAt: updatedAt, items: items)
    }

    private static func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

@available(iOS 17.0, *)
struct ToggleCheckWidgetItemIntent: AppIntent {
    static var title: LocalizedStringResource = "切换打卡状态"
    static var description = IntentDescription("在桌面小组件里完成或撤销一条今日打卡。")

    @Parameter(title: "打卡项")
    var title: String

    @Parameter(title: "日期")
    var dateKey: String

    init() {
        title = ""
        dateKey = ""
    }

    init(title: String, dateKey: String) {
        self.title = title
        self.dateKey = dateKey
    }

    func perform() async throws -> some IntentResult {
        CheckWidgetSnapshotStore.toggleItem(title: title, dateKey: dateKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "CheckWidget")
        return .result()
    }
}

extension JSONEncoder {
    static var widgetSnapshotEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }
}

extension JSONDecoder {
    static var widgetSnapshotDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
