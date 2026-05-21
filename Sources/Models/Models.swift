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

enum TimeEntryCrossDayKey {
    static let groupID = "crossDayGroupID"
    static let role = "crossDayRole"
    static let startDateKey = "crossDayStartDateKey"
    static let endDateKey = "crossDayEndDateKey"
    static let start = "crossDayStart"
    static let end = "crossDayEnd"

    static let roleStart = "start"
    static let roleEnd = "end"
}

struct TaskEntry: Identifiable {
    var id: UUID = UUID()
    var title: String
    var detail: String
    var status: String
    var priority: String
    var dueDate: String          // "yyyy-MM-dd" — 预定日期
    var date: String             // 创建日 / 记录归档日
    var completedAt: Date? = nil // 完成时间；老数据可能为空
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

enum AgentActionKind: String, Codable, Equatable {
    case inbox
    case task
    case time
}

struct AgentActionDraft: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kind: AgentActionKind
    var inboxType: String?
    var mood: Int?
    var feelings: [String]
    var module: String?
    var title: String
    var detail: String
    var date: String?
    var startTime: String?
    var endTime: String?
    var confidence: Double
    var reason: String
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        kind: AgentActionKind,
        inboxType: String? = nil,
        mood: Int? = nil,
        feelings: [String] = [],
        module: String? = nil,
        title: String,
        detail: String,
        date: String? = nil,
        startTime: String? = nil,
        endTime: String? = nil,
        confidence: Double,
        reason: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.inboxType = inboxType
        self.mood = mood
        self.feelings = feelings
        self.module = module
        self.title = title
        self.detail = detail
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.reason = reason
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case inboxType
        case mood
        case feelings
        case module
        case title
        case detail
        case date
        case startTime
        case endTime
        case confidence
        case reason
        case createdAt
    }

    private enum AlternateCodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let alternate = try decoder.container(keyedBy: AlternateCodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        kind = (try? c.decode(AgentActionKind.self, forKey: .kind)) ?? .inbox
        inboxType = (try? c.decodeIfPresent(String.self, forKey: .inboxType))
            ?? (try? alternate.decodeIfPresent(String.self, forKey: .type))
        mood = try? c.decodeIfPresent(Int.self, forKey: .mood)
        feelings = (try? c.decodeIfPresent([String].self, forKey: .feelings)) ?? []
        module = try? c.decodeIfPresent(String.self, forKey: .module)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        detail = (try? c.decode(String.self, forKey: .detail)) ?? ""
        date = try? c.decodeIfPresent(String.self, forKey: .date)
        startTime = try? c.decodeIfPresent(String.self, forKey: .startTime)
        endTime = try? c.decodeIfPresent(String.self, forKey: .endTime)
        confidence = (try? c.decode(Double.self, forKey: .confidence)) ?? 0.6
        reason = (try? c.decode(String.self, forKey: .reason)) ?? ""
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
    }
}

struct AgentChatMessage: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var role: String            // user / assistant
    var content: String
    var createdAt: Date = Date()
    var isError: Bool = false   // 错误兜底消息，不发送给 AI
}

struct AgentChatSession: Codable, Equatable {
    var id: UUID = UUID()
    var messages: [AgentChatMessage] = []
    var pendingActions: [AgentActionDraft] = []
    var updatedAt: Date = Date()
}

struct AgentChatThread: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String = ""
    var messages: [AgentChatMessage] = []
    var pendingActions: [AgentActionDraft] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var titleGenerated: Bool = false
    var memoryExtractedCount: Int = 0

    var session: AgentChatSession {
        AgentChatSession(
            id: id,
            messages: messages,
            pendingActions: pendingActions,
            updatedAt: updatedAt
        )
    }

    init(
        id: UUID = UUID(),
        title: String = "",
        messages: [AgentChatMessage] = [],
        pendingActions: [AgentActionDraft] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        titleGenerated: Bool = false
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.pendingActions = pendingActions
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.titleGenerated = titleGenerated
    }
}

struct AgentChatThreadIndexItem: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var messageCount: Int

    init(thread: AgentChatThread) {
        id = thread.id
        title = thread.title
        createdAt = thread.createdAt
        updatedAt = thread.updatedAt
        messageCount = thread.messages.count
    }
}

struct AgentMemory: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var content: String
    var category: String       // fact / preference / summary
    var createdAt: Date = Date()
    var lastUsedAt: Date = Date()
    var source: String = "auto" // auto / user
}

struct AgentToolCall: Codable, Equatable {
    var name: String
    var args: [String: String]?
}

struct AgentChatResponse: Decodable, Equatable {
    var reply: String
    var followUpQuestion: String?
    var actionSuggestions: [AgentActionDraft]
    var toolCall: AgentToolCall?
    var debug: AgentChatDebugPayload?
    var rawBody: String?
    var usage: AgentTokenUsage?

    private enum CodingKeys: String, CodingKey {
        case reply
        case followUpQuestion
        case actionSuggestions
        case actions
        case toolCall
        case debug
        case usage
    }

    init(reply: String, followUpQuestion: String? = nil, actionSuggestions: [AgentActionDraft] = [], toolCall: AgentToolCall? = nil, debug: AgentChatDebugPayload? = nil, rawBody: String? = nil, usage: AgentTokenUsage? = nil) {
        self.reply = reply
        self.followUpQuestion = followUpQuestion
        self.actionSuggestions = actionSuggestions
        self.toolCall = toolCall
        self.debug = debug
        self.rawBody = rawBody
        self.usage = usage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reply = (try? c.decode(String.self, forKey: .reply)) ?? ""
        followUpQuestion = try? c.decodeIfPresent(String.self, forKey: .followUpQuestion)
        actionSuggestions = (try? c.decode([AgentActionDraft].self, forKey: .actionSuggestions))
            ?? (try? c.decode([AgentActionDraft].self, forKey: .actions))
            ?? []
        toolCall = try? c.decodeIfPresent(AgentToolCall.self, forKey: .toolCall)
        debug = try? c.decodeIfPresent(AgentChatDebugPayload.self, forKey: .debug)
        usage = try? c.decodeIfPresent(AgentTokenUsage.self, forKey: .usage)
        rawBody = nil
    }
}

struct AgentTokenUsage: Codable, Equatable {
    var promptTokens: Int?
    var completionTokens: Int?
    var totalTokens: Int?
    var promptTokenDetails: [String: Int]?

    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case promptTokenDetails = "prompt_tokens_details"
    }
}

struct AgentChatDebugPayload: Codable, Equatable {
    var persona: String?
    var userProfile: String?
    var policy: String?
    var messagesUsed: [AgentChatRequestMessage]?
    var contextSummary: String?
    var rawModelOutput: String?
    var suppressedActionsReason: String?
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
    var extensions: [BrainCardExtension] = [] // 后续补充的延伸思考，保留想法演化顺序
    var createdAt: Date
    var updatedAt: Date
}

struct BrainCardSource: Codable, Equatable {
    var noteId: UUID
    var excerpt: String              // 创建时截取的 turn 原文片段，防原 note 改后失语境
}

struct BrainCardExtension: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var content: String
    var createdAt: Date
    var updatedAt: Date
}

extension BrainCard {
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case content
        case topics
        case sources
        case links
        case extensions
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        topics = try container.decodeIfPresent([String].self, forKey: .topics) ?? []
        sources = try container.decodeIfPresent([BrainCardSource].self, forKey: .sources) ?? []
        links = try container.decodeIfPresent([UUID].self, forKey: .links) ?? []
        extensions = try container.decodeIfPresent([BrainCardExtension].self, forKey: .extensions) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

struct AIFailureLog: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var createdAt: Date
    var context: String
    var inputExcerpt: String
    var errorType: String
    var message: String
}

struct AgentChatDebugLog: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var createdAt: Date
    var input: String
    var currentDate: String
    var currentTime: String
    var personaSummary: String
    var userSummary: String
    var contextSummary: String
    var messagesSummary: [String]
    var reply: String
    var followUpQuestion: String
    var actionSuggestionsSummary: [String]
    var mergedActionSummary: [String]
    var rawResponse: String
    var errorMessage: String
}
