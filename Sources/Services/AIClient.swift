import Foundation

protocol AIClient {
    func chat(
        input: String,
        messages: [AgentChatRequestMessage],
        contextSummary: String,
        currentDate: String,
        currentTime: String,
        traceId: String?,
        sessionId: String?,
        threadId: String?,
        userProfile: String?,
        agentMode: String?,
        dbtSession: AgentDBTSessionState?,
        agentPersona: [String: String]?
    ) async throws -> AgentChatResponse

    func quick(
        input: String,
        currentDate: String,
        currentTime: String,
        traceId: String?,
        sessionId: String?,
        threadId: String?
    ) async throws -> AgentChatResponse

    func suggestTitle(content: String) async throws -> String

    func chatStream(
        input: String,
        messages: [AgentChatRequestMessage],
        contextSummary: String,
        currentDate: String,
        currentTime: String,
        traceId: String?,
        sessionId: String?,
        threadId: String?,
        userProfile: String?,
        trigger: String?,
        agentMode: String?,
        dbtSession: AgentDBTSessionState?,
        agentPersona: [String: String]?
    ) -> AsyncThrowingStream<StreamEvent, Error>
}

struct DefaultAIClient: AIClient {
    func chat(
        input: String,
        messages: [AgentChatRequestMessage],
        contextSummary: String,
        currentDate: String,
        currentTime: String,
        traceId: String?,
        sessionId: String?,
        threadId: String?,
        userProfile: String?,
        agentMode: String? = nil,
        dbtSession: AgentDBTSessionState? = nil,
        agentPersona: [String: String]? = nil
    ) async throws -> AgentChatResponse {
        try await AIParser.chat(
            input: input,
            messages: messages,
            contextSummary: contextSummary,
            currentDate: currentDate,
            currentTime: currentTime,
            traceId: traceId,
            sessionId: sessionId,
            threadId: threadId,
            userProfile: userProfile,
            agentMode: agentMode,
            dbtSession: dbtSession,
            agentPersona: agentPersona
        )
    }

    func quick(
        input: String,
        currentDate: String,
        currentTime: String,
        traceId: String?,
        sessionId: String?,
        threadId: String?
    ) async throws -> AgentChatResponse {
        try await AIParser.quick(
            input: input,
            currentDate: currentDate,
            currentTime: currentTime,
            traceId: traceId,
            sessionId: sessionId,
            threadId: threadId
        )
    }

    func suggestTitle(content: String) async throws -> String {
        try await AIParser.suggestAgentThreadTitle(content: content)
    }

    func chatStream(
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
        agentMode: String? = nil,
        dbtSession: AgentDBTSessionState? = nil,
        agentPersona: [String: String]? = nil
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AIParser.chatStream(
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
    }
}
