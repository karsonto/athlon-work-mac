import Foundation

/// Stub compaction middleware: estimates tokens and truncates very long tool results.
nonisolated struct CompactionTurnMiddleware: TurnMiddleware {
    func onBeforeModelRound(
        round: Int,
        messages: inout [ChatMessage],
        context: AgentRunContext
    ) async throws {
        let settings = context.settings.contextCompaction
        guard settings.toolResultEviction.enabled else { return }

        let maxChars = settings.toolResultEviction.maxResultChars
        let preview = settings.toolResultEviction.previewChars
        let excluded = Set(settings.toolResultEviction.excludedToolNames.map { $0.lowercased() })

        for index in messages.indices {
            guard messages[index].role == .tool else { continue }
            let content = messages[index].content
            if content.count <= maxChars { continue }

            // Prefer skipping eviction for certain tool names when we can infer them from nearby assistant toolCalls.
            if let toolCallId = messages[index].toolCallId,
               let toolName = findToolName(toolCallId: toolCallId, in: messages),
               excluded.contains(toolName.lowercased()) {
                continue
            }

            let head = String(content.prefix(preview))
            let tokens = TokenEstimator.estimateTokens(content)
            messages[index].content =
                head
                + "\n\n…(tool result truncated; ~\(tokens) tokens estimated, kept \(preview) chars)"
        }
    }

    private func findToolName(toolCallId: String, in messages: [ChatMessage]) -> String? {
        for message in messages.reversed() {
            guard let calls = message.toolCalls else { continue }
            if let match = calls.first(where: { $0.id == toolCallId }) {
                return match.name
            }
        }
        return nil
    }
}
