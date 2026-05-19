import Foundation

protocol AIClient {
    func chat(
        input: String,
        messages: [AgentChatRequestMessage],
        contextSummary: String,
        currentDate: String,
        currentTime: String
    ) async throws -> AgentChatResponse
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
}
