import Foundation

protocol SubAgentTurnExecuting: AnyObject {
    func executeSubTurn(session: AgentSession, userInput: String) async throws -> AgentSession
}
