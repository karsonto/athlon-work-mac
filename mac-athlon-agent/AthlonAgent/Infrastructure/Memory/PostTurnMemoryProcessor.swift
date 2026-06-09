import Foundation

/// Post-turn processor that triggers memory flush after each conversation turn,
/// then consolidates when the configured minimum gap has elapsed.
final class PostTurnMemoryProcessor: IPostTurnMemoryProcessor {
    private let flushService: MemoryFlushService
    private let consolidationService: MemoryConsolidating
    private let settings: MemorySettings
    private var lastConsolidation = Date.distantPast

    init(flushService: MemoryFlushService,
         consolidationService: MemoryConsolidating,
         settings: MemorySettings) {
        self.flushService = flushService
        self.consolidationService = consolidationService
        self.settings = settings
    }

    func processTurn(messages: [ChatMessage]) async throws -> MemoryFlushResult {
        guard settings.enabled else { return .skipped }

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

        let now = Date()
        if now.timeIntervalSince(lastConsolidation) >= settings.consolidationMinGap {
            lastConsolidation = now
            AgentFileLogger.log("post-turn memory consolidation starting", category: "Memory")
            await consolidationService.consolidate()
        }

        return result
    }
}
