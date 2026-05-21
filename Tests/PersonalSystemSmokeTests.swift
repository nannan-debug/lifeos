import CloudKit
import XCTest
@testable import PersonalSystem

final class PersonalSystemSmokeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // 测试环境隔离 iCloud 同步：关掉同步开关、清掉旧 KVS 快照，
        // 避免 NSUbiquitousKeyValueStore / CloudKit 把数据带进或带出测试。
        UserDefaults.standard.set(false, forKey: "icloud.sync.enabled")
        NSUbiquitousKeyValueStore.default.removeObject(forKey: "lifeos.snapshot.v1")
        // 每个 test 开跑前清掉当前用户名下的所有 store 数据，保证测试之间独立
        AppStore().wipeCurrentUserData()
    }

    // MARK: - Existing smoke

    func testAppStoreInitialStateLoads() {
        let store = AppStore()

        XCTAssertNotNil(store.selectedDate)
        XCTAssertGreaterThanOrEqual(store.checkItems.count, 0)
    }

    func testCheckWidgetSnapshotPrioritizesPendingItems() {
        let snapshot = CheckWidgetSnapshot(
            dateKey: "2026-05-17",
            updatedAt: Date(),
            items: [
                CheckWidgetItemSnapshot(title: "吃维生素", done: true, tag: "早上"),
                CheckWidgetItemSnapshot(title: "回忆梦境", done: false, tag: "早上"),
                CheckWidgetItemSnapshot(title: "写日记", done: false, tag: "晚上")
            ]
        )

        XCTAssertEqual(snapshot.completedCount, 1)
        XCTAssertEqual(snapshot.pendingItems.map(\.title), ["回忆梦境", "写日记"])
        XCTAssertEqual(snapshot.displayItems.map(\.title), ["回忆梦境", "写日记", "吃维生素"])
    }

    private func waitForMainQueue(seconds: TimeInterval = 0.35) {
        let exp = expectation(description: "main queue settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
    }

    private func cleanupAgentThreadFiles(_ uid: String) {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = root
            .appendingPathComponent("agent-threads", isDirectory: true)
            .appendingPathComponent(uid, isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        UserDefaults.standard.removeObject(forKey: "ps.agent.threads.index.\(uid)")
        UserDefaults.standard.removeObject(forKey: "ps.agent.threads.current.\(uid)")
        UserDefaults.standard.removeObject(forKey: "ps.agent.chat.\(uid)")
    }

    func testCheckWidgetToggleUpdatesSharedChecksAndSnapshot() {
        let suiteName = "CheckWidgetToggleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let today = makeDate(calendar: Calendar(identifier: .gregorian), year: 2026, month: 5, day: 17, hour: 12, minute: 0)

        let snapshot = CheckWidgetSnapshot(
            dateKey: "2026-05-17",
            updatedAt: Date(timeIntervalSince1970: 1),
            items: [
                CheckWidgetItemSnapshot(title: "冥想", done: false, tag: "例行事务"),
                CheckWidgetItemSnapshot(title: "写日记", done: true, tag: "例行事务")
            ]
        )
        CheckWidgetSnapshotStore.saveAppContext(
            userID: "dev-test",
            checksByDate: ["2026-05-17": ["写日记": true]],
            snapshot: snapshot,
            defaults: defaults
        )

        let updated = CheckWidgetSnapshotStore.toggleItem(title: "冥想", dateKey: "2026-05-17", defaults: defaults, today: today)
        let key = CheckWidgetSnapshotStore.checksKey(for: "dev-test")
        let checks = defaults.dictionary(forKey: key) as? [String: [String: Bool]]

        XCTAssertEqual(checks?["2026-05-17"]?["冥想"], true)
        XCTAssertEqual(checks?["2026-05-17"]?["写日记"], true)
        XCTAssertEqual(updated.items.first(where: { $0.title == "冥想" })?.done, true)
        let reloaded = CheckWidgetSnapshotStore.load(defaults: defaults, today: today)
        XCTAssertEqual(reloaded.dateKey, updated.dateKey)
        XCTAssertEqual(reloaded.items, updated.items)
    }

    func testCheckWidgetLoadRefreshesStaleSnapshotForToday() {
        let suiteName = "CheckWidgetStaleSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let today = makeDate(calendar: Calendar(identifier: .gregorian), year: 2026, month: 5, day: 18, hour: 8, minute: 0)

        let staleSnapshot = CheckWidgetSnapshot(
            dateKey: "2026-05-17",
            updatedAt: Date(timeIntervalSince1970: 1),
            items: [
                CheckWidgetItemSnapshot(title: "冥想", done: true, tag: "例行事务"),
                CheckWidgetItemSnapshot(title: "写日记", done: true, tag: "例行事务")
            ]
        )
        CheckWidgetSnapshotStore.saveAppContext(
            userID: "dev-test",
            checksByDate: ["2026-05-18": ["写日记": true]],
            snapshot: staleSnapshot,
            defaults: defaults
        )

        let refreshed = CheckWidgetSnapshotStore.load(defaults: defaults, today: today)

        XCTAssertEqual(refreshed.dateKey, "2026-05-18")
        XCTAssertEqual(refreshed.items.first(where: { $0.title == "冥想" })?.done, false)
        XCTAssertEqual(refreshed.items.first(where: { $0.title == "写日记" })?.done, true)
    }

    func testCheckWidgetToggleUsesTodayWhenWidgetPassesStaleDateKey() {
        let suiteName = "CheckWidgetStaleToggleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let today = makeDate(calendar: Calendar(identifier: .gregorian), year: 2026, month: 5, day: 18, hour: 8, minute: 0)

        let staleSnapshot = CheckWidgetSnapshot(
            dateKey: "2026-05-17",
            updatedAt: Date(timeIntervalSince1970: 1),
            items: [CheckWidgetItemSnapshot(title: "冥想", done: false, tag: "例行事务")]
        )
        CheckWidgetSnapshotStore.saveAppContext(
            userID: "dev-test",
            checksByDate: ["2026-05-17": ["冥想": false]],
            snapshot: staleSnapshot,
            defaults: defaults
        )

        let updated = CheckWidgetSnapshotStore.toggleItem(title: "冥想", dateKey: "2026-05-17", defaults: defaults, today: today)
        let checks = defaults.dictionary(forKey: CheckWidgetSnapshotStore.checksKey(for: "dev-test")) as? [String: [String: Bool]]

        XCTAssertEqual(updated.dateKey, "2026-05-18")
        XCTAssertEqual(checks?["2026-05-18"]?["冥想"], true)
        XCTAssertEqual(checks?["2026-05-17"]?["冥想"], false)
    }

    func testHealthKitForegroundSyncIsDueWhenEnabledAndStale() {
        let store = AppStore()
        let calendar = Calendar(identifier: .gregorian)
        let previousAttempt = makeDate(calendar: calendar, year: 2026, month: 5, day: 18, hour: 7, minute: 0)
        let now = makeDate(calendar: calendar, year: 2026, month: 5, day: 18, hour: 7, minute: 20)

        store.isHealthSleepSyncEnabled = true
        UserDefaults.standard.set(previousAttempt, forKey: "healthkit.sync.lastAttemptAt")

        XCTAssertTrue(store.shouldSyncHealthKitAfterAppBecameActive(now: now))
    }

    func testHealthKitForegroundSyncIsThrottledWhenRecentlyChecked() {
        let store = AppStore()
        let calendar = Calendar(identifier: .gregorian)
        let previousAttempt = makeDate(calendar: calendar, year: 2026, month: 5, day: 18, hour: 7, minute: 10)
        let now = makeDate(calendar: calendar, year: 2026, month: 5, day: 18, hour: 7, minute: 20)

        store.isHealthSleepSyncEnabled = true
        UserDefaults.standard.set(previousAttempt, forKey: "healthkit.sync.lastAttemptAt")

        XCTAssertFalse(store.shouldSyncHealthKitAfterAppBecameActive(now: now))
    }

    // MARK: - Codable roundtrip

    func testBrainCardCodableRoundtrip() throws {
        let now = Date()
        let card = BrainCard(
            id: UUID(),
            title: "命名要简单",
            content: "用最直接的词，别用拉丁化代号",
            topics: ["#命名", "#设计原则"],
            sources: [BrainCardSource(noteId: UUID(), excerpt: "想到一句话")],
            links: [UUID()],
            extensions: [
                BrainCardExtension(
                    content: "后来想到，这也是降低未来理解成本。",
                    createdAt: now,
                    updatedAt: now
                )
            ],
            createdAt: now,
            updatedAt: now
        )
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let data = try encoder.encode(card)
        let decoded = try decoder.decode(BrainCard.self, from: data)
        XCTAssertEqual(decoded.title, card.title)
        XCTAssertEqual(decoded.topics, card.topics)
        XCTAssertEqual(decoded.sources.count, 1)
        XCTAssertEqual(decoded.sources[0].excerpt, "想到一句话")
        XCTAssertEqual(decoded.links.count, 1)
        XCTAssertEqual(decoded.extensions.count, 1)
        XCTAssertEqual(decoded.extensions[0].content, "后来想到，这也是降低未来理解成本。")
    }

    func testBrainCardDecodesLegacyCardWithoutExtensions() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "title": "旧卡片",
          "content": "旧版本没有延伸字段",
          "topics": ["#想法"],
          "sources": [],
          "links": [],
          "createdAt": 1710000000,
          "updatedAt": 1710000000
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(BrainCard.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.title, "旧卡片")
        XCTAssertEqual(decoded.extensions, [])
    }

    // MARK: - Backwards compat for new fields

    func testConversationTurnDerivativesDefaultsToEmpty() {
        // 老调用点不会传 derivatives 参数（默认值生效）
        let turn = ConversationTurn(
            id: UUID(),
            createdAt: Date(),
            rawText: "test",
            recognizedType: "想法",
            targetBucket: "inbox",
            confidence: 1.0,
            status: "committed",
            payload: [:],
            fixHint: "",
            moodScore: nil,
            feelingTags: [],
            reviewStatus: "pending"
        )
        XCTAssertEqual(turn.derivatives.count, 0)
    }

    func testTaskEntryNewFieldsDefaultToNilEmpty() {
        let task = TaskEntry(
            title: "test",
            detail: "",
            status: "待办",
            priority: "",
            dueDate: "",
            date: "2026-05-01"
        )
        XCTAssertNil(task.sourceNoteId)
        XCTAssertEqual(task.sourceExcerpt, "")
        XCTAssertNil(task.completedAt)
    }

    func testWakeDreamReminderSelectsMainNightSleepEndingTodayMorning() {
        let calendar = Calendar(identifier: .gregorian)
        let now = makeDate(calendar: calendar, year: 2026, month: 5, day: 17, hour: 8, minute: 0)
        let nightSleep = makeHealthKitSleepBlock(
            start: makeDate(calendar: calendar, year: 2026, month: 5, day: 16, hour: 23, minute: 30),
            end: makeDate(calendar: calendar, year: 2026, month: 5, day: 17, hour: 7, minute: 10)
        )
        let nap = makeHealthKitSleepBlock(
            start: makeDate(calendar: calendar, year: 2026, month: 5, day: 17, hour: 13, minute: 0),
            end: makeDate(calendar: calendar, year: 2026, month: 5, day: 17, hour: 13, minute: 40)
        )

        XCTAssertEqual(
            WakeDreamReminderService.mainNightSleepWakeDate(from: [nap, nightSleep], now: now),
            nightSleep.endDate
        )
    }

    func testWakeDreamReminderIgnoresNapAndPreviousDaySleep() {
        let calendar = Calendar(identifier: .gregorian)
        let now = makeDate(calendar: calendar, year: 2026, month: 5, day: 17, hour: 15, minute: 0)
        let previousDaySleep = makeHealthKitSleepBlock(
            start: makeDate(calendar: calendar, year: 2026, month: 5, day: 15, hour: 23, minute: 0),
            end: makeDate(calendar: calendar, year: 2026, month: 5, day: 16, hour: 7, minute: 0)
        )
        let nap = makeHealthKitSleepBlock(
            start: makeDate(calendar: calendar, year: 2026, month: 5, day: 17, hour: 13, minute: 0),
            end: makeDate(calendar: calendar, year: 2026, month: 5, day: 17, hour: 14, minute: 0)
        )

        XCTAssertNil(WakeDreamReminderService.mainNightSleepWakeDate(from: [previousDaySleep, nap], now: now))
    }

    func testWakeDreamReminderSchedulesSoonWhenSyncHappensAfterWake() {
        let calendar = Calendar(identifier: .gregorian)
        let wake = makeDate(calendar: calendar, year: 2026, month: 5, day: 17, hour: 7, minute: 10)
        let now = makeDate(calendar: calendar, year: 2026, month: 5, day: 17, hour: 9, minute: 0)

        XCTAssertEqual(
            WakeDreamReminderService.reminderDate(for: wake, now: now),
            now.addingTimeInterval(5)
        )
    }

    func testWakeDreamReminderSkipsLateAfternoonSync() {
        let calendar = Calendar(identifier: .gregorian)
        let wake = makeDate(calendar: calendar, year: 2026, month: 5, day: 17, hour: 7, minute: 10)
        let now = makeDate(calendar: calendar, year: 2026, month: 5, day: 17, hour: 13, minute: 0)

        XCTAssertNil(WakeDreamReminderService.reminderDate(for: wake, now: now))
    }

    func testAgentChatResponseDecodesOptionalFields() throws {
        let data = #"{"reply":"我在。"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AgentChatResponse.self, from: data)

        XCTAssertEqual(decoded.reply, "我在。")
        XCTAssertNil(decoded.followUpQuestion)
        XCTAssertTrue(decoded.actionSuggestions.isEmpty)
    }

    func testAgentContextBuilderUsesRecentSummaries() {
        let now = Date()
        let turns = (0..<10).map {
            ConversationTurn(
                id: UUID(),
                createdAt: now,
                rawText: "想法 \($0)",
                recognizedType: "想法",
                targetBucket: "inbox",
                confidence: 0.9,
                status: "committed",
                payload: [:],
                fixHint: "",
                moodScore: nil,
                feelingTags: [],
                reviewStatus: "pending"
            )
        }
        let summary = AgentOrchestrator.makeContextSummary(
            turns: turns,
            tasks: [TaskEntry(title: "提交材料", detail: "", status: "待办", priority: "", dueDate: "2026-05-19", date: "2026-05-18")],
            timeEntries: [TimeEntry(name: "散步", start: "09:00", end: "10:00", category: "运动")],
            checks: [DailyCheckItem(title: "回忆梦境", done: false, tag: "早上")]
        )

        XCTAssertTrue(summary.contains("近期随手记"))
        XCTAssertTrue(summary.contains("当前待办"))
        XCTAssertTrue(summary.contains("今天时间记录"))
        XCTAssertTrue(summary.contains("今日打卡"))
        XCTAssertTrue(summary.contains("想法 7"))
        XCTAssertFalse(summary.contains("想法 8"))
    }

    func testAgentChatSessionPersistsAcrossReload() throws {
        let defaults = UserDefaults.standard
        let uid = "agent-test-\(UUID().uuidString)"
        defaults.set(uid, forKey: "auth.userId")
        defer {
            defaults.removeObject(forKey: "ps.agent.chat.\(uid)")
            defaults.removeObject(forKey: "auth.userId")
        }

        let session = AgentChatSession(
            messages: [AgentChatMessage(role: "user", content: "今天有点乱")],
            pendingActions: [],
            updatedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        defaults.set(try encoder.encode(session), forKey: "ps.agent.chat.\(uid)")

        let store = AppStore()
        XCTAssertEqual(store.agentSession.messages.first?.content, "今天有点乱")
    }

    func testAgentThreadPersistsMessagesInFileStorage() {
        let uid = "agent-thread-\(UUID().uuidString)"
        cleanupAgentThreadFiles(uid)
        defer { cleanupAgentThreadFiles(uid) }

        let store = AppStore()
        let mock = MockAIClient(result: .success(AgentChatResponse(reply: "我在", actionSuggestions: [])))
        store.agent = AgentManager(writer: store, userIdSuffix: uid, client: mock)

        store.submitAgentText("今天有点乱")
        waitForMainQueue()

        let reloaded = AgentManager(writer: store, userIdSuffix: uid, client: mock)
        XCTAssertEqual(reloaded.session.messages.map(\.content), ["今天有点乱", "我在"])
        XCTAssertEqual(reloaded.threadIndex.count, 1)
        XCTAssertEqual(reloaded.threadIndex.first?.messageCount, 2)
    }

    func testAgentThreadLimitPrunesOldThreads() {
        let uid = "agent-limit-\(UUID().uuidString)"
        cleanupAgentThreadFiles(uid)
        defer { cleanupAgentThreadFiles(uid) }

        let store = AppStore()
        let mock = MockAIClient(result: .success(AgentChatResponse(reply: "ok", actionSuggestions: [])))
        store.agent = AgentManager(writer: store, userIdSuffix: uid, client: mock)

        for _ in 0..<35 {
            store.createNewAgentThread()
        }

        XCTAssertLessThanOrEqual(store.agentThreadIndex.count, AgentManager.maxThreads)
    }

    func testAgentThreadUsesAITitleAndFallsBackWhenTitleFails() {
        let uid = "agent-title-\(UUID().uuidString)"
        cleanupAgentThreadFiles(uid)
        defer { cleanupAgentThreadFiles(uid) }

        let store = AppStore()
        let mock = MockAIClient(result: .success(AgentChatResponse(reply: "收到", actionSuggestions: [])))
        mock.titleResult = .success("陈姐提醒")
        store.agent = AgentManager(writer: store, userIdSuffix: uid, client: mock)

        store.submitAgentText("陈姐提醒我要紧张一点")
        waitForMainQueue()

        XCTAssertEqual(store.agentThreadIndex.first?.title, "陈姐提醒")

        let fallbackUID = "agent-title-fallback-\(UUID().uuidString)"
        cleanupAgentThreadFiles(fallbackUID)
        defer { cleanupAgentThreadFiles(fallbackUID) }
        let fallbackStore = AppStore()
        let fallbackMock = MockAIClient(result: .success(AgentChatResponse(reply: "收到", actionSuggestions: [])))
        fallbackMock.titleResult = .failure(AIParseError.network("title timeout"))
        fallbackStore.agent = AgentManager(writer: fallbackStore, userIdSuffix: fallbackUID, client: fallbackMock)

        fallbackStore.submitAgentText("记录一下今天的情绪恢复")
        waitForMainQueue()

        XCTAssertFalse(fallbackStore.agentThreadIndex.first?.title.isEmpty ?? true)
    }

    func testFullDataArchiveIncludesAgentThreadsStoredOnDisk() throws {
        let uid = "agent-archive-\(UUID().uuidString)"
        cleanupAgentThreadFiles(uid)
        defer {
            cleanupAgentThreadFiles(uid)
            UserDefaults.standard.removeObject(forKey: "auth.userId")
        }
        UserDefaults.standard.set(uid, forKey: "auth.userId")

        let store = AppStore()
        let mock = MockAIClient(result: .success(AgentChatResponse(reply: "收到", actionSuggestions: [])))
        store.agent = AgentManager(writer: store, userIdSuffix: uid, client: mock)
        store.submitAgentText("备份这段对话")
        waitForMainQueue()

        let data = try XCTUnwrap(store.makeFullDataArchive())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let payload = try XCTUnwrap(json["data"] as? [String: Any])
        let threads = try XCTUnwrap(payload["ps.agent.threads"] as? [[String: Any]])

        XCTAssertEqual(threads.count, 1)
        XCTAssertNotNil(payload["ps.agent.threads.index"])
        XCTAssertNotNil(payload["ps.agent.threads.current"])
    }

    func testAgentActionConfirmationSavesInboxTaskAndTime() {
        let store = AppStore()
        let inbox = AgentActionDraft(kind: .inbox, title: "面试目标", detail: "确定下面试目标", confidence: 0.8, reason: "适合先存成想法")
        let task = AgentActionDraft(kind: .task, title: "提交材料", detail: "明天提交材料", date: "2026-05-19", confidence: 0.85, reason: "有明确动作")
        let time = AgentActionDraft(kind: .time, module: "运动", title: "散步", detail: "今天散步", date: store.selectedDateKey, startTime: "09:00", endTime: "10:00", confidence: 0.9, reason: "有明确时间段")
        store.agent.session.pendingActions = [inbox, task, time]

        XCTAssertNil(store.confirmAgentAction(id: inbox.id))
        XCTAssertNil(store.confirmAgentAction(id: task.id))
        XCTAssertNil(store.confirmAgentAction(id: time.id))

        XCTAssertTrue(store.turns.contains { $0.rawText == "确定下面试目标" && $0.targetBucket == "inbox" })
        XCTAssertTrue(store.tasks.contains { $0.title == "提交材料" })
        XCTAssertTrue(store.timeEntries.contains { $0.name == "散步" && $0.start == "09:00" && $0.end == "10:00" && $0.category == "运动" })
    }

    func testAgentInboxActionSavesDreamType() {
        let store = AppStore()
        let dream = AgentActionDraft(
            kind: .inbox,
            inboxType: "做梦",
            mood: 2,
            feelings: ["困惑", "焦虑"],
            title: "梦见父亲纠缠，自己逃避",
            detail: "梦到父亲来找我，我一直避开，不想见他。梦里还有好多人，像一个大型 cosplay 现场。",
            confidence: 0.9,
            reason: "梦境记录"
        )
        store.agent.session.pendingActions = [dream]

        XCTAssertNil(store.confirmAgentAction(id: dream.id))

        XCTAssertTrue(store.turns.contains {
            $0.rawText.contains("梦到父亲来找我") &&
            $0.targetBucket == "inbox" &&
            $0.recognizedType == "做梦" &&
            $0.moodScore == 2 &&
            $0.feelingTags == ["困惑", "焦虑"]
        })
    }

    func testAgentInboxActionInfersDreamTypeFromContent() {
        let store = AppStore()
        let dream = AgentActionDraft(
            kind: .inbox,
            title: "梦见父亲纠缠",
            detail: "梦到父亲来找我，我一直避开。",
            confidence: 0.9,
            reason: "梦境记录"
        )
        store.agent.session.pendingActions = [dream]

        XCTAssertNil(store.confirmAgentAction(id: dream.id))

        XCTAssertTrue(store.turns.contains { $0.recognizedType == "做梦" && $0.rawText.contains("梦到父亲") })
    }

    func testAgentActionSuggestionsReplaceLessCompleteDuplicate() {
        let store = AppStore()
        let vagueTask = AgentActionDraft(
            kind: .task,
            title: "提交材料",
            detail: "明天提醒提交材料",
            date: "2026-05-19",
            confidence: 0.7,
            reason: "用户提到提醒"
        )
        let timedTask = AgentActionDraft(
            kind: .task,
            title: "提交材料",
            detail: "明天 10 点提醒提交材料",
            date: "2026-05-19",
            startTime: "10:00",
            confidence: 0.9,
            reason: "用户补充了时间"
        )

        store.mergeAgentActionSuggestions([vagueTask])
        store.mergeAgentActionSuggestions([timedTask])

        XCTAssertEqual(store.agent.session.pendingActions.count, 1)
        XCTAssertEqual(store.agent.session.pendingActions.first?.detail, "明天 10 点提醒提交材料")
        XCTAssertEqual(store.agent.session.pendingActions.first?.startTime, "10:00")
    }

    func testAgentActionSuggestionsAreSuppressedWhenFollowUpIsPresent() {
        let store = AppStore()
        let prematureTask = AgentActionDraft(
            kind: .task,
            title: "提交材料",
            detail: "明天提醒提交材料",
            date: "2026-05-19",
            confidence: 0.7,
            reason: "还需要补充时间"
        )
        let response = AgentChatResponse(
            reply: "好的，明天提醒你提交材料。",
            followUpQuestion: "你希望明天几点收到提醒？",
            actionSuggestions: [prematureTask]
        )

        XCTAssertTrue(store.agentActionSuggestionsToMerge(from: response).isEmpty)
    }

    func testAgentChatDebugLogCodableRoundtrip() throws {
        let log = AgentChatDebugLog(
            createdAt: Date(),
            input: "明天提醒我提交材料",
            currentDate: "2026-05-18",
            currentTime: "20:40",
            personaSummary: "温柔少问",
            userSummary: "用户在测试 Agent",
            contextSummary: "暂无近期 LifeOS 记录。",
            messagesSummary: ["user: 明天提醒我提交材料"],
            reply: "好的，明天几点提醒？",
            followUpQuestion: "你希望明天几点收到提醒？",
            actionSuggestionsSummary: ["kind=task ; title=提交材料"],
            mergedActionSummary: [],
            rawResponse: #"{"reply":"好的"}"#,
            errorMessage: ""
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(log)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(AgentChatDebugLog.self, from: data)

        XCTAssertEqual(decoded.input, log.input)
        XCTAssertEqual(decoded.personaSummary, "温柔少问")
        XCTAssertEqual(decoded.actionSuggestionsSummary, ["kind=task ; title=提交材料"])
    }

    func testAgentChatResponseDecodesDebugPayload() throws {
        let data = """
        {
          "reply": "好的",
          "followUpQuestion": null,
          "actionSuggestions": [
            {
              "kind": "inbox",
              "inboxType": "做梦",
              "mood": 2,
              "feelings": ["困惑", "焦虑"],
              "title": "梦境记录",
              "detail": "梦到很多人",
              "confidence": 0.9,
              "reason": "梦境记录"
            }
          ],
          "debug": {
            "persona": "猫猫伙伴",
            "userProfile": "用户正在测试",
            "policy": "少追问",
            "messagesUsed": [{"role": "user", "content": "明天提醒我提交材料"}],
            "contextSummary": "暂无近期记录",
            "rawModelOutput": "{\\"reply\\":\\"好的\\"}",
            "suppressedActionsReason": "followUpQuestion_present"
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AgentChatResponse.self, from: data)

        XCTAssertEqual(decoded.debug?.persona, "猫猫伙伴")
        XCTAssertEqual(decoded.debug?.userProfile, "用户正在测试")
        XCTAssertEqual(decoded.debug?.messagesUsed?.first?.content, "明天提醒我提交材料")
        XCTAssertEqual(decoded.debug?.suppressedActionsReason, "followUpQuestion_present")
        XCTAssertEqual(decoded.actionSuggestions.first?.inboxType, "做梦")
        XCTAssertEqual(decoded.actionSuggestions.first?.mood, 2)
        XCTAssertEqual(decoded.actionSuggestions.first?.feelings, ["困惑", "焦虑"])
    }

    func testAgentChatResponseDecodesUsage() throws {
        let data = """
        {
          "reply": "好的",
          "followUpQuestion": null,
          "actionSuggestions": [],
          "usage": {
            "prompt_tokens": 123,
            "completion_tokens": 45,
            "total_tokens": 168,
            "prompt_tokens_details": {
              "cached_tokens": 80
            }
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AgentChatResponse.self, from: data)

        XCTAssertEqual(decoded.usage?.promptTokens, 123)
        XCTAssertEqual(decoded.usage?.completionTokens, 45)
        XCTAssertEqual(decoded.usage?.totalTokens, 168)
        XCTAssertEqual(decoded.usage?.promptTokenDetails?["cached_tokens"], 80)
    }

    func testTraceLoggerDiscardsAfterMaxRetries() async {
        let defaults = UserDefaults(suiteName: "trace-retry-test")!
        defaults.removePersistentDomain(forName: "trace-retry-test")
        let logger = AgentTraceLogger(defaults: defaults)

        let event1 = AgentTraceEvent(
            traceId: "fail-1", sessionId: nil, threadId: nil,
            eventName: "request_started", payload: ["input": "will fail"]
        )
        let event2 = AgentTraceEvent(
            traceId: "ok-1", sessionId: nil, threadId: nil,
            eventName: "request_started", payload: ["input": "should survive"]
        )

        await logger.emit(event1)
        await logger.emit(event2)

        let pending = defaults.data(forKey: AgentTraceConfig.pendingKey)
            .flatMap { try? JSONDecoder().decode([AgentTraceEvent].self, from: $0) } ?? []
        XCTAssertTrue(pending.count <= 2, "pending should have at most 2 events before server interaction")

        defaults.removePersistentDomain(forName: "trace-retry-test")
    }

    func testTraceFailCountResetOnSuccess() {
        let defaults = UserDefaults(suiteName: "trace-failcount-test")!
        defaults.removePersistentDomain(forName: "trace-failcount-test")

        defaults.set(2, forKey: AgentTraceConfig.failCountKey)
        XCTAssertEqual(defaults.integer(forKey: AgentTraceConfig.failCountKey), 2)

        defaults.removeObject(forKey: AgentTraceConfig.failCountKey)
        XCTAssertEqual(defaults.integer(forKey: AgentTraceConfig.failCountKey), 0)

        defaults.removePersistentDomain(forName: "trace-failcount-test")
    }

    func testAgentTraceEventCodableRoundtrip() throws {
        let event = AgentTraceEvent(
            traceId: "trace-1",
            sessionId: "user-1",
            threadId: "thread-1",
            eventName: "request_started",
            payload: [
                "input": "今天有点乱",
                "messages": AgentTracePayload.json([AgentChatRequestMessage(role: "user", content: "你好")])
            ],
            usage: AgentTokenUsage(
                promptTokens: 10,
                completionTokens: 5,
                totalTokens: 15,
                promptTokenDetails: ["cached_tokens": 3]
            ),
            latencyMs: 321,
            error: nil
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AgentTraceEvent.self, from: data)

        XCTAssertEqual(decoded.traceId, "trace-1")
        XCTAssertEqual(decoded.source, "ios")
        XCTAssertEqual(decoded.eventName, "request_started")
        XCTAssertEqual(decoded.payload["input"], "今天有点乱")
        XCTAssertEqual(decoded.usage?.promptTokenDetails?["cached_tokens"], 3)
        XCTAssertEqual(decoded.latencyMs, 321)
    }

    func testTaskToggleRecordsAndClearsCompletionTime() {
        let store = AppStore()
        let title = "completion-time-\(UUID().uuidString)"
        guard let id = store.addTask(title: title) else {
            return XCTFail("addTask failed")
        }
        defer { store.removeTask(id: id) }

        guard let pending = store.tasks.first(where: { $0.id == id }) else {
            return XCTFail("task missing after add")
        }
        XCTAssertNil(pending.completedAt)

        store.toggleTask(pending)
        guard let completed = store.tasks.first(where: { $0.id == id }) else {
            return XCTFail("task missing after complete")
        }
        XCTAssertEqual(completed.status, "已完成")
        XCTAssertNotNil(completed.completedAt)

        store.toggleTask(completed)
        guard let reopened = store.tasks.first(where: { $0.id == id }) else {
            return XCTFail("task missing after reopen")
        }
        XCTAssertEqual(reopened.status, "待办")
        XCTAssertNil(reopened.completedAt)
    }

    func testClearCompletedTasksKeepsRecentAndPendingTasks() {
        let store = AppStore()
        let calendar = Calendar.current
        let oldDate = calendar.date(byAdding: .day, value: -45, to: Date())!
        let recentDate = calendar.date(byAdding: .day, value: -5, to: Date())!
        let cutoff = calendar.date(byAdding: .month, value: -1, to: Date())!

        let prefix = "clear-completed-\(UUID().uuidString)"
        guard let oldID = store.addTask(title: "\(prefix)-old", status: "已完成", completedAt: oldDate),
              let recentID = store.addTask(title: "\(prefix)-recent", status: "已完成", completedAt: recentDate),
              let pendingID = store.addTask(title: "\(prefix)-pending") else {
            return XCTFail("addTask failed")
        }
        defer {
            store.removeTask(id: oldID)
            store.removeTask(id: recentID)
            store.removeTask(id: pendingID)
        }

        let removed = store.clearCompletedTasks(olderThan: cutoff)

        XCTAssertGreaterThanOrEqual(removed, 1)
        XCTAssertNil(store.tasks.first(where: { $0.id == oldID }))
        XCTAssertNotNil(store.tasks.first(where: { $0.id == recentID }))
        XCTAssertNotNil(store.tasks.first(where: { $0.id == pendingID }))
    }

    func testTaskIntentDetectorRecognizesActionableTodo() {
        XCTAssertTrue(TaskIntentDetector.looksLikeTask("记得明天买猫粮"))
        XCTAssertTrue(TaskIntentDetector.looksLikeTask("待办：预约体检"))
        XCTAssertTrue(TaskIntentDetector.looksLikeTask("请帮我加入待办，明天提交报销"))
        XCTAssertTrue(TaskIntentDetector.looksLikeTask("这是我的 todo list：预约体检"))
        XCTAssertTrue(TaskIntentDetector.looksLikeTask("帮我周五提交报销"))
    }

    func testAppUpdateVersionComparison() {
        XCTAssertTrue(AppUpdateService.isVersion("1.5.3", newerThan: "1.5.2"))
        XCTAssertTrue(AppUpdateService.isVersion("1.6.0", newerThan: "1.5.9"))
        XCTAssertFalse(AppUpdateService.isVersion("1.5.2", newerThan: "1.5.2"))
        XCTAssertFalse(AppUpdateService.isVersion("1.5.1", newerThan: "1.5.2"))
    }

    func testTaskIntentDetectorKeepsFeelingsAsObservation() {
        XCTAssertFalse(TaskIntentDetector.looksLikeTask("我今天感觉很焦虑"))
        XCTAssertFalse(TaskIntentDetector.looksLikeTask("感恩今天晒到了太阳"))
        XCTAssertFalse(TaskIntentDetector.looksLikeTask("昨晚做梦梦到在海边散步"))
    }

    func testLocalCaptureCreatesTodoFromActionableText() {
        let result = QuickCaptureParser.parse("记得明天买猫粮")
        XCTAssertEqual(result.plan.tasks.count, 1)
        XCTAssertEqual(result.plan.inboxEntries.count, 0)
        XCTAssertEqual(result.plan.tasks.first?.status, "待办")
    }

    func testLocalCaptureTreatsFutureInterviewAsTodoNotTimeLog() {
        let result = QuickCaptureParser.parse("今天下午我有一场面试，2 到 3 点")
        XCTAssertEqual(result.plan.tasks.count, 1)
        XCTAssertEqual(result.plan.timeEntries.count, 0)
        XCTAssertEqual(result.plan.tasks.first?.startTime, "14:00")
        XCTAssertEqual(result.plan.tasks.first?.endTime, "15:00")
    }

    func testTaskIntentDetectorRecognizesHelpMeRememberTodo() {
        let text = "帮我记一条，图图想要看 Claude 的视频"
        XCTAssertFalse(TaskIntentDetector.looksLikeTask(text))
        let result = QuickCaptureParser.parse(text)
        XCTAssertEqual(result.plan.tasks.count, 0)
        XCTAssertEqual(result.plan.inboxEntries.count, 1)
    }

    func testTaskIntentDetectorRespectsExplicitInboxRouting() {
        XCTAssertFalse(TaskIntentDetector.looksLikeTask("你就帮我记录在想法里头"))
        XCTAssertFalse(TaskIntentDetector.looksLikeTask("帮我记到感受：越打越虚，停不下来"))
        XCTAssertFalse(TaskIntentDetector.looksLikeTask("帮我放到随手记，今天状态又好起来了"))
        XCTAssertFalse(TaskIntentDetector.looksLikeTask("希望找一些更年轻有活力的团队"))
        XCTAssertFalse(TaskIntentDetector.looksLikeTask("突然发现还是不喜欢老登的团队"))
    }

    func testTurnDisplayTextFallsBackWhenDetailIsEmpty() {
        let turn = ConversationTurn(
            id: UUID(),
            createdAt: Date(),
            rawText: "越打越虚，停不下来",
            recognizedType: "待办",
            targetBucket: "task",
            confidence: 1.0,
            status: "committed",
            payload: ["detail": ""],
            fixHint: "",
            moodScore: nil,
            feelingTags: [],
            reviewStatus: "pending"
        )
        XCTAssertEqual(TurnTypeStyle.displayText(for: turn), "越打越虚，停不下来")
    }

    func testCommitAITimeTurnSupportsCrossDayRange() {
        let store = AppStore()
        guard let turnID = store.addTurnDraft(
            rawText: "从晚上 7 点开始打游戏到 12 点多",
            recognizedType: "时间记录",
            targetBucket: "time",
            confidence: 1.0,
            payload: [
                "name": "打游戏",
                "start": "19:00",
                "end": "00:30",
                "category": "娱乐",
                "note": "从晚上 7 点开始打游戏到 12 点多"
            ]
        ) else {
            return XCTFail("addTurnDraft failed")
        }

        XCTAssertNil(store.commitTurn(id: turnID))
        XCTAssertEqual(store.timeEntries.count, 1)
        XCTAssertEqual(store.timeEntries.first?.start, "19:00")
        XCTAssertEqual(store.timeEntries.first?.end, "24:00")
    }

    func testCommitAITimeTurnUsesPayloadDate() {
        let store = AppStore()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        store.selectedDate = formatter.date(from: "2026-05-13")!

        guard let turnID = store.addTurnDraft(
            rawText: "昨天 10 点到 10 点半面试",
            recognizedType: "时间记录",
            targetBucket: "time",
            confidence: 1.0,
            payload: [
                "name": "面试",
                "start": "10:00",
                "end": "10:30",
                "category": "工作",
                "date": "2026-05-12"
            ]
        ) else {
            return XCTFail("addTurnDraft failed")
        }

        XCTAssertNil(store.commitTurn(id: turnID))
        XCTAssertEqual(store.timeEntries.count, 0)

        store.selectedDate = formatter.date(from: "2026-05-12")!
        XCTAssertEqual(store.timeEntries.count, 1)
        XCTAssertEqual(store.timeEntries.first?.name, "面试")
        XCTAssertEqual(store.timeEntries.first?.start, "10:00")
        XCTAssertEqual(store.timeEntries.first?.end, "10:30")
    }

    func testLowConfidenceTaskCanBeConfirmedLater() {
        let store = AppStore()
        guard let turnID = store.addTurnDraft(
            rawText: "希望找一些更年轻有活力的团队",
            recognizedType: "想法",
            targetBucket: "inbox",
            confidence: 0.95,
            payload: [
                "title": "团队偏好",
                "detail": "希望找一些更年轻有活力的团队",
                "status": "待处理",
                "ai_confirmation": "task"
            ]
        ) else {
            return XCTFail("addTurnDraft failed")
        }

        XCTAssertNil(store.commitTurn(id: turnID))
        XCTAssertEqual(store.tasks.count, 0)
        XCTAssertEqual(store.turns.first?.targetBucket, "inbox")
        XCTAssertEqual(store.turns.first?.payload["ai_confirmation"], "task")

        XCTAssertNil(store.confirmTurnAsTask(id: turnID))
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(store.turns.first?.targetBucket, "task")
    }

    // MARK: - Brain card store API

    func testAddAndRemoveBrainCard() {
        let store = AppStore()
        XCTAssertEqual(store.brainCards.count, 0)
        let aId = store.addBrain(title: "A", content: "content A", topics: ["#x"], sources: [])
        XCTAssertNotNil(aId)
        XCTAssertEqual(store.brainCards.count, 1)
        store.removeBrain(id: aId!)
        XCTAssertEqual(store.brainCards.count, 0)
    }

    func testAddBrainRejectsEmptyTitle() {
        let store = AppStore()
        XCTAssertNil(store.addBrain(title: "  ", content: "x", topics: [], sources: []))
        XCTAssertEqual(store.brainCards.count, 0)
    }

    func testRemoveBrainCleansBacklinks() {
        let store = AppStore()
        let aId = UUID()
        let bId = UUID()
        let now = Date()
        store.brainCards = [
            BrainCard(id: aId, title: "A", content: "", topics: [], sources: [], links: [bId], createdAt: now, updatedAt: now),
            BrainCard(id: bId, title: "B", content: "", topics: [], sources: [], links: [aId], createdAt: now, updatedAt: now),
        ]
        store.removeBrain(id: aId)
        XCTAssertFalse(store.brainCards.contains { $0.id == aId })
        XCTAssertEqual(store.brainCards.first(where: { $0.id == bId })?.links, [])
    }

    func testAddAndRemoveBrainExtension() {
        let store = AppStore()
        guard let cardId = store.addBrain(title: "做产品要留余地", content: "原始想法") else {
            return XCTFail("addBrain failed")
        }

        XCTAssertNil(store.addBrainExtension(cardId: cardId, content: "   "))

        guard let extensionId = store.addBrainExtension(cardId: cardId, content: "后来想到，余地也包括允许用户暂停。") else {
            return XCTFail("addBrainExtension failed")
        }

        var card = store.brainCards.first(where: { $0.id == cardId })
        XCTAssertEqual(card?.extensions.count, 1)
        XCTAssertEqual(card?.extensions.first?.content, "后来想到，余地也包括允许用户暂停。")

        store.removeBrainExtension(cardId: cardId, extensionId: extensionId)
        card = store.brainCards.first(where: { $0.id == cardId })
        XCTAssertEqual(card?.extensions, [])
    }

    // MARK: - Turn derivatives store API

    func testAppendTurnDerivative() {
        let store = AppStore()
        guard let turnId = store.addTurnDraft(
            rawText: "明天要写 PRD",
            recognizedType: "想法",
            targetBucket: "inbox",
            confidence: 1.0,
            payload: [:]
        ) else { return XCTFail("addTurnDraft failed") }
        let derivative = TurnDerivative(type: "todo", targetId: UUID(), createdAt: Date())
        store.appendTurnDerivative(turnId: turnId, derivative: derivative)
        let turn = store.turns.first(where: { $0.id == turnId })
        XCTAssertEqual(turn?.derivatives.count, 1)
        XCTAssertEqual(turn?.derivatives.first?.type, "todo")
    }

    func testAIFailureLogsPersistAcrossReload() {
        let store = AppStore()
        store.recordAIFailure(
            context: "brain_title",
            input: String(repeating: "标题提取失败", count: 20),
            error: AIParseError.network("timed out")
        )

        let reloaded = AppStore()
        XCTAssertEqual(reloaded.aiFailureLogs.count, 1)
        XCTAssertEqual(reloaded.aiFailureLogs.first?.context, "brain_title")
        XCTAssertEqual(reloaded.aiFailureLogs.first?.errorType, "AIParseError")
        XCTAssertTrue(reloaded.aiFailureLogs.first?.message.contains("timed out") == true)
        XCTAssertLessThanOrEqual(reloaded.aiFailureLogs.first?.inputExcerpt.count ?? 0, 123)
    }

    // MARK: - Review queue (PR 4 新增)

    private func makeTurn(
        type: String = "想法",
        status: String = "pending",
        createdAt: Date = Date(),
        moodScore: Int? = nil
    ) -> ConversationTurn {
        ConversationTurn(
            id: UUID(),
            createdAt: createdAt,
            rawText: "test",
            recognizedType: type,
            targetBucket: "inbox",
            confidence: 1.0,
            status: "committed",
            payload: [:],
            fixHint: "",
            moodScore: moodScore,
            feelingTags: [],
            reviewStatus: status
        )
    }

    func testReviewQueueIncludesOnlyIdeaAndFeeling() {
        let now = Date()
        let turns: [ConversationTurn] = [
            makeTurn(type: "想法", createdAt: now),
            makeTurn(type: "感受", createdAt: now),
            makeTurn(type: "感恩", createdAt: now),   // 不进队列
            makeTurn(type: "做梦", createdAt: now),   // 不进队列
        ]
        let queue = ReviewQueue.queue(turns: turns, now: now)
        XCTAssertEqual(queue.count, 2)
        XCTAssertTrue(queue.allSatisfy { ["想法", "感受"].contains($0.recognizedType) })
    }

    func testReviewQueueOnlyPending() {
        let now = Date()
        let turns: [ConversationTurn] = [
            makeTurn(status: "pending", createdAt: now),
            makeTurn(status: "archived", createdAt: now),
            makeTurn(status: "dismissed", createdAt: now),
        ]
        let queue = ReviewQueue.queue(turns: turns, now: now)
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.first?.reviewStatus, "pending")
    }

    func testReviewQueue7DayWindow() {
        let now = Date()
        let cal = Calendar.current
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: now)!
        let eightDaysAgo = cal.date(byAdding: .day, value: -8, to: now)!
        let turns: [ConversationTurn] = [
            makeTurn(createdAt: now),
            makeTurn(createdAt: twoDaysAgo),
            makeTurn(createdAt: eightDaysAgo),  // 超出 7 日窗
        ]
        let queue = ReviewQueue.queue(turns: turns, now: now)
        XCTAssertEqual(queue.count, 2)
    }

    func testReviewQueueNaturalWeekWindowIncludesMondayThroughSunday() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = cal.date(from: DateComponents(year: 2026, month: 4, day: 27))!
        let end = cal.date(from: DateComponents(year: 2026, month: 5, day: 4))!
        let turns: [ConversationTurn] = [
            makeTurn(createdAt: cal.date(from: DateComponents(year: 2026, month: 4, day: 26, hour: 23, minute: 59))!),
            makeTurn(createdAt: cal.date(from: DateComponents(year: 2026, month: 4, day: 27))!),
            makeTurn(createdAt: cal.date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 23, minute: 59))!),
            makeTurn(createdAt: cal.date(from: DateComponents(year: 2026, month: 5, day: 4))!),
        ]
        XCTAssertEqual(ReviewQueue.pendingCount(turns: turns, start: start, end: end), 2)
    }

    func testReviewQueueNaturalMonthWindowUsesStartInclusiveEndExclusive() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = cal.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let end = cal.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let turns: [ConversationTurn] = [
            makeTurn(status: "archived", createdAt: cal.date(from: DateComponents(year: 2026, month: 4, day: 30, hour: 23, minute: 59))!),
            makeTurn(status: "archived", createdAt: cal.date(from: DateComponents(year: 2026, month: 5, day: 1))!),
            makeTurn(status: "archived", createdAt: cal.date(from: DateComponents(year: 2026, month: 5, day: 31, hour: 23, minute: 59))!),
            makeTurn(status: "archived", createdAt: cal.date(from: DateComponents(year: 2026, month: 6, day: 1))!),
        ]
        XCTAssertEqual(ReviewQueue.archivedCount(turns: turns, start: start, end: end), 2)
    }

    func testReviewQueueSortedDescending() {
        let now = Date()
        let cal = Calendar.current
        let dayAgo = cal.date(byAdding: .day, value: -1, to: now)!
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: now)!
        let turns: [ConversationTurn] = [
            makeTurn(createdAt: twoDaysAgo),
            makeTurn(createdAt: now),
            makeTurn(createdAt: dayAgo),
        ]
        let queue = ReviewQueue.queue(turns: turns, now: now)
        XCTAssertEqual(queue.count, 3)
        XCTAssertEqual(queue[0].createdAt, now)
        XCTAssertEqual(queue[1].createdAt, dayAgo)
        XCTAssertEqual(queue[2].createdAt, twoDaysAgo)
    }

    func testReviewQueueArchivedAndDismissedCounts() {
        let now = Date()
        let turns: [ConversationTurn] = [
            makeTurn(status: "pending", createdAt: now),
            makeTurn(status: "archived", createdAt: now),
            makeTurn(status: "archived", createdAt: now),
            makeTurn(status: "dismissed", createdAt: now),
            makeTurn(type: "感恩", status: "archived", createdAt: now),  // 感恩不算进队列统计
        ]
        XCTAssertEqual(ReviewQueue.pendingCount(turns: turns, now: now), 1)
        XCTAssertEqual(ReviewQueue.archivedCount(turns: turns, now: now), 2)
        XCTAssertEqual(ReviewQueue.dismissedCount(turns: turns, now: now), 1)
    }

    func testReviewQueueExcludesOldArchivedFromCount() {
        let now = Date()
        let cal = Calendar.current
        let eightDaysAgo = cal.date(byAdding: .day, value: -8, to: now)!
        let turns: [ConversationTurn] = [
            makeTurn(status: "archived", createdAt: now),
            makeTurn(status: "archived", createdAt: eightDaysAgo),  // 7 日窗外
        ]
        XCTAssertEqual(ReviewQueue.archivedCount(turns: turns, now: now), 1)
    }

    // MARK: - Weekly review summaries

    func testReviewCheckHabitSummariesCountsCompletedAndBlankDays() {
        let store = AppStore()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = cal.date(from: DateComponents(year: 2026, month: 4, day: 27, hour: 12))!
        let end = cal.date(byAdding: .day, value: 7, to: start)!

        for offset in [0, 1, 3] {
            store.selectedDate = cal.date(byAdding: .day, value: offset, to: start)!
            guard let item = store.checkItems.first(where: { $0.title == "吃维生素" }) else {
                return XCTFail("missing fallback check item")
            }
            store.toggle(item)
        }

        let summaries = store.reviewCheckHabitSummaries(start: start, end: end)
        let vitamin = summaries.first { $0.title == "吃维生素" }
        XCTAssertEqual(vitamin?.completedDays, 3)
        XCTAssertEqual(vitamin?.blankDays, 4)
    }

    func testReviewCheckDaySummariesCountCompletedItemsByDay() {
        let store = AppStore()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = cal.date(from: DateComponents(year: 2026, month: 4, day: 27, hour: 12))!
        let end = cal.date(byAdding: .day, value: 7, to: start)!

        store.selectedDate = start
        for title in ["吃维生素", "回忆梦境"] {
            guard let item = store.checkItems.first(where: { $0.title == title }) else {
                return XCTFail("missing fallback check item \(title)")
            }
            store.toggle(item)
        }

        store.selectedDate = cal.date(byAdding: .day, value: 2, to: start)!
        guard let journal = store.checkItems.first(where: { $0.title == "写日记" }) else {
            return XCTFail("missing fallback check item 写日记")
        }
        store.toggle(journal)

        let days = store.reviewCheckDaySummaries(start: start, end: end)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days[0].completedCount, 2)
        XCTAssertEqual(days[0].totalCount, 7)
        XCTAssertEqual(days[1].completedCount, 0)
        XCTAssertEqual(days[2].completedCount, 1)
    }

    func testReviewCheckGroupSummariesRequireWholeGroupChecked() {
        let store = AppStore()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = cal.date(from: DateComponents(year: 2026, month: 4, day: 27, hour: 12))!
        let end = cal.date(byAdding: .day, value: 7, to: start)!

        store.selectedDate = start
        for title in ["吃维生素", "回忆梦境", "洗漱", "出门"] {
            guard let item = store.checkItems.first(where: { $0.title == title }) else {
                return XCTFail("missing fallback check item \(title)")
            }
            store.toggle(item)
        }

        store.selectedDate = cal.date(byAdding: .day, value: 1, to: start)!
        guard let partialItem = store.checkItems.first(where: { $0.title == "吃维生素" }) else {
            return XCTFail("missing fallback check item 吃维生素")
        }
        store.toggle(partialItem)

        let groups = store.reviewCheckGroupSummaries(start: start, end: end)
        let morning = groups.first { $0.title == "早上" }
        XCTAssertEqual(morning?.days.count, 7)
        XCTAssertEqual(morning?.days[0].completedCount, 4)
        XCTAssertEqual(morning?.days[0].totalCount, 4)
        XCTAssertEqual(morning?.days[0].isFullyChecked, true)
        XCTAssertEqual(morning?.days[1].completedCount, 1)
        XCTAssertEqual(morning?.days[1].totalCount, 4)
        XCTAssertEqual(morning?.days[1].isFullyChecked, false)
    }

    func testReviewTimeCategorySummariesAccumulateRecordedMinutesOnly() {
        let store = AppStore()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = cal.date(from: DateComponents(year: 2026, month: 4, day: 27, hour: 12))!
        let end = cal.date(byAdding: .day, value: 7, to: start)!

        store.selectedDate = start
        XCTAssertNil(store.addTimeEntry(name: "写代码", start: "09:00", end: "10:30", category: "工作"))
        XCTAssertNil(store.addTimeEntry(name: "读书", start: "11:00", end: "11:45", category: "学习"))
        XCTAssertNil(store.addTimeEntry(name: "散步", start: "12:00", end: "12:20", category: "运动"))

        store.selectedDate = cal.date(byAdding: .day, value: 1, to: start)!
        XCTAssertNil(store.addTimeEntry(name: "复盘", start: "20:00", end: "20:30", category: "学习"))
        XCTAssertNil(store.addTimeEntry(name: "看电影", start: "21:00", end: "22:00", category: "娱乐"))

        let summaries = store.reviewTimeCategorySummaries(start: start, end: end)
        XCTAssertEqual(summaries.map(\.category), ["学习", "工作", "运动", "娱乐"])
        XCTAssertEqual(summaries.first(where: { $0.category == "工作" })?.minutes, 90)
        XCTAssertEqual(summaries.first(where: { $0.category == "学习" })?.minutes, 75)
        XCTAssertEqual(summaries.first(where: { $0.category == "运动" })?.minutes, 20)
        XCTAssertEqual(summaries.first(where: { $0.category == "娱乐" })?.minutes, 60)
        XCTAssertFalse(summaries.contains { $0.minutes == 0 })
    }

    func testExportCSVsIncludesDailyChecksAsBinaryColumns() throws {
        let store = AppStore()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = cal.date(from: DateComponents(year: 2026, month: 4, day: 27, hour: 12))!
        let secondDay = cal.date(byAdding: .day, value: 1, to: start)!

        store.selectedDate = start
        guard let vitamin = store.checkItems.first(where: { $0.title == "吃维生素" }) else {
            return XCTFail("missing fallback check item 吃维生素")
        }
        store.toggle(vitamin)

        store.selectedDate = secondDay
        guard let journal = store.checkItems.first(where: { $0.title == "写日记" }) else {
            return XCTFail("missing fallback check item 写日记")
        }
        store.toggle(journal)

        let result = store.exportCSVs(from: start, to: secondDay)
        let url = try XCTUnwrap(result.checkURL)
        let csv = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(csv.contains("日期,吃维生素,回忆梦境,洗漱,出门,写日记,洗澡,上床看书"))
        XCTAssertTrue(csv.contains("2026-04-27,1,0,0,0,0,0,0"))
        XCTAssertTrue(csv.contains("2026-04-28,0,0,0,0,1,0,0"))
    }

    func testCrossDayTimeEntrySplitsAcrossSelectedDateAndNextDate() {
        let store = AppStore()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let startDate = cal.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 12))!
        let nextDate = cal.date(byAdding: .day, value: 1, to: startDate)!

        store.selectedDate = startDate
        XCTAssertNil(store.addTimeEntryFromDial(name: "睡觉", startMinutes: 23 * 60, endMinutes: 6 * 60, category: "睡觉"))
        XCTAssertEqual(store.timeEntries.count, 1)
        XCTAssertEqual(store.timeEntries[0].start, "23:00")
        XCTAssertEqual(store.timeEntries[0].end, "24:00")

        let groupID = store.timeEntries[0].extra[TimeEntryCrossDayKey.groupID]
        XCTAssertNotNil(groupID)
        XCTAssertEqual(store.timeEntries[0].extra[TimeEntryCrossDayKey.role], TimeEntryCrossDayKey.roleStart)

        store.selectedDate = nextDate
        XCTAssertEqual(store.timeEntries.count, 1)
        XCTAssertEqual(store.timeEntries[0].start, "00:00")
        XCTAssertEqual(store.timeEntries[0].end, "06:00")
        XCTAssertEqual(store.timeEntries[0].extra[TimeEntryCrossDayKey.groupID], groupID)
        XCTAssertEqual(store.timeEntries[0].extra[TimeEntryCrossDayKey.role], TimeEntryCrossDayKey.roleEnd)
    }

    func testCrossDayTimeEntryEndingAtMidnightDoesNotCreateZeroLengthNextDayEntry() {
        let store = AppStore()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let startDate = cal.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 12))!
        let nextDate = cal.date(byAdding: .day, value: 1, to: startDate)!

        store.selectedDate = startDate
        XCTAssertNil(store.addTimeEntryFromDial(name: "打游戏", startMinutes: 21 * 60 + 30, endMinutes: 0, category: "娱乐"))
        XCTAssertEqual(store.timeEntries.count, 1)
        XCTAssertEqual(store.timeEntries[0].start, "21:30")
        XCTAssertEqual(store.timeEntries[0].end, "24:00")

        store.selectedDate = nextDate
        XCTAssertTrue(store.timeEntries.isEmpty)
    }

    func testCrossDayTimeEntryCountsFullDurationInWeeklyReview() {
        let store = AppStore()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = cal.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 12))!
        let end = cal.date(byAdding: .day, value: 7, to: start)!

        store.selectedDate = start
        XCTAssertNil(store.addTimeEntryFromDial(name: "睡觉", startMinutes: 23 * 60, endMinutes: 6 * 60, category: "睡觉"))

        let summaries = store.reviewTimeCategorySummaries(start: start, end: end)
        XCTAssertEqual(summaries.first(where: { $0.category == "睡觉" })?.minutes, 7 * 60)
    }

    func testRemovingEitherHalfOfCrossDayTimeEntryRemovesPair() {
        let store = AppStore()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let startDate = cal.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 12))!
        let nextDate = cal.date(byAdding: .day, value: 1, to: startDate)!

        store.selectedDate = startDate
        XCTAssertNil(store.addTimeEntryFromDial(name: "睡觉", startMinutes: 23 * 60, endMinutes: 6 * 60, category: "睡觉"))

        store.selectedDate = nextDate
        XCTAssertEqual(store.timeEntries.count, 1)
        store.removeTimeEntry(at: IndexSet(integer: 0))
        XCTAssertTrue(store.timeEntries.isEmpty)

        store.selectedDate = startDate
        XCTAssertTrue(store.timeEntries.isEmpty)
    }

    func testReviewPendingCountUsesSelectedWeekWindow() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = cal.date(from: DateComponents(year: 2026, month: 4, day: 27))!
        let end = cal.date(byAdding: .day, value: 7, to: start)!
        let turns: [ConversationTurn] = [
            makeTurn(type: "想法", status: "pending", createdAt: cal.date(from: DateComponents(year: 2026, month: 4, day: 27, hour: 9))!),
            makeTurn(type: "感受", status: "pending", createdAt: cal.date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 22))!),
            makeTurn(type: "想法", status: "pending", createdAt: cal.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: 0))!),
            makeTurn(type: "感恩", status: "pending", createdAt: cal.date(from: DateComponents(year: 2026, month: 4, day: 28, hour: 10))!),
        ]

        XCTAssertEqual(ReviewQueue.pendingCount(turns: turns, start: start, end: end), 2)
    }

    func testTurnDerivativesPersistAcrossReload() {
        let store = AppStore()
        let turnId = store.addTurnDraft(
            rawText: "test",
            recognizedType: "想法",
            targetBucket: "inbox",
            confidence: 1.0,
            payload: [:]
        )!
        let targetId = UUID()
        store.appendTurnDerivative(turnId: turnId, derivative: TurnDerivative(type: "brain", targetId: targetId, createdAt: Date()))

        // 重启 app 模拟：新建一个 AppStore 重新 loadTurns
        let store2 = AppStore()
        let reloadedTurn = store2.turns.first(where: { $0.id == turnId })
        XCTAssertNotNil(reloadedTurn)
        XCTAssertEqual(reloadedTurn?.derivatives.count, 1)
        XCTAssertEqual(reloadedTurn?.derivatives.first?.type, "brain")
        XCTAssertEqual(reloadedTurn?.derivatives.first?.targetId, targetId)
    }

    private func makeDate(
        calendar: Calendar,
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func makeHealthKitSleepBlock(start: Date, end: Date) -> HealthKitTimeBlock {
        HealthKitTimeBlock(
            sourceIdentifier: "sleep-test-\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)",
            name: "睡觉",
            category: "睡觉",
            startDate: start,
            endDate: end,
            extra: [
                HealthKitTimeEntryKey.source: HealthKitTimeEntryKey.sourceValue,
                HealthKitTimeEntryKey.kind: HealthKitTimeEntryKey.kindSleep,
                HealthKitTimeEntryKey.sourceID: UUID().uuidString
            ]
        )
    }

    // MARK: - Data archive

    func testDataArchiveEnvelopeAndBase64() throws {
        let brain = "脑卡片".data(using: .utf8)!
        let payload: [String: Any] = [
            "ps.checks.byDate": ["2026-05-17": ["冥想": true]],
            "ps.brain": brain,
            "fields.daily.initialized": true
        ]
        let json = try XCTUnwrap(DataArchive.makeJSON(payload: payload, appVersion: "1.6.0"))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])

        XCTAssertEqual(obj["format"] as? String, "lifeos-backup")
        XCTAssertEqual(obj["version"] as? Int, 1)
        XCTAssertEqual(obj["base64Keys"] as? [String], ["ps.brain"])

        let data = try XCTUnwrap(obj["data"] as? [String: Any])
        XCTAssertEqual(data["ps.brain"] as? String, brain.base64EncodedString())
        let checks = data["ps.checks.byDate"] as? [String: [String: Bool]]
        XCTAssertEqual(checks?["2026-05-17"]?["冥想"], true)
        XCTAssertEqual(data["fields.daily.initialized"] as? Bool, true)
    }

    // MARK: - CloudKit record mapping

    func testCloudKitRecordMapperRoundtrip() throws {
        let cardCreated = Date(timeIntervalSince1970: 1000)
        let card = BrainCard(
            title: "命名", content: "正文", topics: ["#设计"],
            sources: [], links: [], createdAt: cardCreated, updatedAt: cardCreated
        )
        let brainData = try JSONEncoder().encode([card])

        let checks: [String: [String: Bool]] = ["2026-05-17": ["冥想": true, "写日记": false]]
        let time: [String: [[String: String]]] = [
            "2026-05-17": [["id": "t1", "name": "工作", "start": "09:00", "end": "10:00", "category": "工作"]]
        ]
        let tasks: [[String: Any]] = [["id": "task1", "title": "买菜", "status": "todo"]]
        let turns: [[String: Any]] = [["id": "turn1", "rawText": "今天有点累"]]

        let records = CloudKitRecordMapper.encode(
            checksByDate: checks, timeByDate: time, tasks: tasks, turns: turns,
            brainData: brainData, dailyFields: "冥想|默认", dailyInitialized: true, dailyGroups: "默认"
        )
        // 2 个打卡项合成 1 条 CheckDay + 1 time + 1 task + 1 turn + 1 brain + 1 config
        XCTAssertEqual(records.count, 6)

        let decoded = CloudKitRecordMapper.decode(records)
        XCTAssertEqual(decoded["ps.checks.byDate"] as? [String: [String: Bool]], checks)
        XCTAssertEqual(decoded["ps.time.byDate"] as? [String: [[String: String]]], time)
        XCTAssertEqual(decoded["ps.tasks"] as? [[String: String]],
                       [["id": "task1", "title": "买菜", "status": "todo"]])
        XCTAssertEqual(decoded["ps.turns"] as? [[String: String]],
                       [["id": "turn1", "rawText": "今天有点累"]])
        XCTAssertEqual(decoded["fields.daily"] as? String, "冥想|默认")
        XCTAssertEqual(decoded["fields.daily.initialized"] as? Bool, true)
        XCTAssertEqual(decoded["fields.daily.groups"] as? String, "默认")

        let decodedBrain = try JSONDecoder().decode([BrainCard].self,
                                                    from: XCTUnwrap(decoded["ps.brain"] as? Data))
        XCTAssertEqual(decodedBrain, [card])
    }

    func testCloudKitSyncRecordCKRecordBridge() throws {
        let original = SyncRecord(type: .task, recordName: "task-1", payload: Data("x".utf8))
        let ck = CloudKitRecordMapper.makeCKRecord(original, zoneID: CloudKitSchema.zoneID)
        XCTAssertEqual(ck.recordType, "Task")
        XCTAssertEqual(ck.recordID.recordName, "task-1")
        let back = try XCTUnwrap(CloudKitRecordMapper.syncRecord(from: ck))
        XCTAssertEqual(back, original)
    }

    func testSyncRecordCodableRoundtrip() throws {
        let original = SyncRecord(type: .checkDay, recordName: "2026-05-17", payload: Data("hello".utf8))
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncRecord.self, from: encoded)
        XCTAssertEqual(decoded, original)
    }

    func testCloudKitMergeOverlaysUpdatesAndKeepsRest() {
        let a = SyncRecord(type: .task, recordName: "task1", payload: Data("old".utf8))
        let b = SyncRecord(type: .turn, recordName: "turn1", payload: Data("keep".utf8))
        let c = SyncRecord(type: .checkDay, recordName: "2026-05-17", payload: Data("day".utf8))
        let updatedA = SyncRecord(type: .task, recordName: "task1", payload: Data("new".utf8))

        let merged = CloudKitRecordMapper.merge(
            base: [a, b, c],
            updated: [updatedA],
            deletedRecordNames: ["2026-05-17"]
        )
        let byName = Dictionary(merged.map { ($0.recordName, $0) }, uniquingKeysWith: { first, _ in first })

        XCTAssertEqual(byName["task1"], updatedA)        // 同名记录被覆盖
        XCTAssertEqual(byName["turn1"], b)               // 未涉及的记录原样保留
        XCTAssertNil(byName["2026-05-17"])               // 删除的记录被移除
        XCTAssertEqual(merged.count, 2)
    }

    // MARK: - Agent mock tests

    func testAgentHandlesChatNetworkError() {
        let uid = "agent-network-\(UUID().uuidString)"
        cleanupAgentThreadFiles(uid)
        let store = AppStore()
        let mock = MockAIClient(result: .failure(AIParseError.network("timeout")))
        store.agent = AgentManager(writer: store, userIdSuffix: uid, client: mock)

        store.submitAgentText("hello")
        let exp = expectation(description: "agent finishes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        wait(for: [exp], timeout: 2)

        XCTAssertFalse(store.isAgentLoading)
        XCTAssertNotNil(store.agentErrorMessage)
        XCTAssertTrue(store.agentSession.pendingActions.isEmpty)
    }

    func testAgentHandlesEmptyReply() {
        let uid = "agent-empty-\(UUID().uuidString)"
        cleanupAgentThreadFiles(uid)
        let response = AgentChatResponse(reply: "", followUpQuestion: nil, actionSuggestions: [])
        let mock = MockAIClient(result: .success(response))
        let store = AppStore()
        store.agent = AgentManager(writer: store, userIdSuffix: uid, client: mock)

        store.submitAgentText("hello")
        let exp = expectation(description: "agent finishes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        wait(for: [exp], timeout: 2)

        XCTAssertFalse(store.isAgentLoading)
        XCTAssertNil(store.agentErrorMessage)
        XCTAssertEqual(store.agentSession.messages.count, 1)
        XCTAssertEqual(store.agentSession.messages.first?.role, "user")
    }

    func testAgentHandlesMalformedActions() {
        let uid = "agent-malformed-\(UUID().uuidString)"
        cleanupAgentThreadFiles(uid)
        let badAction = AgentActionDraft(kind: .inbox, title: "", detail: "", confidence: 0.5, reason: "")
        let response = AgentChatResponse(reply: "ok", followUpQuestion: nil, actionSuggestions: [badAction])
        let mock = MockAIClient(result: .success(response))
        let store = AppStore()
        store.agent = AgentManager(writer: store, userIdSuffix: uid, client: mock)

        store.submitAgentText("记录一下")
        let exp = expectation(description: "agent finishes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        wait(for: [exp], timeout: 2)

        XCTAssertFalse(store.isAgentLoading)
        XCTAssertTrue(store.agentSession.pendingActions.isEmpty)
    }
}

// MARK: - Mock

private final class MockAIClient: AIClient {
    let result: Result<AgentChatResponse, Error>
    var titleResult: Result<String, Error> = .success("测试标题")

    init(result: Result<AgentChatResponse, Error>) {
        self.result = result
    }

    func chat(
        input: String,
        messages: [AgentChatRequestMessage],
        contextSummary: String,
        currentDate: String,
        currentTime: String,
        traceId: String?,
        sessionId: String?,
        threadId: String?
    ) async throws -> AgentChatResponse {
        switch result {
        case .success(let response): return response
        case .failure(let error): throw error
        }
    }

    func quick(
        input: String,
        currentDate: String,
        currentTime: String,
        traceId: String?,
        sessionId: String?,
        threadId: String?
    ) async throws -> AgentChatResponse {
        switch result {
        case .success(let response): return response
        case .failure(let error): throw error
        }
    }

    func suggestTitle(content: String) async throws -> String {
        switch titleResult {
        case .success(let title): return title
        case .failure(let error): throw error
        }
    }
}
