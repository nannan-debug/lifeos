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
}
