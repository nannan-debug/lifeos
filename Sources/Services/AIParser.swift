import Foundation

struct AgentChatRequestMessage: Codable, Equatable {
    let role: String
    let content: String
}

enum AIParseError: Error, LocalizedError {
    case badURL
    case network(String)
    case unauthorized
    case serverError(Int, String)
    case decoding(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .badURL: return "AI 服务地址无效"
        case .network(let msg): return "网络异常：\(msg)"
        case .unauthorized: return "AI 服务鉴权失败"
        case .serverError(let code, let body): return "AI 服务返回 \(code)：\(body.prefix(120))"
        case .decoding(let msg): return "AI 返回格式异常：\(msg)"
        case .empty: return "AI 返回为空"
        }
    }
}

enum AIParser {
    static let workerURL = URL(string: "https://ai.dogdada.com")!
    static var clientSecret: String { Secrets.aiClientSecret }
    static let timeout: TimeInterval = 60
    private static let maxNetworkAttempts = 3

    static func warmUp() {
        var req = URLRequest(url: workerURL)
        req.httpMethod = "GET"
        req.timeoutInterval = 5
        URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
    }

    // MARK: - Chat

    static func chat(
        input: String,
        messages: [AgentChatRequestMessage],
        contextSummary: String,
        currentDate: String,
        currentTime: String,
        traceId: String? = nil,
        sessionId: String? = nil,
        threadId: String? = nil,
        userProfile: String? = nil,
        agentMode: String? = nil,
        dbtSession: AgentDBTSessionState? = nil,
        agentPersona: [String: String]? = nil
    ) async throws -> AgentChatResponse {
        var body: [String: Any] = [
            "mode": "chat",
            "input": input,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "contextSummary": contextSummary,
            "currentDate": currentDate,
            "currentTime": currentTime
        ]
        body["traceId"] = traceId
        body["sessionId"] = sessionId
        body["threadId"] = threadId
        if let userProfile, !userProfile.isEmpty {
            body["userProfile"] = userProfile
        }
        if let agentMode, !agentMode.isEmpty {
            body["agentMode"] = agentMode
        }
        if let dbtSession,
           let data = try? JSONEncoder().encode(dbtSession),
           let object = try? JSONSerialization.jsonObject(with: data) {
            body["dbtSession"] = object
        }
        if let agentPersona, !agentPersona.isEmpty {
            body["agentPersona"] = agentPersona
        }
        let data = try await postWorker(body: body)
        do {
            let decoded = try JSONDecoder().decode(AgentChatResponse.self, from: data)
            return AgentChatResponse(
                reply: decoded.reply,
                followUpQuestion: decoded.followUpQuestion,
                actionSuggestions: decoded.actionSuggestions,
                toolCall: decoded.toolCall,
                dbtSession: decoded.dbtSession,
                debug: decoded.debug,
                rawBody: String(data: data, encoding: .utf8) ?? "<binary>",
                usage: decoded.usage
            )
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<binary>"
            throw AIParseError.decoding("\(error.localizedDescription) · raw=\(raw.prefix(200))")
        }
    }

    // MARK: - Quick (lightweight single-turn)

    static func quick(
        input: String,
        currentDate: String,
        currentTime: String,
        traceId: String? = nil,
        sessionId: String? = nil,
        threadId: String? = nil
    ) async throws -> AgentChatResponse {
        var body: [String: Any] = [
            "mode": "quick",
            "input": input,
            "currentDate": currentDate,
            "currentTime": currentTime
        ]
        body["traceId"] = traceId
        body["sessionId"] = sessionId
        body["threadId"] = threadId
        let data = try await postWorker(body: body)
        do {
            let decoded = try JSONDecoder().decode(AgentChatResponse.self, from: data)
            return AgentChatResponse(
                reply: decoded.reply,
                followUpQuestion: decoded.followUpQuestion,
                actionSuggestions: decoded.actionSuggestions,
                debug: decoded.debug,
                rawBody: String(data: data, encoding: .utf8) ?? "<binary>",
                usage: decoded.usage
            )
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<binary>"
            throw AIParseError.decoding("\(error.localizedDescription) · raw=\(raw.prefix(200))")
        }
    }

    // MARK: - Utility: extract memories

    struct ExtractedMemory: Decodable {
        let content: String
        let category: String
        let scope: String?
        let confidence: Double?
    }

    static func extractMemories(messages: [AgentChatRequestMessage]) async throws -> [ExtractedMemory] {
        let body: [String: Any] = [
            "mode": "utility",
            "task": "extract_memories",
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        let data = try await postWorker(body: body)
        struct MemoryResponse: Decodable {
            let result: [ExtractedMemory]
        }
        let wrapper = try JSONDecoder().decode(MemoryResponse.self, from: data)
        return wrapper.result
    }

    // MARK: - Utility: suggest topics

    static func suggestTopics(title: String, content: String) async throws -> [String] {
        let body: [String: Any] = [
            "mode": "utility",
            "task": "suggest_topics",
            "title": title,
            "content": content
        ]
        do {
            let data = try await postWorker(body: body)
            let wrapper = try JSONDecoder().decode(UtilityArrayResponse.self, from: data)
            let topics = normalizedBrainTopics(title: title, content: content, suggestions: wrapper.result)
            if !topics.isEmpty { return Array(topics.prefix(5)) }
        } catch {}
        return fallbackTopics(title: title, content: content)
    }

    // MARK: - Utility: suggest title

    static func suggestBrainTitle(content: String) async throws -> String {
        let body: [String: Any] = [
            "mode": "utility",
            "task": "suggest_title",
            "content": content
        ]
        do {
            let data = try await postWorker(body: body)
            let wrapper = try JSONDecoder().decode(UtilityStringResponse.self, from: data)
            let title = normalizedBrainTitle(wrapper.result)
            if !title.isEmpty { return title }
        } catch {}
        return fallbackTitle(from: content)
    }

    static func suggestAgentThreadTitle(content: String) async throws -> String {
        let title = try await suggestBrainTitle(content: content)
        return threadFallbackTitle(from: title.isEmpty ? content : title)
    }

    // MARK: - Streaming Chat (SSE)

    static func chatStream(
        input: String,
        messages: [AgentChatRequestMessage],
        contextSummary: String,
        currentDate: String,
        currentTime: String,
        traceId: String? = nil,
        sessionId: String? = nil,
        threadId: String? = nil,
        userProfile: String? = nil,
        trigger: String? = nil,
        agentMode: String? = nil,
        dbtSession: AgentDBTSessionState? = nil,
        agentPersona: [String: String]? = nil
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var body: [String: Any] = [
                        "mode": "chat",
                        "stream": true,
                        "input": input,
                        "messages": messages.map { ["role": $0.role, "content": $0.content] },
                        "contextSummary": contextSummary,
                        "currentDate": currentDate,
                        "currentTime": currentTime,
                    ]
                    body["traceId"] = traceId
                    body["sessionId"] = sessionId
                    body["threadId"] = threadId
                    if let userProfile, !userProfile.isEmpty {
                        body["userProfile"] = userProfile
                    }
                    if let trigger, !trigger.isEmpty {
                        body["trigger"] = trigger
                    }
                    if let agentMode, !agentMode.isEmpty {
                        body["agentMode"] = agentMode
                    }
                    if let dbtSession,
                       let data = try? JSONEncoder().encode(dbtSession),
                       let object = try? JSONSerialization.jsonObject(with: data) {
                        body["dbtSession"] = object
                    }
                    if let agentPersona, !agentPersona.isEmpty {
                        body["agentPersona"] = agentPersona
                    }

                    var req = URLRequest(url: workerURL)
                    req.httpMethod = "POST"
                    req.timeoutInterval = 120 // longer for streaming
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue(clientSecret, forHTTPHeaderField: "X-Client-Secret")
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)

                    guard let http = response as? HTTPURLResponse else {
                        throw AIParseError.network("no http response")
                    }
                    if http.statusCode == 401 { throw AIParseError.unauthorized }
                    guard (200...299).contains(http.statusCode) else {
                        // Collect error body
                        var errData = Data()
                        for try await byte in bytes { errData.append(byte) }
                        let errBody = String(data: errData, encoding: .utf8) ?? ""
                        throw AIParseError.serverError(http.statusCode, errBody)
                    }

                    let decoder = JSONDecoder()
                    for try await line in bytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.hasPrefix("data: ") else { continue }
                        let payload = String(trimmed.dropFirst(6))
                        if payload == "[DONE]" { break }
                        guard let jsonData = payload.data(using: .utf8) else { continue }
                        if let event = try? decoder.decode(StreamEvent.self, from: jsonData) {
                            continuation.yield(event)
                            if event.type == .done || event.type == .error { break }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Helpers

    static func isoDate(_ d: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    static func isoTime(_ d: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    // MARK: - Network

    private static func postWorker(body: [String: Any]) async throws -> Data {
        var req = URLRequest(url: workerURL)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(clientSecret, forHTTPHeaderField: "X-Client-Secret")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await sendWorkerRequestWithRetry(req)

        guard let http = response as? HTTPURLResponse else {
            throw AIParseError.network("no http response")
        }
        if http.statusCode == 401 { throw AIParseError.unauthorized }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIParseError.serverError(http.statusCode, body)
        }
        guard !data.isEmpty else { throw AIParseError.empty }
        return data
    }

    private static func sendWorkerRequestWithRetry(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var lastError: Error?

        for attempt in 0..<maxNetworkAttempts {
            do {
                return try await URLSession.shared.data(for: request)
            } catch {
                lastError = error
                guard shouldRetryNetworkError(error), attempt < maxNetworkAttempts - 1 else {
                    throw AIParseError.network(error.localizedDescription)
                }

                let delayNs = UInt64(350_000_000) * UInt64(attempt + 1)
                try? await Task.sleep(nanoseconds: delayNs)
            }
        }

        throw AIParseError.network(lastError?.localizedDescription ?? "request failed")
    }

    private static func shouldRetryNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .networkConnectionLost, .timedOut, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    // MARK: - Local fallbacks

    static let fixedBrainTopics = ["生活", "工作", "学习", "读书摘要", "情绪", "灵感"]

    static func normalizedBrainTitle(_ raw: String, maxLength: Int = 22) -> String {
        let clean = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'\u{201c}\u{201d}\u{2018}\u{2019}\u{300c}\u{300d}\u{300e}\u{300f}[]\u{3010}\u{3011}\u{ff08}\u{ff09}()\u{3002}.\u{ff01}!\u{ff1f}?\u{ff1a}:\u{ff0c},\u{3001}"))
        guard !clean.isEmpty else { return "" }
        if clean.count <= maxLength { return clean }

        let separators = CharacterSet(charactersIn: "。.!！?？\n；;")
        if let sentence = clean.components(separatedBy: separators).first?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sentence.isEmpty,
           sentence.count <= maxLength {
            return sentence
        }

        let softSeparators = CharacterSet(charactersIn: "，,、：:")
        let phrase = clean.components(separatedBy: softSeparators).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if phrase.count >= 6 && phrase.count <= maxLength {
            return phrase
        }

        return String(clean.prefix(maxLength))
    }

    static func normalizedBrainTopics(title: String, content: String, suggestions: [String]) -> [String] {
        let text = "\(title) \(content)"
        var result: [String] = []

        for suggestion in suggestions {
            appendTopic(mappedBrainTopic(for: suggestion, context: text), to: &result)
        }
        for topic in inferredBrainTopics(from: text) {
            appendTopic(topic, to: &result)
        }

        return Array(result.prefix(2))
    }

    private static func fallbackTopics(title: String, content: String) -> [String] {
        let topics = normalizedBrainTopics(title: title, content: content, suggestions: [])
        return topics.isEmpty ? ["灵感"] : topics
    }

    private static func inferredBrainTopics(from text: String) -> [String] {
        let rules: [(String, [String])] = [
            ("读书摘要", ["读书", "书摘", "读后感", "阅读", "摘录", "摘要", "书里", "这本书"]),
            ("工作", ["工作", "项目", "产品", "会议", "客户", "同事", "PRD", "需求", "开发", "代码", "技术", "行业", "公司", "面试", "taste"]),
            ("学习", ["学习", "课程", "考试", "复习", "论文", "知识", "研究", "教程"]),
            ("生活", ["生活", "吃饭", "睡觉", "运动", "打球", "休息", "健康"]),
            ("情绪", ["情绪", "感受", "焦虑", "开心", "难过", "失望", "压力", "DBT", "心情"]),
            ("灵感", ["灵感", "想法", "创意", "点子", "设计", "观察", "洞察", "突然想到"])
        ]
        var result: [String] = []
        for (topic, keywords) in rules {
            if keywords.contains(where: { text.localizedCaseInsensitiveContains($0) }) {
                result.append(topic)
            }
            if result.count == 2 { break }
        }
        return result
    }

    private static func mappedBrainTopic(for raw: String, context: String) -> String? {
        let clean = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#＃"))
        guard !clean.isEmpty else { return nil }
        if clean == "灵感", contextContainsWorkSignal(context) { return "工作" }
        if fixedBrainTopics.contains(clean) { return clean }
        if clean.localizedCaseInsensitiveContains("读书")
            || clean.localizedCaseInsensitiveContains("书摘")
            || clean.localizedCaseInsensitiveContains("阅读") {
            return "读书摘要"
        }
        if clean.localizedCaseInsensitiveContains("情绪")
            || clean.localizedCaseInsensitiveContains("感受")
            || clean.localizedCaseInsensitiveContains("心情") {
            return "情绪"
        }
        if clean.localizedCaseInsensitiveContains("工作")
            || clean.localizedCaseInsensitiveContains("职业")
            || clean.localizedCaseInsensitiveContains("产品")
            || clean.localizedCaseInsensitiveContains("技术")
            || clean.localizedCaseInsensitiveContains("行业")
            || clean.localizedCaseInsensitiveContains("商业") {
            return "工作"
        }
        if clean.localizedCaseInsensitiveContains("学习")
            || clean.localizedCaseInsensitiveContains("研究")
            || clean.localizedCaseInsensitiveContains("课程") {
            return "学习"
        }
        if clean.localizedCaseInsensitiveContains("生活")
            || clean.localizedCaseInsensitiveContains("健康")
            || clean.localizedCaseInsensitiveContains("日常") {
            return "生活"
        }
        if clean.localizedCaseInsensitiveContains("灵感")
            || clean.localizedCaseInsensitiveContains("想法")
            || clean.localizedCaseInsensitiveContains("创意")
            || clean.localizedCaseInsensitiveContains("观察") {
            return contextContainsWorkSignal(context) ? "工作" : "灵感"
        }
        return nil
    }

    private static func contextContainsWorkSignal(_ text: String) -> Bool {
        ["工作", "项目", "产品", "技术", "行业", "商业", "公司", "客户", "需求", "PRD", "taste"].contains {
            text.localizedCaseInsensitiveContains($0)
        }
    }

    private static func appendTopic(_ topic: String?, to result: inout [String]) {
        guard let topic, fixedBrainTopics.contains(topic), !result.contains(topic) else { return }
        result.append(topic)
    }

    private static func fallbackTitle(from content: String) -> String {
        threadFallbackTitle(from: content)
    }

    static func threadFallbackTitle(from content: String) -> String {
        let clean = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'\u{201c}\u{201d}\u{2018}\u{2019}\u{300c}\u{300d}\u{300e}\u{300f}[]\u{3010}\u{3011}\u{ff08}\u{ff09}()\u{3002}.\u{ff01}!\u{ff1f}?\u{ff1a}:\u{ff0c},\u{3001}"))
        guard !clean.isEmpty else { return "" }
        let separators = CharacterSet(charactersIn: "。.!！?？\n")
        let firstSentence = clean
            .components(separatedBy: separators)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? clean
        let prefixes = ["今天", "我", "感觉", "觉得", "突然想到", "记录一下", "就是", "然后"]
        var title = firstSentence
        for prefix in prefixes where title.hasPrefix(prefix) {
            title.removeFirst(prefix.count)
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        return normalizedBrainTitle(title, maxLength: 22)
    }
}

// MARK: - Utility response types

private struct UtilityArrayResponse: Decodable {
    let result: [String]
}

private struct UtilityStringResponse: Decodable {
    let result: String
}
