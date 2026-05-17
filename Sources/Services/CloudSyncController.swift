import CloudKit
import Foundation

/// CloudKit 同步引擎的数据来源。由 AppStore 实现。
protocol CloudSyncDataSource: AnyObject {
    /// 当前本机全部需同步的记录。
    func allCloudSyncRecords() -> [SyncRecord]
    /// 把云端拉取到的变更应用回本地。
    func applyCloudChanges(updated: [SyncRecord], deletedRecordNames: [String])
}

/// 基于 `CKSyncEngine` 的 CloudKit 同步控制器。
///
/// 上行：本地变更推送到 private database。
/// 下行：云端变更应用回本地。退役旧 KVS 留到后续阶段。
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

    /// 用同步缓存里的记录恢复本地（无需联网）。
    /// 用于「本地数据丢失、但同步引擎状态仍以为已同步」时自愈——调用方需确认本地确实为空，
    /// 因为这会把缓存内容覆盖上去。
    func restoreFromCacheIfAvailable() {
        guard !syncedCache.isEmpty else { return }
        dataSource?.applyCloudChanges(updated: Array(syncedCache.values), deletedRecordNames: [])
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
        // 安全阀：本地内容记录为 0（只剩配置）却要删掉云端一批记录，几乎一定是
        // 本地数据没加载好的故障态，绝不能据此把云端删空。
        let deletions = syncedCache.keys.filter { !currentNames.contains($0) }
        let localContentCount = current.filter { $0.type != .dailyConfig }.count
        if localContentCount > 0 || deletions.isEmpty {
            for name in deletions {
                pending.append(.deleteRecord(makeRecordID(name)))
            }
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
        case .fetchedRecordZoneChanges(let event):
            var updated: [SyncRecord] = []
            for modification in event.modifications {
                guard let record = CloudKitRecordMapper.syncRecord(from: modification.record) else { continue }
                syncedCache[record.recordName] = record
                updated.append(record)
            }
            var deletedNames: [String] = []
            for deletion in event.deletions {
                let name = deletion.recordID.recordName
                syncedCache.removeValue(forKey: name)
                deletedNames.append(name)
            }
            guard !updated.isEmpty || !deletedNames.isEmpty else { break }
            saveCache()
            dataSource?.applyCloudChanges(updated: updated, deletedRecordNames: deletedNames)
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
