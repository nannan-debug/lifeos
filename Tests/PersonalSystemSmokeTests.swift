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

    // MARK: - Review queue (PR 4 新增)

    private func makeTurn(
        type: String = "想法",
        status: String = "pending",
        createdAt: Date = Date()
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
            moodScore: nil,
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
