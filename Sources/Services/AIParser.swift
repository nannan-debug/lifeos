import Foundation

/// AI-parsed record coming back from Cloudflare Worker proxy (DeepSeek)
/// 对应 Worker system prompt 约定的 schema
struct AIParsedRecord: Decodable {
    let bucket: String           // "time" | "note"

    // Time fields
    let eventName: String?
    let module: String?
    let startTime: String?       // "HH:mm"
    let endTime: String?
    let notes: String?

    // Note fields
    let type: String?            // "想法" | "感受" | "感恩" | "做梦"
    let title: String?
    let details: String?
    let mood: Int?               // 1-5
    let feelings: [String]?

    // Shared
    let date: String?            // "YYYY-MM-DD"
}

struct AIParseResponse: Decodable {
    let records: [AIParsedRecord]
    let needsClarification: String?

    private enum CodingKeys: String, CodingKey {
        case records
        case needsClarification
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // DeepSeek 偶尔不返回 records 字段，容错处理成空数组走本地兜底
        self.records = (try? c.decode([AIParsedRecord].self, forKey: .records)) ?? []
        self.needsClarification = try? c.decodeIfPresent(String.self, forKey: .needsClarification)
    }
}

private struct AITopicResponse: Decodable {
    let topics: [String]?
    let suggestions: [String]?
}

private struct AITitleResponse: Decodable {
    let title: String?
    let suggestion: String?
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
    /// Cloudflare Worker 地址（绑了自定义域名，国内无需梯子）
    /// 老地址 `personal-ai-proxy.pancakepaipai.workers.dev` 依然可用（Cloudflare 两边都挂着 Worker）
    static let workerURL = URL(string: "https://ai.dogdada.com")!

    /// 与 Worker 端 CLIENT_SECRET 对应。
    /// 真实值保存在 Sources/Services/Secrets.swift（被 .gitignore 忽略）。
    static var clientSecret: String { Secrets.aiClientSecret }

    /// 请求超时（秒）。DeepSeek 偶尔会 10-20s 才返回（长段落 / 高峰期），留足余量。
    static let timeout: TimeInterval = 30

    /// 轻量预热：向 Worker 发一个短请求让它从休眠中醒来，不关心返回结果。
    /// 目的是把 Cloudflare Worker + DeepSeek 的冷启动开销提前摊销，避免用户真发送时才等。
    static func warmUp() {
        var req = URLRequest(url: workerURL)
        req.httpMethod = "GET"
        req.timeoutInterval = 5
        // 不加 client secret，Worker 会 401 —— 但这已足够唤醒。
        URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
    }

    /// 调用 AI 解析一段口述
    /// - Parameters:
    ///   - text: 原始输入
    ///   - currentDate: "YYYY-MM-DD"
    ///   - currentTime: "HH:mm"
    static func parse(
        text: String,
        currentDate: String,
        currentTime: String
    ) async throws -> AIParseResponse {
        var req = URLRequest(url: workerURL)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(clientSecret, forHTTPHeaderField: "X-Client-Secret")

        let body: [String: Any] = [
            "text": text,
            "currentDate": currentDate,
            "currentTime": currentTime
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw AIParseError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AIParseError.network("no http response")
        }

        if http.statusCode == 401 {
            throw AIParseError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIParseError.serverError(http.statusCode, body)
        }

        guard !data.isEmpty else { throw AIParseError.empty }

        do {
            return try JSONDecoder().decode(AIParseResponse.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<binary>"
            throw AIParseError.decoding("\(error.localizedDescription) · raw=\(raw.prefix(200))")
        }
    }

    static func suggestTopics(title: String, content: String) async throws -> [String] {
        let prompt = """
        你是一个第二大脑卡片分类助手。给定一张卡片的 title 和 content，输出 1-3 个最贴切的主题标签。

        优先从以下默认集选：[工作, 学习, 生活, 灵感, 人际]。
        如默认集都不贴切，可以创新，但应简洁、可复用、有概括性。

        输出 JSON 数组，每项是字符串，不带 # 前缀。不要输出任何解释。
        如果当前接口必须返回随手记 records，请把 JSON 数组放进 details 字段。

        title: \(title)
        content: \(content)
        """

        var req = URLRequest(url: workerURL)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(clientSecret, forHTTPHeaderField: "X-Client-Secret")

        let body: [String: Any] = [
            "text": prompt,
            "currentDate": isoDate(),
            "currentTime": isoTime()
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw AIParseError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AIParseError.network("no http response")
        }

        if http.statusCode == 401 {
            throw AIParseError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIParseError.serverError(http.statusCode, body)
        }

        guard !data.isEmpty else { throw AIParseError.empty }
        let topics = parseTopicPayload(data)
        let normalized = normalizeTopics(topics)
        if !normalized.isEmpty {
            return normalized
        }
        return fallbackTopics(title: title, content: content)
    }

    static func suggestBrainTitle(content: String) async throws -> String {
        let prompt = """
        你是一个第二大脑卡片标题助手。请把下面这段内容总结成一个中文短标题。

        要求：
        - 8 个字以内，最多不超过 10 个字。
        - 只输出标题本身，不要解释。
        - 不要加引号、编号、标点。
        - 如果无法总结，输出空字符串。
        - 如果当前接口必须返回随手记 records，请把标题放进 title 字段。

        content: \(content)
        """

        var req = URLRequest(url: workerURL)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(clientSecret, forHTTPHeaderField: "X-Client-Secret")

        let body: [String: Any] = [
            "text": prompt,
            "currentDate": isoDate(),
            "currentTime": isoTime()
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw AIParseError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AIParseError.network("no http response")
        }

        if http.statusCode == 401 {
            throw AIParseError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIParseError.serverError(http.statusCode, body)
        }

        guard !data.isEmpty else { throw AIParseError.empty }
        return normalizeShortTitle(parseTitlePayload(data))
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

    private static func parseTopicPayload(_ data: Data) -> [String] {
        let decoder = JSONDecoder()

        if let direct = try? decoder.decode([String].self, from: data) {
            return direct
        }

        if let wrapped = try? decoder.decode(AITopicResponse.self, from: data) {
            return wrapped.topics ?? wrapped.suggestions ?? []
        }

        if let parsed = try? decoder.decode(AIParseResponse.self, from: data) {
            return parsed.records.flatMap { record in
                topicCandidates(from: record)
            }
        }

        if let text = String(data: data, encoding: .utf8) {
            return parseTopicText(text)
        }

        return []
    }

    private static func parseTitlePayload(_ data: Data) -> String {
        let decoder = JSONDecoder()

        if let direct = try? decoder.decode(String.self, from: data) {
            return direct
        }

        if let wrapped = try? decoder.decode(AITitleResponse.self, from: data) {
            return wrapped.title ?? wrapped.suggestion ?? ""
        }

        if let parsed = try? decoder.decode(AIParseResponse.self, from: data) {
            return parsed.records.compactMap { record in
                [record.title, record.details, record.notes]
                    .compactMap { $0 }
                    .first { !normalizeShortTitle($0).isEmpty }
            }.first ?? ""
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func topicCandidates(from record: AIParsedRecord) -> [String] {
        let fields = [
            record.title,
            record.details,
            record.notes,
            record.type
        ].compactMap { $0 }

        let parsedFields = fields.flatMap { parseTopicText($0) }
        if !parsedFields.isEmpty {
            return parsedFields
        }

        if let feelings = record.feelings, !feelings.isEmpty {
            return feelings
        }

        return fields.flatMap { splitTopicText($0) }
    }

    private static func parseTopicText(_ text: String) -> [String] {
        if let data = text.data(using: .utf8),
           let direct = try? JSONDecoder().decode([String].self, from: data) {
            return direct
        }

        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]"),
              start <= end else {
            return []
        }

        let json = String(text[start...end])
        guard let data = json.data(using: .utf8),
              let direct = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return direct
    }

    private static func splitTopicText(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: "，,、/｜|\n\t "))
            .map {
                $0.trimmingCharacters(in: CharacterSet(charactersIn: " #＃[]【】「」\"'“”‘’：:。.!！?？"))
            }
            .filter { item in
                guard !item.isEmpty else { return false }
                guard item.count <= 8 else { return false }
                return !["主题", "主题建议", "建议", "想法", "感受", "记录"].contains(item)
            }
    }

    private static func normalizeTopics(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for item in raw {
            let clean = item
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#＃"))
            guard !clean.isEmpty, !seen.contains(clean) else { continue }
            seen.insert(clean)
            result.append(clean)
            if result.count == 3 { break }
        }

        return result
    }

    private static func fallbackTopics(title: String, content: String) -> [String] {
        let text = "\(title) \(content)"
        let rules: [(String, [String])] = [
            ("工作", ["工作", "项目", "产品", "会议", "客户", "同事", "PRD", "需求", "开发", "代码"]),
            ("学习", ["学习", "读书", "课程", "考试", "复习", "论文", "知识", "研究"]),
            ("生活", ["生活", "吃饭", "睡觉", "运动", "打球", "家务", "休息", "健康"]),
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

    private static func normalizeShortTitle(_ raw: String) -> String {
        var clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        clean = clean.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’「」『』[]【】（）()。.!！?？：:，,、"))

        if clean.hasPrefix("{"), let data = clean.data(using: .utf8) {
            if let wrapped = try? JSONDecoder().decode(AITitleResponse.self, from: data) {
                clean = wrapped.title ?? wrapped.suggestion ?? ""
            }
        }

        guard !clean.isEmpty else { return "" }
        return String(clean.prefix(10))
    }
}
