import CloudKit
import Foundation

/// CloudKit 同步引擎的数据来源。由 AppStore 实现。
protocol CloudSyncDataSource: AnyObject {
    /// 当前本机全部需同步的记录。
    func allCloudSyncRecords() -> [SyncRecord]
}

/// 基于 `CKSyncEngine` 的 CloudKit 同步控制器。
///
/// 阶段 1（本 PR）：只做上行——把本地变更推送到 private database。
/// 下行（应用云端变更回本地）与退役旧 KVS 留到后续阶段。
final class CloudSyncController {
    private let container: CKContainer
    private weak var dataSource: CloudSyncDataSource?
    private var engine: CKSyncEngine?

    /// 已同步到服务器的记录快照（recordName → SyncRecord），用于增量 diff。
    private var syncedCache: [String: SyncRecord]
    private let stateURL: URL
    private let cacheURL: URL
    private var didEnqueueZone = false

    init(dataSource: CloudSyncDataSource) {
        container = CKContainer(identifier: CloudKitSchema.containerID)
        self.dataSource = dataSource
        let dir = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        stateURL = dir.appendingPathComponent("cloudkit-sync-state.json")
        cacheURL = dir.appendingPathComponent("cloudkit-sync-cache.json")
        syncedCache = Self.loadCache(from: cacheURL)
    }

    var isRunning: Bool { engine != nil }

    func start() {
        guard engine == nil else { return }
        var state: CKSyncEngine.State.Serialization?
        if let data = try? Data(contentsOf: stateURL) {
            state = try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
        }
        let config = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: state,
            delegate: self
        )
        engine = CKSyncEngine(config)
    }

    func stop() {
        engine = nil
    }

    /// 本地数据变更后调用：算出与云端的差异，排进上传队列。
    func pushLocalChanges() {
        guard let engine, let dataSource else { return }
        let current = dataSource.allCloudSyncRecords()
        let currentNames = Set(current.map(\.recordName))
        var pending: [CKSyncEngine.PendingRecordZoneChange] = []
        for record in current where syncedCache[record.recordName] != record {
            pending.append(.saveRecord(makeRecordID(record.recordName)))
        }
        for name in syncedCache.keys where !currentNames.contains(name) {
            pending.append(.deleteRecord(makeRecordID(name)))
        }
        guard !pending.isEmpty else { return }
        if !didEnqueueZone {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudKitSchema.zoneID))])
            didEnqueueZone = true
        }
        engine.state.add(pendingRecordZoneChanges: pending)
    }

    // MARK: - Helpers

    private func makeRecordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: CloudKitSchema.zoneID)
    }

    private func currentRecordsByName() -> [String: SyncRecord] {
        let records = dataSource?.allCloudSyncRecords() ?? []
        return Dictionary(records.map { ($0.recordName, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func saveCache() {
        if let data = try? JSONEncoder().encode(syncedCache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    private static func loadCache(from url: URL) -> [String: SyncRecord] {
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode([String: SyncRecord].self, from: data) else {
            return [:]
        }
        return cache
    }
}

extension CloudSyncController: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let event):
            if let data = try? JSONEncoder().encode(event.stateSerialization) {
                try? data.write(to: stateURL, options: .atomic)
            }
        case .sentRecordZoneChanges(let event):
            let byName = currentRecordsByName()
            for saved in event.savedRecords {
                if let record = byName[saved.recordID.recordName] {
                    syncedCache[saved.recordID.recordName] = record
                }
            }
            for deleted in event.deletedRecordIDs {
                syncedCache.removeValue(forKey: deleted.recordName)
            }
            saveCache()
        case .fetchedRecordZoneChanges:
            break // 阶段 1：暂不应用下行变更，只上传。
        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        let byName = currentRecordsByName()
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            guard let record = byName[recordID.recordName] else { return nil }
            return CloudKitRecordMapper.makeCKRecord(record, zoneID: CloudKitSchema.zoneID)
        }
    }
}
