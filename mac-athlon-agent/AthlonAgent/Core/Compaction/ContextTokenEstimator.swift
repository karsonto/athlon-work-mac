import Foundation

/// Character-based token estimation aligned with AgentScope TokenCounterUtil (mixed EN/ZH, conservative).
enum ContextTokenEstimator {
    private static let charsPerToken = 2.5
    private static let messageOverhead = 5
    private static let toolCallOverhead = 10
    private static let toolResultOverhead = 8

    static func estimateTextTokens(_ text: String?, calibrationMultiplier: Double = 1.0) -> Int {
        let tokens = estimateTextTokens(text)
        if calibrationMultiplier <= 0 || abs(calibrationMultiplier - 1.0) < 0.001 { return tokens }
        return Int(ceil(Double(tokens) * calibrationMultiplier))
    }

    static func estimate(
        _ messages: [ChatMessage],
        includeReasoningInModelContext: Bool = false,
        calibrationMultiplier: Double = 1.0
    ) -> Int {
        guard !messages.isEmpty else { return 0 }
        let total = messages.reduce(0) { partial, message in
            message.role == .compaction
                ? partial
                : partial + estimateMessage(message, includeReasoningInModelContext: includeReasoningInModelContext)
        }
        if calibrationMultiplier <= 0 || abs(calibrationMultiplier - 1.0) < 0.001 { return total }
        return Int(ceil(Double(total) * calibrationMultiplier))
    }

    static func estimateMessage(_ message: ChatMessage, includeReasoningInModelContext: Bool = false) -> Int {
        if message.role == .compaction { return 0 }

        var tokens = messageOverhead
        tokens += estimateTextTokens(message.role.rawValue)

        switch message.role {
        case .user, .assistant, .system:
            tokens += estimateTextTokens(message.content)
            if includeReasoningInModelContext {
                tokens += estimateTextTokens(message.reasoningContent)
            }
            tokens += estimateToolCallsTokens(message)
        case .tool:
            tokens += toolResultOverhead
            tokens += estimateTextTokens(message.content)
        default:
            tokens += estimateTextTokens(message.content)
        }

        return tokens
    }

    static func estimateSuffix(
        _ messages: [ChatMessage],
        startIndex: Int,
        includeReasoningInModelContext: Bool = false
    ) -> Int {
        guard startIndex >= 0, startIndex < messages.count else { return 0 }
        var total = 0
        for index in startIndex..<messages.count {
            total += estimateMessage(
                messages[index],
                includeReasoningInModelContext: includeReasoningInModelContext
            )
        }
        return total
    }

    private static func estimateToolCallsTokens(_ message: ChatMessage) -> Int {
        guard let calls = AssistantToolCallsCodec.deserializeToolCalls(from: message), !calls.isEmpty else {
            return 0
        }

        var tokens = 0
        for call in calls {
            tokens += toolCallOverhead
            tokens += estimateTextTokens(call.name)
            tokens += estimateTextTokens(call.id)
            for (key, value) in call.arguments {
                tokens += estimateTextTokens(key)
                tokens += estimateTextTokens(value)
            }
        }
        return tokens
    }

    static func estimateTextTokens(_ text: String?) -> Int {
        guard let text, !text.isEmpty else { return 0 }
        return Int(ceil(Double(text.count) / charsPerToken))
    }
}
