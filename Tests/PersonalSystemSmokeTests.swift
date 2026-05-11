import XCTest
@testable import PersonalSystem

final class PersonalSystemSmokeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // 每个 test 开跑前清掉当前用户名下的所有 store 数据，保证测试之间独立
        AppStore().wipeCurrentUserData()
    }

    // MARK: - Existing smoke

    func testAppStoreInitialStateLoads() {
        let store = AppStore()

        XCTAssertNotNil(store.selectedDate)
        XCTAssertGreaterThanOrEqual(store.checkItems.count, 0)
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
    }

    func testTaskIntentDetectorRecognizesActionableTodo() {
        XCTAssertTrue(TaskIntentDetector.looksLikeTask("记得明天买猫粮"))
        XCTAssertTrue(TaskIntentDetector.looksLikeTask("帮我周五提交报销"))
        XCTAssertTrue(TaskIntentDetector.looksLikeTask("待办：预约体检"))
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
        XCTAssertTrue(TaskIntentDetector.looksLikeTask(text))
        let result = QuickCaptureParser.parse(text)
        XCTAssertEqual(result.plan.tasks.count, 1)
        XCTAssertEqual(result.plan.inboxEntries.count, 0)
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
}
