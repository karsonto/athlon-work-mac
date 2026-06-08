import Foundation

protocol IPostTurnMemoryProcessor {
    /// Called after a conversation turn completes.
    /// Processes the turn's messages for memory extraction.
    func processTurn(messages: [ChatMessage]) async throws -> MemoryFlushResult
}
