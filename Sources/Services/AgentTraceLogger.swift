import Foundation

struct AgentTraceRetry: Codable, Equatable {
    var attempt: Int
    var willRetry: Bool?
}

struct AgentTraceErrorInfo: Codable, Equatable {
    var type: String
    var message: String
    var status: Int?
}

struct AgentTraceEvent: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var traceId: String
    var sessionId: String?
    var threadId: String?
    var eventName: String
    var source: String = "ios"
    var timestamp: String = AgentTraceEvent.isoFormatter.string(from: Date())
    var appVersion: String
    var build: String
    var model: String?
    var provider: String?
    var temperature: Double?
    var maxTokens: Int?
    var usage: AgentTokenUsage?
    var cache: [String: Int]?
    var latencyMs: Int?
    var retry: AgentTraceRetry?
    var error: AgentTraceErrorInfo?
    var payload: [String: String]

    init(
        traceId: String,
        sessionId: String?,
        threadId: String?,
        eventName: String,
        payload: [String: String] = [:],
        usage: AgentTokenUsage? = nil,
        latencyMs: Int? = nil,
        error: AgentTraceErrorInfo? = nil
    ) {
        self.traceId = traceId
        self.sessionId = sessionId
        self.threadId = threadId
        self.eventName = eventName
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        self.build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        self.payload = payload
        self.usage = usage
        self.cache = usage?.promptTokenDetails
        self.latencyMs = latencyMs
        self.error = error
    }

    static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

enum AgentTraceConfig {
    static let maxPendingEvents = 80
    static let maxRetries = 3
    static let pendingKey = "ps.agent.trace.pending.v1"
    static let failCountKey = "ps.agent.trace.failcount.v1"

    static var endpoint: URL? {
        URL(string: Secrets.agentTraceEndpoint.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static var token: String {
        Secrets.agentTraceToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var isEnabled: Bool {
        endpoint != nil && !token.isEmpty && !token.hasPrefix("REPLACE_ME")
    }
}

actor AgentTraceLogger {
    static let shared = AgentTraceLogger()

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var isFlushing = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func emit(_ event: AgentTraceEvent) async {
        guard AgentTraceConfig.isEnabled else { return }
        var pending = loadPending()
        pending.append(event)
        if pending.count > AgentTraceConfig.maxPendingEvents {
            pending = Array(pending.suffix(AgentTraceConfig.maxPendingEvents))
        }
        savePending(pending)
        await flushPending()
    }

    func flushPending() async {
        guard !isFlushing, AgentTraceConfig.isEnabled else { return }
        isFlushing = true
        defer { isFlushing = false }

        while true {
            var pending = loadPending()
            guard !pending.isEmpty else {
                resetFailCount()
                return
            }
            do {
                try await send(pending[0])
                pending.removeFirst()
                savePending(pending)
                resetFailCount()
            } catch {
                let count = incrementFailCount()
                if count >= AgentTraceConfig.maxRetries {
                    pending.removeFirst()
                    savePending(pending)
                    resetFailCount()
                } else {
                    return
                }
            }
        }
    }

    func clearPendingForTests() {
        defaults.removeObject(forKey: AgentTraceConfig.pendingKey)
    }

    private func send(_ event: AgentTraceEvent) async throws {
        guard let endpoint = AgentTraceConfig.endpoint else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AgentTraceConfig.token, forHTTPHeaderField: "X-LifeOS-Trace-Token")
        request.httpBody = try encoder.encode(event)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AIParseError.network("trace upload failed")
        }
    }

    private func incrementFailCount() -> Int {
        let count = defaults.integer(forKey: AgentTraceConfig.failCountKey) + 1
        defaults.set(count, forKey: AgentTraceConfig.failCountKey)
        return count
    }

    private func resetFailCount() {
        defaults.removeObject(forKey: AgentTraceConfig.failCountKey)
    }

    private func loadPending() -> [AgentTraceEvent] {
        guard let data = defaults.data(forKey: AgentTraceConfig.pendingKey) else { return [] }
        return (try? decoder.decode([AgentTraceEvent].self, from: data)) ?? []
    }

    private func savePending(_ events: [AgentTraceEvent]) {
        guard let data = try? encoder.encode(events) else { return }
        defaults.set(data, forKey: AgentTraceConfig.pendingKey)
    }
}

enum AgentTracePayload {
    static func json<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }
}
