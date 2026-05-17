import Foundation
import WidgetKit

struct PendingClarification {
    let originalText: String
    let hint: String
}

struct ReviewCheckHabitSummary: Equatable {
    let title: String
    let completedDays: Int
    let blankDays: Int
}

struct ReviewCheckDaySummary: Equatable {
    let date: Date
    let completedCount: Int
    let totalCount: Int
}

struct ReviewCheckGroupSummary: Equatable {
    struct Day: Equatable {
        let date: Date
        let completedCount: Int
        let totalCount: Int
        var isFullyChecked: Bool { totalCount > 0 && completedCount == totalCount }
    }

    let title: String
    let days: [Day]
}

struct ReviewTimeCategorySummary: Equatable {
    let category: String
    let minutes: Int
}

final class AppStore: ObservableObject, CloudSyncDataSource {
    private struct TimeCommitResult {
        let id: UUID?
        let dateKey: String?
    }

    private static let dateKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let healthKitDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let taskDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    @Published var selectedDate = Date() { didSet { loadForSelectedDate() } }
    @Published var checkItems: [DailyCheckItem] = []
    @Published var timeEntries: [TimeEntry] = []
    @Published var tasks: [TaskEntry] = []
    @Published var turns: [ConversationTurn] = []
    @Published var brainCards: [BrainCard] = []
    @Published var aiFailureLogs: [AIFailureLog] = []
    @Published var aiDebugLogs: [AIDebugLog] = []

    // MARK: - AI dispatch state (全局输入框用)
    @Published var isAILoading: Bool = false
    @Published var aiDebugMessage: String? = nil

    // TodayView 当前 segment（"check" / "todo"），供 RootTabView 控制 AI 输入框可见性
    @Published var todaySegment: String = "check"
    @Published var isICloudSyncEnabled: Bool
    @Published var iCloudSyncStatusText: String
    @Published var isHealthSleepSyncEnabled: Bool
    @Published var isHealthWorkoutSyncEnabled: Bool
    @Published var isWakeDreamReminderEnabled: Bool
    @Published var healthSyncStatusText: String
    @Published var healthSyncCompletionMessage: String? = nil

    /// 上一轮 AI 追问的上下文：当 AI 返回 needsClarification 时，暂存原文与 hint。
    /// 用户下次提交时自动把两段拼起来发给 AI，避免"9 点到 10 点"这种裸时间丢失上下文。
    @Published var pendingClarification: PendingClarification? = nil

    private let defaults = UserDefaults.standard
    private let authUserIdKey = "auth.userId"
    private let iCloudSyncEnabledKey = "icloud.sync.enabled"
    private let cloudKitMigratedKey = "cloudkit.migrated.v1"
    private lazy var cloudSync = CloudSyncController(dataSource: self)
    private let healthSleepSyncEnabledKey = "healthkit.sync.sleep.enabled"
    private let healthWorkoutSyncEnabledKey = "healthkit.sync.workout.enabled"

    private let scopedDataKeyBases = [
        "ps.checks.byDate",
        "ps.time.byDate",
        "ps.tasks",
        "ps.turns",
        "ps.brain",
        "ps.ai.failures",
        "fields.daily",
        "fields.daily.initialized",
        "fields.daily.groups",
        "ps.inbox"
    ]

    /// 当前设备的本地稳定 ID。对用户不可见，仅用于继续兼容既有本机分库。
    private var currentUserId: String? {
        let raw = defaults.string(forKey: authUserIdKey) ?? ""
        return raw.isEmpty ? nil : raw
    }

    private func scopedKey(_ base: String) -> String {
        guard let uid = currentUserId else { return base }
        return "\(base).\(uid)"
    }

    private var keyChecks: String { scopedKey("ps.checks.byDate") }
    private var keyTime: String { scopedKey("ps.time.byDate") }
    private var keyTasks: String { scopedKey("ps.tasks") }
    private var keyTurns: String { scopedKey("ps.turns") }
    private var keyBrain: String { scopedKey("ps.brain") }
    private var keyAIFailures: String { scopedKey("ps.ai.failures") }
    private var keyAIDebugLogs: String { scopedKey("ps.ai.debug.logs") }
    private var keyDailyFields: String { scopedKey("fields.daily") }
    private var keyDailyInitialized: String { scopedKey("fields.daily.initialized") }
    private var keyDailyGroups: String { scopedKey("fields.daily.groups") }

    // 兼容旧版本（未按用户隔离）
    private let legacyKeyDailyFields = "fields.daily"
    private let legacyKeyDailyInitialized = "fields.daily.initialized"

    // 全新用户首次启动时预置的打卡项（按顺序展示，分到「早上 / 晚上」两组）。
    // 老用户（已 initialized）不会被覆盖。
    private let fallbackCheckEntries: [(title: String, tag: String)] = [
        ("吃维生素", "早上"),
        ("回忆梦境", "早上"),
        ("洗漱", "早上"),
        ("出门", "早上"),
        ("写日记", "晚上"),
        ("洗澡", "晚上"),
        ("上床看书", "晚上"),
    ]

    init() {
        if defaults.object(forKey: iCloudSyncEnabledKey) == nil {
            // 新安装默认开启 iCloud 同步；已有用户的显式选择不覆盖。
            defaults.set(true, forKey: iCloudSyncEnabledKey)
        }
        let syncEnabled = defaults.bool(forKey: iCloudSyncEnabledKey)
        isICloudSyncEnabled = syncEnabled
        iCloudSyncStatusText = Self.defaultICloudSyncStatus(isEnabled: syncEnabled)
        let sleepSyncEnabled = defaults.bool(forKey: healthSleepSyncEnabledKey)
        let workoutSyncEnabled = defaults.bool(forKey: healthWorkoutSyncEnabledKey)
        let wakeDreamReminderEnabled = sleepSyncEnabled && defaults.bool(forKey: WakeDreamReminderService.enabledKey)
        isHealthSleepSyncEnabled = sleepSyncEnabled
        isHealthWorkoutSyncEnabled = workoutSyncEnabled
        isWakeDreamReminderEnabled = wakeDreamReminderEnabled
        if !wakeDreamReminderEnabled {
            WakeDreamReminderService.setEnabled(false)
        }
        healthSyncStatusText = Self.defaultHealthSyncStatus(sleepEnabled: sleepSyncEnabled, workoutEnabled: workoutSyncEnabled)
        cleanupLegacyInboxIfNeeded()
        loadTasks()
        loadTurns()
        loadBrain()
        loadAIFailureLogs()
        loadAIDebugLogs()
        loadForSelectedDate()
        publishCheckWidgetSnapshot()
        if isICloudSyncEnabled {
            cloudSync.start()
            // 本地无数据但同步缓存有记录：用缓存自愈，覆盖「本地丢了、引擎却以为已同步」的错位。
            if !hasMeaningfulLocalData() {
                cloudSync.restoreFromCacheIfAvailable()
            }
            migrateToCloudKitIfNeeded()
        }
        if sleepSyncEnabled || workoutSyncEnabled {
            syncHealthKitNow()
        }
    }

    var currentAuthUserId: String {
        defaults.string(forKey: authUserIdKey) ?? ""
    }

    func ensureLocalIdentity() {
        guard currentAuthUserId.isEmpty else { return }
        let uid = makeAnonymousUserId()
        defaults.set(uid, forKey: authUserIdKey)
        migrateLegacyGlobalData(to: uid)
        reloadForCurrentUser()
    }

    func setICloudSyncEnabled(_ enabled: Bool) {
        isICloudSyncEnabled = enabled
        defaults.set(enabled, forKey: iCloudSyncEnabledKey)
        guard enabled else {
            cloudSync.stop()
            iCloudSyncStatusText = "已关闭。数据只保存在本机。"
            return
        }

        cloudSync.start()
        // 本机为空但同步缓存有记录：用缓存自愈。
        if !hasMeaningfulLocalData() {
            cloudSync.restoreFromCacheIfAvailable()
        }
        migrateToCloudKitIfNeeded()
        iCloudSyncStatusText = isICloudAccountAvailable
            ? "已开启。会在同一 Apple ID 的设备间同步。"
            : "已开启。请先在系统里登录 iCloud。"
    }

    func setHealthSleepSyncEnabled(_ enabled: Bool) {
        isHealthSleepSyncEnabled = enabled
        defaults.set(enabled, forKey: healthSleepSyncEnabledKey)
        if !enabled {
            setWakeDreamReminderEnabled(false)
        }
        syncHealthKitNow()
    }

    func setHealthWorkoutSyncEnabled(_ enabled: Bool) {
        isHealthWorkoutSyncEnabled = enabled
        defaults.set(enabled, forKey: healthWorkoutSyncEnabledKey)
        syncHealthKitNow()
    }

    func setWakeDreamReminderEnabled(_ enabled: Bool) {
        guard isHealthSleepSyncEnabled || !enabled else {
            isWakeDreamReminderEnabled = false
            WakeDreamReminderService.setEnabled(false)
            return
        }
        isWakeDreamReminderEnabled = enabled
        WakeDreamReminderService.setEnabled(enabled)
        if enabled {
            syncHealthKitNow()
        }
    }

    func syncHealthKitNow(showCompletionAlert: Bool = false) {
        let readSleep = isHealthSleepSyncEnabled
        let readWorkouts = isHealthWorkoutSyncEnabled
        guard readSleep || readWorkouts else {
            healthSyncStatusText = Self.defaultHealthSyncStatus(sleepEnabled: false, workoutEnabled: false)
            if showCompletionAlert {
                healthSyncCompletionMessage = "请先开启睡眠或运动同步。"
            }
            return
        }

        healthSyncStatusText = "正在从 Apple 健康同步..."
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: endDate) ?? endDate

        Task {
            do {
                try await HealthKitSyncService.shared.requestAuthorization(readSleep: readSleep, readWorkouts: readWorkouts)
                let blocks = try await HealthKitSyncService.shared.fetchTimeBlocks(readSleep: readSleep, readWorkouts: readWorkouts, since: startDate, until: endDate)
                if readSleep {
                    _ = await WakeDreamReminderService.scheduleIfNeeded(from: blocks)
                }
                await MainActor.run {
                    let imported = self.importHealthKitTimeBlocks(blocks, replacingSleepSince: readSleep ? startDate : nil, until: endDate)
                    if imported > 0 {
                        self.healthSyncStatusText = "已同步 \(imported) 条睡眠/运动记录。"
                    } else {
                        self.healthSyncStatusText = "已检查 Apple 健康，没有新的记录。"
                    }
                    if showCompletionAlert {
                        self.healthSyncCompletionMessage = self.healthSyncStatusText
                    }
                }
            } catch {
                await MainActor.run {
                    self.healthSyncStatusText = error.localizedDescription
                    self.isHealthSleepSyncEnabled = false
                    self.isHealthWorkoutSyncEnabled = false
                    self.defaults.set(false, forKey: self.healthSleepSyncEnabledKey)
                    self.defaults.set(false, forKey: self.healthWorkoutSyncEnabledKey)
                    if showCompletionAlert {
                        self.healthSyncCompletionMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    /// 切换本地数据空间后调用，按当前 userId 重新装载所有数据。
    func reloadForCurrentUser() {
        cleanupLegacyInboxIfNeeded()
        loadTasks()
        loadTurns()
        loadBrain()
        loadAIFailureLogs()
        loadAIDebugLogs()
        loadForSelectedDate()
        publishCheckWidgetSnapshot()
    }

    /// 清空当前用户的所有数据（用于注销账户）。不影响其他用户。
    func wipeCurrentUserData() {
        [keyChecks, keyTime, keyTasks, keyTurns, keyBrain, keyAIFailures, keyAIDebugLogs, keyDailyFields, keyDailyInitialized, keyDailyGroups].forEach { defaults.removeObject(forKey: $0) }
        // 旧版本随手记镜像（已废弃）一并兜底清掉
        defaults.removeObject(forKey: scopedKey("ps.inbox"))
        checkItems = []
        timeEntries = []
        tasks = []
        turns = []
        brainCards = []
        aiFailureLogs = []
        aiDebugLogs = []
        publishCheckWidgetSnapshot()
        syncICloudAfterLocalChange()
    }

    private func makeAnonymousUserId() -> String {
        "dev-" + UUID().uuidString
    }

    private func scopedKey(_ base: String, userId: String) -> String {
        "\(base).\(userId)"
    }

    private func migrateLegacyGlobalData(to userId: String) {
        for base in scopedDataKeyBases {
            let targetKey = scopedKey(base, userId: userId)
            guard defaults.object(forKey: targetKey) == nil, let value = defaults.object(forKey: base) else { continue }
            defaults.set(value, forKey: targetKey)
        }
    }

    private static func defaultICloudSyncStatus(isEnabled: Bool) -> String {
        isEnabled ? "开启中。会在同一 Apple ID 的设备间同步。" : "关闭。数据只保存在本机。"
    }

    private static func defaultHealthSyncStatus(sleepEnabled: Bool, workoutEnabled: Bool) -> String {
        switch (sleepEnabled, workoutEnabled) {
        case (true, true):
            return "已开启睡眠和运动同步。"
        case (true, false):
            return "已开启睡眠同步。"
        case (false, true):
            return "已开启运动同步。"
        case (false, false):
            return "关闭时不会读取 Apple 健康。"
        }
    }

    private var isICloudAccountAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// 本地数据变更后调用：把变更同步到 CloudKit。
    private func syncICloudAfterLocalChange() {
        guard isICloudSyncEnabled else { return }
        cloudSync.pushLocalChanges()
    }

    // MARK: - CloudKit 同步

    func allCloudSyncRecords() -> [SyncRecord] {
        let checks = defaults.dictionary(forKey: keyChecks) as? [String: [String: Bool]] ?? [:]
        let time = defaults.dictionary(forKey: keyTime) as? [String: [[String: String]]] ?? [:]
        let tasks = defaults.array(forKey: keyTasks) as? [[String: Any]] ?? []
        let turns = defaults.array(forKey: keyTurns) as? [[String: Any]] ?? []
        return CloudKitRecordMapper.encode(
            checksByDate: checks,
            timeByDate: time,
            tasks: tasks,
            turns: turns,
            brainData: defaults.data(forKey: keyBrain),
            dailyFields: defaults.string(forKey: keyDailyFields),
            dailyInitialized: defaults.bool(forKey: keyDailyInitialized),
            dailyGroups: defaults.string(forKey: keyDailyGroups)
        )
    }

    /// 把云端拉取到的变更应用回本地。只覆盖涉及的记录，不动其它本地数据。
    func applyCloudChanges(updated: [SyncRecord], deletedRecordNames: [String]) {
        guard !updated.isEmpty || !deletedRecordNames.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let merged = CloudKitRecordMapper.merge(
                base: self.allCloudSyncRecords(),
                updated: updated,
                deletedRecordNames: deletedRecordNames
            )
            let localData = CloudKitRecordMapper.decode(merged)
            for (base, value) in localData {
                self.defaults.set(value, forKey: self.scopedKey(base))
            }
            // 必须先把恢复后的打卡同步进小组件 App Group：否则下面 reloadForCurrentUser
            // → loadChecksForDate → mergeCheckWidgetStateIfNeeded 会用重装后为空的
            // 小组件状态，把刚从云端恢复的打卡又覆盖掉。
            self.publishCheckWidgetSnapshot()
            self.reloadForCurrentUser()
        }
    }

    /// 首次迁移到 CloudKit：迁移前自动写一份本地备份，再把现有数据推上云。一次性。
    private func migrateToCloudKitIfNeeded() {
        guard !defaults.bool(forKey: cloudKitMigratedKey) else { return }
        if hasMeaningfulLocalData() {
            writeAutomaticBackup()
        }
        cloudSync.pushLocalChanges()
        defaults.set(true, forKey: cloudKitMigratedKey)
    }

    /// 把当前完整数据写一份 JSON 备份到 App 沙盒，作为迁移前的安全网。
    @discardableResult
    private func writeAutomaticBackup() -> URL? {
        guard let data = makeFullDataArchive() else { return nil }
        let dir = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("pre-cloudkit-backup.json")
        try? data.write(to: url, options: .atomic)
        return url
    }

    private func hasMeaningfulLocalData() -> Bool {
        if let checks = defaults.dictionary(forKey: keyChecks), !checks.isEmpty { return true }
        if let time = defaults.dictionary(forKey: keyTime), !time.isEmpty { return true }
        if let tasks = defaults.array(forKey: keyTasks), !tasks.isEmpty { return true }
        if let turns = defaults.array(forKey: keyTurns), !turns.isEmpty { return true }
        if let brain = defaults.data(forKey: keyBrain), !brain.isEmpty { return true }
        return false
    }

    /// 把旧版本镜像写入 `ps.inbox.<userId>` 的 InboxNote 数据一次性清掉。
    /// 旧版本里每条 AI 输入都会同时写一份 turn + 一份 InboxNote 镜像，但 InboxView
    /// 已经下线，那份镜像没人读。直接 removeObject 即可，turn 才是真数据。
    private func cleanupLegacyInboxIfNeeded() {
        let flagKey = scopedKey("ps.cleanup.legacy_inbox.v1")
        guard !defaults.bool(forKey: flagKey) else { return }
        defaults.removeObject(forKey: scopedKey("ps.inbox"))
        defaults.set(true, forKey: flagKey)
    }

    // MARK: - Date key
    var selectedDateKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: selectedDate)
    }

    // MARK: - Checks
    func toggle(_ item: DailyCheckItem) {
        guard let idx = checkItems.firstIndex(where: { $0.id == item.id }) else { return }
        checkItems[idx].done.toggle()
        saveChecksForDate()
    }

    var doneCount: Int { checkItems.filter { $0.done }.count }

    // MARK: - Time entries
    func addTimeEntry(name: String, start: String, end: String, category: String, extra: [String: String] = [:]) -> String? {
        if let err = validateTimeInput(name: name, start: start, end: end) { return err }
        timeEntries.insert(.init(name: name, start: start, end: end, category: category, extra: extra), at: 0)
        saveTimeForDate()
        return nil
    }

    func updateTimeEntry(id: UUID, name: String, start: String, end: String, category: String, extra: [String: String] = [:]) -> String? {
        if let err = validateTimeInput(name: name, start: start, end: end) { return err }
        guard let idx = timeEntries.firstIndex(where: { $0.id == id }) else { return "记录不存在" }
        timeEntries[idx].name = name
        timeEntries[idx].start = start
        timeEntries[idx].end = end
        timeEntries[idx].category = category
        timeEntries[idx].extra = extra
        saveTimeForDate()
        return nil
    }

    func removeTimeEntry(at offsets: IndexSet) {
        let targets = offsets.compactMap { index in
            timeEntries.indices.contains(index) ? timeEntries[index] : nil
        }
        for target in targets {
            removeTimeEntryByID(target.id, dateKey: selectedDateKey)
        }
        loadTimeForDate()
    }

    func addTimeEntryFromDial(name: String, startMinutes: Int, endMinutes: Int, category: String, extra: [String: String] = [:]) -> String? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanName.isEmpty { return "事件名称不能为空" }
        if startMinutes == endMinutes { return "结束时间必须晚于开始时间" }

        if endMinutes > startMinutes {
            return addTimeEntry(
                name: cleanName,
                start: Self.clockText(from: startMinutes),
                end: Self.clockText(from: endMinutes),
                category: category,
                extra: extra
            )
        }

        if let err = addCrossDayTimeEntry(
            name: cleanName,
            startMinutes: startMinutes,
            endMinutes: endMinutes,
            category: category,
            extra: extra,
            startDateKey: selectedDateKey
        ) {
            return err
        }
        loadTimeForDate()
        syncICloudAfterLocalChange()
        return nil
    }

    func updateTimeEntryFromDial(id: UUID, name: String, startMinutes: Int, endMinutes: Int, category: String, extra: [String: String] = [:]) -> String? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanName.isEmpty { return "事件名称不能为空" }
        if startMinutes == endMinutes { return "结束时间必须晚于开始时间" }
        guard let existing = timeEntries.first(where: { $0.id == id }) else { return "记录不存在" }

        let startDateKey = existing.extra[TimeEntryCrossDayKey.startDateKey] ?? selectedDateKey
        removeTimeEntryByID(id, dateKey: selectedDateKey)

        if endMinutes > startMinutes {
            insertTimeEntry(
                .init(name: cleanName, start: Self.clockText(from: startMinutes), end: Self.clockText(from: endMinutes), category: category, extra: extra),
                dateKey: startDateKey
            )
        } else {
            if let err = addCrossDayTimeEntry(
                name: cleanName,
                startMinutes: startMinutes,
                endMinutes: endMinutes,
                category: category,
                extra: extra,
                startDateKey: startDateKey
            ) {
                return err
            }
        }

        loadTimeForDate()
        syncICloudAfterLocalChange()
        return nil
    }

    private func importHealthKitTimeBlocks(_ blocks: [HealthKitTimeBlock], replacingSleepSince sleepStartDate: Date?, until endDate: Date) -> Int {
        let hasSleepBlocks = blocks.contains { $0.extra[HealthKitTimeEntryKey.kind] == HealthKitTimeEntryKey.kindSleep }
        if let sleepStartDate, hasSleepBlocks {
            let exclusiveEnd = Calendar.current.date(byAdding: .day, value: 1, to: endDate) ?? endDate
            removeHealthKitTimeEntries(kind: HealthKitTimeEntryKey.kindSleep, in: Set(dateKeys(start: sleepStartDate, end: exclusiveEnd)))
        }
        var existingSourceIDs = existingHealthKitSourceIDs()
        var imported = 0

        for block in blocks {
            guard !existingSourceIDs.contains(block.sourceIdentifier),
                  insertHealthKitTimeBlock(block) else { continue }
            existingSourceIDs.insert(block.sourceIdentifier)
            imported += 1
        }

        if imported > 0 {
            loadTimeForDate()
            syncICloudAfterLocalChange()
        }
        return imported
    }

    private func existingHealthKitSourceIDs() -> Set<String> {
        let map = defaults.dictionary(forKey: keyTime) as? [String: [[String: String]]] ?? [:]
        var ids = Set<String>()
        for rows in map.values {
            for row in rows {
                let extra = decodeExtra(row["extra"])
                if extra[HealthKitTimeEntryKey.source] == HealthKitTimeEntryKey.sourceValue,
                   let sourceID = extra[HealthKitTimeEntryKey.sourceID],
                   !sourceID.isEmpty {
                    ids.insert(sourceID)
                }
            }
        }
        return ids
    }

    private func removeHealthKitTimeEntries(kind: String, in dateKeys: Set<String>) {
        guard !dateKeys.isEmpty else { return }
        var map = defaults.dictionary(forKey: keyTime) as? [String: [[String: String]]] ?? [:]
        var didRemove = false

        for key in dateKeys {
            guard var rows = map[key] else { continue }
            let before = rows.count
            rows.removeAll { row in
                let extra = decodeExtra(row["extra"])
                return extra[HealthKitTimeEntryKey.source] == HealthKitTimeEntryKey.sourceValue
                    && extra[HealthKitTimeEntryKey.kind] == kind
            }
            if rows.count != before {
                map[key] = rows
                didRemove = true
            }
        }

        if didRemove {
            defaults.set(map, forKey: keyTime)
        }
    }

    private func insertHealthKitTimeBlock(_ block: HealthKitTimeBlock) -> Bool {
        guard block.endDate > block.startDate else { return false }

        var extra = block.extra
        extra[HealthKitTimeEntryKey.source] = HealthKitTimeEntryKey.sourceValue
        extra[HealthKitTimeEntryKey.sourceID] = block.sourceIdentifier
        extra["healthkitStartDate"] = Self.healthKitDateFormatter.string(from: block.startDate)
        extra["healthkitEndDate"] = Self.healthKitDateFormatter.string(from: block.endDate)

        let startDateKey = dateKey(for: block.startDate)
        if calendarDate(block.startDate, isSameDayAs: block.endDate) {
            insertTimeEntry(
                .init(
                    name: block.name,
                    start: Self.clockText(from: minutesSinceMidnight(block.startDate)),
                    end: Self.clockText(from: minutesSinceMidnight(block.endDate)),
                    category: block.category,
                    extra: extra
                ),
                dateKey: startDateKey
            )
            return true
        }

        if dateKeyByAddingDays(1, to: startDateKey) == dateKey(for: block.endDate),
           addCrossDayTimeEntry(
                name: block.name,
                startMinutes: minutesSinceMidnight(block.startDate),
                endMinutes: minutesSinceMidnight(block.endDate),
                category: block.category,
                extra: extra,
                startDateKey: startDateKey
           ) == nil {
            return true
        }

        return insertMultiDayHealthKitTimeBlock(block, extra: extra)
    }

    private func insertMultiDayHealthKitTimeBlock(_ block: HealthKitTimeBlock, extra: [String: String]) -> Bool {
        var cursor = block.startDate
        var segmentIndex = 0
        var inserted = false

        while cursor < block.endDate {
            let dayStart = Calendar.current.startOfDay(for: cursor)
            let nextDayStart = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? block.endDate
            let segmentEnd = min(nextDayStart, block.endDate)
            let startMinutes = minutesSinceMidnight(cursor)
            let endMinutes = Calendar.current.isDate(segmentEnd, inSameDayAs: cursor) ? minutesSinceMidnight(segmentEnd) : 24 * 60

            if endMinutes > startMinutes {
                var segmentExtra = extra
                segmentExtra["healthkitSegmentIndex"] = "\(segmentIndex)"
                insertTimeEntry(
                    .init(
                        name: block.name,
                        start: Self.clockText(from: startMinutes),
                        end: Self.clockText(from: endMinutes),
                        category: block.category,
                        extra: segmentExtra
                    ),
                    dateKey: dateKey(for: cursor)
                )
                inserted = true
            }

            segmentIndex += 1
            cursor = segmentEnd
        }
        return inserted
    }

    private func calendarDate(_ left: Date, isSameDayAs right: Date) -> Bool {
        Calendar.current.isDate(left, inSameDayAs: right)
    }

    private func minutesSinceMidnight(_ date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    // MARK: - Task entries
    @discardableResult
    func addTask(
        title: String,
        detail: String = "",
        status: String = "待办",
        priority: String = "",
        dueDate: String = "",
        date: String? = nil,
        completedAt: Date? = nil,
        isAllDay: Bool = true,
        startTime: String = "",
        endTime: String = "",
        location: String = "",
        sourceNoteId: UUID? = nil,
        sourceExcerpt: String = ""
    ) -> UUID? {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let task = TaskEntry(
            title: cleaned,
            detail: detail,
            status: status,
            priority: priority,
            dueDate: dueDate,
            date: date ?? selectedDateKey,
            completedAt: status == "已完成" ? (completedAt ?? Date()) : nil,
            isAllDay: isAllDay,
            startTime: startTime,
            endTime: endTime,
            location: location,
            sourceNoteId: sourceNoteId,
            sourceExcerpt: sourceExcerpt
        )
        tasks.insert(task, at: 0)
        saveTasks()
        return task.id
    }

    /// 更新任务的所有可编辑字段（编辑面板用）
    func updateTask(
        id: UUID,
        title: String,
        detail: String,
        priority: String,
        dueDate: String,
        isAllDay: Bool,
        startTime: String,
        endTime: String,
        location: String
    ) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        tasks[idx].title = clean
        tasks[idx].detail = detail
        tasks[idx].priority = priority
        tasks[idx].dueDate = dueDate
        tasks[idx].isAllDay = isAllDay
        tasks[idx].startTime = startTime
        tasks[idx].endTime = endTime
        tasks[idx].location = location
        saveTasks()
    }

    /// 切换任务完成状态：待办 ↔ 已完成
    func toggleTask(_ task: TaskEntry) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        if tasks[idx].status == "已完成" {
            tasks[idx].status = "待办"
            tasks[idx].completedAt = nil
        } else {
            tasks[idx].status = "已完成"
            tasks[idx].completedAt = Date()
        }
        saveTasks()
    }

    /// 删除指定 id 的任务
    func removeTask(id: UUID) {
        tasks.removeAll { $0.id == id }
        saveTasks()
    }

    @discardableResult
    func clearCompletedTasks(olderThan cutoff: Date?) -> Int {
        let beforeCount = tasks.count
        tasks.removeAll { task in
            guard task.status == "已完成" else { return false }
            guard let cutoff else { return true }
            return (task.completedAt ?? dateFromKey(task.date) ?? .distantPast) < cutoff
        }
        let removedCount = beforeCount - tasks.count
        if removedCount > 0 {
            saveTasks()
        }
        return removedCount
    }

    private func dateFromKey(_ key: String) -> Date? {
        Self.dateKeyFormatter.date(from: key)
    }

    func removeTimeEntry(id: UUID) {
        removeTimeEntryByID(id, dateKey: selectedDateKey)
    }

    // MARK: - Daily check-in item management
    /// 新增打卡项目（追加到 fields.daily 末尾，按 title 去重）
    /// tag 为空表示"未分组"，UI 上不会出现在分组 header 下，单独排在最后
    @discardableResult
    func addDailyCheckItem(_ title: String, tag: String = "") -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return false }
        var entries = currentCheckEntries()
        guard !entries.contains(where: { $0.title == cleanTitle }) else { return false }
        entries.append((title: cleanTitle, tag: cleanTag))
        defaults.set(encodeCheckEntries(entries), forKey: keyDailyFields)
        defaults.set(true, forKey: keyDailyInitialized)
        // 如果带了一个尚未注册的分组，顺手注册进 groups 列表
        if !cleanTag.isEmpty {
            var groups = savedGroups
            if !groups.contains(cleanTag) {
                groups.append(cleanTag)
                saveGroups(groups)
            }
        }
        reloadFieldConfig()
        publishCheckWidgetSnapshot()
        syncICloudAfterLocalChange()
        return true
    }

    /// 删除打卡项目
    func removeDailyCheckItem(_ title: String) {
        var entries = currentCheckEntries()
        entries.removeAll { $0.title == title }
        defaults.set(encodeCheckEntries(entries), forKey: keyDailyFields)
        defaults.set(true, forKey: keyDailyInitialized)
        reloadFieldConfig()
        publishCheckWidgetSnapshot()
        syncICloudAfterLocalChange()
    }

    /// 重命名打卡项。会同步迁移历史所有日期的勾选状态（按 title 落库），
    /// 这样中途改名不会导致今天/历史的"已完成"被清零。
    /// 重名（与已有打卡项冲突）或源不存在 → false。
    @discardableResult
    func renameDailyCheckItem(from oldTitle: String, to newTitle: String) -> Bool {
        let oldClean = oldTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let newClean = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oldClean.isEmpty, !newClean.isEmpty else { return false }
        guard oldClean != newClean else { return true }

        var entries = currentCheckEntries()
        guard let idx = entries.firstIndex(where: { $0.title == oldClean }) else { return false }
        guard !entries.contains(where: { $0.title == newClean }) else { return false }
        entries[idx] = (title: newClean, tag: entries[idx].tag)
        defaults.set(encodeCheckEntries(entries), forKey: keyDailyFields)
        defaults.set(true, forKey: keyDailyInitialized)

        // 迁移所有日期的勾选状态：oldTitle 的 done 值搬到 newTitle 名下
        var map = defaults.dictionary(forKey: keyChecks) as? [String: [String: Bool]] ?? [:]
        var changed = false
        for (date, var day) in map {
            if let done = day.removeValue(forKey: oldClean) {
                day[newClean] = done
                map[date] = day
                changed = true
            }
        }
        if changed {
            defaults.set(map, forKey: keyChecks)
        }

        reloadFieldConfig()
        publishCheckWidgetSnapshot()
        syncICloudAfterLocalChange()
        return true
    }

    /// 给外部 UI 列出所有打卡项标题
    var dailyCheckTitles: [String] { currentCheckEntries().map { $0.title } }

    /// 给外部 UI 列出所有打卡项（含 tag）
    var dailyCheckEntries: [(title: String, tag: String)] { currentCheckEntries() }

    /// 历史出现过的全部 tag，按首次出现顺序（不含空分组）
    var dailyCheckTags: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for e in currentCheckEntries() where !e.tag.isEmpty && !seen.contains(e.tag) {
            seen.insert(e.tag)
            ordered.append(e.tag)
        }
        return ordered
    }

    // MARK: - Daily check-in group management
    /// 用户显式管理过的分组顺序（独立于打卡项保存，允许空分组存在）
    private var savedGroups: [String] {
        let raw = defaults.string(forKey: keyDailyGroups) ?? ""
        return raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func saveGroups(_ groups: [String]) {
        defaults.set(groups.joined(separator: ","), forKey: keyDailyGroups)
        syncICloudAfterLocalChange()
    }

    /// 全部分组（手动建的 + 项目里出现过的，去重保序）。空字符串不算分组。
    var dailyCheckGroups: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for g in savedGroups where !g.isEmpty && seen.insert(g).inserted {
            ordered.append(g)
        }
        for e in currentCheckEntries() where !e.tag.isEmpty && seen.insert(e.tag).inserted {
            ordered.append(e.tag)
        }
        return ordered
    }

    /// 某分组下打卡项数量（用于删除确认弹窗）
    func dailyCheckItemCount(forGroup name: String) -> Int {
        currentCheckEntries().filter { $0.tag == name }.count
    }

    /// 新建一个空分组。重名返回 false。
    @discardableResult
    func addDailyCheckGroup(_ name: String) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        var groups = savedGroups
        // 跟"已有分组（含从 items 推出来的）"判重，否则新建跟现有 item tag 同名会变成同一组
        guard !dailyCheckGroups.contains(clean) else { return false }
        groups.append(clean)
        saveGroups(groups)
        reloadFieldConfig()
        publishCheckWidgetSnapshot()
        syncICloudAfterLocalChange()
        return true
    }

    /// 重命名分组。组内打卡项的 tag 同步更新。重名（与现有分组冲突）返回 false。
    @discardableResult
    func renameDailyCheckGroup(from oldName: String, to newName: String) -> Bool {
        let oldClean = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let newClean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oldClean.isEmpty, !newClean.isEmpty else { return false }
        guard oldClean != newClean else { return true } // 名字没变，视为成功
        guard !dailyCheckGroups.contains(newClean) else { return false }

        // 更新 saved groups 列表
        var groups = savedGroups
        if let idx = groups.firstIndex(of: oldClean) {
            groups[idx] = newClean
        } else {
            // 来自 items 的隐式分组，没注册过 → 直接追加
            groups.append(newClean)
        }
        saveGroups(groups)

        // 同步更新所有 items 的 tag
        let entries = currentCheckEntries().map { entry -> (title: String, tag: String) in
            entry.tag == oldClean ? (title: entry.title, tag: newClean) : entry
        }
        defaults.set(encodeCheckEntries(entries), forKey: keyDailyFields)
        defaults.set(true, forKey: keyDailyInitialized)

        reloadFieldConfig()
        publishCheckWidgetSnapshot()
        return true
    }

    /// 删除分组（连带删除该分组下所有打卡项）
    func removeDailyCheckGroup(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        // 从 saved groups 移除
        let groups = savedGroups.filter { $0 != clean }
        saveGroups(groups)

        // 级联删除该分组下打卡项
        let entries = currentCheckEntries().filter { $0.tag != clean }
        defaults.set(encodeCheckEntries(entries), forKey: keyDailyFields)
        defaults.set(true, forKey: keyDailyInitialized)

        reloadFieldConfig()
        publishCheckWidgetSnapshot()
        syncICloudAfterLocalChange()
    }

    // MARK: - Conversation turns (voice timeline)
    @discardableResult
    func addTurnDraft(rawText: String, recognizedType: String, targetBucket: String, confidence: Double, payload: [String: String], status: String = "draft", fixHint: String = "", moodScore: Int? = nil, feelingTags: [String] = []) -> UUID? {
        let clean = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let id = UUID()
        turns.insert(
            .init(
                id: id,
                createdAt: Date(),
                rawText: clean,
                recognizedType: recognizedType,
                targetBucket: targetBucket,
                confidence: max(0, min(1, confidence)),
                status: status,
                payload: payload,
                fixHint: fixHint,
                moodScore: moodScore,
                feelingTags: feelingTags,
                reviewStatus: "pending"
            ),
            at: 0
        )
        saveTurns()
        return id
    }

    func updateTurnMood(id: UUID, moodScore: Int?, feelingTags: [String]) {
        guard let idx = turns.firstIndex(where: { $0.id == id }) else { return }
        turns[idx].moodScore = moodScore
        turns[idx].feelingTags = feelingTags
        saveTurns()
    }

    func updateTurnReviewStatus(id: UUID, reviewStatus: String) {
        guard let idx = turns.firstIndex(where: { $0.id == id }) else { return }
        turns[idx].reviewStatus = reviewStatus
        saveTurns()
    }

    func updateTurnClassification(id: UUID, recognizedType: String, targetBucket: String) {
        guard let idx = turns.firstIndex(where: { $0.id == id }) else { return }
        turns[idx].recognizedType = recognizedType
        turns[idx].targetBucket = targetBucket
        if turns[idx].status == "needs_fix" {
            turns[idx].status = "draft"
            turns[idx].fixHint = ""
        }
        saveTurns()
    }

    func updateTurnContent(id: UUID, text: String) {
        guard let idx = turns.firstIndex(where: { $0.id == id }) else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        turns[idx].rawText = clean
        switch turns[idx].targetBucket {
        case "time":
            turns[idx].payload["note"] = clean
            let oldName = turns[idx].payload["name"] ?? ""
            if oldName.isEmpty || oldName.hasSuffix("时间块") {
                turns[idx].payload["name"] = summarizeTurnTitle(clean)
            }
        case "task":
            turns[idx].payload["title"] = summarizeTurnTitle(clean)
            turns[idx].payload["detail"] = clean
        default:
            turns[idx].payload["title"] = summarizeTurnTitle(clean)
            turns[idx].payload["detail"] = clean
        }

        if turns[idx].status == "needs_fix" {
            turns[idx].status = "draft"
            turns[idx].fixHint = ""
        }
        saveTurns()
    }

    func markTurnNeedsFix(id: UUID, hint: String) {
        guard let idx = turns.firstIndex(where: { $0.id == id }) else { return }
        turns[idx].status = "needs_fix"
        turns[idx].fixHint = hint
        saveTurns()
    }

    func dismissAIConfirmation(id: UUID) {
        guard let idx = turns.firstIndex(where: { $0.id == id }) else { return }
        turns[idx].payload.removeValue(forKey: "ai_confirmation")
        turns[idx].payload.removeValue(forKey: "ai_confirmation_reason")
        saveTurns()
    }

    func confirmTurnAsTask(id: UUID) -> String? {
        guard let turn = turns.first(where: { $0.id == id }) else { return "记录不存在" }
        return reviseCommittedTurn(
            id: id,
            recognizedType: "待办",
            targetBucket: "task",
            text: TurnTypeStyle.displayText(for: turn)
        )
    }

    @discardableResult
    func commitTurn(id: UUID) -> String? {
        guard let idx = turns.firstIndex(where: { $0.id == id }) else { return "记录不存在" }
        var turn = turns[idx]

        switch turn.targetBucket {
        case "time":
            let start = turn.payload["start"] ?? ""
            let end = turn.payload["end"] ?? ""
            let category = turn.payload["category"] ?? "其他"
            let rawName = turn.payload["name"] ?? ""
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? category : rawName
            let note = turn.payload["note"] ?? ""
            if start.isEmpty || end.isEmpty {
                turns[idx].status = "needs_fix"
                turns[idx].fixHint = "时间记录缺少开始/结束时间，请先补全再写入。"
                saveTurns()
                return turns[idx].fixHint
            }
            let dateKey = normalizedAIRecordDateKey(turn.payload["date"])
            let result = commitTimeEntryFromTurn(
                name: name,
                start: start,
                end: end,
                category: category,
                note: note,
                dateKey: dateKey
            )
            if let err = result.error {
                turns[idx].status = "needs_fix"
                turns[idx].fixHint = err
                saveTurns()
                return err
            }
            if let insertedID = result.inserted.id {
                turn.payload["committedTimeEntryID"] = insertedID.uuidString
            }
            if let committedDateKey = result.inserted.dateKey {
                turn.payload["committedDateKey"] = committedDateKey
            }

        case "task":
            let title = turn.payload["title"] ?? ""
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                turns[idx].status = "needs_fix"
                turns[idx].fixHint = "待办标题为空，请补充。"
                saveTurns()
                return turns[idx].fixHint
            }
            let taskID = addTask(
                title: title,
                detail: turn.payload["detail"] ?? turn.rawText,
                status: turn.payload["status"] ?? "待办",
                priority: turn.payload["priority"] ?? "",
                dueDate: turn.payload["dueDate"] ?? "",
                date: turn.payload["date"] ?? selectedDateKey,
                isAllDay: (turn.payload["isAllDay"] ?? "1") == "1",
                startTime: turn.payload["startTime"] ?? "",
                endTime: turn.payload["endTime"] ?? ""
            )
            if let taskID {
                turn.payload["committedTaskID"] = taskID.uuidString
            }

        default: // note bucket（想法/感受/感恩/做梦）
            // turn 自身就是数据载体，不再写镜像 InboxNote
            break
        }

        turn.status = "committed"
        turn.fixHint = ""
        turns[idx] = turn
        saveTurns()
        return nil
    }

    private func commitTimeEntryFromTurn(name: String, start: String, end: String, category: String, note: String, dateKey: String? = nil) -> (error: String?, inserted: TimeCommitResult) {
        let extra = note.isEmpty ? [:] : ["备注": note]
        guard let startMinutes = Self.clockMinutes(from: start, allow24: false),
              let endMinutes = Self.clockMinutes(from: end, allow24: true) else {
            let err = addTimeEntry(name: name, start: start, end: end, category: category, extra: extra)
            return (err, TimeCommitResult(id: err == nil ? timeEntries.first?.id : nil, dateKey: err == nil ? selectedDateKey : nil))
        }
        if endMinutes == startMinutes {
            return ("结束时间必须晚于开始时间", TimeCommitResult(id: nil, dateKey: nil))
        }
        let targetDateKey = dateKey ?? selectedDateKey
        if endMinutes < startMinutes {
            let result = addCrossDayTimeEntryForDate(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                startMinutes: startMinutes,
                endMinutes: endMinutes,
                category: category,
                extra: extra,
                startDateKey: targetDateKey
            )
            if result.error == nil {
                loadTimeForDate()
                syncICloudAfterLocalChange()
            }
            return result
        }
        if targetDateKey == selectedDateKey {
            let err = addTimeEntry(name: name, start: start, end: end, category: category, extra: extra)
            return (err, TimeCommitResult(id: err == nil ? timeEntries.first?.id : nil, dateKey: err == nil ? selectedDateKey : nil))
        }

        if let err = validateTimeInput(name: name, start: start, end: end) {
            return (err, TimeCommitResult(id: nil, dateKey: nil))
        }
        let entry = TimeEntry(name: name.trimmingCharacters(in: .whitespacesAndNewlines), start: start, end: end, category: category, extra: extra)
        insertTimeEntry(entry, dateKey: targetDateKey)
        syncICloudAfterLocalChange()
        return (nil, TimeCommitResult(id: entry.id, dateKey: targetDateKey))
    }

    func removeTurn(id: UUID) {
        turns.removeAll { $0.id == id }
        saveTurns()
    }

    func isTurnCommitted(id: UUID) -> Bool {
        turns.first(where: { $0.id == id })?.status == "committed"
    }

    @discardableResult
    func reviseCommittedTurn(id: UUID, recognizedType: String, targetBucket: String, text: String) -> String? {
        guard let idx = turns.firstIndex(where: { $0.id == id }) else { return "记录不存在" }
        let wasCommitted = turns[idx].status == "committed"

        if wasCommitted {
            rollbackCommittedPayload(for: turns[idx])
            turns[idx].status = "draft"
            turns[idx].fixHint = ""
            saveTurns()
        }

        updateTurnClassification(id: id, recognizedType: recognizedType, targetBucket: targetBucket)
        updateTurnContent(id: id, text: text)

        if wasCommitted {
            return commitTurn(id: id)
        }
        return nil
    }

    func removeCommittedTurn(id: UUID) {
        guard let idx = turns.firstIndex(where: { $0.id == id }) else { return }
        let turn = turns[idx]
        if turn.status == "committed" {
            rollbackCommittedPayload(for: turn)
        }
        turns.remove(at: idx)
        saveTurns()
    }

    private func rollbackCommittedPayload(for turn: ConversationTurn) {
        switch turn.targetBucket {
        case "time":
            guard let rawID = turn.payload["committedTimeEntryID"], let id = UUID(uuidString: rawID) else { return }
            removeTimeEntryByID(id, dateKey: turn.payload["committedDateKey"])
        case "task":
            guard let rawID = turn.payload["committedTaskID"], let id = UUID(uuidString: rawID) else { return }
            tasks.removeAll { $0.id == id }
            saveTasks()
        default:
            // note bucket：turn 自身即数据载体，回滚不需要联动其他存储
            break
        }
    }

    private func removeTimeEntryByID(_ id: UUID, dateKey: String?) {
        var map = defaults.dictionary(forKey: keyTime) as? [String: [[String: String]]] ?? [:]
        let matchedRow = findTimeEntryRow(id, dateKey: dateKey, in: map)
        let groupID = decodeExtra(matchedRow?["extra"])[TimeEntryCrossDayKey.groupID]

        if let groupID {
            for key in map.keys {
                map[key]?.removeAll { row in
                    decodeExtra(row["extra"])[TimeEntryCrossDayKey.groupID] == groupID
                }
            }
            defaults.set(map, forKey: keyTime)
            syncICloudAfterLocalChange()
        } else if let key = dateKey {
            if var day = map[key] {
                day.removeAll { ($0["id"] ?? "") == id.uuidString }
                map[key] = day
                defaults.set(map, forKey: keyTime)
                syncICloudAfterLocalChange()
            }
        } else {
            for key in map.keys {
                var day = map[key] ?? []
                let before = day.count
                day.removeAll { ($0["id"] ?? "") == id.uuidString }
                if day.count != before {
                    map[key] = day
                }
            }
            defaults.set(map, forKey: keyTime)
            syncICloudAfterLocalChange()
        }

        if selectedDateKey == (dateKey ?? selectedDateKey) {
            loadTimeForDate()
        }
    }

    private func addCrossDayTimeEntry(name: String, startMinutes: Int, endMinutes: Int, category: String, extra: [String: String], startDateKey: String) -> String? {
        addCrossDayTimeEntryForDate(
            name: name,
            startMinutes: startMinutes,
            endMinutes: endMinutes,
            category: category,
            extra: extra,
            startDateKey: startDateKey
        ).error
    }

    private func addCrossDayTimeEntryForDate(name: String, startMinutes: Int, endMinutes: Int, category: String, extra: [String: String], startDateKey: String) -> (error: String?, inserted: TimeCommitResult) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanName.isEmpty {
            return ("事件名称不能为空", TimeCommitResult(id: nil, dateKey: nil))
        }
        guard (0..<24 * 60).contains(startMinutes), (0..<24 * 60).contains(endMinutes), endMinutes < startMinutes else {
            return ("跨日时间需要从今天晚些时候延续到明天", TimeCommitResult(id: nil, dateKey: nil))
        }
        guard let endDateKey = dateKeyByAddingDays(1, to: startDateKey) else {
            return ("无法计算次日日期", TimeCommitResult(id: nil, dateKey: nil))
        }

        let groupID = UUID().uuidString
        let startText = Self.clockText(from: startMinutes)
        let endText = Self.clockText(from: endMinutes)

        var startExtra = extra
        startExtra[TimeEntryCrossDayKey.groupID] = groupID
        startExtra[TimeEntryCrossDayKey.role] = TimeEntryCrossDayKey.roleStart
        startExtra[TimeEntryCrossDayKey.startDateKey] = startDateKey
        startExtra[TimeEntryCrossDayKey.endDateKey] = endDateKey
        startExtra[TimeEntryCrossDayKey.start] = startText
        startExtra[TimeEntryCrossDayKey.end] = endText

        var endExtra = startExtra
        endExtra[TimeEntryCrossDayKey.role] = TimeEntryCrossDayKey.roleEnd

        let startEntry = TimeEntry(name: cleanName, start: startText, end: "24:00", category: category, extra: startExtra)
        insertTimeEntry(startEntry, dateKey: startDateKey)
        if endMinutes > 0 {
            insertTimeEntry(
                .init(name: cleanName, start: "00:00", end: endText, category: category, extra: endExtra),
                dateKey: endDateKey
            )
        }
        return (nil, TimeCommitResult(id: startEntry.id, dateKey: startDateKey))
    }

    private func insertTimeEntry(_ entry: TimeEntry, dateKey: String) {
        var map = defaults.dictionary(forKey: keyTime) as? [String: [[String: String]]] ?? [:]
        var day = map[dateKey] ?? []
        day.insert(row(from: entry), at: 0)
        map[dateKey] = day
        defaults.set(map, forKey: keyTime)
    }

    private func findTimeEntryRow(_ id: UUID, dateKey: String?, in map: [String: [[String: String]]]) -> [String: String]? {
        if let dateKey {
            return map[dateKey]?.first { ($0["id"] ?? "") == id.uuidString }
        }
        for day in map.values {
            if let row = day.first(where: { ($0["id"] ?? "") == id.uuidString }) {
                return row
            }
        }
        return nil
    }

    // MARK: - Load/Save
    private func loadForSelectedDate() {
        loadChecksForDate()
        loadTimeForDate()
    }

    private func loadChecksForDate() {
        mergeCheckWidgetStateIfNeeded()
        let map = defaults.dictionary(forKey: keyChecks) as? [String: [String: Bool]] ?? [:]
        let day = map[selectedDateKey] ?? [:]
        checkItems = currentCheckEntries().map { .init(title: $0.title, done: day[$0.title] ?? false, tag: $0.tag) }
    }

    private func saveChecksForDate() {
        var map = defaults.dictionary(forKey: keyChecks) as? [String: [String: Bool]] ?? [:]
        let day = Dictionary(uniqueKeysWithValues: checkItems.map { ($0.title, $0.done) })
        map[selectedDateKey] = day
        defaults.set(map, forKey: keyChecks)
        publishCheckWidgetSnapshot()
        syncICloudAfterLocalChange()
    }

    func refreshChecksFromWidget() {
        mergeCheckWidgetStateIfNeeded()
        loadChecksForDate()
        publishCheckWidgetSnapshot()
    }

    private func mergeCheckWidgetStateIfNeeded() {
        guard let sharedChecks = CheckWidgetSnapshotStore.loadSharedChecks(userID: currentUserId) else { return }
        let localChecks = defaults.dictionary(forKey: keyChecks) as? [String: [String: Bool]] ?? [:]
        guard localChecks != sharedChecks else { return }
        defaults.set(sharedChecks, forKey: keyChecks)
        // 从桌面小组件打的卡只写进 App Group,这里合并回本地后必须再推一次 iCloud,否则换设备看不到。
        syncICloudAfterLocalChange()
    }

    private func publishCheckWidgetSnapshot() {
        let todayKey = dateKey(for: Date())
        let map = defaults.dictionary(forKey: keyChecks) as? [String: [String: Bool]] ?? [:]
        let today = map[todayKey] ?? [:]
        let items = currentCheckEntries().map { entry in
            CheckWidgetItemSnapshot(
                title: entry.title,
                done: today[entry.title] ?? false,
                tag: entry.tag
            )
        }
        let snapshot = CheckWidgetSnapshot(dateKey: todayKey, updatedAt: Date(), items: items)
        CheckWidgetSnapshotStore.saveAppContext(
            userID: currentUserId,
            checksByDate: map,
            snapshot: snapshot
        )
        WidgetCenter.shared.reloadTimelines(ofKind: "CheckWidget")
    }

    private func loadTimeForDate() {
        let map = defaults.dictionary(forKey: keyTime) as? [String: [[String: String]]] ?? [:]
        let day = map[selectedDateKey] ?? []
        timeEntries = day
            .map(timeEntry(from:))
            .filter { !isZeroLengthCrossDayContinuation($0) }
    }

    private func isZeroLengthCrossDayContinuation(_ entry: TimeEntry) -> Bool {
        entry.extra[TimeEntryCrossDayKey.role] == TimeEntryCrossDayKey.roleEnd
            && entry.start == "00:00"
            && entry.end == "00:00"
    }

    private func saveTimeForDate() {
        var map = defaults.dictionary(forKey: keyTime) as? [String: [[String: String]]] ?? [:]
        map[selectedDateKey] = timeEntries.map(row(from:))
        defaults.set(map, forKey: keyTime)
        syncICloudAfterLocalChange()
    }

    private func row(from entry: TimeEntry) -> [String: String] {
        [
            "id": entry.id.uuidString,
            "name": entry.name,
            "start": entry.start,
            "end": entry.end,
            "category": entry.category,
            "extra": encodeExtra(entry.extra)
        ]
    }

    private func timeEntry(from row: [String: String]) -> TimeEntry {
        let extra = decodeExtra(row["extra"])
        let rawCategory = row["category"] ?? ""
        let id = UUID(uuidString: row["id"] ?? "") ?? UUID()
        return TimeEntry(
            id: id,
            name: row["name"] ?? "",
            start: row["start"] ?? "",
            end: row["end"] ?? "",
            category: normalizeLegacyTimeCategory(rawCategory),
            extra: extra
        )
    }

    private func loadTasks() {
        let arr = defaults.array(forKey: keyTasks) as? [[String: String]] ?? []
        tasks = arr.map {
            let id = UUID(uuidString: $0["id"] ?? "") ?? UUID()
            // 兼容老记录：没有 isAllDay 字段时按全天处理
            let allDayRaw = $0["isAllDay"]
            let isAllDay = allDayRaw == nil ? true : (allDayRaw == "1")
            // 兼容老记录：没有 sourceNoteId / sourceExcerpt 字段时按手工建处理
            let srcRaw = $0["sourceNoteId"] ?? ""
            let srcId: UUID? = srcRaw.isEmpty ? nil : UUID(uuidString: srcRaw)
            return TaskEntry(
                id: id,
                title: $0["title"] ?? "",
                detail: $0["detail"] ?? "",
                status: $0["status"] ?? "待办",
                priority: $0["priority"] ?? "",
                dueDate: $0["dueDate"] ?? "",
                date: $0["date"] ?? currentDateKey(),
                completedAt: Self.taskDateFormatter.date(from: $0["completedAt"] ?? ""),
                isAllDay: isAllDay,
                startTime: $0["startTime"] ?? "",
                endTime: $0["endTime"] ?? "",
                location: $0["location"] ?? "",
                sourceNoteId: srcId,
                sourceExcerpt: $0["sourceExcerpt"] ?? ""
            )
        }
    }

    private func saveTasks() {
        let arr = tasks.map {
            [
                "id": $0.id.uuidString,
                "title": $0.title,
                "detail": $0.detail,
                "status": $0.status,
                "priority": $0.priority,
                "dueDate": $0.dueDate,
                "date": $0.date,
                "completedAt": $0.completedAt.map(Self.taskDateFormatter.string(from:)) ?? "",
                "isAllDay": $0.isAllDay ? "1" : "0",
                "startTime": $0.startTime,
                "endTime": $0.endTime,
                "location": $0.location,
                "sourceNoteId": $0.sourceNoteId?.uuidString ?? "",
                "sourceExcerpt": $0.sourceExcerpt
            ]
        }
        defaults.set(arr, forKey: keyTasks)
        syncICloudAfterLocalChange()
    }

    private func loadTurns() {
        let arr = defaults.array(forKey: keyTurns) as? [[String: String]] ?? []
        turns = arr.compactMap { row in
            guard let idRaw = row["id"], let id = UUID(uuidString: idRaw) else { return nil }
            let ts = Double(row["createdAt"] ?? "") ?? Date().timeIntervalSince1970
            let moodRaw = row["moodScore"] ?? ""
            let feelingRaw = row["feelingTags"] ?? ""
            let feelings = feelingRaw.isEmpty ? [] : feelingRaw.components(separatedBy: "|")
            return ConversationTurn(
                id: id,
                createdAt: Date(timeIntervalSince1970: ts),
                rawText: row["rawText"] ?? "",
                recognizedType: row["recognizedType"] ?? "想法",
                targetBucket: row["targetBucket"] ?? "inbox",
                confidence: Double(row["confidence"] ?? "0.5") ?? 0.5,
                status: row["status"] ?? "draft",
                payload: decodeExtra(row["payload"]),
                fixHint: row["fixHint"] ?? "",
                moodScore: moodRaw.isEmpty ? nil : Int(moodRaw),
                feelingTags: feelings,
                reviewStatus: row["reviewStatus"] ?? "pending",
                derivatives: decodeDerivatives(row["derivatives"])
            )
        }
    }

    private func saveTurns() {
        let arr = turns.map { turn in
            [
                "id": turn.id.uuidString,
                "createdAt": String(turn.createdAt.timeIntervalSince1970),
                "rawText": turn.rawText,
                "recognizedType": turn.recognizedType,
                "targetBucket": turn.targetBucket,
                "confidence": String(turn.confidence),
                "status": turn.status,
                "payload": encodeExtra(turn.payload),
                "fixHint": turn.fixHint,
                "moodScore": turn.moodScore.map(String.init) ?? "",
                "feelingTags": turn.feelingTags.joined(separator: "|"),
                "reviewStatus": turn.reviewStatus,
                "derivatives": encodeDerivatives(turn.derivatives)
            ]
        }
        defaults.set(arr, forKey: keyTurns)
        syncICloudAfterLocalChange()
    }

    // MARK: - Brain cards (第二大脑)

    @discardableResult
    func addBrain(title: String, content: String = "", topics: [String] = [], sources: [BrainCardSource] = []) -> UUID? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }
        let now = Date()
        let card = BrainCard(
            title: cleanTitle,
            content: content,
            topics: topics,
            sources: sources,
            links: [],
            createdAt: now,
            updatedAt: now
        )
        brainCards.insert(card, at: 0)
        saveBrain()
        return card.id
    }

    func updateBrain(id: UUID, title: String, content: String, topics: [String]) {
        guard let idx = brainCards.firstIndex(where: { $0.id == id }) else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        brainCards[idx].title = cleanTitle
        brainCards[idx].content = content
        brainCards[idx].topics = topics
        brainCards[idx].updatedAt = Date()
        saveBrain()
    }

    @discardableResult
    func addBrainExtension(cardId: UUID, content: String) -> UUID? {
        guard let idx = brainCards.firstIndex(where: { $0.id == cardId }) else { return nil }
        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanContent.isEmpty else { return nil }
        let now = Date()
        let extensionNote = BrainCardExtension(
            content: cleanContent,
            createdAt: now,
            updatedAt: now
        )
        brainCards[idx].extensions.insert(extensionNote, at: 0)
        brainCards[idx].updatedAt = now
        saveBrain()
        return extensionNote.id
    }

    func removeBrainExtension(cardId: UUID, extensionId: UUID) {
        guard let idx = brainCards.firstIndex(where: { $0.id == cardId }) else { return }
        brainCards[idx].extensions.removeAll { $0.id == extensionId }
        brainCards[idx].updatedAt = Date()
        saveBrain()
    }

    func removeBrain(id: UUID) {
        brainCards.removeAll { $0.id == id }
        // 反向清理：其他卡片 links 数组里把这张卡的 id 拿掉，避免悬空引用
        for i in brainCards.indices {
            brainCards[i].links.removeAll { $0 == id }
        }
        saveBrain()
    }

    /// 给某条 turn append 一条衍生链接（Review 模式下"→ ToDo / → 第二大脑"会调）。
    /// derivatives 是 append-only，不去重——同一个 turn 对同一个目标建多次链接是合法的（虽不该发生）。
    func appendTurnDerivative(turnId: UUID, derivative: TurnDerivative) {
        guard let idx = turns.firstIndex(where: { $0.id == turnId }) else { return }
        turns[idx].derivatives.append(derivative)
        saveTurns()
    }

    private func loadBrain() {
        guard let data = defaults.data(forKey: keyBrain) else { brainCards = []; return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        brainCards = (try? decoder.decode([BrainCard].self, from: data)) ?? []
    }

    private func saveBrain() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(brainCards) else { return }
        defaults.set(data, forKey: keyBrain)
        syncICloudAfterLocalChange()
    }

    func recordAIFailure(context: String, input: String, error: Error) {
        let cleanInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let excerpt = cleanInput.count > 120 ? String(cleanInput.prefix(120)) + "..." : cleanInput
        let message = error.localizedDescription
        let log = AIFailureLog(
            createdAt: Date(),
            context: context,
            inputExcerpt: excerpt,
            errorType: String(describing: type(of: error)),
            message: message
        )

        aiFailureLogs.insert(log, at: 0)
        if aiFailureLogs.count > 30 {
            aiFailureLogs = Array(aiFailureLogs.prefix(30))
        }
        saveAIFailureLogs()
    }

    private func loadAIFailureLogs() {
        guard let data = defaults.data(forKey: keyAIFailures) else {
            aiFailureLogs = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        aiFailureLogs = (try? decoder.decode([AIFailureLog].self, from: data)) ?? []
    }

    private func saveAIFailureLogs() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(aiFailureLogs) else { return }
        defaults.set(data, forKey: keyAIFailures)
    }

    @discardableResult
    private func recordAIDebugLog(
        input: String,
        currentDate: String,
        currentTime: String,
        rawResponse: String?,
        records: [AIParsedRecord],
        needsClarification: String?,
        errorMessage: String = ""
    ) -> UUID {
        let log = AIDebugLog(
            createdAt: Date(),
            input: input.trimmingCharacters(in: .whitespacesAndNewlines),
            currentDate: currentDate,
            currentTime: currentTime,
            rawResponse: rawResponse ?? "",
            needsClarification: needsClarification ?? "",
            recordsSummary: records.map { aiDebugRecordSummary($0, rawText: input) },
            commitSummary: [],
            errorMessage: errorMessage
        )
        aiDebugLogs.insert(log, at: 0)
        trimAndSaveAIDebugLogs()
        return log.id
    }

    private func appendAIDebugCommit(logID: UUID?, summary: String) {
        guard let logID, let idx = aiDebugLogs.firstIndex(where: { $0.id == logID }) else { return }
        aiDebugLogs[idx].commitSummary.append(summary)
        trimAndSaveAIDebugLogs()
    }

    func clearAIDebugLogs() {
        aiDebugLogs = []
        defaults.removeObject(forKey: keyAIDebugLogs)
    }

    private func loadAIDebugLogs() {
        guard let data = defaults.data(forKey: keyAIDebugLogs) else {
            aiDebugLogs = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        aiDebugLogs = (try? decoder.decode([AIDebugLog].self, from: data)) ?? []
    }

    private func trimAndSaveAIDebugLogs() {
        if aiDebugLogs.count > 20 {
            aiDebugLogs = Array(aiDebugLogs.prefix(20))
        }
        saveAIDebugLogs()
    }

    private func saveAIDebugLogs() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(aiDebugLogs) else { return }
        defaults.set(data, forKey: keyAIDebugLogs)
    }

    private func aiDebugRecordSummary(_ rec: AIParsedRecord, rawText: String) -> String {
        let appBucket = AIRoutingPolicy.appBucket(for: rec, rawText: rawText)
        let title = rec.eventName ?? rec.title ?? ""
        let type = rec.type ?? rec.module ?? ""
        let date = rec.date ?? ""
        let start = rec.startTime ?? ""
        let end = rec.endTime ?? ""
        let detail = rec.details ?? rec.notes ?? ""
        return [
            "aiBucket=\(rec.bucket)",
            appBucket == rec.bucket ? "" : "appBucket=\(appBucket)",
            title.isEmpty ? "" : "title=\(title)",
            type.isEmpty ? "" : "type=\(type)",
            date.isEmpty ? "" : "date=\(date)",
            start.isEmpty && end.isEmpty ? "" : "time=\(start)-\(end)",
            detail.isEmpty ? "" : "detail=\(detail)"
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    private func encodeDerivatives(_ arr: [TurnDerivative]) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(arr),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }

    private func decodeDerivatives(_ raw: String?) -> [TurnDerivative] {
        guard let raw, !raw.isEmpty, let data = raw.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([TurnDerivative].self, from: data)) ?? []
    }

    // 当前阶段：字段配置锁定为 Notion 结构，不开放自定义
    var timeFieldNames: [String] { ["一句话描述", "开始时间", "结束时间", "模块分类", "备注"] }
    var timeFieldTypes: [String] { ["text", "time", "time", "select", "text"] }
    var timeFieldOptions: [String: [String]] {
        ["模块分类": ["睡觉", "社交", "运动", "其他", "娱乐", "工作", "学习"]]
    }

    func reloadFieldConfig() {
        loadChecksForDate()
        objectWillChange.send()
    }

    var exportJSONString: String {
        let payload: [String: Any] = [
            "selectedDate": selectedDateKey,
            "checkItems": checkItems.map { ["title": $0.title, "done": $0.done] },
            "timeEntries": timeEntries.map { ["name": $0.name, "start": $0.start, "end": $0.end, "category": $0.category, "extra": $0.extra] },
            "tasks": tasks.map {
                [
                    "title": $0.title,
                    "detail": $0.detail,
                    "status": $0.status,
                    "priority": $0.priority,
                    "dueDate": $0.dueDate,
                    "date": $0.date,
                    "completedAt": $0.completedAt.map(Self.taskDateFormatter.string(from:)) ?? ""
                ]
            }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    var exportCSVString: String {
        var lines: [String] = ["type,date,name_or_title,start,end,category,status,detail"]
        for t in timeEntries {
            lines.append("time,\(selectedDateKey),\(escapeCSV(t.name)),\(escapeCSV(t.start)),\(escapeCSV(t.end)),\(escapeCSV(t.category)),, ")
        }
        for t in tasks {
            lines.append("task,\(escapeCSV(t.date)),\(escapeCSV(t.title)),,,,\(escapeCSV(t.status)),\(escapeCSV(t.detail))")
        }
        return lines.joined(separator: "\n")
    }

    @discardableResult
    func importCSVString(_ csv: String) -> String? {
        let rows = csv.split(whereSeparator: { $0.isNewline }).map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !rows.isEmpty else { return "CSV 内容为空" }

        var timeMap = defaults.dictionary(forKey: keyTime) as? [String: [[String: String]]] ?? [:]
        var taskArr = defaults.array(forKey: keyTasks) as? [[String: String]] ?? []

        var importedCount = 0
        for (idx, row) in rows.enumerated() {
            if idx == 0 && row.lowercased().contains("type") && row.lowercased().contains("date") { continue }

            let cols = parseCSVRow(row)
            if cols.count < 8 { continue }

            let type = cols[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let date = normalizeDate(cols[1]) ?? selectedDateKey
            let nameOrTitle = cols[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let start = cols[3].trimmingCharacters(in: .whitespacesAndNewlines)
            let end = cols[4].trimmingCharacters(in: .whitespacesAndNewlines)
            let category = cols[5].trimmingCharacters(in: .whitespacesAndNewlines)
            let status = cols[6].trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = cols[7].trimmingCharacters(in: .whitespacesAndNewlines)

            switch type {
            case "time":
                guard !nameOrTitle.isEmpty, isValidHHmm(start), isValidHHmm(end) else { continue }
                let item: [String: String] = [
                    "name": nameOrTitle,
                    "start": start,
                    "end": end,
                    "category": category.isEmpty ? "其他" : category,
                    "extra": "{}"
                ]
                var day = timeMap[date] ?? []
                day.insert(item, at: 0)
                timeMap[date] = day
                importedCount += 1

            case "task":
                guard !nameOrTitle.isEmpty else { continue }
                let item: [String: String] = [
                    "title": nameOrTitle,
                    "detail": detail,
                    "status": status.isEmpty ? "待办" : status,
                    "priority": "",
                    "dueDate": "",
                    "date": date,
                    "completedAt": status == "已完成" ? Self.taskDateFormatter.string(from: Date()) : ""
                ]
                taskArr.insert(item, at: 0)
                importedCount += 1

            default:
                continue
            }
        }

        if importedCount == 0 { return "未识别到可导入记录，请检查 CSV 列格式" }

        defaults.set(timeMap, forKey: keyTime)
        defaults.set(taskArr, forKey: keyTasks)
        syncICloudAfterLocalChange()

        loadForSelectedDate()
        loadTasks()
        objectWillChange.send()
        return nil
    }

    private func validateTimeInput(name: String, start: String, end: String) -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "事件名称不能为空" }
        guard let s = Self.clockMinutes(from: start, allow24: false),
              let e = Self.clockMinutes(from: end, allow24: true) else {
            return "时间格式应为 HH:mm（例如 09:30）"
        }
        if e <= s { return "结束时间必须晚于开始时间" }
        return nil
    }

    private static func clockMinutes(from value: String, allow24: Bool) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...59).contains(minute) else { return nil }
        if allow24, hour == 24, minute == 0 { return 24 * 60 }
        guard (0...23).contains(hour) else { return nil }
        return hour * 60 + minute
    }

    private static func clockText(from minutes: Int) -> String {
        if minutes == 24 * 60 { return "24:00" }
        let h = max(0, min(23, minutes / 60))
        let m = max(0, min(59, minutes % 60))
        return String(format: "%02d:%02d", h, m)
    }

    private func encodeExtra(_ extra: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: extra, options: []),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    private func decodeExtra(_ raw: String?) -> [String: String] {
        guard let raw, let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        return obj
    }

    private func currentCheckTitles() -> [String] {
        currentCheckEntries().map { $0.title }
    }

    /// 解析 fields.daily 的 "title|tag,title|tag" 格式；若没有 `|` 则 tag = "默认"
    /// 只有在从未初始化过时才走 fallback；用户主动删成空之后不再复活
    private func currentCheckEntries() -> [(title: String, tag: String)] {
        // 优先读按用户隔离后的 key
        let rawScoped = defaults.string(forKey: keyDailyFields)

        // 兼容旧版本：若当前用户还没有 scoped 配置，但全局老 key 有内容，迁移一次
        if rawScoped == nil,
           let legacyRaw = defaults.string(forKey: legacyKeyDailyFields) {
            defaults.set(legacyRaw, forKey: keyDailyFields)
            let legacyInitialized = defaults.bool(forKey: legacyKeyDailyInitialized)
            defaults.set(legacyInitialized, forKey: keyDailyInitialized)
        }

        let initialized = defaults.bool(forKey: keyDailyInitialized)
        let rawOpt = defaults.string(forKey: keyDailyFields)
        let raw: String
        if let r = rawOpt {
            raw = r
        } else if !initialized {
            raw = encodeCheckEntries(fallbackCheckEntries)
        } else {
            raw = ""
        }
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var didNormalize = false
        let entries: [(String, String)] = parts.map { item in
            if let sep = item.firstIndex(of: "|") {
                let title = String(item[..<sep]).trimmingCharacters(in: .whitespaces)
                let rawTag = String(item[item.index(after: sep)...]).trimmingCharacters(in: .whitespaces)
                let normalized = normalizeCheckTag(rawTag)
                if normalized != rawTag { didNormalize = true }
                return (title, normalized)
            }
            return (item, "")
        }.filter { !$0.0.isEmpty }
        // 已初始化但为空 → 如实返回空；未初始化且 fallback 也空 → 返回空
        if entries.isEmpty && !initialized {
            return fallbackCheckEntries
        }
        // 一次性把旧的 "早"/"晚"/"默认" 落盘成统一形式，避免新旧标签在打卡页分两栏显示
        if didNormalize {
            defaults.set(encodeCheckEntries(entries), forKey: keyDailyFields)
        }
        return entries
    }

    /// 把历史上的简写标签归一到当前预设。
    /// "默认" → 空字符串（未分组），UI 上不再以分组形式呈现。
    private func normalizeCheckTag(_ tag: String) -> String {
        switch tag {
        case "早", "晨间", "morning": return "早上"
        case "晚", "夜间", "evening": return "晚上"
        case "默认": return ""
        default: return tag
        }
    }

    private func encodeCheckEntries(_ entries: [(title: String, tag: String)]) -> String {
        entries.map { "\($0.title)|\($0.tag)" }.joined(separator: ",")
    }

    private func escapeCSV(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func parseCSVRow(_ row: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(row)
        var i = 0

        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if inQuotes && i + 1 < chars.count && chars[i + 1] == "\"" {
                    current.append("\"")
                    i += 1
                } else {
                    inQuotes.toggle()
                }
            } else if c == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(c)
            }
            i += 1
        }

        result.append(current)
        return result
    }

    private func normalizeDate(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: text) else { return nil }
        return f.string(from: d)
    }

    private func isValidHHmm(_ value: String) -> Bool {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.date(from: value) != nil
    }

    private func summarizeTurnTitle(_ raw: String) -> String {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return "未命名记录" }
        if clean.count <= 20 { return clean }
        return String(clean.prefix(20)) + "…"
    }

    private func currentDateKey() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }

    // MARK: - Record trace helpers (for calendar/date strip UI)
    func checkDoneCount(on date: Date) -> Int {
        let key = dateKey(for: date)
        let map = defaults.dictionary(forKey: keyChecks) as? [String: [String: Bool]] ?? [:]
        let day = map[key] ?? [:]
        return day.values.filter { $0 }.count
    }

    func timeEntryCount(on date: Date) -> Int {
        let key = dateKey(for: date)
        let map = defaults.dictionary(forKey: keyTime) as? [String: [[String: String]]] ?? [:]
        return (map[key] ?? []).count
    }

    func timeCategories(on date: Date) -> [String] {
        let key = dateKey(for: date)
        let map = defaults.dictionary(forKey: keyTime) as? [String: [[String: String]]] ?? [:]
        let rows = map[key] ?? []

        var seen = Set<String>()
        var ordered: [String] = []
        for row in rows {
            let category = (row["category"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !category.isEmpty, !seen.contains(category) else { continue }
            seen.insert(category)
            ordered.append(category)
            if ordered.count >= 4 { break }
        }
        return ordered
    }

    func reviewCheckHabitSummaries(start: Date, end: Date) -> [ReviewCheckHabitSummary] {
        let keys = dateKeys(start: start, end: end)
        let map = defaults.dictionary(forKey: keyChecks) as? [String: [String: Bool]] ?? [:]

        return currentCheckEntries().map { entry in
            let completed = keys.reduce(0) { total, key in
                total + ((map[key]?[entry.title] == true) ? 1 : 0)
            }
            return ReviewCheckHabitSummary(
                title: entry.title,
                completedDays: completed,
                blankDays: max(keys.count - completed, 0)
            )
        }
    }

    func reviewCheckDaySummaries(start: Date, end: Date) -> [ReviewCheckDaySummary] {
        let days = dates(start: start, end: end)
        let map = defaults.dictionary(forKey: keyChecks) as? [String: [String: Bool]] ?? [:]
        let titles = currentCheckEntries().map(\.title)

        return days.map { date in
            let key = dateKey(for: date)
            let day = map[key] ?? [:]
            let completed = titles.reduce(0) { total, title in
                total + ((day[title] == true) ? 1 : 0)
            }
            return ReviewCheckDaySummary(date: date, completedCount: completed, totalCount: titles.count)
        }
    }

    func reviewCheckGroupSummaries(start: Date, end: Date) -> [ReviewCheckGroupSummary] {
        let days = dates(start: start, end: end)
        let map = defaults.dictionary(forKey: keyChecks) as? [String: [String: Bool]] ?? [:]
        let entries = currentCheckEntries()
        let grouped = Dictionary(grouping: entries, by: { $0.tag.isEmpty ? "未分组" : $0.tag })
        let orderedGroups = entries.reduce(into: [String]()) { result, entry in
            let title = entry.tag.isEmpty ? "未分组" : entry.tag
            if !result.contains(title) { result.append(title) }
        }

        return orderedGroups.compactMap { groupTitle in
            guard let groupEntries = grouped[groupTitle], !groupEntries.isEmpty else { return nil }
            let groupDays = days.map { date in
                let key = dateKey(for: date)
                let day = map[key] ?? [:]
                let completed = groupEntries.reduce(0) { total, entry in
                    total + ((day[entry.title] == true) ? 1 : 0)
                }
                return ReviewCheckGroupSummary.Day(
                    date: date,
                    completedCount: completed,
                    totalCount: groupEntries.count
                )
            }
            return ReviewCheckGroupSummary(title: groupTitle, days: groupDays)
        }
    }

    func reviewTimeCategorySummaries(start: Date, end: Date) -> [ReviewTimeCategorySummary] {
        let keys = Set(dateKeys(start: start, end: end))
        let map = defaults.dictionary(forKey: keyTime) as? [String: [[String: String]]] ?? [:]
        var minutesByCategory: [String: Int] = [:]

        for key in keys.sorted() {
            for row in map[key] ?? [] {
                let category = normalizeLegacyTimeCategory(row["category"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard let startMinutes = parseClockMinutes(row["start"] ?? ""),
                      let endMinutes = parseClockMinutes(row["end"] ?? ""),
                      endMinutes > startMinutes else { continue }
                let cleanCategory = category.isEmpty ? "其他" : category
                minutesByCategory[cleanCategory, default: 0] += endMinutes - startMinutes
            }
        }

        let categoryOrder = ["学习", "工作", "运动", "娱乐", "社交", "睡觉", "其他"]
        let known = categoryOrder
            .map { ReviewTimeCategorySummary(category: $0, minutes: minutesByCategory[$0] ?? 0) }
            .filter { $0.minutes > 0 }
        let otherKnown = Set(categoryOrder)
        let custom = minutesByCategory.keys
            .filter { !otherKnown.contains($0) }
            .sorted()
            .map { ReviewTimeCategorySummary(category: $0, minutes: minutesByCategory[$0] ?? 0) }
            .filter { $0.minutes > 0 }
        return known + custom
    }

    func hasRecordTrace(on date: Date) -> Bool {
        checkDoneCount(on: date) > 0 || timeEntryCount(on: date) > 0
    }

    func calendarDateKey(for date: Date) -> String {
        dateKey(for: date)
    }

    func recordTraceDateKeys(inMonth month: Date) -> Set<String> {
        let keys = Set(monthDateKeys(for: month))
        let checkMap = defaults.dictionary(forKey: keyChecks) as? [String: [String: Bool]] ?? [:]
        let timeMap = defaults.dictionary(forKey: keyTime) as? [String: [[String: String]]] ?? [:]

        var result = Set<String>()
        for key in keys {
            if let day = checkMap[key], day.values.contains(true) {
                result.insert(key)
                continue
            }
            if let rows = timeMap[key], !rows.isEmpty {
                result.insert(key)
            }
        }
        return result
    }

    func timeCategoriesByDateKey(inMonth month: Date) -> [String: [String]] {
        let keys = Set(monthDateKeys(for: month))
        let map = defaults.dictionary(forKey: keyTime) as? [String: [[String: String]]] ?? [:]

        var result: [String: [String]] = [:]
        for key in keys {
            guard let rows = map[key], !rows.isEmpty else { continue }
            var seen = Set<String>()
            var ordered: [String] = []
            for row in rows {
                let category = (row["category"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !category.isEmpty, !seen.contains(category) else { continue }
                seen.insert(category)
                ordered.append(category)
                if ordered.count >= 4 { break }
            }
            if !ordered.isEmpty {
                result[key] = ordered
            }
        }
        return result
    }

    private func dateKey(for date: Date) -> String {
        Self.dateKeyFormatter.string(from: date)
    }

    private func dateKeyByAddingDays(_ days: Int, to key: String) -> String? {
        guard let date = Self.dateKeyFormatter.date(from: key),
              let shifted = Calendar.current.date(byAdding: .day, value: days, to: date) else { return nil }
        return dateKey(for: shifted)
    }

    private func normalizedAIRecordDateKey(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        if Self.dateKeyFormatter.date(from: clean) != nil {
            return clean
        }
        return nil
    }

    private func dateKeys(start: Date, end: Date) -> [String] {
        dates(start: start, end: end).map { dateKey(for: $0) }
    }

    private func dates(start: Date, end: Date) -> [Date] {
        let calendar = Calendar.current
        var result: [Date] = []
        var cursor = calendar.startOfDay(for: start)
        let exclusiveEnd = calendar.startOfDay(for: end)
        while cursor < exclusiveEnd {
            result.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    private func parseClockMinutes(_ value: String) -> Int? {
        Self.clockMinutes(from: value, allow24: true)
    }

    private func monthDateKeys(for month: Date) -> [String] {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: month)
        guard
            let start = calendar.date(from: comps),
            let range = calendar.range(of: .day, in: .month, for: start)
        else { return [] }

        return range.compactMap { day -> String? in
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: start) else { return nil }
            return dateKey(for: date)
        }
    }

    private func normalizeLegacyTimeCategory(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value == "产品" { return "工作" }
        return value
    }

    // MARK: - AI Dispatch Pipeline
    // 全局 AI 输入框调用这些方法；原本住在 QuickCaptureView 的私有实现搬进来。

    /// 入口：AI 优先，失败降级本地关键词。调用方只需传原文。
    func submitAIText(_ text: String) {
        let cleanInput = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanInput.isEmpty else { return }

        // 如果上一轮是追问等澄清，把原文 + 这次的补充拼起来再发，保留上下文
        let pending = pendingClarification
        let effectiveText: String
        if let p = pending {
            effectiveText = "\(p.originalText)\n补充：\(cleanInput)"
        } else {
            effectiveText = cleanInput
        }

        isAILoading = true
        aiDebugMessage = nil

        let today = AIParser.isoDate()
        let now = AIParser.isoTime()

        Task { [weak self] in
            guard let self else { return }
            do {
                let resp = try await AIParser.parse(text: effectiveText, currentDate: today, currentTime: now)
                await MainActor.run {
                    self.isAILoading = false
                    let debugLogID = self.recordAIDebugLog(
                        input: effectiveText,
                        currentDate: today,
                        currentTime: now,
                        rawResponse: resp.rawBody,
                        records: resp.records,
                        needsClarification: resp.needsClarification
                    )
                    if resp.records.isEmpty {
                        if let hint = resp.needsClarification {
                            // 保存上下文，等用户补充后再次提交时合并
                            self.pendingClarification = PendingClarification(
                                originalText: effectiveText,
                                hint: hint
                            )
                            self.aiDebugMessage = "还差一点：\(hint)"
                            self.appendAIDebugCommit(logID: debugLogID, summary: "needsClarification=\(hint)")
                        } else {
                            self.pendingClarification = nil
                            self.aiDebugMessage = "AI 未识别内容 · 已走本地兜底"
                            self.dispatchLocalFallback(effectiveText, markSource: "local")
                            self.appendAIDebugCommit(logID: debugLogID, summary: "AI 无 records，已走本地兜底")
                        }
                        return
                    }
                    // 解析成功：清掉追问上下文
                    self.pendingClarification = nil
                    // 感恩/感受：同一次输入 AI 拆成了多条的话，合并成一条保留在同一 turn 里
                    // （"今天感恩 A，感恩 B，感恩 C" 不应该变成 3 条独立记录）
                    let mergedRecords = self.mergeSameTypeNoteRecords(resp.records)
                    for rec in mergedRecords {
                        self.commitAIRecord(rec, rawText: effectiveText, debugLogID: debugLogID)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isAILoading = false
                    self.aiDebugMessage = "AI 调用失败：\(error.localizedDescription.prefix(80)) · 已走本地兜底"
                    let debugLogID = self.recordAIDebugLog(
                        input: effectiveText,
                        currentDate: today,
                        currentTime: now,
                        rawResponse: nil,
                        records: [],
                        needsClarification: nil,
                        errorMessage: error.localizedDescription
                    )
                    self.dispatchLocalFallback(effectiveText, markSource: "local")
                    self.appendAIDebugCommit(logID: debugLogID, summary: "AI 调用失败，已走本地兜底：\(error.localizedDescription)")
                }
            }
        }
    }

    /// 快捷：跳过 AI，直接本地关键词入库（⚡️ 按钮）
    func submitLocalOnly(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        aiDebugMessage = nil
        dispatchLocalFallback(clean, markSource: "local")
    }

    /// AI 偶尔会把一次说出的多件感恩/感受拆成多条独立 record。
    /// 这里按 type 归并：同一种 note（感恩/感受），details 用换行拼接，只保留一条。
    /// 想法 / 做梦 / 时间 / 待办 不合并（它们各自独立才对）。
    private func mergeSameTypeNoteRecords(_ records: [AIParsedRecord]) -> [AIParsedRecord] {
        guard records.count > 1 else { return records }

        let mergeableTypes: Set<String> = ["感恩", "感受"]
        var result: [AIParsedRecord] = []
        var mergeIndex: [String: Int] = [:]  // type -> 在 result 中的索引

        for rec in records {
            let isNote = rec.bucket != "time" && rec.bucket != "task"
            let type = rec.type ?? ""
            guard isNote, mergeableTypes.contains(type) else {
                result.append(rec)
                continue
            }
            if let idx = mergeIndex[type] {
                // 合并：details 拼接（每条前加短横线，便于阅读）
                let prev = result[idx]
                let prevDetail = prev.details ?? ""
                let newDetail = rec.details ?? ""
                let joined: String = {
                    let a = prevDetail.trimmingCharacters(in: .whitespacesAndNewlines)
                    let b = newDetail.trimmingCharacters(in: .whitespacesAndNewlines)
                    if a.isEmpty { return b }
                    if b.isEmpty { return a }
                    // 已经是列表就直接追加；否则两段都加 "- " 变成列表
                    if a.contains("\n- ") || a.hasPrefix("- ") {
                        return a + "\n- " + b
                    }
                    return "- " + a + "\n- " + b
                }()
                // 合并 feelings（去重保序）
                var feelings = prev.feelings ?? []
                for f in (rec.feelings ?? []) where !feelings.contains(f) {
                    feelings.append(f)
                }
                result[idx] = AIParsedRecord(
                    bucket: prev.bucket,
                    eventName: prev.eventName,
                    module: prev.module,
                    startTime: prev.startTime,
                    endTime: prev.endTime,
                    notes: prev.notes,
                    type: prev.type,
                    title: prev.title,
                    details: joined,
                    mood: prev.mood ?? rec.mood,
                    feelings: feelings,
                    date: prev.date ?? rec.date
                )
            } else {
                mergeIndex[type] = result.count
                result.append(rec)
            }
        }
        return result
    }

    /// 把一条 AI 返回的 record 按 bucket 落库
    private func commitAIRecord(_ rec: AIParsedRecord, rawText: String, debugLogID: UUID? = nil) {
        let routing = AIRoutingPolicy.decision(for: rec, rawText: rawText)
        switch routing.action {
        case .time:
            let start = rec.startTime ?? ""
            let end = rec.endTime ?? ""
            let category = rec.module ?? "✨ 其他"
            let rawName = rec.eventName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = rawName.isEmpty ? category : rawName
            let note = rec.notes ?? ""
            let result = dispatchAndCommit(
                rawText: rawText,
                recognizedType: routing.recognizedType,
                targetBucket: routing.targetBucket,
                confidence: routing.confidence,
                payload: [
                    "name": name, "start": start, "end": end,
                    "category": category, "note": note,
                    "date": rec.date ?? "",
                    "ai_source": routing.source
                ]
            )
            let dateSummary = normalizedAIRecordDateKey(rec.date) ?? selectedDateKey
            appendAIDebugCommit(logID: debugLogID, summary: "time · \(dateSummary) · \(name) · \(start)-\(end) · \(result)")

        case .task:
            let title = rec.title?.isEmpty == false ? rec.title! : (rec.eventName ?? aiFallbackTitle(rawText))
            let detail = rec.details ?? rec.notes ?? ""
            let start = rec.startTime ?? ""
            let end = rec.endTime ?? ""
            let result = dispatchAndCommit(
                rawText: rawText,
                recognizedType: routing.recognizedType,
                targetBucket: routing.targetBucket,
                confidence: routing.confidence,
                payload: [
                    "title": title,
                    "detail": detail,
                    "status": "待办",
                    "dueDate": rec.date ?? "",
                    "isAllDay": start.isEmpty ? "1" : "0",
                    "startTime": start,
                    "endTime": end,
                    "ai_source": routing.source
                ]
            )
            appendAIDebugCommit(logID: debugLogID, summary: "task · \(title) · \(result)")

        case .inbox:
            let type = routing.recognizedType
            let title = rec.title?.isEmpty == false ? rec.title! : aiFallbackTitle(rawText)
            let detail = type == "感受" ? rawText : (rec.details ?? rawText)
            var payload = [
                "title": title,
                "detail": detail,
                "status": "待处理",
                "ai_source": routing.source
            ]
            if routing.needsTaskConfirmation {
                payload["ai_confirmation"] = "task"
                payload["ai_confirmation_reason"] = "AI 觉得它像待办，但原文没有明确待办信号"
            }
            let result = dispatchAndCommit(
                rawText: rawText,
                recognizedType: type,
                targetBucket: routing.targetBucket,
                confidence: routing.confidence,
                payload: payload,
                moodScore: rec.mood,
                feelingTags: rec.feelings ?? []
            )
            appendAIDebugCommit(logID: debugLogID, summary: "inbox/\(type) · \(title) · \(result)")

        case .skip:
            appendAIDebugCommit(logID: debugLogID, summary: "time skipped · \(routing.skipReason)")
            return
        }
    }

    /// 本地关键词兜底
    private func dispatchLocalFallback(_ text: String, markSource: String = "local") {
        let result = QuickCaptureParser.parse(text)
        if let t = result.plan.timeEntries.first {
            dispatchAndCommit(
                rawText: text,
                recognizedType: "时间记录",
                targetBucket: "time",
                confidence: 0.82,
                payload: [
                    "name": t.name, "start": t.start, "end": t.end,
                    "category": t.category, "note": t.note, "ai_source": markSource
                ]
            )
            return
        }
        if let t = result.plan.tasks.first {
            dispatchAndCommit(
                rawText: text,
                recognizedType: "待办",
                targetBucket: "task",
                confidence: 0.78,
                payload: [
                    "title": t.title, "detail": t.detail,
                    "status": "待办",
                    "dueDate": t.dueDate,
                    "isAllDay": t.startTime.isEmpty ? "1" : "0",
                    "startTime": t.startTime,
                    "endTime": t.endTime,
                    "ai_source": markSource
                ]
            )
            return
        }
        if let n = result.plan.inboxEntries.first {
            let type = aiNormalizeKind(n.kind)
            dispatchAndCommit(
                rawText: text,
                recognizedType: type,
                targetBucket: aiDefaultBucket(for: type),
                confidence: 0.74,
                payload: [
                    "title": n.title, "detail": n.detail,
                    "status": "待处理", "ai_source": markSource
                ]
            )
            return
        }
        // 全部没识别出来 → 保底当"想法"
        dispatchAndCommit(
            rawText: text,
            recognizedType: "想法",
            targetBucket: "inbox",
            confidence: 0.70,
            payload: [
                "title": aiFallbackTitle(text),
                "detail": text,
                "status": "待处理",
                "ai_source": markSource
            ]
        )
    }

    /// addTurnDraft + commitTurn 的薄包装，失败写入 aiDebugMessage
    @discardableResult
    private func dispatchAndCommit(
        rawText: String,
        recognizedType: String,
        targetBucket: String,
        confidence: Double,
        payload: [String: String],
        moodScore: Int? = nil,
        feelingTags: [String] = []
    ) -> String {
        guard !isRecentDuplicateTurn(rawText: rawText, recognizedType: recognizedType, targetBucket: targetBucket, payload: payload) else {
            aiDebugMessage = nil
            return "跳过：最近 180 秒内已有同类重复记录"
        }
        guard let id = addTurnDraft(
            rawText: rawText,
            recognizedType: recognizedType,
            targetBucket: targetBucket,
            confidence: confidence,
            payload: payload,
            status: "draft",
            fixHint: "",
            moodScore: moodScore,
            feelingTags: feelingTags
        ) else { return "跳过：原文为空，未创建 turn" }
        if let err = commitTurn(id: id) {
            aiDebugMessage = err
            return "失败：\(err)"
        }
        return "已提交 turn=\(id.uuidString)"
    }

    private func isRecentDuplicateTurn(rawText: String, recognizedType: String, targetBucket: String, payload: [String: String]) -> Bool {
        let key = duplicateComparableText(rawText: rawText, targetBucket: targetBucket, payload: payload)
        guard !key.isEmpty else { return false }
        let now = Date()
        return turns.contains { turn in
            guard turn.recognizedType == recognizedType,
                  turn.targetBucket == targetBucket,
                  now.timeIntervalSince(turn.createdAt) <= 180 else {
                return false
            }
            return duplicateComparableText(rawText: turn.rawText, targetBucket: turn.targetBucket, payload: turn.payload) == key
        }
    }

    private func duplicateComparableText(rawText: String, targetBucket: String, payload: [String: String]) -> String {
        let value: String
        if targetBucket == "time" {
            value = [
                payload["name"] ?? "",
                payload["start"] ?? "",
                payload["end"] ?? "",
                payload["category"] ?? ""
            ].joined(separator: "|")
        } else {
            let detail = payload["detail"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            value = detail.isEmpty ? rawText : detail
        }
        return value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: " ", with: "")
    }

    private func aiNormalizeKind(_ raw: String) -> String {
        if raw.contains("感恩") { return "感恩" }
        if raw.contains("感受") || raw.contains("情绪") || raw.contains("Emotion") { return "感受" }
        if raw.contains("梦") { return "做梦" }
        return "想法"
    }

    private func aiDefaultBucket(for type: String) -> String {
        switch type {
        case "时间记录": return "time"
        case "待办": return "task"
        default: return "inbox"
        }
    }

    private func aiFallbackTitle(_ text: String) -> String {
        if text.count <= 18 { return text }
        return String(text.prefix(18)) + "…"
    }

    // MARK: - CSV 导出

    /// 在 [start, end] 闭区间内导出时间记录、随手记、打卡三个 CSV 文件到临时目录，返回文件 URL。
    /// 跨日时间块按数据库原样输出两行（拆分段），符合规划 Q15-3 = a。
    func exportCSVs(from start: Date, to end: Date) -> (timeURL: URL?, inboxURL: URL?, checkURL: URL?, errorMessage: String?) {
        let timeURL = buildTimeCSV(from: start, to: end)
        let inboxURL = buildInboxCSV(from: start, to: end)
        let checkURL = buildCheckCSV(from: start, to: end)
        if timeURL == nil && inboxURL == nil && checkURL == nil {
            return (nil, nil, nil, "所选区间没有可导出的内容")
        }
        return (timeURL, inboxURL, checkURL, nil)
    }

    // MARK: - 完整数据备份

    /// CloudKit 同步范围内的核心数据基础键名（不含 userId 后缀）。
    private static let backupKeyBases = [
        "ps.checks.byDate", "ps.time.byDate", "ps.tasks", "ps.turns",
        "ps.brain", "fields.daily", "fields.daily.initialized", "fields.daily.groups"
    ]

    /// 把核心数据打包成带版本的 JSON 备份。返回 nil 表示当前没有可备份的数据。
    func makeFullDataArchive() -> Data? {
        var payload: [String: Any] = [:]
        for base in Self.backupKeyBases {
            if let value = defaults.object(forKey: scopedKey(base)) {
                payload[base] = value
            }
        }
        guard !payload.isEmpty else { return nil }
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return DataArchive.makeJSON(payload: payload, appVersion: appVersion)
    }

    /// 生成完整备份文件，返回可分享的临时文件 URL。
    func exportFullDataFile() -> URL? {
        guard let data = makeFullDataArchive() else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        let name = "LifeOS-备份-\(f.string(from: Date())).json"
        return try? DataArchive.writeToTemporary(data, name: name)
    }

    private func buildTimeCSV(from start: Date, to end: Date) -> URL? {
        let map = defaults.dictionary(forKey: keyTime) as? [String: [[String: String]]] ?? [:]
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let startKey = f.string(from: start)
        let endKey = f.string(from: end)

        var rows: [[String]] = []
        for dateKey in map.keys.sorted() where dateKey >= startKey && dateKey <= endKey {
            let entries = (map[dateKey] ?? []).map(timeEntry(from:))
            for entry in entries {
                let duration = Self.durationMinutes(start: entry.start, end: entry.end)
                rows.append([
                    dateKey,
                    entry.name,
                    Self.userExtraNote(from: entry.extra),
                    entry.category,
                    entry.start,
                    entry.end,
                    duration.map(String.init) ?? ""
                ])
            }
        }
        guard !rows.isEmpty else { return nil }
        let csv = CSVExporter.makeCSV(
            header: ["日期", "事件名", "备注", "类别", "开始时间", "结束时间", "时长(分钟)"],
            rows: rows
        )
        let filename = "lifeos-time-\(startKey)_\(endKey).csv"
        return try? CSVExporter.writeToTemporary(name: filename, content: csv)
    }

    private func buildInboxCSV(from start: Date, to end: Date) -> URL? {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: start)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end

        let dt = DateFormatter()
        dt.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let startKey = f.string(from: start)
        let endKey = f.string(from: end)

        let filtered = turns
            .filter { $0.targetBucket == "inbox" }
            .filter { $0.createdAt >= dayStart && $0.createdAt < dayEnd }
            .sorted { $0.createdAt < $1.createdAt }

        guard !filtered.isEmpty else { return nil }

        let rows: [[String]] = filtered.map { turn in
            [
                dt.string(from: turn.createdAt),
                turn.recognizedType,
                turn.rawText,
                turn.moodScore.map(String.init) ?? "",
                turn.feelingTags.joined(separator: " · ")
            ]
        }
        let csv = CSVExporter.makeCSV(
            header: ["日期时间", "识别类型", "内容", "心情分", "情绪标签"],
            rows: rows
        )
        let filename = "lifeos-notes-\(startKey)_\(endKey).csv"
        return try? CSVExporter.writeToTemporary(name: filename, content: csv)
    }

    private func buildCheckCSV(from start: Date, to end: Date) -> URL? {
        let entries = currentCheckEntries()
        guard !entries.isEmpty else { return nil }

        let map = defaults.dictionary(forKey: keyChecks) as? [String: [String: Bool]] ?? [:]
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let startKey = f.string(from: start)
        let endKey = f.string(from: end)
        let calendar = Calendar.current

        var rows: [[String]] = []
        var cursor = calendar.startOfDay(for: start)
        let finalDay = calendar.startOfDay(for: end)
        while cursor <= finalDay {
            let dateKey = f.string(from: cursor)
            let day = map[dateKey] ?? [:]
            rows.append([dateKey] + entries.map { day[$0.title] == true ? "1" : "0" })
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        guard !rows.isEmpty else { return nil }
        let csv = CSVExporter.makeCSV(
            header: ["日期"] + entries.map(\.title),
            rows: rows
        )
        let filename = "lifeos-checks-\(startKey)_\(endKey).csv"
        return try? CSVExporter.writeToTemporary(name: filename, content: csv)
    }

    /// 把时间字符串 "HH:mm" / "24:00" 换算成相对零点的分钟数。
    private static func minutesSinceMidnight(_ clock: String) -> Int? {
        let parts = clock.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }

    private static func durationMinutes(start: String, end: String) -> Int? {
        guard let s = minutesSinceMidnight(start), let e = minutesSinceMidnight(end) else { return nil }
        return max(0, e - s)
    }

    /// 过滤掉 TimeEntryCrossDayKey 这些系统键之后，把剩余 extra 序列化成 "k=v ; k=v" 形式。
    private static func userExtraNote(from extra: [String: String]) -> String {
        let systemKeys: Set<String> = [
            TimeEntryCrossDayKey.groupID,
            TimeEntryCrossDayKey.role,
            TimeEntryCrossDayKey.startDateKey,
            TimeEntryCrossDayKey.endDateKey,
            TimeEntryCrossDayKey.start,
            TimeEntryCrossDayKey.end,
        ]
        let userPairs = extra
            .filter { !systemKeys.contains($0.key) }
            .sorted { $0.key < $1.key }
        // 单条用户字段（绝大多数情况就是「备注」）直接输出值；多条才退回 "k=v ; k=v" 区分。
        if userPairs.count == 1, let only = userPairs.first {
            return only.value
        }
        return userPairs.map { "\($0.key)=\($0.value)" }.joined(separator: " ; ")
    }
}
