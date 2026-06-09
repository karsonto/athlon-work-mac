import Foundation

final class SubAgentTurnRunner: SubAgentTurnExecuting {
    private var runtimeProvider: (() -> AgentRuntime)?

    func configure(runtimeProvider: @escaping () -> AgentRuntime) {
        self.runtimeProvider = runtimeProvider
    }

    func executeSubTurn(session: AgentSession, userInput: String) async throws -> AgentSession {
        guard let runtimeProvider else {
            throw ToolError.failed("Sub-agent unavailable", detail: "Runtime provider not configured.")
        }
        var working = session
        let userMessage = ChatMessage(
            id: UUID().uuidString,
            role: .user,
            content: userInput,
            createdAt: Date()
        )
        working = working.withMessage(userMessage)
        return try await runtimeProvider().sendAsync(session: working)
    }
}
