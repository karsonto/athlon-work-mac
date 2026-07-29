import Foundation

/// AG-UI-aligned stream events (matches Windows `AgentStreamEvent`).
nonisolated enum AgentStreamEvent: Sendable, Equatable {
    case runStarted(sessionId: String, runId: String)
    case runFinished(sessionId: String, runId: String)
    case textMessageStart(messageId: String, role: String)
    case textMessageContent(messageId: String, delta: String)
    case textMessageEnd(messageId: String)
    case reasoningMessageStart(messageId: String, role: String)
    case reasoningMessageContent(messageId: String, delta: String)
    case reasoningMessageEnd(messageId: String)
    case toolCallStart(toolCallId: String, toolName: String, index: Int?)
    case toolCallArgs(toolCallId: String, delta: String)
    case toolCallEnd(toolCallId: String)
    case toolCallResult(toolCallId: String, content: String, messageId: String)
    /// Incremental stdout/stderr while a tool is still running.
    case toolCallOutput(toolCallId: String, delta: String)
    /// Non-streaming persisted messages (compaction notices, fallbacks).
    case chatMessageAppended(ChatMessage)
    case clearEmptyAssistantPlaceholder
    case usageRecorded(SessionUsageSnapshot)
    case contextHygieneApplied(estimatedSavingsTokens: Int)
}
