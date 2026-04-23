import Foundation

struct DailyCheckItem: Identifiable {
    let id = UUID()
    let title: String
    var done: Bool
    var tag: String = "默认"   // 分组标签，如 "早" / "晚" / 用户自定义
}

struct TimeEntry: Identifiable {
    var id: UUID = UUID()
    var name: String
    var start: String
    var end: String
    var category: String
    var extra: [String: String] = [:]
}

struct InboxNote: Identifiable {
    var id: UUID = UUID()
    var title: String
    var detail: String
    var kind: String
    var status: String
    var extra: [String: String] = [:]
}

struct TaskEntry: Identifiable {
    var id: UUID = UUID()
    var title: String
    var detail: String
    var status: String
    var priority: String
    var dueDate: String          // "yyyy-MM-dd" — 预定日期
    var date: String             // 创建日 / 记录归档日
    // --- Apple Calendar 风格扩展字段 ---
    var isAllDay: Bool = true    // 全天事件默认 true
    var startTime: String = ""   // "HH:mm"，isAllDay 时为空
    var endTime: String = ""     // "HH:mm"，isAllDay 时为空
    var location: String = ""    // 地点，为将来日历联动预留
}

struct ConversationTurn: Identifiable {
    let id: UUID
    var createdAt: Date
    var rawText: String
    var recognizedType: String
    var targetBucket: String   // time / inbox / task
    var confidence: Double
    var status: String         // draft / needs_fix / committed
    var payload: [String: String]
    var fixHint: String
    var moodScore: Int?        // 1-5: 非常不愉快..非常愉快
    var feelingTags: [String]  // e.g. ["焦虑", "有动力"]
    var reviewStatus: String   // pending / archived / dismissed
}
