import XCTest
@testable import PersonalSystem

final class AIRoutingPolicyTests: XCTestCase {
    func testFixtureCasesMatchExpectedRouting() throws {
        for testCase in try loadRoutingCases() {
            XCTAssertEqual(testCase.aiRecords.count, testCase.expectedRecords.count, testCase.id)

            for (index, pair) in zip(testCase.aiRecords, testCase.expectedRecords).enumerated() {
                let decision = AIRoutingPolicy.decision(for: pair.0.record, rawText: testCase.input)

                XCTAssertEqual(decision.action.rawValue, pair.1.action, "\(testCase.id)[\(index)] action")
                XCTAssertEqual(decision.targetBucket, pair.1.targetBucket, "\(testCase.id)[\(index)] targetBucket")
                XCTAssertEqual(decision.recognizedType, pair.1.recognizedType, "\(testCase.id)[\(index)] recognizedType")
                XCTAssertEqual(decision.needsTaskConfirmation, pair.1.needsTaskConfirmation, "\(testCase.id)[\(index)] confirmation")

                if let expectedReason = pair.1.skipReasonContains {
                    XCTAssertTrue(decision.skipReason.contains(expectedReason), "\(testCase.id)[\(index)] skipReason")
                }
            }
        }
    }

    func testLongInterviewCaseKeepsTimeAndObservationOutOfTask() throws {
        let testCase = try requiredCase("mixed-interview-and-team-observation")
        let decisions = testCase.aiRecords.map { AIRoutingPolicy.decision(for: $0.record, rawText: testCase.input) }

        XCTAssertEqual(decisions.map(\.action), [.time, .inbox])
        XCTAssertEqual(decisions.map(\.targetBucket), ["time", "inbox"])
        XCTAssertEqual(decisions.map(\.recognizedType), ["时间记录", "想法"])
        XCTAssertFalse(decisions.contains { $0.action == .task })
    }

    func testParsedDurationUsesAIRecordRangeEvenWhenRawTextHasOneClockToken() throws {
        let testCase = try requiredCase("time-parsed-duration-one-clock")
        let decision = AIRoutingPolicy.decision(for: testCase.aiRecords[0].record, rawText: testCase.input)

        XCTAssertEqual(decision.action, .time)
        XCTAssertEqual(decision.targetBucket, "time")
        XCTAssertEqual(decision.recognizedType, "时间记录")
    }

    func testZeroLengthTimeIsSkippedInsteadOfFallingBackToInbox() throws {
        let testCase = try requiredCase("time-zero-length-skip")
        let decision = AIRoutingPolicy.decision(for: testCase.aiRecords[0].record, rawText: testCase.input)

        XCTAssertEqual(decision.action, .skip)
        XCTAssertEqual(decision.targetBucket, "time")
        XCTAssertTrue(decision.skipReason.contains("起止时间无效"))
    }

    private func requiredCase(_ id: String) throws -> AIRoutingCase {
        guard let testCase = try loadRoutingCases().first(where: { $0.id == id }) else {
            throw XCTSkip("Missing fixture case \(id)")
        }
        return testCase
    }

    private func loadRoutingCases() throws -> [AIRoutingCase] {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let fixtureURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("ai-routing-cases.json")
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode([AIRoutingCase].self, from: data)
    }
}

private struct AIRoutingCase: Decodable {
    var id: String
    var input: String
    var aiRecords: [FixtureAIRecord]
    var expectedRecords: [ExpectedRoutingRecord]
    var notes: String
    var tags: [String]
}

private struct FixtureAIRecord: Decodable {
    var bucket: String
    var eventName: String?
    var module: String?
    var startTime: String?
    var endTime: String?
    var notes: String?
    var type: String?
    var title: String?
    var details: String?
    var mood: Int?
    var feelings: [String]?
    var date: String?

    var record: AIParsedRecord {
        AIParsedRecord(
            bucket: bucket,
            eventName: eventName,
            module: module,
            startTime: startTime,
            endTime: endTime,
            notes: notes,
            type: type,
            title: title,
            details: details,
            mood: mood,
            feelings: feelings,
            date: date
        )
    }
}

private struct ExpectedRoutingRecord: Decodable {
    var action: String
    var targetBucket: String
    var recognizedType: String
    var needsTaskConfirmation: Bool
    var skipReasonContains: String?
}
