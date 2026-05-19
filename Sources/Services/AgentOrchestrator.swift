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

    static func makeRequest(
        input: String,
        session: AgentChatSession,
        turns: [ConversationTurn],
        tasks: [TaskEntry],
        timeEntries: [TimeEntry],
        checks: [DailyCheckItem],
        memories: [AgentMemory] = [],
        trigger: AgentTrigger = .userMessage
    ) -> Request {
        let recentMessages = session.messages.suffix(8).map {
            AgentChatRequestMessage(role: $0.role, content: $0.content)
        }
        return Request(
            input: input,
            messages: recentMessages,
            contextSummary: makeContextSummary(
                turns: turns,
                tasks: tasks,
                timeEntries: timeEntries,
                checks: checks,
                memories: memories
            ),
            trigger: trigger
        )
    }

    static func makeContextSummary(
        turns: [ConversationTurn],
        tasks: [TaskEntry],
        timeEntries: [TimeEntry],
        checks: [DailyCheckItem],
        memories: [AgentMemory] = []
    ) -> String {
        var sections: [String] = []

        let recentTurns = turns.prefix(maxContextTurns).map {
            "- \($0.recognizedType)：\($0.rawText.prefix(80))"
        }
        if !recentTurns.isEmpty {
            sections.append("近期随手记：\n" + recentTurns.joined(separator: "\n"))
        }

        let openTasks = tasks.filter { $0.status != "已完成" }.prefix(maxContextTasks).map {
            "- \($0.title)\($0.dueDate.isEmpty ? "" : "（\($0.dueDate)）")"
        }
        if !openTasks.isEmpty {
            sections.append("当前待办：\n" + openTasks.joined(separator: "\n"))
        }

        let recentTime = timeEntries.prefix(maxContextTimeEntries).map {
            "- \($0.start)-\($0.end) \($0.name) / \($0.category)"
        }
        if !recentTime.isEmpty {
            sections.append("今天时间记录：\n" + recentTime.joined(separator: "\n"))
        }

        let checkState = checks.prefix(maxContextChecks).map {
            "- \($0.title)：\($0.done ? "已完成" : "留白")"
        }
        if !checkState.isEmpty {
            sections.append("今日打卡：\n" + checkState.joined(separator: "\n"))
        }

        let memoryLines = memories.prefix(10).map { "- \($0.content)" }
        if !memoryLines.isEmpty {
            sections.append("历史记忆：\n" + memoryLines.joined(separator: "\n"))
        }

        if sections.isEmpty {
            return "暂无近期 LifeOS 记录。"
        }
        return sections.joined(separator: "\n\n")
    }

    static func fallbackResponse(for input: String) -> AgentChatResponse {
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let reply = clean.isEmpty
            ? "我在。你可以先说一点点，不用整理好。"
            : "我先接住这句。现在网络里的对话服务暂时没接上，但这段话没有丢。你愿意的话，可以再补一句：这件事更像想法、待办，还是一段时间记录？"
        return AgentChatResponse(reply: reply)
    }
}
