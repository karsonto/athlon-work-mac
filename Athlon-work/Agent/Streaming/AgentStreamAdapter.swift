import Foundation

/// Converts streaming `ModelDelta` values into AG-UI `AgentStreamEvent`s.
nonisolated final class AgentStreamAdapter: @unchecked Sendable {
    private let messageId: String
    private var textStarted = false
    private var textEnded = false
    private var reasoningStarted = false
    private var reasoningEnded = false
    private var openToolCalls = Set<String>()

    init(messageId: String = UUID().uuidString.replacingOccurrences(of: "-", with: "")) {
        self.messageId = messageId
    }

    var assistantMessageId: String { messageId }

    func events(for delta: ModelDelta) -> [AgentStreamEvent] {
        switch delta {
        case let .content(text):
            guard !text.isEmpty else { return [] }
            var events: [AgentStreamEvent] = []
            if !textStarted {
                textStarted = true
                events.append(.textMessageStart(messageId: messageId, role: "assistant"))
            }
            events.append(.textMessageContent(messageId: messageId, delta: text))
            return events

        case let .reasoning(text):
            guard !text.isEmpty else { return [] }
            var events: [AgentStreamEvent] = []
            if !reasoningStarted {
                reasoningStarted = true
                events.append(.reasoningMessageStart(messageId: messageId, role: "assistant"))
            }
            events.append(.reasoningMessageContent(messageId: messageId, delta: text))
            return events

        case let .toolCallStart(id, name, index):
            openToolCalls.insert(id)
            return [.toolCallStart(toolCallId: id, toolName: name, index: index)]

        case let .toolCallArgs(id, delta):
            return [.toolCallArgs(toolCallId: id, delta: delta)]

        case let .toolCallEnd(id):
            openToolCalls.remove(id)
            return [.toolCallEnd(toolCallId: id)]
        }
    }

    func finishEvents() -> [AgentStreamEvent] {
        var events: [AgentStreamEvent] = []
        if reasoningStarted && !reasoningEnded {
            reasoningEnded = true
            events.append(.reasoningMessageEnd(messageId: messageId))
        }
        if textStarted && !textEnded {
            textEnded = true
            events.append(.textMessageEnd(messageId: messageId))
        }
        for id in openToolCalls {
            events.append(.toolCallEnd(toolCallId: id))
        }
        openToolCalls.removeAll()
        return events
    }
}
