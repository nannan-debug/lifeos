import Foundation
import UIKit

protocol AgentDataWriter: AnyObject {
    var selectedDateKey: String { get }
    var userProfile: String { get set }
    var catName: String { get }
    var catStyle: String { get }
    var catRole: String { get }
    var catProactivity: String { get }
    var catMemoryPreference: String { get }
    var catInstructions: String { get }
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
    func addBrain(
        title: String,
        content: String,
        topics: [String],
        sources: [BrainCardSource],
        kind: String,
        dbtSession: BrainDBTSession?
    ) -> UUID?
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
    private var activeRequestToken: UUID?
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
        if handleMemoryCorrectionIfNeeded(clean) {
            return
        }
        let requestThreadID = currentThreadID
        let requestToken = UUID()
        activeRequestToken = requestToken
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
                "memoryDebug": AgentOrchestrator.memoryDebugSummary(memories, input: clean),
                "messages": AgentTracePayload.json(request.messages)
            ]
        )

        let persona = buildAgentPersona()

        currentRequestTask = Task { [weak self] in
            guard let self else { return }
            let bgTaskId = await UIApplication.shared.beginBackgroundTask(withName: "AgentChat") {}
            defer { Task { @MainActor in UIApplication.shared.endBackgroundTask(bgTaskId) } }
            let startedAt = Date()

            await MainActor.run {
                guard self.isCurrentRequest(requestToken, threadID: requestThreadID) else { return }
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
                        userProfile: userProfile,
                        agentMode: "chat",
                        dbtSession: self.session.dbtSession,
                        agentPersona: persona
                    )
                } catch {
                    if Self.isNetworkLostError(error) {
                        await MainActor.run {
                            guard self.isCurrentRequest(requestToken, threadID: requestThreadID) else { return }
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
                            userProfile: userProfile,
                            agentMode: "chat",
                            dbtSession: self.session.dbtSession,
                            agentPersona: persona
                        )
                        await MainActor.run {
                            guard self.isCurrentRequest(requestToken, threadID: requestThreadID) else { return }
                            self.streamingPhase = .done
                        }
                    } else {
                        throw error
                    }
                }

                let responseSnapshot = response

                if let toolCall = responseSnapshot.toolCall, let executor = toolExecutor {
                    await MainActor.run {
                        guard self.isCurrentRequest(requestToken, threadID: requestThreadID) else { return }
                        if !responseSnapshot.reply.isEmpty {
                            self.appendMessage(AgentChatMessage(
                                role: "assistant",
                                content: responseSnapshot.reply,
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
                            "intermediateReply": responseSnapshot.reply
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
                    let toolFollowUpInput = "[toolResult:\(toolCall.name)] 以上是查询结果，请据此回答用户。"
                    let followUpRequest = AgentOrchestrator.makeRequest(
                        input: toolFollowUpInput,
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
                        userProfile: userProfile,
                        agentMode: "chat",
                        dbtSession: nil,
                        agentPersona: persona
                    )
                    await MainActor.run {
                        guard self.isCurrentRequest(requestToken, threadID: requestThreadID) else { return }
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
                        guard self.isCurrentRequest(requestToken, threadID: requestThreadID) else { return }
                        let mergedActions = self.actionSuggestionsToMerge(from: responseSnapshot)
                        self.finishStreaming(
                            response: responseSnapshot,
                            mergedActions: mergedActions
                        )
                        self.emitTrace(
                            traceID: traceID,
                            eventName: "response_merged",
                            usage: responseSnapshot.usage,
                            latencyMs: Self.msSince(startedAt),
                            payload: [
                                "mode": "chat",
                                "reply": responseSnapshot.reply,
                                "followUpQuestion": responseSnapshot.followUpQuestion ?? "",
                                "actionSuggestions": AgentTracePayload.json(responseSnapshot.actionSuggestions),
                                "mergedActions": AgentTracePayload.json(mergedActions),
                                "rawResponse": responseSnapshot.rawBody ?? ""
                            ]
                        )
                        self.recordDebugLog(
                            input: clean,
                            request: request,
                            currentDate: today,
                            currentTime: now,
                            response: responseSnapshot,
                            mergedActions: mergedActions,
                            traceID: traceID
                        )
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard self.isCurrentRequest(requestToken, threadID: requestThreadID) else { return }
                    self.streamingPhase = .idle
                    self.streamingReasoning = ""
                    self.streamingContent = ""
                    self.isLoading = false
                    self.activeRequestToken = nil
                    self.currentRequestTask = nil
                    self.session.messages.append(
                        AgentChatMessage(role: "assistant", content: "已取消", isError: true)
                    )
                    self.saveCurrentThread()
                    self.processQueue()
                }
            } catch {
                await MainActor.run {
                    guard self.isCurrentRequest(requestToken, threadID: requestThreadID) else { return }
                    self.streamingPhase = .idle
                    self.streamingReasoning = ""
                    self.streamingContent = ""
                    self.activeRequestToken = nil
                    self.currentRequestTask = nil

                    let fallback = AgentOrchestrator.fallbackResponse(for: clean, weeklySummary: weeklySummary)
                    self.errorMessage = weeklySummary != nil && AgentOrchestrator.detectsReviewIntent(clean)
                        ? nil
                        : "对话服务暂时没有接上，我先用本地方式陪你。"
                    let mergedActions = self.actionSuggestionsToMerge(from: fallback)
                    self.isLoading = false
                    let content = self.assistantContent(reply: fallback.reply, followUpQuestion: fallback.followUpQuestion)
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
                    self.activeRequestToken = nil
                    self.currentRequestTask = nil
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
                    trigger: "scheduledNudge",
                    agentPersona: self.buildAgentPersona()
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
        activeRequestToken = nil
        currentRequestTask?.cancel()
        currentRequestTask = nil
        isLoading = false
        streamingPhase = .idle
        streamingReasoning = ""
        streamingContent = ""
        reasoningTimeMs = nil
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
        lastUserInput = clean
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
                    let content = self.assistantContent(reply: response.reply, followUpQuestion: response.followUpQuestion)
                    if !content.isEmpty {
                        self.appendMessage(AgentChatMessage(role: "assistant", content: content))
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
        let suggestions = response.actionSuggestions.isEmpty
            ? synthesizedDBTCompletionActions(from: response)
            : response.actionSuggestions
        guard isAskingFollowUp else { return suggestions }
        return suggestions.filter { shouldAllowActionWhileAskingFollowUp($0, response: response) }
    }

    private func shouldAllowActionWhileAskingFollowUp(_ action: AgentActionDraft, response: AgentChatResponse) -> Bool {
        isCompletedDBTResponse(response) && isDBTPractice(action)
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

        resolved = coalescedTimeActions(resolved)

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
        case .brain:
            // 第二大脑记录不需要解析已有 record target。
            return nil
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
        if !a.isMutation && !isDBTPractice(a) && !input.isEmpty && !a.title.isEmpty {
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

    private func coalescedTimeActions(_ actions: [AgentActionDraft]) -> [AgentActionDraft] {
        var kept: [AgentActionDraft] = []
        for action in actions {
            guard action.kind == .time,
                  let actionRange = timeRange(for: action) else {
                kept.append(action)
                continue
            }

            if let existingIndex = kept.firstIndex(where: { existing in
                guard existing.kind == .time,
                      sameActionDate(existing, action),
                      let existingRange = timeRange(for: existing) else { return false }
                return rangesOverlap(actionRange, existingRange)
            }) {
                if timeActionScore(action) > timeActionScore(kept[existingIndex]) {
                    kept[existingIndex] = action
                }
            } else {
                kept.append(action)
            }
        }
        return kept
    }

    private func sameActionDate(_ lhs: AgentActionDraft, _ rhs: AgentActionDraft) -> Bool {
        (lhs.date ?? writer?.selectedDateKey ?? "") == (rhs.date ?? writer?.selectedDateKey ?? "")
    }

    private func timeRange(for action: AgentActionDraft) -> Range<Int>? {
        guard let start = clockMinutes(action.startTime, allow24: false),
              let end = clockMinutes(action.endTime, allow24: true),
              end > start else { return nil }
        return start..<end
    }

    private func rangesOverlap(_ lhs: Range<Int>, _ rhs: Range<Int>) -> Bool {
        max(lhs.lowerBound, rhs.lowerBound) < min(lhs.upperBound, rhs.upperBound)
    }

    private func clockMinutes(_ value: String?, allow24: Bool) -> Int? {
        guard let value else { return nil }
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...59).contains(minute) else { return nil }
        if allow24, hour == 24, minute == 0 { return 24 * 60 }
        guard (0...23).contains(hour) else { return nil }
        return hour * 60 + minute
    }

    private func timeActionScore(_ action: AgentActionDraft) -> Int {
        completenessScore(action) * 100
            + action.detail.trimmingCharacters(in: .whitespacesAndNewlines).count
            + action.title.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    /// 判断是否自动保存：AI confidence 只做参考，用规则兜底
    private func shouldAutoConfirm(_ action: AgentActionDraft) -> Bool {
        // Mutation 操作永不自动确认
        if action.isMutation { return false }
        // AI 自报 confidence 太低时不自动保存
        guard action.confidence >= 0.7 else { return false }
        switch action.kind {
        case .inbox:
            // DBT 旧格式仍保留人工确认，避免继续自动落到随手记。
            if action.inboxType == "DBT练习" { return false }
            // 随手记：有标题或内容就自动存
            return !action.title.isEmpty || !action.detail.isEmpty
        case .brain:
            // 目前只开放 DBT 技能训练直接沉淀到第二大脑，避免普通闲聊污染知识库。
            return isDBTPractice(action) && (!action.title.isEmpty || !action.detail.isEmpty)
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
        case .brain:
            let brainId = commitBrainActionReturningId(action)
            ref = brainId.map { _ in AutoSavedActionRef(kind: .brain, title: action.title) }
            result = brainId == nil ? "内容为空，未保存" : nil
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
                autoSavedAction: ref,
                isActionResult: true
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

    private func commitBrainActionReturningId(_ action: AgentActionDraft, sourceTurnId: UUID? = nil) -> UUID? {
        guard let writer else { return nil }
        guard isDBTPractice(action) else { return nil }
        let titleSeed = action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fallbackTitle(action.detail)
            : action.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !titleSeed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let title = titleSeed.hasPrefix("DBT") ? titleSeed : "DBT 会话：\(titleSeed)"
        let activeDBT = session.dbtSession
        let summary = activeDBT?.summary.isEmpty == false ? (activeDBT?.summary ?? []) : dbtSummaryBullets(for: action)
        let skillIds = activeDBT?.skillIds.isEmpty == false ? (activeDBT?.skillIds ?? []) : [normalizedDBTSkillId(activeDBT?.skillId)]
        let sessionRecord = BrainDBTSession(
            summary: summary,
            skills: dbtSkills(for: action, skillIds: skillIds),
            actions: activeDBT?.followUpActions.isEmpty == false ? (activeDBT?.followUpActions ?? []) : dbtActions(for: action),
            transcript: currentDBTTranscript(),
            emotionalShift: activeDBT?.emotionalShift ?? dbtEmotionalShift(for: action),
            sourceThreadId: currentThreadID
        )
        let sources: [BrainCardSource]
        if let sourceTurnId {
            sources = [BrainCardSource(noteId: sourceTurnId, excerpt: excerpt(action.detail.isEmpty ? action.title : action.detail, maxLength: 180))]
        } else {
            sources = []
        }
        return writer.addBrain(
            title: title,
            content: dbtBrainContent(summary: summary, action: action),
            topics: ["#DBT", "#情绪调节", "#AI对话"],
            sources: sources,
            kind: "dbtSession",
            dbtSession: sessionRecord
        )
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
        let note = timeNote(for: action)
        guard !start.isEmpty, !end.isEmpty else { return nil }
        guard let id = writer.addTurnDraft(
            rawText: note.isEmpty ? title : note,
            recognizedType: "时间记录",
            targetBucket: "time",
            confidence: action.confidence,
            payload: [
                "name": title.isEmpty ? "时间记录" : title,
                "start": start,
                "end": end,
                "category": timeModule(for: action),
                "note": note,
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

    private func timeNote(for action: AgentActionDraft) -> String {
        let detail = action.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detail.isEmpty, !isOverbroadTimeDetail(detail, title: title) {
            return detail
        }
        return ""
    }

    private func isOverbroadTimeDetail(_ detail: String, title: String) -> Bool {
        if detail.count > 48 { return true }
        let normalizedTitle = normalizedText(title)
        if !normalizedTitle.isEmpty, normalizedText(detail) == normalizedTitle { return true }
        let input = lastUserInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return false }
        let normalizedDetail = normalizedText(detail)
        let normalizedInput = normalizedText(input)
        if normalizedDetail == normalizedInput { return true }
        return normalizedDetail.count >= 24 && normalizedInput.contains(normalizedDetail)
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
        var actionRef: AutoSavedActionRef? = nil
        switch action.kind {
        case .inbox:
            if let turnId = commitInboxActionReturningId(action) {
                actionRef = AutoSavedActionRef(kind: .inbox, title: action.title, turnId: turnId)
                if isDBTPractice(action) { saveDBTSessionToBrain(action: action, sourceTurnId: turnId) }
                result = nil
            } else {
                result = "内容为空，未保存"
            }
        case .brain:
            if commitBrainActionReturningId(action) != nil {
                actionRef = AutoSavedActionRef(kind: .brain, title: action.title)
                result = nil
            } else {
                result = "内容为空，未保存"
            }
        case .task:
            if let taskId = commitTaskActionReturningId(action) {
                actionRef = AutoSavedActionRef(kind: .task, title: action.title, taskId: taskId)
                result = nil
            } else {
                result = "待办标题为空"
            }
        case .time:
            if let turnId = commitTimeActionReturningId(action) {
                actionRef = AutoSavedActionRef(kind: .time, title: action.title, turnId: turnId)
                result = nil
            } else {
                result = "时间记录缺少开始/结束时间"
            }
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
            if actionRef == nil {
                if (action.kind == .deleteTask || action.kind == .deleteTime || action.kind == .deleteInbox),
                   let snapshot = lastDeletedSnapshot {
                    actionRef = AutoSavedActionRef(kind: action.kind, title: action.title, deletedRecord: snapshot)
                    lastDeletedSnapshot = nil
                } else if action.kind == .calendarEvent, let eventId = lastCalendarEventId {
                    actionRef = AutoSavedActionRef(kind: .calendarEvent, title: action.title, calendarEventId: eventId)
                    lastCalendarEventId = nil
                }
            }
            let msg = AgentChatMessage(
                role: "assistant",
                content: savedMessage(for: action),
                autoSavedAction: actionRef,
                isActionResult: true
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
        case .brain:
            break
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

    func setMessageFeedback(messageId: UUID, feedback: String?) {
        guard let idx = session.messages.firstIndex(where: { $0.id == messageId }) else { return }
        session.messages[idx].feedback = feedback
        saveCurrentThread()
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
        cancelCurrentRequest()
        messageQueue.removeAll()
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
        cancelCurrentRequest()
        messageQueue.removeAll()
        extractMemoriesForCurrentThreadIfNeeded()
        let thread = loadThread(id: id) ?? AgentChatThread(id: id)
        currentThreadID = thread.id
        session = thread.session
        upsertIndex(for: thread)
        saveThreadIndex()
        defaults.set(thread.id.uuidString, forKey: keyCurrentThreadID)
    }

    @discardableResult
    func renameThread(id: UUID, title: String) -> Bool {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, var thread = loadThread(id: id) else { return false }
        thread.title = clean
        thread.titleGenerated = true
        saveThread(thread)
        upsertIndex(for: thread)
        saveThreadIndex()
        return true
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

    func addMemory(content: String, category: String = "fact", source: String = "user", scope: String = "state") {
        let clean = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if memories.contains(where: { $0.content == clean }) { return }
        memories.append(AgentMemory(
            content: clean,
            category: category,
            source: source,
            scope: scope,
            expiresAt: defaultExpiry(for: scope),
            confidence: source == "user" ? 1.0 : 0.7,
            sourceThreadId: currentThreadID,
            lastConfirmedAt: source == "user" ? Date() : nil
        ))
        trimMemories()
        saveMemories()
    }

    func updateMemory(id: UUID, content: String, scope: String, status: String) {
        guard let index = memories.firstIndex(where: { $0.id == id }) else { return }
        let clean = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        memories[index].content = clean
        memories[index].scope = AgentMemory.normalizedScope(scope, category: memories[index].category)
        memories[index].status = status
        memories[index].lastConfirmedAt = Date()
        if memories[index].scope == "profile" || memories[index].scope == "preference" {
            memories[index].expiresAt = nil
        } else if memories[index].expiresAt == nil && status == "active" {
            memories[index].expiresAt = defaultExpiry(for: memories[index].scope)
        }
        saveMemories()
    }

    func confirmMemoryAsLongTerm(id: UUID) {
        guard let index = memories.firstIndex(where: { $0.id == id }) else { return }
        memories[index].scope = "profile"
        memories[index].expiresAt = nil
        memories[index].lastConfirmedAt = Date()
        memories[index].status = "active"
        saveMemories()
    }

    func expireMemory(id: UUID) {
        guard let index = memories.firstIndex(where: { $0.id == id }) else { return }
        memories[index].expiresAt = Date()
        memories[index].status = "archived"
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

    @discardableResult
    private func handleMemoryCorrectionIfNeeded(_ input: String) -> Bool {
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let forgetPrefixes = ["忘掉", "忘记", "别再提", "不要再提", "这个不对"]
        if forgetPrefixes.contains(where: { clean.contains($0) }) {
            let target = forgetPrefixes.reduce(clean) { partial, prefix in
                partial.replacingOccurrences(of: prefix, with: "")
            }
            let matched = markMatchingMemoriesInactive(keyword: target)
            appendMessage(AgentChatMessage(role: "user", content: clean))
            let reply = matched > 0
                ? "好，我已经把相关记忆先放下了。之后不会再主动拿它当背景。"
                : "好，我会注意不再主动提这件事。如果你愿意，也可以到设置里的猫猫记忆里检查一下。"
            appendMessage(AgentChatMessage(role: "assistant", content: reply))
            return true
        }

        let rememberPrefixes = ["记住", "你可以记住", "以后你要知道"]
        guard rememberPrefixes.contains(where: { clean.contains($0) }) else { return false }
        let content = rememberPrefixes.reduce(clean) { partial, prefix in
            partial.replacingOccurrences(of: prefix, with: "")
        }
        let trimmed = content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        guard !trimmed.isEmpty else { return false }
        addMemory(content: trimmed, category: "preference", source: "user", scope: inferredScope(for: trimmed))
        appendMessage(AgentChatMessage(role: "user", content: clean))
        appendMessage(AgentChatMessage(role: "assistant", content: "我先记住这一点，之后你可以随时让我忘掉或改掉。"))
        return true
    }

    private func markMatchingMemoriesInactive(keyword: String) -> Int {
        let clean = keyword.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        guard !clean.isEmpty else { return 0 }
        var count = 0
        for index in memories.indices {
            let shouldMatch = memories[index].content.localizedCaseInsensitiveContains(clean) || clean.localizedCaseInsensitiveContains(memories[index].content)
            guard shouldMatch else { continue }
            memories[index].status = "rejected"
            memories[index].expiresAt = Date()
            count += 1
        }
        if count > 0 { saveMemories() }
        return count
    }

    private func inferredScope(for content: String) -> String {
        if content.contains("喜欢") || content.contains("偏好") || content.localizedCaseInsensitiveContains("prefer") {
            return "preference"
        }
        if content.contains("下周") || content.contains("明天") || content.contains("周五") || content.contains("面试") {
            return "plan"
        }
        return "state"
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
        let response = cleanStructuredLeak(from: response)
        isLoading = false
        let actions = mergedActions ?? actionSuggestionsToMerge(from: response)
        let content = assistantContent(
            reply: stripLocalActionResultText(from: response.reply, actions: actions),
            followUpQuestion: response.followUpQuestion
        )
        if !content.isEmpty {
            session.messages.append(AgentChatMessage(role: "assistant", content: content))
        }
        applyDBTSessionUpdate(response.dbtSession)
        completeDBTSessionIfNeeded(response: response, actions: actions)
        mergeActionSuggestions(actions)
        saveCurrentThread()
    }

    // MARK: - Persona

    private func buildAgentPersona() -> [String: String]? {
        let name = writer?.catName ?? ""
        let style = writer?.catStyle ?? ""
        let role = writer?.catRole ?? "安静陪伴"
        let proactivity = writer?.catProactivity ?? "偶尔接回"
        let memoryPreference = writer?.catMemoryPreference ?? "平衡记忆"
        let instructions = writer?.catInstructions ?? ""
        var p: [String: String] = [:]
        if !name.isEmpty { p["catName"] = name }
        if !style.isEmpty { p["style"] = style }
        p["role"] = role.isEmpty ? "安静陪伴" : role
        p["proactivity"] = proactivity.isEmpty ? "偶尔接回" : proactivity
        p["memoryPreference"] = memoryPreference.isEmpty ? "平衡记忆" : memoryPreference
        if !instructions.isEmpty { p["customInstructions"] = String(instructions.prefix(1200)) }
        return p
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
        trigger: String? = nil,
        agentMode: String = "chat",
        dbtSession: AgentDBTSessionState? = nil,
        agentPersona: [String: String]? = nil
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
            trigger: trigger,
            agentMode: agentMode,
            dbtSession: dbtSession,
            agentPersona: agentPersona
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
                    dbtSession: event.dbtSession,
                    usage: event.usage
                )
            case .error:
                throw AIParseError.network(event.message ?? "stream error")
            }
        }

        guard let response = finalResponse else {
            // Stream ended without done event — use accumulated content
            let reply = await MainActor.run { self.streamingContent }
            return cleanStructuredLeak(from: AgentChatResponse(
                reply: reply.isEmpty ? "我在。你可以继续说一点。" : reply
            ))
        }
        return cleanStructuredLeak(from: response)
    }

    /// Called on MainActor after streaming completes — persists the message with reasoning.
    private func finishStreaming(
        response: AgentChatResponse,
        mergedActions: [AgentActionDraft]
    ) {
        let response = cleanStructuredLeak(from: response)
        isLoading = false
        let content = assistantContent(
            reply: stripLocalActionResultText(from: response.reply, actions: mergedActions),
            followUpQuestion: response.followUpQuestion
        )
        if !content.isEmpty {
            session.messages.append(AgentChatMessage(
                role: "assistant",
                content: content,
                reasoningContent: streamingReasoning.isEmpty ? nil : streamingReasoning,
                reasoningTimeMs: reasoningTimeMs
            ))
        }
        applyDBTSessionUpdate(response.dbtSession)
        completeDBTSessionIfNeeded(response: response, actions: mergedActions)
        mergeActionSuggestions(mergedActions)
        saveCurrentThread()

        streamingPhase = .idle
        streamingReasoning = ""
        streamingContent = ""
        reasoningTimeMs = nil
        activeRequestToken = nil
        currentRequestTask = nil

        processQueue()
    }

    private func stripLocalActionResultText(from reply: String, actions: [AgentActionDraft]) -> String {
        guard !actions.isEmpty else { return reply }
        let localResultPrefixes = [
            "已创建", "已更新", "已删除", "已完成",
            "Created ", "Updated ", "Deleted ", "Completed "
        ]
        return reply
            .components(separatedBy: .newlines)
            .filter { line in
                let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !localResultPrefixes.contains { clean.hasPrefix($0) }
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func assistantContent(reply: String, followUpQuestion: String?) -> String {
        let cleanReply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanQuestion = followUpQuestion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !cleanQuestion.isEmpty else { return cleanReply }
        guard !cleanReply.isEmpty else { return cleanQuestion }

        let normalizedReply = normalizedQuestionText(cleanReply)
        let normalizedQuestion = normalizedQuestionText(cleanQuestion)
        if normalizedReply.contains(normalizedQuestion)
            || followUpQuestionAlreadyCovered(reply: cleanReply, question: cleanQuestion) {
            return cleanReply
        }
        return [cleanReply, cleanQuestion].joined(separator: "\n\n")
    }

    private func followUpQuestionAlreadyCovered(reply: String, question: String) -> Bool {
        let normalizedReply = normalizedQuestionText(reply)
        let fragments = question
            .components(separatedBy: CharacterSet(charactersIn: "，,。！？!?；;：:\n"))
            .map { normalizedQuestionText($0) }
            .filter { $0.count >= 3 }

        guard fragments.count >= 2 else { return false }

        let matched = fragments.filter { normalizedReply.contains($0) }
        let totalLength = fragments.reduce(0) { $0 + $1.count }
        let matchedLength = matched.reduce(0) { $0 + $1.count }
        return matched.count >= 2 && Double(matchedLength) / Double(max(totalLength, 1)) >= 0.7
    }

    private func normalizedQuestionText(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .joined()
    }

    private func cleanStructuredLeak(from response: AgentChatResponse) -> AgentChatResponse {
        let delimiter = "<<<JSON>>>"
        guard let delimiterRange = response.reply.range(of: delimiter) else { return response }

        let visibleReply = String(response.reply[..<delimiterRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = String(response.reply[delimiterRange.upperBound...])
        guard let jsonText = firstJSONObject(in: tail),
              let data = jsonText.data(using: .utf8),
              let structured = try? JSONDecoder().decode(AgentChatResponse.self, from: data)
        else {
            return AgentChatResponse(
                reply: visibleReply.isEmpty ? response.reply.replacingOccurrences(of: delimiter, with: "").trimmingCharacters(in: .whitespacesAndNewlines) : visibleReply,
                followUpQuestion: response.followUpQuestion,
                actionSuggestions: response.actionSuggestions,
                toolCall: response.toolCall,
                dbtSession: response.dbtSession,
                debug: response.debug,
                rawBody: response.rawBody,
                usage: response.usage
            )
        }

        let followUpQuestion = response.followUpQuestion ?? structured.followUpQuestion
        let shouldSuppressActions = followUpQuestion != nil || response.toolCall != nil || structured.toolCall != nil
        let actionSuggestions = shouldSuppressActions
            ? []
            : (response.actionSuggestions.isEmpty ? structured.actionSuggestions : response.actionSuggestions)

        return AgentChatResponse(
            reply: visibleReply,
            followUpQuestion: followUpQuestion,
            actionSuggestions: actionSuggestions,
            toolCall: response.toolCall ?? structured.toolCall,
            dbtSession: response.dbtSession ?? structured.dbtSession,
            debug: response.debug,
            rawBody: response.rawBody,
            usage: response.usage
        )
    }

    private func firstJSONObject(in text: String) -> String? {
        guard let startIndex = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var isInString = false
        var isEscaped = false
        var index = startIndex

        while index < text.endIndex {
            let character = text[index]
            if isInString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInString = false
                }
            } else {
                if character == "\"" {
                    isInString = true
                } else if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(text[startIndex...index])
                    }
                }
            }
            index = text.index(after: index)
        }

        return nil
    }

    private func appendMessage(_ message: AgentChatMessage) {
        session.messages.append(message)
        saveCurrentThread()
    }

    private func isCurrentRequest(_ token: UUID, threadID: UUID?) -> Bool {
        activeRequestToken == token && currentThreadID == threadID
    }

    private func currentThread() -> AgentChatThread? {
        guard let id = currentThreadID else { return nil }
        var thread = loadThread(id: id)
        if thread == nil {
            thread = AgentChatThread(id: id)
        }
        thread?.messages = session.messages
        thread?.pendingActions = session.pendingActions
        thread?.dbtSession = session.dbtSession
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

    private func defaultExpiry(for scope: String) -> Date? {
        let days: Int
        switch scope {
        case "plan": days = 14
        case "state": days = 30
        default: return nil
        }
        return Calendar.current.date(byAdding: .day, value: days, to: Date())
    }

    private func extractMemories(from messages: [AgentChatMessage]) async {
        do {
            let validMessages = messages.filter { !$0.isError }
            let extracted = try await AIParser.extractMemories(
                messages: validMessages.map { AgentChatRequestMessage(role: $0.role, content: $0.content) }
            )
            await MainActor.run {
                var added = 0
                let memoryItems = extracted

                for item in memoryItems where !self.memories.contains(where: { $0.content == item.content }) {
                    let scope = AgentMemory.normalizedScope(item.scope, category: item.category)
                    self.memories.append(AgentMemory(
                        content: item.content,
                        category: item.category,
                        source: "auto",
                        scope: scope,
                        expiresAt: self.defaultExpiry(for: scope),
                        confidence: item.confidence ?? 0.75,
                        sourceThreadId: self.currentThreadID
                    ))
                    added += 1
                }
                self.trimMemories()
                self.saveMemories()

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
        let result = writer.commitTurn(id: id)
        if result == nil, isDBTPractice(action) {
            saveDBTSessionToBrain(action: action, sourceTurnId: id)
        }
        return result
    }

    private func commitBrainAction(_ action: AgentActionDraft) -> String? {
        guard writer != nil else { return "内部错误" }
        return commitBrainActionReturningId(action) == nil ? "内容为空，未保存" : nil
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
        let note = timeNote(for: action)
        guard !start.isEmpty, !end.isEmpty else { return "时间记录缺少开始/结束时间" }
        guard let id = writer.addTurnDraft(
            rawText: note.isEmpty ? title : note,
            recognizedType: "时间记录",
            targetBucket: "time",
            confidence: action.confidence,
            payload: [
                "name": title.isEmpty ? "时间记录" : title,
                "start": start,
                "end": end,
                "category": timeModule(for: action),
                "note": note,
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
        let allowedTypes = ["想法", "感受", "感恩", "做梦", "DBT练习"]
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
        let allowedModules = ["睡觉", "社交", "运动", "其他", "娱乐", "工作", "学习"]
        if let module = action.module?.trimmingCharacters(in: .whitespacesAndNewlines) {
            if module == "休息" { return "其他" }
            if allowedModules.contains(module) { return module }
        }
        let combined = "\(action.title) \(action.detail)"
        if combined.contains("睡觉") || combined.contains("睡眠") || combined.contains("卧床") {
            return "睡觉"
        }
        if combined.contains("电影") || combined.contains("游戏") || combined.contains("娱乐") {
            return "娱乐"
        }
        if combined.contains("朋友") || combined.contains("聚会") || combined.contains("社交") {
            return "社交"
        }
        if combined.contains("运动") || combined.contains("健身") || combined.contains("跑步") {
            return "运动"
        }
        if combined.contains("工作") || combined.contains("会议") || combined.contains("项目") {
            return "工作"
        }
        if combined.contains("学习") || combined.contains("读书") || combined.contains("课程") {
            return "学习"
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
        return title.isEmpty ? L.newConversation : title
    }

    private var currentISODateTime: String {
        "\(AIParser.isoDate())T\(AIParser.isoTime())"
    }

    private func applyDBTSessionUpdate(_ update: AgentDBTSessionState?) {
        guard let update else { return }
        if session.dbtSession == nil {
            session.dbtSession = update
            return
        }
        session.dbtSession = update
    }

    private func completeDBTSessionIfNeeded(response: AgentChatResponse, actions: [AgentActionDraft]) {
        guard var dbt = session.dbtSession, dbt.status == "active" else { return }
        guard isCompletedDBTResponse(response) || actions.contains(where: isDBTPractice) else { return }
        dbt.status = "completed"
        dbt.completedAt = currentISODateTime
        if dbt.sourceThreadId == nil {
            dbt.sourceThreadId = currentThreadID?.uuidString
        }
        session.dbtSession = dbt
    }

    private func synthesizedDBTCompletionActions(from response: AgentChatResponse) -> [AgentActionDraft] {
        guard let dbt = session.dbtSession, dbt.status == "active" else { return [] }
        guard isCompletedDBTResponse(response) else { return [] }
        let reply = response.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = "DBT 会话：\(dbtSkillName(for: dbt.skillId)) 小练习"
        let detail = reply.isEmpty ? "用户完成了一次 DBT 小练习。" : reply
        return [
            AgentActionDraft(
                kind: .brain,
                inboxType: "DBT练习",
                title: title,
                detail: detail,
                date: AIParser.isoDate(),
                confidence: 0.9,
                reason: "DBT Coach 回复表示练习已完成并需要保存，客户端补齐第二大脑记录。"
            )
        ]
    }

    private func isCompletedDBTResponse(_ response: AgentChatResponse) -> Bool {
        if response.dbtSession?.status == "completed" { return true }
        let text = response.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let completionMarkers = [
            "完整的练习",
            "完整小练习",
            "练习完成",
            "已经完成",
            "到这里就够了",
            "到这里就已经",
            "这次练习"
        ]
        let saveMarkers = [
            "帮你简单存",
            "帮你存",
            "存一下",
            "保存",
            "收起来",
            "翻出来就能用",
            "下次如果再遇到"
        ]
        let hasCompletion = completionMarkers.contains { text.localizedCaseInsensitiveContains($0) }
        let hasSaveIntent = saveMarkers.contains { text.localizedCaseInsensitiveContains($0) }
        return hasCompletion && hasSaveIntent
    }

    private func normalizedDBTSkillId(_ id: String?) -> String {
        let clean = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return dbtSkillNames[clean] == nil ? "validation" : clean
    }

    private var dbtSkillNames: [String: String] {
        [
            "check_the_facts": "Check the Facts",
            "opposite_action": "Opposite Action",
            "wise_mind": "Wise Mind",
            "tipp": "TIPP",
            "stop": "STOP",
            "dear_man": "DEAR MAN",
            "behavior_chain_analysis": "Behavior Chain Analysis",
            "validation": "Validation"
        ]
    }

    private func dbtSkillName(for skillId: String) -> String {
        dbtSkillNames[skillId] ?? dbtSkillNames["validation"] ?? "Validation"
    }

    private func isDBTPractice(_ action: AgentActionDraft) -> Bool {
        guard action.kind == .inbox || action.kind == .brain else { return false }
        if action.inboxType == "DBT练习" { return true }
        if action.kind == .brain { return true }
        let t = (action.title + " " + action.detail).lowercased()
        return t.contains("dbt")
    }

    private func saveDBTSessionToBrain(action: AgentActionDraft, sourceTurnId: UUID) {
        _ = commitBrainActionReturningId(action, sourceTurnId: sourceTurnId)
    }

    private func currentDBTTranscript() -> [BrainDBTTurn] {
        session.messages
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map {
                BrainDBTTurn(
                    role: $0.role,
                    content: $0.content,
                    createdAt: $0.createdAt
                )
            }
    }

    private func dbtSummaryBullets(for action: AgentActionDraft) -> [String] {
        let detail = action.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = detail.isEmpty ? title : detail
        let trimSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-•0123456789.、"))
        let lines = base
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: trimSet) }
            .filter { line in
                !line.isEmpty
                    && !line.contains("保留完整对话")
                    && !line.contains("沉淀到第二大脑")
                    && !line.contains("不只停留在当下")
            }
        if !lines.isEmpty {
            return Array(lines.prefix(3))
        }
        return []
    }

    private func dbtSkills(for action: AgentActionDraft, skillIds: [String] = []) -> [BrainDBTSkill] {
        let registrySkills = skillIds
            .map { normalizedDBTSkillId($0) }
            .filter { !$0.isEmpty }
            .map { BrainDBTSkill(name: dbtSkillName(for: $0), note: dbtSkillNote(for: $0)) }
        if !registrySkills.isEmpty { return registrySkills }

        let combined = "\(action.title)\n\(action.detail)"
        var skills: [BrainDBTSkill] = []
        if combined.localizedCaseInsensitiveContains("check the facts") || combined.contains("事实") {
            skills.append(BrainDBTSkill(name: "Check the facts", note: "把事实、解释和灾难化想象分开。"))
        }
        if combined.localizedCaseInsensitiveContains("opposite action") || combined.contains("反向行动") {
            skills.append(BrainDBTSkill(name: "Opposite action", note: "在情绪驱动逃避时，选择一个足够小的相反动作。"))
        }
        if combined.localizedCaseInsensitiveContains("wise mind") || combined.contains("智慧心") {
            skills.append(BrainDBTSkill(name: "Wise mind", note: "同时承认理性判断和情绪需要。"))
        }
        if skills.isEmpty {
            skills = [
                BrainDBTSkill(name: "Validate", note: "先承认感受有其来处，不急着否定自己。"),
                BrainDBTSkill(name: "Wise mind", note: "在情绪和理性之间找一个可执行的小选择。")
            ]
        }
        return skills
    }

    private func dbtSkillNote(for skillId: String) -> String {
        switch normalizedDBTSkillId(skillId) {
        case "check_the_facts": return "把事实、解释和灾难化想象分开。"
        case "opposite_action": return "当情绪冲动不符合事实时，选择一个相反的小行动。"
        case "wise_mind": return "同时承认理性判断和情绪需要。"
        case "tipp": return "先用身体降温、运动和呼吸帮情绪急刹车。"
        case "stop": return "暂停、退一步、观察，再选择有智慧的行动。"
        case "dear_man": return "用清晰、稳定的方式表达需求和边界。"
        case "behavior_chain_analysis": return "复盘触发点、想法、感受、行为和后果。"
        default: return "先承认感受有其来处，不急着否定自己。"
        }
    }

    private func dbtActions(for action: AgentActionDraft) -> [String] {
        let combined = "\(action.title)\n\(action.detail)"
        let markers = ["下一步", "后续行动", "我会", "我准备", "我打算", "行动：", "行动:"]
        let trimSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-•0123456789.、"))
        let lines = combined
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: trimSet) }
            .filter { line in
                guard !line.isEmpty else { return false }
                return markers.contains { line.hasPrefix($0) }
            }
        if !lines.isEmpty { return Array(lines.prefix(4)) }
        return []
    }

    private func dbtEmotionalShift(for action: AgentActionDraft) -> String? {
        let combined = "\(action.title)\n\(action.detail)"
        return combined
            .components(separatedBy: .newlines)
            .first { $0.contains("→") || $0.contains("->") }
            .map { excerpt($0, maxLength: 80) }
    }

    private func dbtBrainContent(summary: [String], action: AgentActionDraft) -> String {
        let bullets = summary.map { "- \($0)" }.joined(separator: "\n")
        let detail = action.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if bullets.isEmpty { return detail }
        if detail.isEmpty { return bullets }
        return "\(bullets)\n\n练习记录：\n\(detail)"
    }

    private func excerpt(_ text: String, maxLength: Int) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > maxLength else { return clean }
        return String(clean.prefix(maxLength)) + "..."
    }

    private func savedMessage(for action: AgentActionDraft) -> String {
        let title = action.title.isEmpty ? action.detail : action.title
        switch action.kind {
        case .inbox: return L.savedInbox(title)
        case .brain: return L.savedBrain(title)
        case .task: return L.savedTask(title)
        case .time: return L.savedTime(title)
        case .calendarEvent: return L.savedCalendar(title)
        case .editTask: return L.savedEditTask(title)
        case .editTime: return L.savedEditTime(title)
        case .editInbox: return L.savedEditInbox(title)
        case .deleteTask: return L.savedDeleteTask(title)
        case .deleteTime: return L.savedDeleteTime(title)
        case .deleteInbox: return L.savedDeleteInbox(title)
        case .completeTask: return L.savedCompleteTask(title)
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
            dbtSession: legacy.dbtSession,
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

#if DEBUG
extension AgentManager {
    func debugReplaceThreads(_ threads: [AgentChatThread], memories seededMemories: [AgentMemory]) {
        ensureThreadDirectory()
        for item in threadIndex {
            deleteThreadFile(id: item.id)
        }

        threadIndex = []
        for thread in threads {
            saveThread(thread)
            upsertIndex(for: thread)
        }
        saveThreadIndex()

        if let current = threads.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
            currentThreadID = current.id
            session = current.session
            defaults.set(current.id.uuidString, forKey: keyCurrentThreadID)
        } else {
            currentThreadID = nil
            session = AgentChatSession()
            defaults.removeObject(forKey: keyCurrentThreadID)
        }

        memories = Array(seededMemories.prefix(Self.maxMemories))
        saveMemories()
    }
}
#endif
