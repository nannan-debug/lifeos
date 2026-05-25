import Foundation
import UIKit

protocol AgentDataWriter: AnyObject {
    var selectedDateKey: String { get }
    var userProfile: String { get set }
    func addTurnDraft(rawText: String, recognizedType: String, targetBucket: String, confidence: Double, payload: [String: String], status: String, fixHint: String, moodScore: Int?, feelingTags: [String]) -> UUID?
    func commitTurn(id: UUID) -> String?
    func addTask(title: String, detail: String, status: String, priority: String, dueDate: String, date: String?, completedAt: Date?, isAllDay: Bool, startTime: String, endTime: String, location: String, sourceNoteId: UUID?, sourceExcerpt: String) -> UUID?
    func undoTurn(id: UUID)
    func undoTask(id: UUID)
    func undoTimeFromTurn(id: UUID)

    // MARK: - Mutation support (edit / delete / complete)
    func resolveTaskId(shortId: String) -> (UUID, TaskEntry)?
    func resolveTimeEntryId(shortId: String) -> (UUID, TimeEntry, String)?
    func updateTaskFromAgent(id: UUID, title: String?, detail: String?, priority: String?, dueDate: String?) -> String?
    func updateTimeEntryFromAgent(id: UUID, name: String?, start: String?, end: String?, category: String?, targetDate: String?) -> String?
    func removeTaskFromAgent(id: UUID) -> DeletedRecordSnapshot?
    func removeTimeEntryFromAgent(id: UUID) -> DeletedRecordSnapshot?
    func toggleTaskFromAgent(id: UUID) -> String?
    func resolveTurnId(shortId: String) -> (UUID, ConversationTurn)?
    func updateTurnFromAgent(id: UUID, title: String?, detail: String?) -> String?
    func removeTurnFromAgent(id: UUID) -> DeletedRecordSnapshot?
    func restoreFromSnapshot(_ snapshot: DeletedRecordSnapshot)
}

final class AgentManager: ObservableObject {
    @Published var session: AgentChatSession = AgentChatSession()
    @Published var threadIndex: [AgentChatThreadIndexItem] = []
    @Published var currentThreadID: UUID?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var debugLogs: [AgentChatDebugLog] = []
    @Published var memories: [AgentMemory] = []
    @Published var memoryStatus: String? = nil

    // MARK: - Streaming state
    @Published var streamingPhase: StreamingPhase = .idle
    @Published var streamingReasoning: String = ""
    @Published var streamingContent: String = ""
    @Published var reasoningTimeMs: Int? = nil

    @Published var executionState: ExecutionState = .idle

    private weak var writer: AgentDataWriter?
    private var lastDeletedSnapshot: DeletedRecordSnapshot?
    private var lastCalendarEventId: String?
    private var nearbyTimeEntries: [(String, [TimeEntry])] = []
    private var currentRequestTask: Task<Void, Never>?
    private var lastUserInput: String = ""
    @Published var messageQueue: [QueuedMessage] = []

    struct QueuedMessage: Identifiable, Equatable {
        let id = UUID()
        let text: String
    }
    private let client: AIClient
    private let defaults: UserDefaults
    private let fileManager: FileManager
    private var userSuffix: String
    private var keyChat: String
    private var keyThreadIndex: String
    private var keyCurrentThreadID: String
    private var keyDebugLogs: String
    private var keyMemories: String
    private var threadDirectory: URL

    static let maxMemories = 15
    static let maxThreads = 30

    init(
        writer: AgentDataWriter,
        userIdSuffix: String,
        client: AIClient = DefaultAIClient(),
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.writer = writer
        self.client = client
        self.defaults = defaults
        self.fileManager = fileManager
        self.userSuffix = userIdSuffix
        let keys = Self.keys(for: userIdSuffix)
        self.keyChat = keys.chat
        self.keyThreadIndex = keys.threadIndex
        self.keyCurrentThreadID = keys.currentThreadID
        self.keyDebugLogs = keys.debugLogs
        self.keyMemories = keys.memories
        self.threadDirectory = Self.threadDirectory(for: userIdSuffix, fileManager: fileManager)
        loadThreads()
        loadDebugLogs()
        loadMemories()
    }

    var currentThreadTitle: String {
        currentThread()?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        ? currentThread()?.title ?? "新的对话"
        : "新的对话"
    }

    func bind(writer: AgentDataWriter) {
        self.writer = writer
    }

    func reloadForUser(suffix: String) {
        userSuffix = suffix
        let keys = Self.keys(for: suffix)
        keyChat = keys.chat
        keyThreadIndex = keys.threadIndex
        keyCurrentThreadID = keys.currentThreadID
        keyDebugLogs = keys.debugLogs
        keyMemories = keys.memories
        threadDirectory = Self.threadDirectory(for: suffix, fileManager: fileManager)
        loadThreads()
        loadDebugLogs()
        loadMemories()
    }

    func send(
        text: String,
        turns: [ConversationTurn],
        tasks: [TaskEntry],
        timeEntries: [TimeEntry],
        checks: [DailyCheckItem],
        nearbyTimeEntries: [(String, [TimeEntry])] = [],
        calendarEvents: [CalendarEventBlock] = [],
        weeklySummary: String? = nil,
        toolExecutor: ((AgentToolCall) -> String)? = nil,
        userProfile: String? = nil
    ) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        self.nearbyTimeEntries = nearbyTimeEntries
        ensureCurrentThread()
        let traceID = UUID().uuidString
        let threadID = currentThreadID?.uuidString

        let request = AgentOrchestrator.makeRequest(
            input: clean,
            session: session,
            turns: turns,
            tasks: tasks,
            timeEntries: timeEntries,
            checks: checks,
            memories: memories,
            nearbyTimeEntries: nearbyTimeEntries,
            calendarEvents: calendarEvents,
            weeklySummary: weeklySummary
        )
        lastUserInput = clean
        markMemoriesUsed()
        appendMessage(AgentChatMessage(role: "user", content: clean))
        requestTitleIfNeeded(seed: clean)
        isLoading = true
        errorMessage = nil
        let today = AIParser.isoDate()
        let now = AIParser.isoTime()
        emitTrace(
            traceID: traceID,
            eventName: "request_started",
            payload: [
                "mode": "chat",
                "input": clean,
                "currentDate": today,
                "currentTime": now,
                "contextSummary": request.contextSummary,
                "messages": AgentTracePayload.json(request.messages)
            ]
        )

        currentRequestTask = Task { [weak self] in
            guard let self else { return }
            let bgTaskId = await UIApplication.shared.beginBackgroundTask(withName: "AgentChat") {}
            defer { Task { @MainActor in UIApplication.shared.endBackgroundTask(bgTaskId) } }
            let startedAt = Date()

            await MainActor.run {
                self.streamingPhase = .reasoning
                self.streamingReasoning = ""
                self.streamingContent = ""
                self.reasoningTimeMs = nil
            }

            do {
                try Task.checkCancellation()
                var response: AgentChatResponse
                do {
                    response = try await self.consumeStream(
                        input: request.input,
                        messages: request.messages,
                        contextSummary: request.contextSummary,
                        currentDate: today,
                        currentTime: now,
                        traceId: traceID,
                        sessionId: self.userSuffix,
                        threadId: threadID,
                        userProfile: userProfile
                    )
                } catch {
                    if Self.isNetworkLostError(error) {
                        // 流式断线（后台切出等），用非流式重试一次
                        await MainActor.run {
                            self.streamingPhase = .reasoning
                            self.streamingReasoning = ""
                            self.streamingContent = ""
                        }
                        response = try await self.client.chat(
                            input: request.input,
                            messages: request.messages,
                            contextSummary: request.contextSummary,
                            currentDate: today,
                            currentTime: now,
                            traceId: traceID,
                            sessionId: self.userSuffix,
                            threadId: threadID,
                            userProfile: userProfile
                        )
                        await MainActor.run { self.streamingPhase = .done }
                    } else {
                        throw error
                    }
                }

                if let toolCall = response.toolCall, let executor = toolExecutor {
                    await MainActor.run {
                        if !response.reply.isEmpty {
                            self.appendMessage(AgentChatMessage(
                                role: "assistant",
                                content: response.reply,
                                reasoningContent: self.streamingReasoning.isEmpty ? nil : self.streamingReasoning,
                                reasoningTimeMs: self.reasoningTimeMs
                            ))
                        }
                        // Reset streaming state for second round
                        self.streamingPhase = .reasoning
                        self.streamingReasoning = ""
                        self.streamingContent = ""
                        self.reasoningTimeMs = nil
                    }
                    self.emitTrace(
                        traceID: traceID,
                        eventName: "tool_call_started",
                        latencyMs: Self.msSince(startedAt),
                        payload: [
                            "mode": "chat",
                            "toolName": toolCall.name,
                            "toolArgs": AgentTracePayload.json(toolCall.args ?? [:]),
                            "intermediateReply": response.reply
                        ]
                    )
                    let toolResult = executor(toolCall)
                    self.emitTrace(
                        traceID: traceID,
                        eventName: "tool_call_result",
                        payload: [
                            "mode": "chat",
                            "toolName": toolCall.name,
                            "toolResult": toolResult
                        ]
                    )
                    let followUpRequest = AgentOrchestrator.makeRequest(
                        input: clean,
                        session: self.session,
                        turns: turns,
                        tasks: tasks,
                        timeEntries: timeEntries,
                        checks: checks,
                        memories: self.memories,
                        toolResult: toolResult
                    )
                    let followUpResponse = try await self.consumeStream(
                        input: followUpRequest.input,
                        messages: followUpRequest.messages,
                        contextSummary: followUpRequest.contextSummary,
                        currentDate: today,
                        currentTime: now,
                        traceId: traceID,
                        sessionId: self.userSuffix,
                        threadId: threadID,
                        userProfile: userProfile
                    )
                    await MainActor.run {
                        let mergedActions = self.actionSuggestionsToMerge(from: followUpResponse)
                        self.finishStreaming(
                            response: followUpResponse,
                            mergedActions: mergedActions
                        )
                        self.emitTrace(
                            traceID: traceID,
                            eventName: "response_merged",
                            usage: followUpResponse.usage,
                            latencyMs: Self.msSince(startedAt),
                            payload: [
                                "mode": "chat",
                                "reply": followUpResponse.reply,
                                "followUpQuestion": followUpResponse.followUpQuestion ?? "",
                                "actionSuggestions": AgentTracePayload.json(followUpResponse.actionSuggestions),
                                "mergedActions": AgentTracePayload.json(mergedActions),
                                "rawResponse": followUpResponse.rawBody ?? "",
                                "toolCallUsed": toolCall.name
                            ]
                        )
                        self.recordDebugLog(
                            input: clean,
                            request: followUpRequest,
                            currentDate: today,
                            currentTime: now,
                            response: followUpResponse,
                            mergedActions: mergedActions,
                            traceID: traceID
                        )
                    }
                } else {
                    await MainActor.run {
                        let mergedActions = self.actionSuggestionsToMerge(from: response)
                        self.finishStreaming(
                            response: response,
                            mergedActions: mergedActions
                        )
                        self.emitTrace(
                            traceID: traceID,
                            eventName: "response_merged",
                            usage: response.usage,
                            latencyMs: Self.msSince(startedAt),
                            payload: [
                                "mode": "chat",
                                "reply": response.reply,
                                "followUpQuestion": response.followUpQuestion ?? "",
                                "actionSuggestions": AgentTracePayload.json(response.actionSuggestions),
                                "mergedActions": AgentTracePayload.json(mergedActions),
                                "rawResponse": response.rawBody ?? ""
                            ]
                        )
                        self.recordDebugLog(
                            input: clean,
                            request: request,
                            currentDate: today,
                            currentTime: now,
                            response: response,
                            mergedActions: mergedActions,
                            traceID: traceID
                        )
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.streamingPhase = .idle
                    self.streamingReasoning = ""
                    self.streamingContent = ""
                    self.isLoading = false
                    self.session.messages.append(
                        AgentChatMessage(role: "assistant", content: "已取消", isError: true)
                    )
                    self.saveCurrentThread()
                    self.processQueue()
                }
            } catch {
                await MainActor.run {
                    self.streamingPhase = .idle
                    self.streamingReasoning = ""
                    self.streamingContent = ""

                    let fallback = AgentOrchestrator.fallbackResponse(for: clean, weeklySummary: weeklySummary)
                    self.errorMessage = weeklySummary != nil && AgentOrchestrator.detectsReviewIntent(clean)
                        ? nil
                        : "对话服务暂时没有接上，我先用本地方式陪你。"
                    let mergedActions = self.actionSuggestionsToMerge(from: fallback)
                    self.isLoading = false
                    let pieces = [fallback.reply, fallback.followUpQuestion]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    let content = pieces.joined(separator: "\n\n")
                    if !content.isEmpty {
                        self.session.messages.append(
                            AgentChatMessage(role: "assistant", content: content, isError: true)
                        )
                    }
                    self.mergeActionSuggestions(mergedActions)
                    self.saveCurrentThread()
                    self.emitTrace(
                        traceID: traceID,
                        eventName: "request_failed",
                        latencyMs: Self.msSince(startedAt),
                        error: AgentTraceErrorInfo(type: String(describing: type(of: error)), message: error.localizedDescription, status: nil),
                        payload: [
                            "mode": "chat",
                            "input": clean,
                            "fallbackReply": fallback.reply
                        ]
                    )
                    self.recordDebugLog(
                        input: clean,
                        request: request,
                        currentDate: today,
                        currentTime: now,
                        response: fallback,
                        mergedActions: mergedActions,
                        errorMessage: error.localizedDescription,
                        traceID: traceID
                    )
                    self.processQueue()
                }
            }
        }
    }

    func sendNudge(
        turns: [ConversationTurn],
        tasks: [TaskEntry],
        timeEntries: [TimeEntry],
        checks: [DailyCheckItem],
        nearbyTimeEntries: [(String, [TimeEntry])] = [],
        calendarEvents: [CalendarEventBlock] = [],
        toolExecutor: ((AgentToolCall) -> String)? = nil,
        userProfile: String? = nil
    ) {
        self.nearbyTimeEntries = nearbyTimeEntries
        ensureCurrentThread()
        let traceID = UUID().uuidString
        let threadID = currentThreadID?.uuidString

        let request = AgentOrchestrator.makeRequest(
            input: "[nudge]",
            session: session,
            turns: turns,
            tasks: tasks,
            timeEntries: timeEntries,
            checks: checks,
            memories: memories,
            nearbyTimeEntries: nearbyTimeEntries,
            calendarEvents: calendarEvents,
            trigger: .scheduledNudge
        )
        markMemoriesUsed()
        isLoading = true
        errorMessage = nil
        let today = AIParser.isoDate()
        let now = AIParser.isoTime()

        currentRequestTask = Task { [weak self] in
            guard let self else { return }
            let bgTaskId = await UIApplication.shared.beginBackgroundTask(withName: "AgentNudge") {}
            defer { Task { @MainActor in UIApplication.shared.endBackgroundTask(bgTaskId) } }

            await MainActor.run {
                self.streamingPhase = .reasoning
                self.streamingReasoning = ""
                self.streamingContent = ""
                self.reasoningTimeMs = nil
            }

            do {
                try Task.checkCancellation()
                let response = try await self.consumeStream(
                    input: "[nudge]",
                    messages: request.messages,
                    contextSummary: request.contextSummary,
                    currentDate: today,
                    currentTime: now,
                    traceId: traceID,
                    sessionId: self.userSuffix,
                    threadId: threadID,
                    userProfile: userProfile,
                    trigger: "scheduledNudge"
                )

                await MainActor.run {
                    let mergedActions = self.actionSuggestionsToMerge(from: response)
                    self.finishStreaming(response: response, mergedActions: mergedActions)
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.streamingPhase = .idle
                    self.streamingReasoning = ""
                    self.streamingContent = ""
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.streamingPhase = .idle
                    self.streamingReasoning = ""
                    self.streamingContent = ""
                    self.isLoading = false
                    self.errorMessage = "主动触达暂时没有接上"
                }
            }
        }
    }

    func cancelCurrentRequest() {
        currentRequestTask?.cancel()
        currentRequestTask = nil
    }

    func enqueueMessage(_ text: String) {
        messageQueue.append(QueuedMessage(text: text))
    }

    func removeQueuedMessage(id: UUID) {
        messageQueue.removeAll { $0.id == id }
    }

    private func processQueue() {
        guard !messageQueue.isEmpty else { return }
        let next = messageQueue.removeFirst()
        queuedMessageHandler?(next.text)
    }

    var queuedMessageHandler: ((String) -> Void)?

    func quickSend(text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        ensureCurrentThread()
        let traceID = UUID().uuidString
        let threadID = currentThreadID?.uuidString
        appendMessage(AgentChatMessage(role: "user", content: clean))
        requestTitleIfNeeded(seed: clean)
        isLoading = true
        errorMessage = nil
        let today = AIParser.isoDate()
        let now = AIParser.isoTime()
        emitTrace(
            traceID: traceID,
            eventName: "request_started",
            payload: [
                "mode": "quick",
                "input": clean,
                "currentDate": today,
                "currentTime": now
            ]
        )

        Task { [weak self] in
            guard let self else { return }
            let startedAt = Date()
            do {
                let response = try await self.client.quick(
                    input: clean,
                    currentDate: today,
                    currentTime: now,
                    traceId: traceID,
                    sessionId: self.userSuffix,
                    threadId: threadID
                )
                await MainActor.run {
                    self.isLoading = false
                    let actions = response.actionSuggestions.filter { self.hasContent($0) }
                    self.mergeActionSuggestions(actions)
                    let pieces = [response.reply, response.followUpQuestion]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    if !pieces.isEmpty {
                        self.appendMessage(AgentChatMessage(role: "assistant", content: pieces.joined(separator: "\n\n")))
                    } else {
                        self.saveCurrentThread()
                    }
                    self.emitTrace(
                        traceID: traceID,
                        eventName: "response_merged",
                        usage: response.usage,
                        latencyMs: Self.msSince(startedAt),
                        payload: [
                            "mode": "quick",
                            "reply": response.reply,
                            "followUpQuestion": response.followUpQuestion ?? "",
                            "actionSuggestions": AgentTracePayload.json(response.actionSuggestions),
                            "mergedActions": AgentTracePayload.json(actions),
                            "rawResponse": response.rawBody ?? ""
                        ]
                    )
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = "快录失败，请重试。"
                    self.saveCurrentThread()
                    self.emitTrace(
                        traceID: traceID,
                        eventName: "request_failed",
                        latencyMs: Self.msSince(startedAt),
                        error: AgentTraceErrorInfo(type: String(describing: type(of: error)), message: error.localizedDescription, status: nil),
                        payload: [
                            "mode": "quick",
                            "input": clean
                        ]
                    )
                }
            }
        }
    }

    func actionSuggestionsToMerge(from response: AgentChatResponse) -> [AgentActionDraft] {
        let isAskingFollowUp = response.followUpQuestion?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        return isAskingFollowUp ? [] : response.actionSuggestions
    }

    func mergeActionSuggestions(_ suggestions: [AgentActionDraft]) {
        let hasConversation = session.messages.count >= 3
        if hasConversation && !suggestions.isEmpty {
            session.pendingActions.removeAll()
        }

        var resolved: [AgentActionDraft] = []
        for var action in suggestions where hasContent(action) || action.isMutation {
            if action.isMutation {
                guard let r = resolveMutationTarget(action) else { continue }
                action = r
            }
            // Self-correction: validate and adjust confidence
            action = validateAction(action)
            resolved.append(action)
        }

        let autoConfirmableCreates = resolved.filter { !$0.isMutation && shouldAutoConfirm($0) }
        let useBatchChecklist = autoConfirmableCreates.count >= 2

        for action in resolved {
            if useBatchChecklist && !action.isMutation && shouldAutoConfirm(action) {
                session.pendingActions.append(action)
            } else if shouldAutoConfirm(action) {
                autoConfirmAction(action)
            } else if let existingIndex = session.pendingActions.firstIndex(where: { isSameIntent($0, action) }) {
                if completenessScore(action) >= completenessScore(session.pendingActions[existingIndex]) {
                    session.pendingActions[existingIndex] = action
                }
            } else {
                session.pendingActions.append(action)
            }
        }
        saveCurrentThread()

        if useBatchChecklist {
            executePendingActions()
        }
    }

    /// 解析 mutation action 的 targetId，验证记录存在，填充 before→after 信息到 detail
    private func resolveMutationTarget(_ action: AgentActionDraft) -> AgentActionDraft? {
        guard let shortId = action.targetId, !shortId.isEmpty else { return nil }
        var resolved = action

        switch action.kind {
        case .editTask, .deleteTask, .completeTask:
            guard let (fullId, task) = writer?.resolveTaskId(shortId: shortId) else { return nil }
            resolved.targetId = fullId.uuidString
            if resolved.title.isEmpty { resolved.title = task.title }
            // 生成 before→after diff 文本
            if action.kind == .editTask {
                var diffs: [String] = []
                if let newTitle = nonEmpty(action.title), newTitle != task.title {
                    diffs.append("标题: \(task.title) → \(newTitle)")
                }
                if let newDate = nonEmpty(action.date), newDate != task.dueDate {
                    diffs.append("日期: \(task.dueDate.isEmpty ? "无" : task.dueDate) → \(newDate)")
                }
                if let newStart = nonEmpty(action.startTime), newStart != task.startTime {
                    diffs.append("开始: \(task.startTime.isEmpty ? "无" : task.startTime) → \(newStart)")
                }
                if let newEnd = nonEmpty(action.endTime), newEnd != task.endTime {
                    diffs.append("结束: \(task.endTime.isEmpty ? "无" : task.endTime) → \(newEnd)")
                }
                if !diffs.isEmpty {
                    resolved.detail = diffs.joined(separator: "\n")
                }
            } else if action.kind == .deleteTask {
                resolved.detail = "将删除待办「\(task.title)」"
            } else if action.kind == .completeTask {
                let current = task.status == "已完成" ? "已完成 → 未完成" : "未完成 → 已完成"
                resolved.detail = current
            }

        case .editInbox, .deleteInbox:
            guard let (fullId, turn) = writer?.resolveTurnId(shortId: shortId) else { return nil }
            resolved.targetId = fullId.uuidString
            if resolved.title.isEmpty {
                resolved.title = turn.payload["title"] ?? String(turn.rawText.prefix(30))
            }
            if action.kind == .editInbox {
                var diffs: [String] = []
                let oldTitle = turn.payload["title"] ?? ""
                if let newTitle = nonEmpty(action.title), newTitle != oldTitle {
                    diffs.append("标题: \(oldTitle) → \(newTitle)")
                }
                if let newDetail = nonEmpty(action.detail), newDetail != turn.rawText {
                    diffs.append("内容已更新")
                }
                if !diffs.isEmpty {
                    resolved.detail = diffs.joined(separator: "\n")
                }
            } else {
                let turnTitle = turn.payload["title"] ?? String(turn.rawText.prefix(30))
                resolved.detail = "将删除随手记「\(turnTitle)」"
            }

        case .editTime, .deleteTime:
            guard let (fullId, entry, sourceDateKey) = writer?.resolveTimeEntryId(shortId: shortId) else { return nil }
            resolved.targetId = fullId.uuidString
            if resolved.title.isEmpty { resolved.title = entry.name }
            if action.kind == .editTime {
                var diffs: [String] = []
                if let newDate = nonEmpty(action.date), newDate != sourceDateKey {
                    diffs.append("日期: \(sourceDateKey) → \(newDate)")
                }
                if let newName = nonEmpty(action.title), newName != entry.name {
                    diffs.append("名称: \(entry.name) → \(newName)")
                }
                if let newStart = nonEmpty(action.startTime), newStart != entry.start {
                    diffs.append("开始: \(entry.start) → \(newStart)")
                }
                if let newEnd = nonEmpty(action.endTime), newEnd != entry.end {
                    diffs.append("结束: \(entry.end) → \(newEnd)")
                }
                if let newModule = nonEmpty(action.module), newModule != entry.category {
                    diffs.append("类别: \(entry.category) → \(newModule)")
                }
                if !diffs.isEmpty {
                    resolved.detail = diffs.joined(separator: "\n")
                }
            } else {
                resolved.detail = "将删除时间记录「\(entry.name)」(\(entry.start)-\(entry.end))"
            }

        default:
            return nil
        }
        return resolved
    }

    private func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    // MARK: - Self-correction Layer 2: local validation

    /// 本地规则校验 action，发现问题则降低 confidence，让用户手动确认
    private func validateAction(_ action: AgentActionDraft) -> AgentActionDraft {
        var a = action
        let input = lastUserInput

        // 1. 标题忠实性：title 关键词应出现在用户输入中
        if !a.isMutation && !input.isEmpty && !a.title.isEmpty {
            let keywords = a.title.components(separatedBy: .whitespaces)
                .flatMap { $0.map { String($0) } }  // 拆成单字
                .filter { $0.count >= 2 }
            // 提取连续的2字词
            let titleBigrams = stride(from: 0, to: max(0, a.title.count - 1), by: 1).compactMap { i -> String? in
                let start = a.title.index(a.title.startIndex, offsetBy: i)
                let end = a.title.index(start, offsetBy: 2, limitedBy: a.title.endIndex) ?? a.title.endIndex
                guard a.title.distance(from: start, to: end) == 2 else { return nil }
                return String(a.title[start..<end])
            }
            let matchCount = titleBigrams.filter { input.contains($0) }.count
            if titleBigrams.count >= 2 && matchCount == 0 {
                a.confidence = min(a.confidence, 0.5)
            }
        }

        // 2. 日期合理性：±30天以外的日期降 confidence
        if let dateStr = a.date {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            fmt.locale = Locale(identifier: "en_US_POSIX")
            if let actionDate = fmt.date(from: dateStr) {
                let daysDiff = abs(Calendar.current.dateComponents([.day], from: Date(), to: actionDate).day ?? 0)
                if daysDiff > 30 {
                    a.confidence = min(a.confidence, 0.3)
                }
            }
        }

        // 3. 时间逻辑：endTime 应在 startTime 之后
        if let start = a.startTime, let end = a.endTime,
           !start.isEmpty, !end.isEmpty, end < start {
            a.confidence = min(a.confidence, 0.4)
        }

        return a
    }

    /// 判断是否自动保存：AI confidence 只做参考，用规则兜底
    private func shouldAutoConfirm(_ action: AgentActionDraft) -> Bool {
        // Mutation 操作永不自动确认
        if action.isMutation { return false }
        // AI 自报 confidence 太低时不自动保存
        guard action.confidence >= 0.7 else { return false }
        // DBT练习记录需要用户确认，不自动保存
        if action.inboxType == "DBT练习" { return false }
        switch action.kind {
        case .inbox:
            // 随手记：有标题或内容就自动存
            return !action.title.isEmpty || !action.detail.isEmpty
        case .task:
            // 待办：必须有标题
            return !action.title.isEmpty
        case .time:
            // 时间记录：必须有标题 + 开始和结束时间
            return !action.title.isEmpty
                && action.startTime != nil && !action.startTime!.isEmpty
                && action.endTime != nil && !action.endTime!.isEmpty
        case .calendarEvent:
            // 日历事件写入系统日历，始终需要用户确认
            return false
        case .editTask, .editTime, .editInbox, .deleteTask, .deleteTime, .deleteInbox, .completeTask:
            return false  // 已被上面的 guard 拦截，这里兜底
        }
    }

    private func autoConfirmAction(_ action: AgentActionDraft) {
        let ref: AutoSavedActionRef?
        let result: String?
        switch action.kind {
        case .inbox:
            let turnId = commitInboxActionReturningId(action)
            ref = turnId.map { AutoSavedActionRef(kind: .inbox, title: action.title, turnId: $0) }
            result = turnId == nil ? "内容为空，未保存" : nil
        case .task:
            let taskId = commitTaskActionReturningId(action)
            ref = taskId.map { AutoSavedActionRef(kind: .task, title: action.title, taskId: $0) }
            result = taskId == nil ? "待办标题为空" : nil
        case .time:
            let turnId = commitTimeActionReturningId(action)
            ref = turnId.map { AutoSavedActionRef(kind: .time, title: action.title, turnId: $0) }
            result = turnId == nil ? "时间记录缺少时间" : nil
        case .calendarEvent:
            ref = nil
            result = "calendarEvent 不走 autoConfirm"
        case .editTask, .editTime, .editInbox, .deleteTask, .deleteTime, .deleteInbox, .completeTask:
            ref = nil
            result = "mutation 不应走 autoConfirm"
        }
        if result == nil, let ref {
            appendMessage(AgentChatMessage(
                role: "assistant",
                content: savedMessage(for: action),
                autoSavedAction: ref
            ))
            emitTrace(
                traceID: UUID().uuidString,
                eventName: "action_auto_confirmed",
                payload: [
                    "actionId": action.id.uuidString,
                    "action": AgentTracePayload.json(action),
                    "confidence": String(action.confidence),
                    "result": savedMessage(for: action)
                ]
            )
        } else {
            session.pendingActions.append(action)
        }
    }

    private func commitInboxActionReturningId(_ action: AgentActionDraft) -> UUID? {
        guard let writer else { return nil }
        let recognizedType = inboxType(for: action)
        guard let id = writer.addTurnDraft(
            rawText: action.detail.isEmpty ? action.title : action.detail,
            recognizedType: recognizedType,
            targetBucket: "inbox",
            confidence: action.confidence,
            payload: [
                "title": action.title.isEmpty ? fallbackTitle(action.detail) : action.title,
                "detail": action.detail,
                "status": "待处理",
                "ai_source": "agent"
            ],
            status: "draft",
            fixHint: "",
            moodScore: normalizedMood(action.mood),
            feelingTags: normalizedFeelings(action.feelings)
        ) else { return nil }
        let err = writer.commitTurn(id: id)
        return err == nil ? id : nil
    }

    private func commitTaskActionReturningId(_ action: AgentActionDraft) -> UUID? {
        guard let writer else { return nil }
        let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return writer.addTask(
            title: title,
            detail: action.detail,
            status: "待办",
            priority: "",
            dueDate: action.date ?? "",
            date: writer.selectedDateKey,
            completedAt: nil,
            isAllDay: (action.startTime ?? "").isEmpty,
            startTime: action.startTime ?? "",
            endTime: action.endTime ?? "",
            location: "",
            sourceNoteId: nil,
            sourceExcerpt: ""
        )
    }

    private func commitTimeActionReturningId(_ action: AgentActionDraft) -> UUID? {
        guard let writer else { return nil }
        let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = action.startTime ?? ""
        let end = action.endTime ?? ""
        guard !start.isEmpty, !end.isEmpty else { return nil }
        guard let id = writer.addTurnDraft(
            rawText: action.detail.isEmpty ? title : action.detail,
            recognizedType: "时间记录",
            targetBucket: "time",
            confidence: action.confidence,
            payload: [
                "name": title.isEmpty ? "时间记录" : title,
                "start": start,
                "end": end,
                "category": timeModule(for: action),
                "note": action.detail,
                "date": action.date ?? writer.selectedDateKey,
                "ai_source": "agent"
            ],
            status: "draft",
            fixHint: "",
            moodScore: nil,
            feelingTags: []
        ) else { return nil }
        let err = writer.commitTurn(id: id)
        return err == nil ? id : nil
    }

    private func emitTrace(
        traceID: String,
        eventName: String,
        usage: AgentTokenUsage? = nil,
        latencyMs: Int? = nil,
        error: AgentTraceErrorInfo? = nil,
        payload: [String: String] = [:]
    ) {
        let event = AgentTraceEvent(
            traceId: traceID,
            sessionId: userSuffix.isEmpty ? nil : userSuffix,
            threadId: currentThreadID?.uuidString,
            eventName: eventName,
            payload: payload,
            usage: usage,
            latencyMs: latencyMs,
            error: error
        )
        Task {
            await AgentTraceLogger.shared.emit(event)
        }
    }

    private static func msSince(_ date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1000)
    }

    private static func isNetworkLostError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return urlError.code == .networkConnectionLost || urlError.code == .timedOut
        }
        if case AIParseError.network(let msg) = error {
            return msg.contains("connection was lost") || msg.contains("networkConnectionLost")
        }
        return false
    }

    @discardableResult
    func confirmAction(id: UUID) -> String? {
        guard let action = session.pendingActions.first(where: { $0.id == id }) else {
            return "建议不存在"
        }

        let result: String?
        switch action.kind {
        case .inbox:
            result = commitInboxAction(action)
        case .task:
            result = commitTaskAction(action)
        case .time:
            result = commitTimeAction(action)
        case .calendarEvent:
            result = commitCalendarEvent(action)
        case .editTask:
            result = commitEditTask(action)
        case .editTime:
            result = commitEditTime(action)
        case .editInbox:
            result = commitEditInbox(action)
        case .deleteTask:
            result = commitDeleteTask(action)
        case .deleteTime:
            result = commitDeleteTime(action)
        case .deleteInbox:
            result = commitDeleteInbox(action)
        case .completeTask:
            result = commitCompleteTask(action)
        }

        if result == nil {
            session.pendingActions.removeAll { $0.id == id }
            // 撤销支持
            var undoRef: AutoSavedActionRef? = nil
            if (action.kind == .deleteTask || action.kind == .deleteTime || action.kind == .deleteInbox),
               let snapshot = lastDeletedSnapshot {
                undoRef = AutoSavedActionRef(kind: action.kind, title: action.title, deletedRecord: snapshot)
                lastDeletedSnapshot = nil
            } else if action.kind == .calendarEvent, let eventId = lastCalendarEventId {
                undoRef = AutoSavedActionRef(kind: .calendarEvent, title: action.title, calendarEventId: eventId)
                lastCalendarEventId = nil
            }
            let msg = AgentChatMessage(
                role: "assistant",
                content: savedMessage(for: action),
                autoSavedAction: undoRef
            )
            appendMessage(msg)
            emitTrace(
                traceID: UUID().uuidString,
                eventName: "action_confirmed",
                payload: [
                    "actionId": id.uuidString,
                    "action": AgentTracePayload.json(action),
                    "result": savedMessage(for: action)
                ]
            )
        }
        return result
    }

    func dismissAction(id: UUID) {
        let action = session.pendingActions.first(where: { $0.id == id })
        session.pendingActions.removeAll { $0.id == id }
        saveCurrentThread()
        emitTrace(
            traceID: UUID().uuidString,
            eventName: "action_dismissed",
            payload: [
                "actionId": id.uuidString,
                "action": action.map { AgentTracePayload.json($0) } ?? ""
            ]
        )
    }

    func executePendingActions() {
        let actions = session.pendingActions.filter { !$0.isMutation }
        guard !actions.isEmpty else { return }
        executionState = .executing(total: actions.count, completed: 0)

        Task { @MainActor in
            var succeeded: [String] = []
            var failed: [String] = []
            for (index, action) in actions.enumerated() {
                let err = confirmAction(id: action.id)
                if let err {
                    failed.append("\(action.title.isEmpty ? action.detail : action.title)（\(err)）")
                } else {
                    succeeded.append(action.title.isEmpty ? action.detail : action.title)
                }
                executionState = .executing(total: actions.count, completed: index + 1)
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            executionState = .idle

            // 执行反馈：≥2 条时追加汇总消息
            if actions.count >= 2 {
                let summary = buildExecutionSummary(succeeded: succeeded, failed: failed)
                appendMessage(AgentChatMessage(role: "assistant", content: summary))
                saveCurrentThread()
            }
        }
    }

    private func buildExecutionSummary(succeeded: [String], failed: [String]) -> String {
        var lines: [String] = []
        if !succeeded.isEmpty {
            lines.append("✅ 已完成 \(succeeded.count) 条")
        }
        if !failed.isEmpty {
            lines.append("⚠️ \(failed.count) 条未成功：")
            for item in failed { lines.append("  · \(item)") }
        }
        if failed.isEmpty && succeeded.count >= 3 {
            lines.append("全部搞定，有问题随时说。")
        }
        return lines.joined(separator: "\n")
    }

    func dismissAllPendingActions() {
        let actions = session.pendingActions.filter { !$0.isMutation }
        for action in actions {
            dismissAction(id: action.id)
        }
    }

    func undoAutoSavedAction(messageId: UUID) {
        guard let idx = session.messages.firstIndex(where: { $0.id == messageId }),
              let ref = session.messages[idx].autoSavedAction else { return }
        switch ref.kind {
        case .inbox:
            if let turnId = ref.turnId { writer?.undoTurn(id: turnId) }
        case .task:
            if let taskId = ref.taskId { writer?.undoTask(id: taskId) }
        case .time:
            if let turnId = ref.turnId {
                writer?.undoTimeFromTurn(id: turnId)
                writer?.undoTurn(id: turnId)
            }
        case .deleteTask, .deleteTime, .deleteInbox:
            if let snapshot = ref.deletedRecord {
                writer?.restoreFromSnapshot(snapshot)
            }
        case .calendarEvent:
            if let eventId = ref.calendarEventId {
                try? CalendarService.shared.deleteEvent(identifier: eventId)
            }
        case .editTask, .editTime, .editInbox, .completeTask:
            break  // edit/complete 暂不支持撤销
        }
        session.messages[idx].content = "已撤销：\(ref.title)"
        session.messages[idx].autoSavedAction = nil
        saveCurrentThread()
        emitTrace(
            traceID: UUID().uuidString,
            eventName: "action_auto_undo",
            payload: [
                "messageId": messageId.uuidString,
                "kind": ref.kind.rawValue,
                "title": ref.title
            ]
        )
    }

    func clearChat() {
        let messagesToExtract = session.messages
        let extractedCount = currentThread()?.memoryExtractedCount ?? 0
        let threadID = currentThreadID
        if let threadID {
            deleteThreadFile(id: threadID)
            threadIndex.removeAll { $0.id == threadID }
        }
        forceCreateNewThread()
        errorMessage = nil

        if messagesToExtract.count >= 10 && messagesToExtract.count > extractedCount {
            memoryStatus = "正在提取记忆..."
            Task { [weak self] in
                await self?.extractMemories(from: messagesToExtract)
            }
        }
    }

    func prepareForPanelClose() {
        extractMemoriesForCurrentThreadIfNeeded()
    }

    func createNewThread(saveOldForMemory: Bool = true) {
        if session.messages.isEmpty && currentThreadID != nil { return }
        forceCreateNewThread(saveOldForMemory: saveOldForMemory)
    }

    private func forceCreateNewThread(saveOldForMemory: Bool = false) {
        if saveOldForMemory {
            extractMemoriesForCurrentThreadIfNeeded()
        }
        let now = Date()
        let thread = AgentChatThread(createdAt: now, updatedAt: now)
        currentThreadID = thread.id
        session = thread.session
        upsertIndex(for: thread)
        saveThread(thread)
        saveThreadIndex()
        defaults.set(thread.id.uuidString, forKey: keyCurrentThreadID)
        enforceThreadLimit()
    }

    func selectThread(id: UUID) {
        guard id != currentThreadID else { return }
        extractMemoriesForCurrentThreadIfNeeded()
        let thread = loadThread(id: id) ?? AgentChatThread(id: id)
        currentThreadID = thread.id
        session = thread.session
        upsertIndex(for: thread)
        saveThreadIndex()
        defaults.set(thread.id.uuidString, forKey: keyCurrentThreadID)
    }

    @discardableResult
    func deleteThread(id: UUID) -> AgentChatThread? {
        let deleted = loadThread(id: id)
        deleteThreadFile(id: id)
        threadIndex.removeAll { $0.id == id }
        saveThreadIndex()

        if id == currentThreadID {
            if let next = threadIndex.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
                selectThread(id: next.id)
            } else {
                forceCreateNewThread()
            }
        }
        return deleted
    }

    func restoreThread(_ thread: AgentChatThread) {
        saveThread(thread)
        upsertIndex(for: thread)
        saveThreadIndex()
        selectThread(id: thread.id)
    }

    func clearDebugLogs() {
        debugLogs = []
        defaults.removeObject(forKey: keyDebugLogs)
    }

    func clearAllUserData() {
        for item in threadIndex {
            deleteThreadFile(id: item.id)
        }
        try? fileManager.removeItem(at: threadDirectory)
        threadIndex = []
        currentThreadID = nil
        session = AgentChatSession()
        memories = []
        debugLogs = []
        defaults.removeObject(forKey: keyChat)
        defaults.removeObject(forKey: keyThreadIndex)
        defaults.removeObject(forKey: keyCurrentThreadID)
        defaults.removeObject(forKey: keyMemories)
        defaults.removeObject(forKey: keyDebugLogs)
        forceCreateNewThread()
    }

    func addMemory(content: String, category: String = "fact", source: String = "user") {
        let clean = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if memories.contains(where: { $0.content == clean }) { return }
        memories.append(AgentMemory(content: clean, category: category, source: source))
        trimMemories()
        saveMemories()
    }

    func removeMemory(id: UUID) {
        memories.removeAll { $0.id == id }
        saveMemories()
    }

    func markMemoriesUsed() {
        let now = Date()
        for i in memories.indices {
            memories[i].lastUsedAt = now
        }
        saveMemories()
    }

    func threadMatchesSearch(_ item: AgentChatThreadIndexItem, query: String) -> Bool {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return true }
        if item.title.localizedCaseInsensitiveContains(clean) { return true }
        guard let thread = loadThread(id: item.id) else { return false }
        return thread.messages.contains { $0.content.localizedCaseInsensitiveContains(clean) }
    }

    func archivedThreadsForBackup() -> [[String: Any]] {
        threadIndex.compactMap { item in
            guard let thread = loadThread(id: item.id),
                  let data = try? JSONEncoder.agentThreadEncoder.encode(thread),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return object
        }
    }

    private func receiveResponse(_ response: AgentChatResponse, mergedActions: [AgentActionDraft]? = nil) {
        isLoading = false
        let pieces = [response.reply, response.followUpQuestion]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let content = pieces.joined(separator: "\n\n")
        if !content.isEmpty {
            session.messages.append(AgentChatMessage(role: "assistant", content: content))
        }
        mergeActionSuggestions(mergedActions ?? actionSuggestionsToMerge(from: response))
        saveCurrentThread()
    }

    // MARK: - Streaming helpers

    /// Consume a streaming response, updating published state on MainActor.
    /// Returns a synthesized AgentChatResponse when the stream completes.
    private func consumeStream(
        input: String,
        messages: [AgentChatRequestMessage],
        contextSummary: String,
        currentDate: String,
        currentTime: String,
        traceId: String?,
        sessionId: String?,
        threadId: String?,
        userProfile: String?,
        trigger: String? = nil
    ) async throws -> AgentChatResponse {
        let stream = client.chatStream(
            input: input,
            messages: messages,
            contextSummary: contextSummary,
            currentDate: currentDate,
            currentTime: currentTime,
            traceId: traceId,
            sessionId: sessionId,
            threadId: threadId,
            userProfile: userProfile,
            trigger: trigger
        )

        var finalResponse: AgentChatResponse?

        for try await event in stream {
            switch event.type {
            case .reasoning:
                if let text = event.text {
                    await MainActor.run {
                        self.streamingReasoning += text
                    }
                }
            case .content:
                if let text = event.text {
                    await MainActor.run {
                        if self.streamingPhase == .reasoning {
                            self.streamingPhase = .content
                        }
                        self.streamingContent += text
                    }
                }
            case .done:
                let reply = event.reply ?? ""
                let reasoningMs = event.reasoningTimeMs
                await MainActor.run {
                    self.streamingPhase = .done
                    self.reasoningTimeMs = reasoningMs
                }
                finalResponse = AgentChatResponse(
                    reply: reply,
                    followUpQuestion: event.followUpQuestion,
                    actionSuggestions: event.actionSuggestions ?? [],
                    toolCall: event.toolCall,
                    usage: event.usage
                )
            case .error:
                throw AIParseError.network(event.message ?? "stream error")
            }
        }

        guard let response = finalResponse else {
            // Stream ended without done event — use accumulated content
            let reply = await MainActor.run { self.streamingContent }
            return AgentChatResponse(
                reply: reply.isEmpty ? "我在。你可以继续说一点。" : reply
            )
        }
        return response
    }

    /// Called on MainActor after streaming completes — persists the message with reasoning.
    private func finishStreaming(
        response: AgentChatResponse,
        mergedActions: [AgentActionDraft]
    ) {
        isLoading = false
        let pieces = [response.reply, response.followUpQuestion]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let content = pieces.joined(separator: "\n\n")
        if !content.isEmpty {
            session.messages.append(AgentChatMessage(
                role: "assistant",
                content: content,
                reasoningContent: streamingReasoning.isEmpty ? nil : streamingReasoning,
                reasoningTimeMs: reasoningTimeMs
            ))
        }
        mergeActionSuggestions(mergedActions)
        saveCurrentThread()

        streamingPhase = .idle
        streamingReasoning = ""
        streamingContent = ""
        reasoningTimeMs = nil

        processQueue()
    }

    private func appendMessage(_ message: AgentChatMessage) {
        session.messages.append(message)
        saveCurrentThread()
    }

    private func currentThread() -> AgentChatThread? {
        guard let id = currentThreadID else { return nil }
        var thread = loadThread(id: id)
        if thread == nil {
            thread = AgentChatThread(id: id)
        }
        thread?.messages = session.messages
        thread?.pendingActions = session.pendingActions
        return thread
    }

    private func ensureCurrentThread() {
        if currentThreadID == nil {
            forceCreateNewThread()
        }
    }

    private func saveCurrentThread() {
        ensureCurrentThread()
        guard var thread = currentThread() else { return }
        thread.updatedAt = Date()
        if thread.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let firstUser = thread.messages.first(where: { $0.role == "user" }) {
            thread.title = localTitle(from: firstUser.content)
        }
        saveThread(thread)
        upsertIndex(for: thread)
        saveThreadIndex()
        defaults.set(thread.id.uuidString, forKey: keyCurrentThreadID)
        session = thread.session
    }

    private func requestTitleIfNeeded(seed: String) {
        guard let id = currentThreadID,
              var thread = loadThread(id: id),
              !thread.titleGenerated,
              thread.messages.filter({ $0.role == "user" }).count == 1
        else { return }
        thread.title = localTitle(from: seed)
        saveThread(thread)
        upsertIndex(for: thread)
        saveThreadIndex()

        Task { [weak self] in
            guard let self else { return }
            let title: String
            do {
                title = try await self.client.suggestTitle(content: seed)
            } catch {
                title = self.localTitle(from: seed)
            }
            await MainActor.run {
                self.applyGeneratedTitle(title, to: id)
            }
        }
    }

    private func applyGeneratedTitle(_ title: String, to id: UUID) {
        let clean = localTitle(from: title)
        guard !clean.isEmpty, var thread = loadThread(id: id), !thread.titleGenerated else { return }
        thread.title = clean
        thread.titleGenerated = true
        saveThread(thread)
        upsertIndex(for: thread)
        saveThreadIndex()
        if id == currentThreadID {
            session = thread.session
        }
    }

    private func extractMemoriesForCurrentThreadIfNeeded() {
        let messages = session.messages
        guard messages.count >= 10 else { return }
        let thread = currentThread()
        guard messages.count > (thread?.memoryExtractedCount ?? 0) else { return }
        memoryStatus = "正在提取记忆..."
        let countAtExtraction = messages.count
        Task { [weak self] in
            await self?.extractMemories(from: messages)
            await MainActor.run {
                guard let self, let id = self.currentThreadID, var thread = self.loadThread(id: id) else { return }
                thread.memoryExtractedCount = countAtExtraction
                self.saveThread(thread)
            }
        }
    }

    private func trimMemories() {
        guard memories.count > Self.maxMemories else { return }
        memories.sort { $0.lastUsedAt > $1.lastUsedAt }
        memories = Array(memories.prefix(Self.maxMemories))
    }

    private func extractMemories(from messages: [AgentChatMessage]) async {
        do {
            let validMessages = messages.filter { !$0.isError }
            let extracted = try await AIParser.extractMemories(
                messages: validMessages.map { AgentChatRequestMessage(role: $0.role, content: $0.content) }
            )
            await MainActor.run {
                var added = 0
                let profileItems = extracted.filter { $0.scope == "profile" }
                let memoryItems = extracted.filter { $0.scope != "profile" }

                for item in memoryItems where !self.memories.contains(where: { $0.content == item.content }) {
                    self.memories.append(AgentMemory(
                        content: item.content,
                        category: item.category,
                        source: "auto"
                    ))
                    added += 1
                }
                self.trimMemories()
                self.saveMemories()

                if !profileItems.isEmpty, let writer = self.writer {
                    let current = writer.userProfile
                    let newFacts = profileItems
                        .map(\.content)
                        .filter { fact in !current.contains(fact) }
                    if !newFacts.isEmpty {
                        let updated = current.isEmpty
                            ? newFacts.joined(separator: "\n")
                            : current + "\n" + newFacts.joined(separator: "\n")
                        writer.userProfile = updated
                    }
                }

                self.memoryStatus = added > 0 ? "已记住 \(added) 条新信息" : nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.memoryStatus = nil
                }
            }
        } catch {
            await MainActor.run {
                self.memoryStatus = nil
            }
        }
    }

    private func commitInboxAction(_ action: AgentActionDraft) -> String? {
        guard let writer else { return "内部错误" }
        let recognizedType = inboxType(for: action)
        guard let id = writer.addTurnDraft(
            rawText: action.detail.isEmpty ? action.title : action.detail,
            recognizedType: recognizedType,
            targetBucket: "inbox",
            confidence: action.confidence,
            payload: [
                "title": action.title.isEmpty ? fallbackTitle(action.detail) : action.title,
                "detail": action.detail,
                "status": "待处理",
                "ai_source": "agent"
            ],
            status: "draft",
            fixHint: "",
            moodScore: normalizedMood(action.mood),
            feelingTags: normalizedFeelings(action.feelings)
        ) else { return "内容为空，未保存" }
        return writer.commitTurn(id: id)
    }

    private func commitTaskAction(_ action: AgentActionDraft) -> String? {
        guard let writer else { return "内部错误" }
        let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return "待办标题为空" }
        _ = writer.addTask(
            title: title,
            detail: action.detail,
            status: "待办",
            priority: "",
            dueDate: action.date ?? "",
            date: writer.selectedDateKey,
            completedAt: nil,
            isAllDay: (action.startTime ?? "").isEmpty,
            startTime: action.startTime ?? "",
            endTime: action.endTime ?? "",
            location: "",
            sourceNoteId: nil,
            sourceExcerpt: ""
        )
        return nil
    }

    private func commitTimeAction(_ action: AgentActionDraft) -> String? {
        guard let writer else { return "内部错误" }
        let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = action.startTime ?? ""
        let end = action.endTime ?? ""
        guard !start.isEmpty, !end.isEmpty else { return "时间记录缺少开始/结束时间" }
        guard let id = writer.addTurnDraft(
            rawText: action.detail.isEmpty ? title : action.detail,
            recognizedType: "时间记录",
            targetBucket: "time",
            confidence: action.confidence,
            payload: [
                "name": title.isEmpty ? "时间记录" : title,
                "start": start,
                "end": end,
                "category": timeModule(for: action),
                "note": action.detail,
                "date": action.date ?? writer.selectedDateKey,
                "ai_source": "agent"
            ],
            status: "draft",
            fixHint: "",
            moodScore: nil,
            feelingTags: []
        ) else { return "内容为空，未保存" }
        return writer.commitTurn(id: id)
    }

    // MARK: - Mutation commit methods

    private func commitEditTask(_ action: AgentActionDraft) -> String? {
        guard let writer else { return "内部错误" }
        guard let targetId = action.targetId, let uuid = UUID(uuidString: targetId) else { return "记录不存在" }
        return writer.updateTaskFromAgent(
            id: uuid,
            title: nonEmpty(action.title),
            detail: nil,  // detail 存的是 diff 文本，不用于更新
            priority: nil,
            dueDate: nonEmpty(action.date)
        )
    }

    private func commitEditTime(_ action: AgentActionDraft) -> String? {
        guard let writer else { return "内部错误" }
        guard let targetId = action.targetId, let uuid = UUID(uuidString: targetId) else { return "记录不存在" }
        return writer.updateTimeEntryFromAgent(
            id: uuid,
            name: nonEmpty(action.title),
            start: nonEmpty(action.startTime),
            end: nonEmpty(action.endTime),
            category: nonEmpty(action.module),
            targetDate: nonEmpty(action.date)
        )
    }

    private func commitDeleteTask(_ action: AgentActionDraft) -> String? {
        guard let writer else { return "内部错误" }
        guard let targetId = action.targetId, let uuid = UUID(uuidString: targetId) else { return "记录不存在" }
        lastDeletedSnapshot = writer.removeTaskFromAgent(id: uuid)
        return lastDeletedSnapshot == nil ? "记录不存在" : nil
    }

    private func commitDeleteTime(_ action: AgentActionDraft) -> String? {
        guard let writer else { return "内部错误" }
        guard let targetId = action.targetId, let uuid = UUID(uuidString: targetId) else { return "记录不存在" }
        lastDeletedSnapshot = writer.removeTimeEntryFromAgent(id: uuid)
        return lastDeletedSnapshot == nil ? "记录不存在" : nil
    }

    private func commitEditInbox(_ action: AgentActionDraft) -> String? {
        guard let writer else { return "内部错误" }
        guard let targetId = action.targetId, let uuid = UUID(uuidString: targetId) else { return "记录不存在" }
        return writer.updateTurnFromAgent(
            id: uuid,
            title: nonEmpty(action.title),
            detail: nonEmpty(action.detail)
        )
    }

    private func commitDeleteInbox(_ action: AgentActionDraft) -> String? {
        guard let writer else { return "内部错误" }
        guard let targetId = action.targetId, let uuid = UUID(uuidString: targetId) else { return "记录不存在" }
        lastDeletedSnapshot = writer.removeTurnFromAgent(id: uuid)
        return lastDeletedSnapshot == nil ? "记录不存在" : nil
    }

    private func commitCompleteTask(_ action: AgentActionDraft) -> String? {
        guard let writer else { return "内部错误" }
        guard let targetId = action.targetId, let uuid = UUID(uuidString: targetId) else { return "记录不存在" }
        return writer.toggleTaskFromAgent(id: uuid)
    }

    private func commitCalendarEvent(_ action: AgentActionDraft) -> String? {
        let status = CalendarService.shared.authorizationStatus
        guard status == .fullAccess || status == .authorized else {
            return "未授权日历访问，请在系统设置中允许"
        }

        let dateStr = action.date ?? AIParser.isoDate()
        let startTimeStr = action.startTime ?? ""
        let endTimeStr = action.endTime ?? ""
        let isAllDay = startTimeStr.isEmpty && endTimeStr.isEmpty

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        let startDate: Date
        let endDate: Date

        if isAllDay {
            fmt.dateFormat = "yyyy-MM-dd"
            startDate = fmt.date(from: dateStr) ?? Date()
            endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        } else {
            fmt.dateFormat = "yyyy-MM-dd HH:mm"
            startDate = fmt.date(from: "\(dateStr) \(startTimeStr.isEmpty ? "09:00" : startTimeStr)") ?? Date()
            endDate = fmt.date(from: "\(dateStr) \(endTimeStr.isEmpty ? "10:00" : endTimeStr)") ?? Date()
        }

        do {
            let eventId = try CalendarService.shared.createEvent(
                title: action.title,
                startDate: startDate,
                endDate: endDate,
                isAllDay: isAllDay,
                location: nil,
                notes: action.detail.isEmpty ? nil : action.detail
            )
            lastCalendarEventId = eventId
            return nil
        } catch {
            return "创建日历事件失败：\(error.localizedDescription)"
        }
    }

    private func inboxType(for action: AgentActionDraft) -> String {
        let allowedTypes = ["想法", "感受", "感恩", "做梦"]
        if let inboxType = action.inboxType?.trimmingCharacters(in: .whitespacesAndNewlines),
           allowedTypes.contains(inboxType) {
            return inboxType
        }
        let combined = "\(action.title) \(action.detail)"
        if combined.contains("梦到") || combined.contains("梦见") || combined.contains("做梦") {
            return "做梦"
        }
        if combined.contains("感恩") || combined.contains("感谢") {
            return "感恩"
        }
        return "想法"
    }

    private func timeModule(for action: AgentActionDraft) -> String {
        let allowedModules = ["工作", "学习", "运动", "休息", "社交", "其他"]
        if let module = action.module?.trimmingCharacters(in: .whitespacesAndNewlines),
           allowedModules.contains(module) {
            return module
        }
        return "其他"
    }

    private func normalizedMood(_ mood: Int?) -> Int? {
        guard let mood, (1...5).contains(mood) else { return nil }
        return mood
    }

    private func normalizedFeelings(_ feelings: [String]) -> [String] {
        let allowed = Set(["开心", "满足", "兴奋", "激动", "感动", "平静", "放松", "疲惫", "焦虑", "烦躁", "沮丧", "难过", "失望", "愤怒", "孤独", "困惑", "无聊", "好奇", "自豪", "遗憾"])
        var seen = Set<String>()
        return feelings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { allowed.contains($0) }
            .filter { seen.insert($0).inserted }
            .prefix(3)
            .map { $0 }
    }

    private func hasContent(_ action: AgentActionDraft) -> Bool {
        !action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !action.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isSameIntent(_ lhs: AgentActionDraft, _ rhs: AgentActionDraft) -> Bool {
        guard lhs.kind == rhs.kind else { return false }
        let lhsTitle = normalizedText(lhs.title)
        let rhsTitle = normalizedText(rhs.title)
        if !lhsTitle.isEmpty, lhsTitle == rhsTitle { return true }
        let lhsDetail = normalizedText(lhs.detail)
        let rhsDetail = normalizedText(rhs.detail)
        return !lhsDetail.isEmpty && lhsDetail == rhsDetail
    }

    private func normalizedText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func completenessScore(_ action: AgentActionDraft) -> Int {
        [
            action.title,
            action.detail,
            action.date ?? "",
            action.startTime ?? "",
            action.endTime ?? "",
            action.reason
        ].reduce(0) { score, value in
            score + (value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
        }
    }

    private func fallbackTitle(_ text: String) -> String {
        if text.count <= 18 { return text }
        return String(text.prefix(18)) + "…"
    }

    private func localTitle(from text: String) -> String {
        let title = AIParser.threadFallbackTitle(from: text)
        return title.isEmpty ? "新的对话" : title
    }

    private func savedMessage(for action: AgentActionDraft) -> String {
        let title = action.title.isEmpty ? action.detail : action.title
        switch action.kind {
        case .inbox: return "已创建随手记：\(title)"
        case .task: return "已创建待办：\(title)"
        case .time: return "已创建时间记录：\(title)"
        case .calendarEvent: return "已创建日历事件：\(title)"
        case .editTask: return "已修改待办：\(title)"
        case .editTime: return "已修改时间记录：\(title)"
        case .editInbox: return "已修改随手记：\(title)"
        case .deleteTask: return "已删除待办：\(title)"
        case .deleteTime: return "已删除时间记录：\(title)"
        case .deleteInbox: return "已删除随手记：\(title)"
        case .completeTask: return "已更新待办状态：\(title)"
        }
    }

    func debugSummary(_ action: AgentActionDraft) -> String {
        var parts: [String] = ["kind=\(action.kind.rawValue)"]
        if let inboxType = action.inboxType, !inboxType.isEmpty { parts.append("inboxType=\(inboxType)") }
        if let mood = action.mood { parts.append("mood=\(mood)") }
        if !action.feelings.isEmpty { parts.append("feelings=\(action.feelings.joined(separator: ","))") }
        if let module = action.module, !module.isEmpty { parts.append("module=\(module)") }
        parts.append("title=\(action.title)")
        if !action.detail.isEmpty { parts.append("detail=\(action.detail)") }
        if let date = action.date, !date.isEmpty { parts.append("date=\(date)") }
        if let startTime = action.startTime, !startTime.isEmpty { parts.append("startTime=\(startTime)") }
        if let endTime = action.endTime, !endTime.isEmpty { parts.append("endTime=\(endTime)") }
        parts.append("confidence=\(action.confidence)")
        if !action.reason.isEmpty { parts.append("reason=\(action.reason)") }
        return parts.joined(separator: " ; ")
    }

    private func loadThreads() {
        ensureThreadDirectory()
        loadThreadIndex()
        migrateLegacySessionIfNeeded()

        if let idString = defaults.string(forKey: keyCurrentThreadID),
           let id = UUID(uuidString: idString),
           let thread = loadThread(id: id) {
            currentThreadID = id
            session = thread.session
        } else if let first = threadIndex.sorted(by: { $0.updatedAt > $1.updatedAt }).first,
                  let thread = loadThread(id: first.id) {
            currentThreadID = thread.id
            session = thread.session
            defaults.set(thread.id.uuidString, forKey: keyCurrentThreadID)
        } else {
            forceCreateNewThread()
        }
        enforceThreadLimit()
    }

    private func loadThreadIndex() {
        guard let data = defaults.data(forKey: keyThreadIndex) else {
            threadIndex = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        threadIndex = (try? decoder.decode([AgentChatThreadIndexItem].self, from: data)) ?? []
    }

    private func saveThreadIndex() {
        threadIndex.sort { $0.updatedAt > $1.updatedAt }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(threadIndex) else { return }
        defaults.set(data, forKey: keyThreadIndex)
    }

    private func migrateLegacySessionIfNeeded() {
        guard threadIndex.isEmpty,
              let data = defaults.data(forKey: keyChat)
        else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let legacy = try? decoder.decode(AgentChatSession.self, from: data),
              !legacy.messages.isEmpty || !legacy.pendingActions.isEmpty
        else { return }
        let firstUser = legacy.messages.first(where: { $0.role == "user" })?.content ?? "旧对话"
        let thread = AgentChatThread(
            id: legacy.id,
            title: localTitle(from: firstUser),
            messages: legacy.messages,
            pendingActions: legacy.pendingActions,
            createdAt: legacy.messages.first?.createdAt ?? legacy.updatedAt,
            updatedAt: legacy.updatedAt,
            titleGenerated: false
        )
        saveThread(thread)
        upsertIndex(for: thread)
        currentThreadID = thread.id
        defaults.set(thread.id.uuidString, forKey: keyCurrentThreadID)
        saveThreadIndex()
    }

    private func loadThread(id: UUID) -> AgentChatThread? {
        let url = threadURL(id: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(AgentChatThread.self, from: data)
    }

    private func saveThread(_ thread: AgentChatThread) {
        ensureThreadDirectory()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(thread) else { return }
        try? data.write(to: threadURL(id: thread.id), options: [.atomic])
    }

    private func upsertIndex(for thread: AgentChatThread) {
        let item = AgentChatThreadIndexItem(thread: thread)
        if let index = threadIndex.firstIndex(where: { $0.id == thread.id }) {
            threadIndex[index] = item
        } else {
            threadIndex.append(item)
        }
        threadIndex.sort { $0.updatedAt > $1.updatedAt }
    }

    private func enforceThreadLimit() {
        guard threadIndex.count > Self.maxThreads else { return }
        let sorted = threadIndex.sorted { $0.updatedAt < $1.updatedAt }
        let removable = sorted.filter { $0.id != currentThreadID }
        let overflow = threadIndex.count - Self.maxThreads
        for item in removable.prefix(overflow) {
            deleteThreadFile(id: item.id)
            threadIndex.removeAll { $0.id == item.id }
        }
        saveThreadIndex()
    }

    private func deleteThreadFile(id: UUID) {
        try? fileManager.removeItem(at: threadURL(id: id))
    }

    private func ensureThreadDirectory() {
        try? fileManager.createDirectory(at: threadDirectory, withIntermediateDirectories: true)
    }

    private func threadURL(id: UUID) -> URL {
        threadDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    private func loadDebugLogs() {
        guard let data = defaults.data(forKey: keyDebugLogs) else {
            debugLogs = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        debugLogs = (try? decoder.decode([AgentChatDebugLog].self, from: data)) ?? []
    }

    private func saveDebugLogs() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(debugLogs) else { return }
        defaults.set(data, forKey: keyDebugLogs)
    }

    private func loadMemories() {
        guard let data = defaults.data(forKey: keyMemories) else {
            memories = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        memories = (try? decoder.decode([AgentMemory].self, from: data)) ?? []
    }

    private func saveMemories() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(memories) else { return }
        defaults.set(data, forKey: keyMemories)
    }

    private func recordDebugLog(
        input: String,
        request: AgentOrchestrator.Request,
        currentDate: String,
        currentTime: String,
        response: AgentChatResponse,
        mergedActions: [AgentActionDraft],
        errorMessage: String = "",
        traceID: String? = nil
    ) {
        let log = AgentChatDebugLog(
            createdAt: Date(),
            input: input,
            currentDate: currentDate,
            currentTime: currentTime,
            personaSummary: response.debug?.persona ?? "",
            userSummary: response.debug?.userProfile ?? "",
            contextSummary: response.debug?.contextSummary ?? request.contextSummary,
            messagesSummary: (response.debug?.messagesUsed ?? request.messages).map { "\($0.role): \($0.content)" },
            reply: response.reply,
            followUpQuestion: response.followUpQuestion ?? "",
            actionSuggestionsSummary: response.actionSuggestions.map(debugSummary),
            mergedActionSummary: mergedActions.map(debugSummary),
            rawResponse: response.debug?.rawModelOutput ?? response.rawBody ?? "",
            errorMessage: errorMessage
        )
        if AgentTraceConfig.isEnabled {
            emitTrace(
                traceID: traceID ?? UUID().uuidString,
                eventName: "debug_log_created",
                payload: [
                    "input": log.input,
                    "currentDate": log.currentDate,
                    "currentTime": log.currentTime,
                    "personaSummary": log.personaSummary,
                    "userSummary": log.userSummary,
                    "contextSummary": log.contextSummary,
                    "messagesSummary": AgentTracePayload.json(log.messagesSummary),
                    "reply": log.reply,
                    "followUpQuestion": log.followUpQuestion,
                    "actionSuggestionsSummary": AgentTracePayload.json(log.actionSuggestionsSummary),
                    "mergedActionSummary": AgentTracePayload.json(log.mergedActionSummary),
                    "rawResponse": log.rawResponse,
                    "errorMessage": log.errorMessage
                ]
            )
            return
        }
        debugLogs.insert(log, at: 0)
        if debugLogs.count > 20 {
            debugLogs = Array(debugLogs.prefix(20))
        }
        saveDebugLogs()
    }

    private static func keys(for suffix: String) -> (
        chat: String,
        threadIndex: String,
        currentThreadID: String,
        debugLogs: String,
        memories: String
    ) {
        let base = suffix.isEmpty ? "" : ".\(suffix)"
        return (
            "ps.agent.chat\(base)",
            "ps.agent.threads.index\(base)",
            "ps.agent.threads.current\(base)",
            "ps.agent.debug.logs\(base)",
            "ps.agent.memories\(base)"
        )
    }

    private static func threadDirectory(for suffix: String, fileManager: FileManager) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let folder = suffix.isEmpty ? "default" : suffix
        return root
            .appendingPathComponent("agent-threads", isDirectory: true)
            .appendingPathComponent(folder, isDirectory: true)
    }
}

private extension JSONEncoder {
    static var agentThreadEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }
}
