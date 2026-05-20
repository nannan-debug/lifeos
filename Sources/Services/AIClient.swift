import Foundation

protocol AIClient {
    func chat(
        input: String,
        messages: [AgentChatRequestMessage],
        contextSummary: String,
        currentDate: String,
        currentTime: String
    ) async throws -> AgentChatResponse

    func quick(
        input: String,
        currentDate: String,
        currentTime: String
    ) async throws -> AgentChatResponse

    func suggestTitle(content: String) async throws -> String
}

struct DefaultAIClient: AIClient {
    func chat(
        input: String,
        messages: [AgentChatRequestMessage],
        contextSummary: String,
        currentDate: String,
        currentTime: String
    ) async throws -> AgentChatResponse {
        try await AIParser.chat(
            input: input,
            messages: messages,
            contextSummary: contextSummary,
            currentDate: currentDate,
            currentTime: currentTime
        )
    }

    func quick(
        input: String,
        currentDate: String,
        currentTime: String
    ) async throws -> AgentChatResponse {
        try await AIParser.quick(
            input: input,
            currentDate: currentDate,
            currentTime: currentTime
        )
    }

    func suggestTitle(content: String) async throws -> String {
        try await AIParser.suggestAgentThreadTitle(content: content)
    }
}
