import Foundation

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
    static func save(_ snapshot: CheckWidgetSnapshot) {
        guard let data = try? JSONEncoder.widgetSnapshotEncoder.encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: CheckWidgetSnapshot.storageKey)
    }

    static func load() -> CheckWidgetSnapshot {
        guard let data = UserDefaults.standard.data(forKey: CheckWidgetSnapshot.storageKey),
              let snapshot = try? JSONDecoder.widgetSnapshotDecoder.decode(CheckWidgetSnapshot.self, from: data) else {
            return .emptyToday
        }
        return snapshot
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
