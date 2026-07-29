import Foundation

nonisolated protocol TurnMiddleware: Sendable {
    func onTurnStarting(sessionId: String, messages: [ChatMessage], context: AgentRunContext) async throws
    func onBeforeModelRound(
        round: Int,
        messages: inout [ChatMessage],
        context: AgentRunContext
    ) async throws
    func onTurnCompleted(sessionId: String, messages: [ChatMessage], context: AgentRunContext) async throws
}

extension TurnMiddleware {
    func onTurnStarting(sessionId: String, messages: [ChatMessage], context: AgentRunContext) async throws {}
    func onBeforeModelRound(
        round: Int,
        messages: inout [ChatMessage],
        context: AgentRunContext
    ) async throws {}
    func onTurnCompleted(sessionId: String, messages: [ChatMessage], context: AgentRunContext) async throws {}
}
