import Foundation

nonisolated enum TokenEstimator {
    /// Rough chars/4 heuristic used for compaction stubs.
    static func estimateTokens(_ text: String) -> Int {
        max(1, (text.utf8.count + 3) / 4)
    }

    static func estimateTokens(messages: [ChatMessage]) -> Int {
        messages.reduce(0) { partial, message in
            var total = partial + estimateTokens(message.content)
            if let reasoning = message.reasoning {
                total += estimateTokens(reasoning)
            }
            if let toolCalls = message.toolCalls {
                for call in toolCalls {
                    total += estimateTokens(call.name) + estimateTokens(call.arguments)
                }
            }
            return total
        }
    }
}
