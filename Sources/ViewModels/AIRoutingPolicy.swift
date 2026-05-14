import Foundation

struct AIRoutingDecision: Equatable {
    enum Action: String, Equatable {
        case time
        case task
        case inbox
        case skip
    }

    var action: Action
    var targetBucket: String
    var recognizedType: String
    var confidence: Double
    var source: String
    var needsTaskConfirmation: Bool
    var skipReason: String
}

enum AIRoutingPolicy {
    static let noteTypes = ["想法", "感受", "感恩", "做梦"]

    static func decision(for record: AIParsedRecord, rawText: String) -> AIRoutingDecision {
        let bucket = normalizedBucket(for: record, rawText: rawText)

        switch bucket {
        case "time":
            let start = record.startTime ?? ""
            let end = record.endTime ?? ""
            let hasParsedTime = !start.isEmpty || !end.isEmpty
            let hasUsableParsedRange = hasUsableTimeRange(start: start, end: end)

            if hasParsedTime && !hasUsableParsedRange {
                return AIRoutingDecision(
                    action: .skip,
                    targetBucket: "time",
                    recognizedType: "时间记录",
                    confidence: 0,
                    source: "ai_invalid_time",
                    needsTaskConfirmation: false,
                    skipReason: "AI 返回的起止时间无效：\(start)-\(end)"
                )
            }

            if hasUsableParsedRange || rawTextHasExplicitTimeRange(rawText) {
                return AIRoutingDecision(
                    action: .time,
                    targetBucket: "time",
                    recognizedType: "时间记录",
                    confidence: 0.95,
                    source: "ai",
                    needsTaskConfirmation: false,
                    skipReason: ""
                )
            }

            return AIRoutingDecision(
                action: .inbox,
                targetBucket: "inbox",
                recognizedType: inboxKind(forRawText: rawText),
                confidence: 0.84,
                source: "ai_vague_time_fallback",
                needsTaskConfirmation: false,
                skipReason: ""
            )

        case "task":
            return AIRoutingDecision(
                action: .task,
                targetBucket: "task",
                recognizedType: "待办",
                confidence: 0.95,
                source: "ai",
                needsTaskConfirmation: false,
                skipReason: ""
            )

        default:
            let rawType = record.type ?? "想法"
            let type = noteTypes.contains(rawType) ? rawType : "想法"
            return AIRoutingDecision(
                action: .inbox,
                targetBucket: "inbox",
                recognizedType: type,
                confidence: 0.95,
                source: "ai",
                needsTaskConfirmation: record.bucket == "task",
                skipReason: ""
            )
        }
    }

    static func normalizedBucket(for record: AIParsedRecord, rawText: String) -> String {
        if record.bucket == "time" { return "time" }
        let candidates = [
            rawText,
            record.title,
            record.details,
            record.eventName,
            record.notes
        ]
        .compactMap { $0 }
        .joined(separator: "\n")

        if record.bucket == "task" {
            return TaskIntentDetector.looksLikeTask(candidates) ? "task" : "note"
        }
        if record.bucket == "note" {
            return "note"
        }
        return TaskIntentDetector.looksLikeTask(candidates) ? "task" : record.bucket
    }

    static func appBucket(for record: AIParsedRecord, rawText: String) -> String {
        let action = decision(for: record, rawText: rawText).action
        if action == .skip { return "skip" }
        let bucket = normalizedBucket(for: record, rawText: rawText)
        return bucket == "note" ? "inbox" : bucket
    }

    static func inboxKind(forRawText raw: String) -> String {
        if raw.contains("感恩") || raw.contains("感谢") { return "感恩" }
        if raw.contains("梦") { return "做梦" }
        if raw.contains("感觉") || raw.contains("感到") || raw.contains("状态") || raw.contains("丧") || raw.contains("焦虑") || raw.contains("难过") || raw.contains("开心") || raw.contains("疲惫") {
            return "感受"
        }
        return "想法"
    }

    static func rawTextHasExplicitTimeRange(_ text: String) -> Bool {
        let normalized = text
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "～", with: "~")
        let clockTokenPattern = #"\d{1,2}\s*:\s*\d{1,2}|\d{1,2}\s*点(?:半|多)?|\d{1,2}\s*时(?:半|多)?"#
        let connectorPattern = #"到|至|-|~|开始|从"#
        let tokenCount = regexMatchCount(pattern: clockTokenPattern, in: normalized)
        return tokenCount >= 2 && regexContains(pattern: connectorPattern, in: normalized)
    }

    static func hasUsableTimeRange(start: String, end: String) -> Bool {
        guard let startMinutes = clockMinutes(from: start, allow24: false),
              let endMinutes = clockMinutes(from: end, allow24: true) else {
            return false
        }
        return startMinutes != endMinutes
    }

    private static func regexContains(pattern: String, in text: String) -> Bool {
        regexMatchCount(pattern: pattern, in: text) > 0
    }

    private static func regexMatchCount(pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.numberOfMatches(in: text, range: range)
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
}
