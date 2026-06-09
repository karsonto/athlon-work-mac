import Foundation

/// AG-UI-style conversion state keyed by persistent messageId.
final class AgentStreamConversionState {
    private var startedTextMessages: Set<String> = []
    private var endedTextMessages: Set<String> = []
    private var startedReasoningMessages: Set<String> = []
    private var endedReasoningMessages: Set<String> = []
    private var startedToolCallIds: Set<String> = []
    private var endedToolCallIds: Set<String> = []

    private(set) var currentTextMessageId: String?
    private(set) var currentReasoningMessageId: String?
    private(set) var activeAssistantMessageId: String?

    var toolIndexToCallId: [Int: String] = [:]

    func hasStartedTextMessage(_ messageId: String) -> Bool {
        startedTextMessages.contains(messageId)
    }

    func hasEndedTextMessage(_ messageId: String) -> Bool {
        endedTextMessages.contains(messageId)
    }

    func hasActiveTextMessage() -> Bool {
        guard let currentTextMessageId else { return false }
        return !hasEndedTextMessage(currentTextMessageId)
    }

    func startTextMessage(_ messageId: String) {
        startedTextMessages.insert(messageId)
        currentTextMessageId = messageId
        activeAssistantMessageId = messageId
    }

    func endTextMessage(_ messageId: String) {
        endedTextMessages.insert(messageId)
        if currentTextMessageId == messageId {
            currentTextMessageId = nil
        }
        if activeAssistantMessageId == messageId, !hasActiveReasoningMessage() {
            activeAssistantMessageId = nil
        }
    }

    func hasStartedReasoningMessage(_ messageId: String) -> Bool {
        startedReasoningMessages.contains(messageId)
    }

    func hasEndedReasoningMessage(_ messageId: String) -> Bool {
        endedReasoningMessages.contains(messageId)
    }

    func hasActiveReasoningMessage() -> Bool {
        guard let currentReasoningMessageId else { return false }
        return !hasEndedReasoningMessage(currentReasoningMessageId)
    }

    func startReasoningMessage(_ messageId: String) {
        startedReasoningMessages.insert(messageId)
        currentReasoningMessageId = messageId
        activeAssistantMessageId = messageId
    }

    func endReasoningMessage(_ messageId: String) {
        endedReasoningMessages.insert(messageId)
        if currentReasoningMessageId == messageId {
            currentReasoningMessageId = nil
        }
        if activeAssistantMessageId == messageId, !hasActiveTextMessage() {
            activeAssistantMessageId = nil
        }
    }

    func hasStartedToolCall(_ toolCallId: String) -> Bool {
        startedToolCallIds.contains(toolCallId)
    }

    func hasEndedToolCall(_ toolCallId: String) -> Bool {
        endedToolCallIds.contains(toolCallId)
    }

    func startToolCall(_ toolCallId: String) {
        startedToolCallIds.insert(toolCallId)
    }

    func endToolCall(_ toolCallId: String) {
        endedToolCallIds.insert(toolCallId)
    }

    var startedTextMessageIds: Set<String> { startedTextMessages }
    var startedReasoningMessageIds: Set<String> { startedReasoningMessages }
    var startedToolCallIdSet: Set<String> { startedToolCallIds }

    func clearActiveAssistantMessage() {
        activeAssistantMessageId = nil
    }

    func reset() {
        startedTextMessages.removeAll()
        endedTextMessages.removeAll()
        startedReasoningMessages.removeAll()
        endedReasoningMessages.removeAll()
        startedToolCallIds.removeAll()
        endedToolCallIds.removeAll()
        toolIndexToCallId.removeAll()
        currentTextMessageId = nil
        currentReasoningMessageId = nil
        activeAssistantMessageId = nil
    }
}
