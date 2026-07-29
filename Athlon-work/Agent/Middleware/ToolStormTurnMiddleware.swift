import Foundation

/// Detects identical tool calls repeated too many times in a turn and stops the loop.
nonisolated final class ToolStormTurnMiddleware: TurnMiddleware, @unchecked Sendable {
    private let lock = NSLock()
    private var recentKeys: [String] = []

    func onTurnStarting(sessionId: String, messages: [ChatMessage], context: AgentRunContext) async throws {
        lock.lock()
        recentKeys = []
        lock.unlock()
    }

    func onBeforeModelRound(
        round: Int,
        messages: inout [ChatMessage],
        context: AgentRunContext
    ) async throws {
        let storm = context.settings.contextCompaction.toolStorm
        guard storm.enabled, round > 1 else { return }

        // Only inspect the assistant message that produced the most recent tool results.
        guard let lastAssistant = messages.last(where: { $0.role == .assistant }),
              let calls = lastAssistant.toolCalls, !calls.isEmpty else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        for call in calls {
            let key = "\(call.name)|\(call.arguments)"
            recentKeys.append(key)
            let window = max(1, storm.windowSize)
            if recentKeys.count > window * 4 {
                recentKeys = Array(recentKeys.suffix(window * 4))
            }
            let identicalCount = recentKeys.filter { $0 == key }.count
            let limit = max(8, storm.windowSize)
            if identicalCount >= limit {
                throw AgentRuntimeError.toolStormDetected(
                    "Tool '\(call.name)' invoked identically \(identicalCount) times"
                )
            }
        }
    }
}
