import Foundation

/// Converts model/runtime signals into AG-UI-aligned stream events.
final class AgentStreamAdapter {
    let sessionId: String
    let runId: String
    let state = AgentStreamConversionState()

    init(sessionId: String, runId: String) {
        self.sessionId = sessionId
        self.runId = runId
    }

    func createRunStarted() -> [AgentStreamEvent] {
        [.runStarted(sessionId: sessionId, runId: runId)]
    }

    func onTextDelta(messageId: String, delta: String) -> [AgentStreamEvent] {
        guard !delta.isEmpty else { return [] }
        var events: [AgentStreamEvent] = []
        ensureActiveTextMessage(messageId: messageId, events: &events)
        events.append(.textMessageContent(messageId: messageId, delta: delta))
        return events
    }

    func onReasoningDelta(messageId: String, delta: String) -> [AgentStreamEvent] {
        guard !delta.isEmpty else { return [] }
        var events: [AgentStreamEvent] = []
        ensureActiveReasoningMessage(messageId: messageId, events: &events)
        events.append(.reasoningMessageContent(messageId: messageId, delta: delta))
        return events
    }

    func onToolCallDelta(messageId: String, delta: StreamingToolCallDelta) -> [AgentStreamEvent] {
        var events: [AgentStreamEvent] = []
        endActiveAssistantMessagesForToolBoundary(messageId: messageId, events: &events)

        let toolCallId: String
        if let id = delta.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            toolCallId = id
        } else {
            toolCallId = "stream-tool-\(delta.index)"
        }

        if !state.hasStartedToolCall(toolCallId) {
            state.startToolCall(toolCallId)
            events.append(.toolCallStart(
                toolCallId: toolCallId,
                toolName: delta.name ?? "unknown",
                index: delta.index
            ))
        }

        state.toolIndexToCallId[delta.index] = toolCallId
        if !delta.argumentsJson.isEmpty {
            events.append(.toolCallArgs(toolCallId: toolCallId, delta: delta.argumentsJson))
        }

        return events
    }

    func onAssistantRoundCompleted(_ message: ChatMessage) -> [AgentStreamEvent] {
        var events: [AgentStreamEvent] = []
        endActiveAssistantMessagesForToolBoundary(messageId: message.id, events: &events)

        let toolCalls = message.toolCalls ?? []
        for (index, toolCall) in toolCalls.enumerated() {
            if !state.hasStartedToolCall(toolCall.id) {
                state.startToolCall(toolCall.id)
                events.append(.toolCallStart(toolCallId: toolCall.id, toolName: toolCall.name, index: index))
            }
            if !state.hasEndedToolCall(toolCall.id) {
                state.endToolCall(toolCall.id)
                events.append(.toolCallEnd(toolCallId: toolCall.id))
            }
        }

        return events
    }

    func onToolResult(toolMessage: ChatMessage, toolCall: AgentToolCall) -> [AgentStreamEvent] {
        var events: [AgentStreamEvent] = []
        if !state.hasStartedToolCall(toolCall.id) {
            state.startToolCall(toolCall.id)
            events.append(.toolCallStart(toolCallId: toolCall.id, toolName: toolCall.name, index: nil))
        }
        if !state.hasEndedToolCall(toolCall.id) {
            state.endToolCall(toolCall.id)
            events.append(.toolCallEnd(toolCallId: toolCall.id))
        }
        events.append(.toolCallResult(
            toolCallId: toolCall.id,
            content: toolMessage.content,
            messageId: toolMessage.id
        ))
        return events
    }

    func finishRun() -> [AgentStreamEvent] {
        var events: [AgentStreamEvent] = []

        for messageId in state.startedTextMessageIds where !state.hasEndedTextMessage(messageId) {
            events.append(.textMessageEnd(messageId: messageId))
            state.endTextMessage(messageId)
        }

        for messageId in state.startedReasoningMessageIds where !state.hasEndedReasoningMessage(messageId) {
            events.append(.reasoningMessageEnd(messageId: messageId))
            state.endReasoningMessage(messageId)
        }

        for toolCallId in state.startedToolCallIdSet where !state.hasEndedToolCall(toolCallId) {
            events.append(.toolCallEnd(toolCallId: toolCallId))
            state.endToolCall(toolCallId)
        }

        state.clearActiveAssistantMessage()
        events.append(.runFinished(sessionId: sessionId, runId: runId))
        return events
    }

    private func ensureActiveTextMessage(messageId: String, events: inout [AgentStreamEvent]) {
        if state.hasActiveTextMessage(), state.currentTextMessageId == messageId {
            return
        }
        if !state.hasStartedTextMessage(messageId) {
            state.startTextMessage(messageId)
            events.append(.textMessageStart(messageId: messageId, role: "assistant"))
        }
    }

    private func ensureActiveReasoningMessage(messageId: String, events: inout [AgentStreamEvent]) {
        if !state.hasStartedTextMessage(messageId) {
            state.startTextMessage(messageId)
            events.append(.textMessageStart(messageId: messageId, role: "assistant"))
        }
        if state.hasActiveReasoningMessage(), state.currentReasoningMessageId == messageId {
            return
        }
        if !state.hasStartedReasoningMessage(messageId) {
            state.startReasoningMessage(messageId)
            events.append(.reasoningMessageStart(messageId: messageId, role: "reasoning"))
        }
    }

    private func endActiveAssistantMessagesForToolBoundary(messageId: String, events: inout [AgentStreamEvent]) {
        if state.hasActiveTextMessage(), state.currentTextMessageId == messageId {
            events.append(.textMessageEnd(messageId: messageId))
            state.endTextMessage(messageId)
        }
        if state.hasActiveReasoningMessage(), state.currentReasoningMessageId == messageId {
            events.append(.reasoningMessageEnd(messageId: messageId))
            state.endReasoningMessage(messageId)
        }
        if state.activeAssistantMessageId == messageId {
            state.clearActiveAssistantMessage()
        }
    }
}
