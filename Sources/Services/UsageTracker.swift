import Foundation

/// 轻量级匿名使用统计。
/// 复用 AgentTraceLogger 基础设施，只发事件名 + 计数，不发任何用户内容。
/// 同类事件在本地聚合，每次 app 进前台时批量上报，避免频繁网络请求。
enum UsageTracker {

    // MARK: - Event names

    static let appOpen           = "usage_app_open"
    static let tabSwitch         = "usage_tab_switch"
    static let turnCreated       = "usage_turn_created"       // 随手记
    static let taskCreated       = "usage_task_created"       // 待办
    static let taskCompleted     = "usage_task_completed"
    static let timeEntryCreated  = "usage_time_created"       // 时间记录
    static let checkToggled      = "usage_check_toggled"      // 打卡
    static let aiChatSent        = "usage_ai_chat_sent"       // Arya 对话
    static let calendarCreated   = "usage_calendar_created"   // 日历事件
    static let reviewOpened      = "usage_review_opened"      // 复盘页
    static let brainCardViewed   = "usage_braincard_viewed"   // 第二大脑
    static let exportUsed        = "usage_export"             // 导出

    // MARK: - Buffered tracking

    private static let bufferKey = "ps.usage.buffer.v1"
    private static let sessionIdKey = "auth.user"

    /// 记录一个事件（本地聚合，不立即发网络请求）
    static func track(_ event: String, extra: [String: String] = [:]) {
        var buffer = loadBuffer()
        let key = event
        buffer[key] = (buffer[key] ?? 0) + 1
        saveBuffer(buffer)
    }

    /// App 进前台时调用，把聚合的事件批量发出去
    static func flush() {
        let buffer = loadBuffer()
        guard !buffer.isEmpty else { return }

        let sessionId = UserDefaults.standard.string(forKey: sessionIdKey) ?? "unknown"
        let traceId = "usage-\(UUID().uuidString.prefix(8))"

        // 把所有聚合计数合成一个 trace 事件
        var payload: [String: String] = [:]
        for (event, count) in buffer {
            payload[event] = String(count)
        }

        let event = AgentTraceEvent(
            traceId: traceId,
            sessionId: sessionId,
            threadId: nil,
            eventName: "usage_batch",
            payload: payload
        )

        // 清空 buffer，然后异步发送
        saveBuffer([:])

        Task {
            await AgentTraceLogger.shared.emit(event)
        }
    }

    // MARK: - Buffer persistence

    private static func loadBuffer() -> [String: Int] {
        guard let data = UserDefaults.standard.data(forKey: bufferKey),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return dict
    }

    private static func saveBuffer(_ buffer: [String: Int]) {
        guard let data = try? JSONEncoder().encode(buffer) else { return }
        UserDefaults.standard.set(data, forKey: bufferKey)
    }
}
