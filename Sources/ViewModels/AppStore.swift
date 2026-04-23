import Foundation

struct PendingClarification {
    let originalText: String
    let hint: String
}

final class AppStore: ObservableObject {
    @Published var selectedDate = Date() { didSet { loadForSelectedDate() } }
    @Published var checkItems: [DailyCheckItem] = []
    @Published var timeEntries: [TimeEntry] = []
    @Published var inbox: [InboxNote] = []
    @Published var tasks: [TaskEntry] = []
    @Published var turns: [ConversationTurn] = []

    // MARK: - AI dispatch state (全局输入框用)
    @Published var isAILoading: Bool = false
    @Published var aiDebugMessage: String? = nil

    /// 上一轮 AI 追问的上下文：当 AI 返回 needsClarification 时，暂存原文与 hint。
    /// 用户下次提交时自动把两段拼起来发给 AI，避免"9 点到 10 点"这种裸时间丢失上下文。
    @Published var pendingClarification: PendingClarification? = nil

    private let defaults = UserDefaults.standard

    /// 当前登录用户的稳定 ID（Apple ID 的 `credential.user`）。
    /// 未登录时为 nil，此时读写落在全局 key（向后兼容老版本本地数据）。
    private var currentUserId: String? {
        let raw = defaults.string(forKey: "auth.userId") ?? ""
        return raw.isEmpty ? nil : raw
    }

    private func scopedKey(_ base: String) -> String {
        guard let uid = currentUserId else { return base }
        return "\(base).\(uid)"
    }

    private var keyChecks: String { scopedKey("ps.checks.byDate") }
    private var keyTime: String { scopedKey("ps.time.byDate") }
    private var keyInbox: String { scopedKey("ps.inbox") }
    private var keyTasks: String { scopedKey("ps.tasks") }
    private var keyTurns: String { scopedKey("ps.turns") }
    private var keyDailyFields: String { scopedKey("fields.daily") }
    private var keyDailyInitialized: String { scopedKey("fields.daily.initialized") }

    // 兼容旧版本（未按用户隔离）
    private let legacyKeyDailyFields = "fields.daily"
    private let legacyKeyDailyInitialized = "fields.daily.initialized"

    private let fallbackCheckTitles = ["吃药", "健康饮食", "感恩", "冥想", "写日记"]

    init() {
        loadInbox()
        loadTasks()
        loadTurns()
        loadForSelectedDate()
    }

    /// 登录 / 切换账号后调用，按当前 userId 重新装载所有数据
    func reloadForCurrentUser() {
        loadInbox()
        loadTasks()
        loadTurns()
        loadForSelectedDate()
    }

    /// 清空当前用户的所有数据（用于注销账户）。不影响其他用户。
    func wipeCurrentUserData() {
        [keyChecks, keyTime, keyInbox, keyTasks, keyTurns, keyDailyFields, keyDailyInitialized].forEach { defaults.removeObject(forKey: $0) }
        checkItems = []
        timeEntries = []
        inbox = []
        tasks = []
        turns = []
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
        timeEntries.remove(atOffsets: offsets)
        saveTimeForDate()
    }

    // MARK: - Inbox
    @discardableResult
    func addInbox(title: String, detail: String, kind: String = "Idea", status: String = "待整理", extra: [String: String] = [:]) -> UUID? {
        guard !title.isEmpty else { return nil }
        let entry = InboxNote(title: title, detail: detail, kind: kind, status: status, extra: extra)
        inbox.insert(entry, at: 0)
        saveInbox()
        return entry.id
    }

    func updateInbox(id: UUID, title: String, detail: String, kind: String, status: String, extra: [String: String] = [:]) {
        guard let idx = inbox.firstIndex(where: { $0.id == id }) else { return }
        inbox[idx].title = title
        inbox[idx].detail = detail
        inbox[idx].kind = kind
        inbox[idx].status = status
        inbox[idx].extra = extra
        saveInbox()
    }

    func markInboxDone(id: UUID) {
        guard let idx = inbox.firstIndex(where: { $0.id == id }) else { return }
        inbox[idx].status = "已整理"
        saveInbox()
    }

    func removeInbox(at offsets: IndexSet) {
        inbox.remove(atOffsets: offsets)
        saveInbox()
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
        isAllDay: Bool = true,
        startTime: String = "",
        endTime: String = "",
        location: String = ""
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
            isAllDay: isAllDay,
            startTime: startTime,
            endTime: endTime,
            location: location
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
        tasks[idx].status = (tasks[idx].status == "已完成") ? "待办" : "已完成"
        saveTasks()
    }

    /// 删除指定 id 的任务
    func removeTask(id: UUID) {
        tasks.removeAll { $0.id == id }
        saveTasks()
    }

    // MARK: - Daily check-in item management
    /// 新增打卡项目（追加到 fields.daily 末尾，按 title 去重）
    @discardableResult
    func addDailyCheckItem(_ title: String, tag: String = "默认") -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return false }
        let finalTag = cleanTag.isEmpty ? "默认" : cleanTag
        var entries = currentCheckEntries()
        guard !entries.contains(where: { $0.title == cleanTitle }) else { return false }
        entries.append((title: cleanTitle, tag: finalTag))
        defaults.set(encodeCheckEntries(entries), forKey: keyDailyFields)
        defaults.set(true, forKey: keyDailyInitialized)
        reloadFieldConfig()
        return true
    }

    /// 删除打卡项目
    func removeDailyCheckItem(_ title: String) {
        var entries = currentCheckEntries()
        entries.removeAll { $0.title == title }
        defaults.set(encodeCheckEntries(entries), forKey: keyDailyFields)
        defaults.set(true, forKey: keyDailyInitialized)
        reloadFieldConfig()
    }

    /// 给外部 UI 列出所有打卡项标题
    var dailyCheckTitles: [String] { currentCheckEntries().map { $0.title } }

    /// 给外部 UI 列出所有打卡项（含 tag）
    var dailyCheckEntries: [(title: String, tag: String)] { currentCheckEntries() }

    /// 历史出现过的全部 tag，按首次出现顺序
    var dailyCheckTags: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for e in currentCheckEntries() where !seen.contains(e.tag) {
            seen.insert(e.tag)
            ordered.append(e.tag)
        }
        return ordered
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

    @discardableResult
    func commitTurn(id: UUID) -> String? {
        guard let idx = turns.firstIndex(where: { $0.id == id }) else { return "记录不存在" }
        var turn = turns[idx]

        switch turn.targetBucket {
        case "time":
            let name = turn.payload["name"] ?? "时间块"
            let start = turn.payload["start"] ?? ""
            let end = turn.payload["end"] ?? ""
            let category = turn.payload["category"] ?? "其他"
            let note = turn.payload["note"] ?? ""
            if start.isEmpty || end.isEmpty {
                turns[idx].status = "needs_fix"
                turns[idx].fixHint = "时间记录缺少开始/结束时间，请先补全再写入。"
                saveTurns()
                return turns[idx].fixHint
            }
            if let err = addTimeEntry(name: name, start: start, end: end, category: category, extra: note.isEmpty ? [:] : ["备注": note]) {
                turns[idx].status = "needs_fix"
                turns[idx].fixHint = err
                saveTurns()
                return err
            }
            if let inserted = timeEntries.first {
                turn.payload["committedTimeEntryID"] = inserted.id.uuidString
                turn.payload["committedDateKey"] = selectedDateKey
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
                date: turn.payload["date"] ?? selectedDateKey
            )
            if let taskID {
                turn.payload["committedTaskID"] = taskID.uuidString
            }

        default: // inbox
            let title = turn.payload["title"] ?? summarizeTurnTitle(turn.rawText)
            let inboxID = addInbox(
                title: title,
                detail: turn.payload["detail"] ?? turn.rawText,
                kind: turn.recognizedType,
                status: turn.payload["status"] ?? "待处理",
                extra: [:]
            )
            if let inboxID {
                turn.payload["committedInboxID"] = inboxID.uuidString
            }
        }

        turn.status = "committed"
        turn.fixHint = ""
        turns[idx] = turn
        saveTurns()
        return nil
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
            guard let rawID = turn.payload["committedInboxID"], let id = UUID(uuidString: rawID) else { return }
            inbox.removeAll { $0.id == id }
            saveInbox()
        }
    }

    private func removeTimeEntryByID(_ id: UUID, dateKey: String?) {
        var map = defaults.dictionary(forKey: keyTime) as? [String: [[String: String]]] ?? [:]

        if let key = dateKey {
            if var day = map[key] {
                day.removeAll { ($0["id"] ?? "") == id.uuidString }
                map[key] = day
                defaults.set(map, forKey: keyTime)
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
        }

        if selectedDateKey == (dateKey ?? selectedDateKey) {
            loadTimeForDate()
        }
    }

    // MARK: - Load/Save
    private func loadForSelectedDate() {
        loadChecksForDate()
        loadTimeForDate()
    }

    private func loadChecksForDate() {
        let map = defaults.dictionary(forKey: keyChecks) as? [String: [String: Bool]] ?? [:]
        let day = map[selectedDateKey] ?? [:]
        checkItems = currentCheckEntries().map { .init(title: $0.title, done: day[$0.title] ?? false, tag: $0.tag) }
    }

    private func saveChecksForDate() {
        var map = defaults.dictionary(forKey: keyChecks) as? [String: [String: Bool]] ?? [:]
        let day = Dictionary(uniqueKeysWithValues: checkItems.map { ($0.title, $0.done) })
        map[selectedDateKey] = day
        defaults.set(map, forKey: keyChecks)
    }

    private func loadTimeForDate() {
        let map = defaults.dictionary(forKey: keyTime) as? [String: [[String: String]]] ?? [:]
        let day = map[selectedDateKey] ?? []
        timeEntries = day.map {
            let extra = decodeExtra($0["extra"])
            let rawCategory = $0["category"] ?? ""
            let id = UUID(uuidString: $0["id"] ?? "") ?? UUID()
            return TimeEntry(id: id, name: $0["name"] ?? "", start: $0["start"] ?? "", end: $0["end"] ?? "", category: normalizeLegacyTimeCategory(rawCategory), extra: extra)
        }
        if timeEntries.isEmpty && selectedDateKey == currentDateKey() {
            timeEntries = [.init(name: "PRD评审", start: "14:00", end: "15:20", category: "工作")]
        }
    }

    private func saveTimeForDate() {
        var map = defaults.dictionary(forKey: keyTime) as? [String: [[String: String]]] ?? [:]
        map[selectedDateKey] = timeEntries.map { ["id": $0.id.uuidString, "name": $0.name, "start": $0.start, "end": $0.end, "category": $0.category, "extra": encodeExtra($0.extra)] }
        defaults.set(map, forKey: keyTime)
    }

    private func loadInbox() {
        let arr = defaults.array(forKey: keyInbox) as? [[String: String]] ?? []
        inbox = arr.map {
            let id = UUID(uuidString: $0["id"] ?? "") ?? UUID()
            return InboxNote(id: id, title: $0["title"] ?? "", detail: $0["detail"] ?? "", kind: $0["kind"] ?? "Idea", status: $0["status"] ?? "待整理", extra: decodeExtra($0["extra"]))
        }
        if inbox.isEmpty {
            inbox = [.init(title: "把录入流程缩短到2步", detail: "先收集后整理", kind: "Idea", status: "待整理")]
        }
    }

    private func saveInbox() {
        let arr = inbox.map { ["id": $0.id.uuidString, "title": $0.title, "detail": $0.detail, "kind": $0.kind, "status": $0.status, "extra": encodeExtra($0.extra)] }
        defaults.set(arr, forKey: keyInbox)
    }

    private func loadTasks() {
        let arr = defaults.array(forKey: keyTasks) as? [[String: String]] ?? []
        tasks = arr.map {
            let id = UUID(uuidString: $0["id"] ?? "") ?? UUID()
            // 兼容老记录：没有 isAllDay 字段时按全天处理
            let allDayRaw = $0["isAllDay"]
            let isAllDay = allDayRaw == nil ? true : (allDayRaw == "1")
            return TaskEntry(
                id: id,
                title: $0["title"] ?? "",
                detail: $0["detail"] ?? "",
                status: $0["status"] ?? "待办",
                priority: $0["priority"] ?? "",
                dueDate: $0["dueDate"] ?? "",
                date: $0["date"] ?? currentDateKey(),
                isAllDay: isAllDay,
                startTime: $0["startTime"] ?? "",
                endTime: $0["endTime"] ?? "",
                location: $0["location"] ?? ""
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
                "isAllDay": $0.isAllDay ? "1" : "0",
                "startTime": $0.startTime,
                "endTime": $0.endTime,
                "location": $0.location
            ]
        }
        defaults.set(arr, forKey: keyTasks)
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
                reviewStatus: row["reviewStatus"] ?? "pending"
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
                "reviewStatus": turn.reviewStatus
            ]
        }
        defaults.set(arr, forKey: keyTurns)
    }

    // 当前阶段：字段配置锁定为 Notion 结构，不开放自定义
    var timeFieldNames: [String] { ["一句话描述", "开始时间", "结束时间", "模块分类", "备注"] }
    var inboxFieldNames: [String] { ["标题", "详情", "类型", "状态", "心情评估", "感受词"] }
    var reviewFieldNames: [String] { ["本期复盘", "本期总结", "下期展望"] }

    var timeFieldTypes: [String] { ["text", "time", "time", "select", "text"] }
    var inboxFieldTypes: [String] { ["text", "text", "select", "select", "number", "text"] }
    var timeFieldOptions: [String: [String]] {
        ["模块分类": ["睡觉", "社交", "运动", "其他", "娱乐", "工作", "学习"]]
    }
    var inboxFieldOptions: [String: [String]] {
        [
            "类型": ["Idea", "Todo", "Emotion", "Decision", "Question", "Reference"],
            "状态": ["待整理", "已整理"]
        ]
    }

    func reloadFieldConfig() {
        loadChecksForDate()
        objectWillChange.send()
    }

    var totalFocusMinutes: Int {
        timeEntries.reduce(0) { $0 + minutesBetween(start: $1.start, end: $1.end) }
    }

    var totalFocusText: String {
        let h = totalFocusMinutes / 60
        let m = totalFocusMinutes % 60
        return "\(h)h\(m)m"
    }

    var weekDoneRateText: String {
        let map = defaults.dictionary(forKey: keyChecks) as? [String: [String: Bool]] ?? [:]
        let keys = recentDateKeys(days: 7)
        var done = 0, total = 0
        for k in keys {
            let day = map[k] ?? [:]
            total += currentCheckTitles().count
            done += day.values.filter { $0 }.count
        }
        guard total > 0 else { return "0%" }
        return "\((done * 100) / total)%"
    }

    var weekFocusText: String {
        let map = defaults.dictionary(forKey: keyTime) as? [String: [[String: String]]] ?? [:]
        let keys = recentDateKeys(days: 7)
        let total = keys.flatMap { map[$0] ?? [] }.reduce(0) { sum, e in
            sum + minutesBetween(start: e["start"] ?? "", end: e["end"] ?? "")
        }
        return "\(total / 60)h\(total % 60)m"
    }

    var weekInboxCountText: String {
        "\(inbox.count)"
    }

    var exportJSONString: String {
        let payload: [String: Any] = [
            "selectedDate": selectedDateKey,
            "checkItems": checkItems.map { ["title": $0.title, "done": $0.done] },
            "timeEntries": timeEntries.map { ["name": $0.name, "start": $0.start, "end": $0.end, "category": $0.category, "extra": $0.extra] },
            "inbox": inbox.map { ["title": $0.title, "detail": $0.detail, "status": $0.status, "kind": $0.kind, "extra": $0.extra] },
            "tasks": tasks.map { ["title": $0.title, "detail": $0.detail, "status": $0.status, "priority": $0.priority, "dueDate": $0.dueDate, "date": $0.date] }
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
        for n in inbox {
            lines.append("inbox,\(selectedDateKey),\(escapeCSV(n.title)),,,,\(escapeCSV(n.status)),\(escapeCSV(n.detail))")
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
        var inboxArr = defaults.array(forKey: keyInbox) as? [[String: String]] ?? []
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

            case "inbox":
                guard !nameOrTitle.isEmpty else { continue }
                let item: [String: String] = [
                    "title": nameOrTitle,
                    "detail": detail,
                    "kind": category.isEmpty ? "Idea" : category,
                    "status": status.isEmpty ? "待整理" : status,
                    "extra": "{}"
                ]
                inboxArr.insert(item, at: 0)
                importedCount += 1

            case "task":
                guard !nameOrTitle.isEmpty else { continue }
                let item: [String: String] = [
                    "title": nameOrTitle,
                    "detail": detail,
                    "status": status.isEmpty ? "待办" : status,
                    "priority": "",
                    "dueDate": "",
                    "date": date
                ]
                taskArr.insert(item, at: 0)
                importedCount += 1

            default:
                continue
            }
        }

        if importedCount == 0 { return "未识别到可导入记录，请检查 CSV 列格式" }

        defaults.set(timeMap, forKey: keyTime)
        defaults.set(inboxArr, forKey: keyInbox)
        defaults.set(taskArr, forKey: keyTasks)

        loadForSelectedDate()
        loadInbox()
        loadTasks()
        objectWillChange.send()
        return nil
    }

    private func minutesBetween(start: String, end: String) -> Int {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        guard let s = f.date(from: start), let e = f.date(from: end) else { return 0 }
        let mins = Int(e.timeIntervalSince(s) / 60)
        return max(mins, 0)
    }

    private func validateTimeInput(name: String, start: String, end: String) -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "事件名称不能为空" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        guard let s = f.date(from: start), let e = f.date(from: end) else {
            return "时间格式应为 HH:mm（例如 09:30）"
        }
        if e <= s { return "结束时间必须晚于开始时间" }
        return nil
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
            raw = fallbackCheckTitles.joined(separator: ",")
        } else {
            raw = ""
        }
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let entries: [(String, String)] = parts.map { item in
            if let sep = item.firstIndex(of: "|") {
                let title = String(item[..<sep]).trimmingCharacters(in: .whitespaces)
                let tag = String(item[item.index(after: sep)...]).trimmingCharacters(in: .whitespaces)
                return (title, tag.isEmpty ? "默认" : tag)
            }
            return (item, "默认")
        }.filter { !$0.0.isEmpty }
        // 已初始化但为空 → 如实返回空；未初始化且 fallback 也空 → 返回空
        if entries.isEmpty && !initialized {
            return fallbackCheckTitles.map { ($0, "默认") }
        }
        return entries
    }

    private func encodeCheckEntries(_ entries: [(title: String, tag: String)]) -> String {
        entries.map { "\($0.title)|\($0.tag)" }.joined(separator: ",")
    }

    private func parseFields(key: String, fallback: [String]) -> [String] {
        let raw = defaults.string(forKey: key) ?? fallback.joined(separator: ",")
        let arr = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return arr.isEmpty ? fallback : arr
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

    private func parseOptionMap(key: String) -> [String: [String]] {
        // 格式：字段名:选项1|选项2;字段名2:选项A|选项B
        let raw = defaults.string(forKey: key) ?? ""
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [:] }
        var map: [String: [String]] = [:]
        for pair in raw.split(separator: ";") {
            let parts = pair.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let k = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let vals = parts[1].split(separator: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if !k.isEmpty, !vals.isEmpty { map[k] = vals }
        }
        return map
    }

    private func recentDateKeys(days: Int) -> [String] {
        let cal = Calendar.current
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return (0..<days).compactMap { d in
            cal.date(byAdding: .day, value: -d, to: Date()).map { f.string(from: $0) }
        }
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

    func hasRecordTrace(on date: Date) -> Bool {
        checkDoneCount(on: date) > 0 || timeEntryCount(on: date) > 0
    }

    private func dateKey(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func normalizeLegacyTimeCategory(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value == "产品" { return "工作" }
        return value
    }

    // MARK: - AI Dispatch Pipeline
    // 全局 AI 输入框调用这些方法；原本住在 QuickCaptureView 的私有实现搬进来。

    /// 已知的记录类型（note bucket 内部的子类型）
    private let aiIntentOptions = ["想法", "感受", "感恩", "做梦"]

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
                    if resp.records.isEmpty {
                        if let hint = resp.needsClarification {
                            // 保存上下文，等用户补充后再次提交时合并
                            self.pendingClarification = PendingClarification(
                                originalText: effectiveText,
                                hint: hint
                            )
                            self.aiDebugMessage = "还差一点：\(hint)"
                        } else {
                            self.pendingClarification = nil
                            self.aiDebugMessage = "AI 未识别内容 · 已走本地兜底"
                            self.dispatchLocalFallback(effectiveText, markSource: "local")
                        }
                        return
                    }
                    // 解析成功：清掉追问上下文
                    self.pendingClarification = nil
                    // 感恩/感受：同一次输入 AI 拆成了多条的话，合并成一条保留在同一 turn 里
                    // （"今天感恩 A，感恩 B，感恩 C" 不应该变成 3 条独立记录）
                    let mergedRecords = self.mergeSameTypeNoteRecords(resp.records)
                    for rec in mergedRecords {
                        self.commitAIRecord(rec, rawText: effectiveText)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isAILoading = false
                    self.aiDebugMessage = "AI 调用失败：\(error.localizedDescription.prefix(80)) · 已走本地兜底"
                    self.dispatchLocalFallback(effectiveText, markSource: "local")
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
    private func commitAIRecord(_ rec: AIParsedRecord, rawText: String) {
        switch rec.bucket {
        case "time":
            let name = rec.eventName ?? "时间块"
            let start = rec.startTime ?? ""
            let end = rec.endTime ?? ""
            let category = rec.module ?? "✨ 其他"
            let note = rec.notes ?? ""
            dispatchAndCommit(
                rawText: rawText,
                recognizedType: "时间记录",
                targetBucket: "time",
                confidence: 0.95,
                payload: [
                    "name": name, "start": start, "end": end,
                    "category": category, "note": note, "ai_source": "ai"
                ]
            )

        case "task":
            let title = rec.title?.isEmpty == false ? rec.title! : (rec.eventName ?? aiFallbackTitle(rawText))
            let detail = rec.details ?? rec.notes ?? ""
            dispatchAndCommit(
                rawText: rawText,
                recognizedType: "待办",
                targetBucket: "task",
                confidence: 0.95,
                payload: [
                    "title": title,
                    "detail": detail,
                    "status": "待办",
                    "dueDate": rec.date ?? "",
                    "ai_source": "ai"
                ]
            )

        default:
            let rawType = rec.type ?? "想法"
            let type = aiIntentOptions.contains(rawType) ? rawType : "想法"
            let title = rec.title?.isEmpty == false ? rec.title! : aiFallbackTitle(rawText)
            let detail = rec.details ?? rawText
            dispatchAndCommit(
                rawText: rawText,
                recognizedType: type,
                targetBucket: "inbox",
                confidence: 0.95,
                payload: [
                    "title": title, "detail": detail,
                    "status": "待处理", "ai_source": "ai"
                ],
                moodScore: rec.mood,
                feelingTags: rec.feelings ?? []
            )
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
                    "status": "待办", "ai_source": markSource
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
    private func dispatchAndCommit(
        rawText: String,
        recognizedType: String,
        targetBucket: String,
        confidence: Double,
        payload: [String: String],
        moodScore: Int? = nil,
        feelingTags: [String] = []
    ) {
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
        ) else { return }
        if let err = commitTurn(id: id) {
            aiDebugMessage = err
        }
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
}
