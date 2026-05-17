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
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return CheckWidgetSnapshot(dateKey: formatter.string(from: Date()), updatedAt: Date(), items: [])
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

    static func load(defaults: UserDefaults = sharedDefaults) -> CheckWidgetSnapshot {
        guard let data = defaults.data(forKey: CheckWidgetSnapshot.storageKey),
              let snapshot = try? JSONDecoder.widgetSnapshotDecoder.decode(CheckWidgetSnapshot.self, from: data) else {
            return .emptyToday
        }
        return snapshot
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
    static func toggleItem(title: String, dateKey requestedDateKey: String?, defaults: UserDefaults = sharedDefaults) -> CheckWidgetSnapshot {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = load(defaults: defaults)
        guard !cleanTitle.isEmpty else { return snapshot }

        let targetDateKey = requestedDateKey?.isEmpty == false ? requestedDateKey! : snapshot.dateKey
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
