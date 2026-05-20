import Foundation

// MARK: - Protocol: Agent 落库需要 AppStore 提供的写入能力

protocol AgentDataWriter: AnyObject {
    var selectedDateKey: String { get }
    func addTurnDraft(rawText: String, recognizedType: String, targetBucket: String, confidence: Double, payload: [String: String], status: String, fixHint: String, moodScore: Int?, feelingTags: [String]) -> UUID?
    func commitTurn(id: UUID) -> String?
    func addTask(title: String, detail: String, status: String, priority: String, dueDate: String, date: String?, completedAt: Date?, isAllDay: Bool, startTime: String, endTime: String, location: String, sourceNoteId: UUID?, sourceExcerpt: String) -> UUID?
}

final class AgentManager: ObservableObject {
    @Published var session: AgentChatSession = AgentChatSession()
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var debugLogs: [AgentChatDebugLog] = []
    @Published var memories: [AgentMemory] = []
    @Published var memoryStatus: String? = nil

    private weak var writer: AgentDataWriter?
    private let client: AIClient
    private let defaults = UserDefaults.standard
    private var keyChat: String
    private var keyDebugLogs: String
    private var keyMemories: String

    static let maxMemories = 15

    init(writer: AgentDataWriter, userIdSuffix: String, client: AIClient = DefaultAIClient()) {
        self.writer = writer
        self.client = client
        let base = userIdSuffix.isEmpty ? "" : ".\(userIdSuffix)"
        self.keyChat = "ps.agent.chat\(base)"
        self.keyDebugLogs = "ps.agent.debug.logs\(base)"
        self.keyMemories = "ps.agent.memories\(base)"
        loadSession()
        loadDebugLogs()
        loadMemories()
    }

    // MARK: - 重新绑定 writer（AppStore init 后设置）

    func bind(writer: AgentDataWriter) {
        self.writer = writer
    }

    // MARK: - 更新 storage keys（用户切换时）

    func reloadForUser(suffix: String) {
        let base = suffix.isEmpty ? "" : ".\(suffix)"
        keyChat = "ps.agent.chat\(base)"
        keyDebugLogs = "ps.agent.debug.logs\(base)"
        keyMemories = "ps.agent.memories\(base)"
        loadSession()
        loadDebugLogs()
        loadMemories()
    }

    // MARK: - Send message

    func send(
        text: String,
        turns: [ConversationTurn],
        tasks: [TaskEntry],
        timeEntries: [TimeEntry],
        checks: [DailyCheckItem]
    ) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        let request = AgentOrchestrator.makeRequest(
            input: clean,
            session: session,
            turns: turns,
            tasks: tasks,
            timeEntries: timeEntries,
            checks: checks,
            memories: memories
        )
        markMemoriesUsed()
        session.messages.append(AgentChatMessage(role: "user", content: clean))
        saveSession()
        isLoading = true
        errorMessage = nil
        let today = AIParser.isoDate()
        let now = AIParser.isoTime()

        Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await self.client.chat(
                    input: request.input,
                    messages: request.messages,
                    contextSummary: request.contextSummary,
                    currentDate: today,
                    currentTime: now
                )
                await MainActor.run {
                    let mergedActions = self.actionSuggestionsToMerge(from: response)
                    self.receiveResponse(response, mergedActions: mergedActions)
                    self.recordDebugLog(
                        input: clean,
                        request: request,
                        currentDate: today,
                        currentTime: now,
                        response: response,
                        mergedActions: mergedActions
                    )
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "对话服务暂时没有接上，我先用本地方式陪你。"
                    let fallback = AgentOrchestrator.fallbackResponse(for: clean)
                    let mergedActions = self.actionSuggestionsToMerge(from: fallback)
                    self.receiveResponse(fallback, mergedActions: mergedActions)
                    self.recordDebugLog(
                        input: clean,
                        request: request,
                        currentDate: today,
                        currentTime: now,
                        response: fallback,
                        mergedActions: mergedActions,
                        errorMessage: error.localizedDescription
                    )
                }
            }
        }
    }

    // MARK: - Quick send (lightweight single-turn)

    func quickSend(text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        let today = AIParser.isoDate()
        let now = AIParser.isoTime()

        Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await self.client.quick(
                    input: clean,
                    currentDate: today,
                    currentTime: now
                )
                await MainActor.run {
                    self.isLoading = false
                    let actions = response.actionSuggestions.filter { self.hasContent($0) }
                    for action in actions {
                        if !self.session.pendingActions.contains(where: { self.isSameIntent($0, action) }) {
                            self.session.pendingActions.append(action)
                        }
                    }
                    if let fq = response.followUpQuestion?.trimmingCharacters(in: .whitespacesAndNewlines), !fq.isEmpty {
                        self.session.messages.append(AgentChatMessage(role: "user", content: clean))
                        self.session.messages.append(AgentChatMessage(role: "assistant", content: fq))
                    }
                    self.saveSession()
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = "快录失败，请重试。"
                }
            }
        }
    }

    // MARK: - Receive response

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
        saveSession()
    }

    // MARK: - Action suggestions: filter, merge, confirm, dismiss

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
        for action in suggestions where hasContent(action) {
            if let existingIndex = session.pendingActions.firstIndex(where: { isSameIntent($0, action) }) {
                if completenessScore(action) >= completenessScore(session.pendingActions[existingIndex]) {
                    session.pendingActions[existingIndex] = action
                }
            } else {
                session.pendingActions.append(action)
            }
        }
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
        }

        if result == nil {
            session.pendingActions.removeAll { $0.id == id }
            saveSession()
        }
        return result
    }

    func dismissAction(id: UUID) {
        session.pendingActions.removeAll { $0.id == id }
        saveSession()
    }

    func clearChat() {
        let messagesToExtract = session.messages
        session = AgentChatSession()
        errorMessage = nil
        defaults.removeObject(forKey: keyChat)

        if messagesToExtract.count >= 4 {
            memoryStatus = "正在提取记忆..."
            Task { [weak self] in
                await self?.extractMemories(from: messagesToExtract)
            }
        }
    }

    func clearDebugLogs() {
        debugLogs = []
        defaults.removeObject(forKey: keyDebugLogs)
    }

    // MARK: - Memory management

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

    private func trimMemories() {
        guard memories.count > Self.maxMemories else { return }
        memories.sort { $0.lastUsedAt > $1.lastUsedAt }
        memories = Array(memories.prefix(Self.maxMemories))
    }

    private func extractMemories(from messages: [AgentChatMessage]) async {
        do {
            let extracted = try await AIParser.extractMemories(
                messages: messages.map { AgentChatRequestMessage(role: $0.role, content: $0.content) }
            )
            await MainActor.run {
                var added = 0
                for item in extracted {
                    if !self.memories.contains(where: { $0.content == item.content }) {
                        self.memories.append(AgentMemory(
                            content: item.content,
                            category: item.category,
                            source: "auto"
                        ))
                        added += 1
                    }
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

    // MARK: - Commit actions → AppStore

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

    // MARK: - Helpers

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

    // MARK: - Persistence

    private func loadSession() {
        guard let data = defaults.data(forKey: keyChat) else {
            session = AgentChatSession()
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        session = (try? decoder.decode(AgentChatSession.self, from: data)) ?? AgentChatSession()
    }

    private func saveSession() {
        session.updatedAt = Date()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(session) else { return }
        defaults.set(data, forKey: keyChat)
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
        errorMessage: String = ""
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
        debugLogs.insert(log, at: 0)
        if debugLogs.count > 20 {
            debugLogs = Array(debugLogs.prefix(20))
        }
        saveDebugLogs()
    }
}
