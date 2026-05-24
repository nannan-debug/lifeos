import Foundation

enum AgentTrigger: String, Codable, Equatable {
    case userMessage
    case manualReview
    case scheduledNudge
}

enum AgentOrchestrator {
    static let maxContextTurns = 8
    static let maxContextTasks = 5
    static let maxContextTimeEntries = 6
    static let maxContextChecks = 8

    struct Request: Equatable {
        var input: String
        var messages: [AgentChatRequestMessage]
        var contextSummary: String
        var trigger: AgentTrigger
    }

    static func detectsReviewIntent(_ input: String) -> Bool {
        let keywords = ["这周", "本周", "最近", "过去几天", "这几天", "周总结", "总结", "状态", "回顾"]
        return keywords.contains(where: { input.contains($0) })
    }

    static func makeRequest(
        input: String,
        session: AgentChatSession,
        turns: [ConversationTurn],
        tasks: [TaskEntry],
        timeEntries: [TimeEntry],
        checks: [DailyCheckItem],
        memories: [AgentMemory] = [],
        nearbyTimeEntries: [(String, [TimeEntry])] = [],
        calendarEvents: [CalendarEventBlock] = [],
        trigger: AgentTrigger = .userMessage,
        weeklySummary: String? = nil,
        toolResult: String? = nil
    ) -> Request {
        let recentMessages = session.messages
            .filter { !$0.isError }
            .suffix(8)
            .map { AgentChatRequestMessage(role: $0.role, content: $0.content) }
        return Request(
            input: input,
            messages: recentMessages,
            contextSummary: makeContextSummary(
                turns: turns,
                tasks: tasks,
                timeEntries: timeEntries,
                checks: checks,
                memories: memories,
                nearbyTimeEntries: nearbyTimeEntries,
                calendarEvents: calendarEvents,
                weeklySummary: weeklySummary,
                toolResult: toolResult
            ),
            trigger: trigger
        )
    }

    static func makeContextSummary(
        turns: [ConversationTurn],
        tasks: [TaskEntry],
        timeEntries: [TimeEntry],
        checks: [DailyCheckItem],
        memories: [AgentMemory] = [],
        nearbyTimeEntries: [(String, [TimeEntry])] = [],
        calendarEvents: [CalendarEventBlock] = [],
        weeklySummary: String? = nil,
        toolResult: String? = nil
    ) -> String {
        var sections: [String] = []

        let recentTurns = turns.prefix(maxContextTurns).map { turn -> String in
            let shortId = String(turn.id.uuidString.prefix(6)).lowercased()
            let title = turn.payload["title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let prefix = title.isEmpty ? "\(turn.recognizedType)：" : "\(turn.recognizedType)【\(title)】："
            return "- [\(shortId)] \(prefix)\(turn.rawText.prefix(80))"
        }
        if !recentTurns.isEmpty {
            sections.append("近期随手记：\n" + recentTurns.joined(separator: "\n"))
        }

        let openTasks = tasks.filter { $0.status != "已完成" }.prefix(maxContextTasks).map {
            let shortId = String($0.id.uuidString.prefix(6)).lowercased()
            return "- [\(shortId)] \($0.title)\($0.dueDate.isEmpty ? "" : "（\($0.dueDate)）")"
        }
        if !openTasks.isEmpty {
            sections.append("当前待办：\n" + openTasks.joined(separator: "\n"))
        }

        let recentTime = timeEntries.prefix(maxContextTimeEntries).map {
            let shortId = String($0.id.uuidString.prefix(6)).lowercased()
            return "- [\(shortId)] \($0.start)-\($0.end) \($0.name) / \($0.category)"
        }
        if !recentTime.isEmpty {
            sections.append("今天时间记录：\n" + recentTime.joined(separator: "\n"))
        }

        for (dateKey, entries) in nearbyTimeEntries {
            let lines = entries.prefix(maxContextTimeEntries).map {
                let shortId = String($0.id.uuidString.prefix(6)).lowercased()
                return "- [\(shortId)] \($0.start)-\($0.end) \($0.name) / \($0.category)"
            }
            if !lines.isEmpty {
                sections.append("\(dateKey) 时间记录：\n" + lines.joined(separator: "\n"))
            }
        }

        let checkState = checks.prefix(maxContextChecks).map {
            "- \($0.title)：\($0.done ? "已完成" : "留白")"
        }
        if !checkState.isEmpty {
            sections.append("今日打卡：\n" + checkState.joined(separator: "\n"))
        }

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        let calendarLines = calendarEvents.prefix(8).map { event -> String in
            if event.isAllDay {
                return "- [全天] \(event.title)\(event.location.map { "（\($0)）" } ?? "")"
            }
            let start = timeFmt.string(from: event.startDate)
            let end = timeFmt.string(from: event.endDate)
            return "- \(start)-\(end) \(event.title)\(event.location.map { "（\($0)）" } ?? "")"
        }
        if !calendarLines.isEmpty {
            sections.append("今日日历：\n" + calendarLines.joined(separator: "\n"))
        }

        let memoryLines = memories.prefix(10).map { "- \($0.content)" }
        if !memoryLines.isEmpty {
            sections.append("历史记忆：\n" + memoryLines.joined(separator: "\n"))
        }

        if let weekly = weeklySummary, !weekly.isEmpty {
            sections.append(weekly)
        }

        if let result = toolResult, !result.isEmpty {
            sections.append("数据查询结果：\n" + result)
        }

        if sections.isEmpty {
            return "暂无近期 LifeOS 记录。"
        }
        return sections.joined(separator: "\n\n")
    }

    static func fallbackResponse(for input: String, weeklySummary: String? = nil) -> AgentChatResponse {
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let summary = weeklySummary, !summary.isEmpty, detectsReviewIntent(clean) {
            let reply = "网络暂时没接上，我先用本地数据帮你看看：\n\n\(summary)"
            return AgentChatResponse(reply: reply)
        }
        let reply = clean.isEmpty
            ? "我在。你可以先说一点点，不用整理好。"
            : "我先接住这句。现在网络里的对话服务暂时没接上，但这段话没有丢。你愿意的话，可以再补一句：这件事更像想法、待办，还是一段时间记录？"
        return AgentChatResponse(reply: reply)
    }
}
