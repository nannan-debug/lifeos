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
    // --- 来源指针：从随手记 turn 衍生 ToDo 时记下 ---
    var sourceNoteId: UUID? = nil    // 手工建的待办为 nil
    var sourceExcerpt: String = ""   // 创建时截取的 turn 原文片段，防原文改后失语境
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
    // Review 模式衍生出的 ToDo / 第二大脑卡片，append-only。
    // 即便下游 TaskEntry / BrainCard 被删，这里的链接条目依然保留作为历史。
    var derivatives: [TurnDerivative] = []
}

/// 一条 ConversationTurn 通过 Review 模式衍生出的下游产物（ToDo 或第二大脑卡片）。
struct TurnDerivative: Codable, Equatable {
    var type: String          // "todo" | "brain"
    var targetId: UUID        // 指向 TaskEntry.id 或 BrainCard.id
    var createdAt: Date
}

/// 第二大脑卡片：一条主题 + 正文，可挂主题标签 / 来源（从 turn 衍生）/ 互相关联。
struct BrainCard: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var content: String              // V1 plain text，未来可能升级 Markdown
    var topics: [String]             // 软聚合标签，比如 ["#命名", "#设计原则"]
    var sources: [BrainCardSource]   // 从哪些 turn 衍生而来（Review 模式自动建立）
    var links: [UUID]                // 关联的其他 BrainCard.id（用户在详情页手动建，双向）
    var createdAt: Date
    var updatedAt: Date
}

struct BrainCardSource: Codable, Equatable {
    var noteId: UUID
    var excerpt: String              // 创建时截取的 turn 原文片段，防原 note 改后失语境
}
