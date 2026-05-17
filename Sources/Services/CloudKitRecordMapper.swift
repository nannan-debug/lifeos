import CloudKit
import Foundation

/// 一条待同步记录的、与 CloudKit 解耦的中间表示。
struct SyncRecord: Codable, Equatable {
    let type: CloudKitSchema.RecordType
    let recordName: String
    let payload: Data
}

/// 本地数据（UserDefaults 表示）与 CloudKit 记录之间的双向转换。
///
/// 除第二大脑卡片用 JSON（`BrainCard` 是 Codable）外，其余 payload 都用二进制 plist 编码：
/// 与具体字段无关，可无损还原任意 UserDefaults 值，模型加字段也不需要改这里。
enum CloudKitRecordMapper {

    // MARK: - 本地数据 → SyncRecord

    static func encode(
        checksByDate: [String: [String: Bool]],
        timeByDate: [String: [[String: String]]],
        tasks: [[String: Any]],
        turns: [[String: Any]],
        brainData: Data?,
        dailyFields: String?,
        dailyInitialized: Bool,
        dailyGroups: String?
    ) -> [SyncRecord] {
        var records: [SyncRecord] = []

        for (date, checks) in checksByDate where !checks.isEmpty {
            if let payload = plist(["date": date, "checks": checks]) {
                records.append(SyncRecord(type: .checkDay, recordName: date, payload: payload))
            }
        }

        for (date, entries) in timeByDate {
            for entry in entries {
                guard let id = entry["id"], !id.isEmpty,
                      let payload = plist(["date": date, "entry": entry]) else { continue }
                records.append(SyncRecord(type: .timeEntry, recordName: id, payload: payload))
            }
        }

        for task in tasks {
            guard let id = task["id"] as? String, !id.isEmpty,
                  let payload = plist(task) else { continue }
            records.append(SyncRecord(type: .task, recordName: id, payload: payload))
        }

        for turn in turns {
            guard let id = turn["id"] as? String, !id.isEmpty,
                  let payload = plist(turn) else { continue }
            records.append(SyncRecord(type: .turn, recordName: id, payload: payload))
        }

        for card in decodeBrain(brainData) {
            if let payload = try? JSONEncoder().encode(card) {
                records.append(SyncRecord(type: .brainCard, recordName: card.id.uuidString, payload: payload))
            }
        }

        let config: [String: Any] = [
            "fields": dailyFields ?? "",
            "initialized": dailyInitialized,
            "groups": dailyGroups ?? ""
        ]
        if let payload = plist(config) {
            records.append(SyncRecord(type: .dailyConfig,
                                      recordName: CloudKitSchema.dailyConfigRecordName,
                                      payload: payload))
        }

        return records
    }

    // MARK: - SyncRecord → 本地数据

    /// 还原成按基础键名（不含 userId 后缀）索引的 UserDefaults 值，可直接写回本地。
    static func decode(_ records: [SyncRecord]) -> [String: Any] {
        var checksByDate: [String: [String: Bool]] = [:]
        var timeByDate: [String: [[String: String]]] = [:]
        var tasks: [[String: Any]] = []
        var turns: [[String: Any]] = []
        var brain: [BrainCard] = []
        var dailyFields = ""
        var dailyInitialized = false
        var dailyGroups = ""

        for record in records {
            switch record.type {
            case .checkDay:
                guard let obj = fromPlist(record.payload),
                      let date = obj["date"] as? String,
                      let checks = obj["checks"] as? [String: Bool] else { continue }
                checksByDate[date] = checks
            case .timeEntry:
                guard let obj = fromPlist(record.payload),
                      let date = obj["date"] as? String,
                      let entry = obj["entry"] as? [String: String] else { continue }
                timeByDate[date, default: []].append(entry)
            case .task:
                if let obj = fromPlist(record.payload) { tasks.append(obj) }
            case .turn:
                if let obj = fromPlist(record.payload) { turns.append(obj) }
            case .brainCard:
                if let card = try? JSONDecoder().decode(BrainCard.self, from: record.payload) {
                    brain.append(card)
                }
            case .dailyConfig:
                guard let obj = fromPlist(record.payload) else { continue }
                dailyFields = obj["fields"] as? String ?? ""
                dailyInitialized = obj["initialized"] as? Bool ?? false
                dailyGroups = obj["groups"] as? String ?? ""
            }
        }

        // CloudKit 记录无固有顺序，按稳定键排序保证可重现。
        for (date, entries) in timeByDate {
            timeByDate[date] = entries.sorted {
                ($0["start"] ?? "", $0["id"] ?? "") < ($1["start"] ?? "", $1["id"] ?? "")
            }
        }
        tasks.sort { ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") }
        turns.sort { ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") }
        brain.sort { $0.createdAt < $1.createdAt }

        var result: [String: Any] = [
            "ps.checks.byDate": checksByDate,
            "ps.time.byDate": timeByDate,
            "ps.tasks": tasks,
            "ps.turns": turns,
            "fields.daily": dailyFields,
            "fields.daily.initialized": dailyInitialized,
            "fields.daily.groups": dailyGroups
        ]
        if let brainData = try? JSONEncoder().encode(brain) {
            result["ps.brain"] = brainData
        }
        return result
    }

    // MARK: - SyncRecord ↔ CKRecord

    static func makeCKRecord(_ syncRecord: SyncRecord, zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: syncRecord.recordName, zoneID: zoneID)
        let record = CKRecord(recordType: syncRecord.type.rawValue, recordID: recordID)
        record[CloudKitSchema.payloadField] = syncRecord.payload as CKRecordValue
        return record
    }

    static func syncRecord(from record: CKRecord) -> SyncRecord? {
        guard let type = CloudKitSchema.RecordType(rawValue: record.recordType),
              let payload = record[CloudKitSchema.payloadField] as? Data else {
            return nil
        }
        return SyncRecord(type: type, recordName: record.recordID.recordName, payload: payload)
    }

    // MARK: - Helpers

    private static func plist(_ object: Any) -> Data? {
        try? PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
    }

    private static func fromPlist(_ data: Data) -> [String: Any]? {
        (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }

    private static func decodeBrain(_ data: Data?) -> [BrainCard] {
        guard let data, !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([BrainCard].self, from: data)) ?? []
    }
}
