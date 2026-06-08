import Foundation

/// Post-turn processor that triggers memory flush after each conversation turn.
final class PostTurnMemoryProcessor: IPostTurnMemoryProcessor {
    private let flushService: MemoryFlushService

    init(flushService: MemoryFlushService) {
        self.flushService = flushService
    }

    func processTurn(messages: [ChatMessage]) async -> MemoryFlushResult {
        AgentFileLogger.log("post-turn memory flush starting", category: "Memory")
        let result = await flushService.flush(messages: messages)
        switch result {
        case .success(let text):
            AgentFileLogger.log("memory flush extracted \(text.count) chars", category: "Memory")
        case .skipped:
            AgentFileLogger.log("memory flush skipped", category: "Memory")
        case .failed(let error):
            AgentFileLogger.log("memory flush failed: \(error)", category: "Memory")
        }
        return result
    }
}
