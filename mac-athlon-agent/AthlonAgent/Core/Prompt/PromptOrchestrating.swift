import Foundation

protocol PromptOrchestrating {
    func prepareForTurn(
        session: AgentSession,
        tools: [ToolDefinition]
    ) -> FrozenSystemPrompt

    func buildForReasoningIteration(
        frozen: FrozenSystemPrompt,
        session: AgentSession,
        tools: [ToolDefinition]
    ) async -> String
}

extension SystemPromptOrchestrator: PromptOrchestrating {}

extension SubAgentSystemPromptOrchestrator: PromptOrchestrating {}
