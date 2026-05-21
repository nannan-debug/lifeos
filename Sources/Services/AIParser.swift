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
    static let timeout: TimeInterval = 30
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
        threadId: String? = nil
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
            let topics = wrapper.result.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
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
            let title = wrapper.result.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { return String(title.prefix(10)) }
        } catch {}
        return fallbackTitle(from: content)
    }

    static func suggestAgentThreadTitle(content: String) async throws -> String {
        let title = try await suggestBrainTitle(content: content)
        return threadFallbackTitle(from: title.isEmpty ? content : title)
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

    private static func fallbackTopics(title: String, content: String) -> [String] {
        let text = "\(title) \(content)"
        let rules: [(String, [String])] = [
            ("工作", ["工作", "项目", "产品", "会议", "客户", "同事", "PRD", "需求", "开发", "代码"]),
            ("学习", ["学习", "读书", "课程", "考试", "复习", "论文", "知识", "研究"]),
            ("生活", ["生活", "吃饭", "睡觉", "运动", "打球", "休息", "健康"]),
            ("人际", ["朋友", "家人", "沟通", "关系", "聊天", "社交", "同学"]),
            ("灵感", ["灵感", "想法", "创意", "点子", "设计", "感觉", "突然想到"])
        ]
        var result: [String] = []
        for (topic, keywords) in rules {
            if keywords.contains(where: { text.localizedCaseInsensitiveContains($0) }) {
                result.append(topic)
            }
            if result.count == 3 { break }
        }
        return result.isEmpty ? ["灵感"] : result
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
        return String(title.prefix(14))
    }
}

// MARK: - Utility response types

private struct UtilityArrayResponse: Decodable {
    let result: [String]
}

private struct UtilityStringResponse: Decodable {
    let result: String
}
