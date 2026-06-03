import Foundation

enum SessionTurnSnapshotBuilder {
    static func collectIncompleteToolCalls(
        session: AgentSession,
        assistantMessageId: String?,
        uiMessages: [ChatMessage]
    ) -> [AgentToolCall] {
        var answered = Set<String>()
        for message in session.messages where message.role == .tool {
            if let toolCallId = message.toolCallId, !toolCallId.isEmpty {
                answered.insert(toolCallId)
            } else if let extracted = extractToolCallId(message.content) {
                answered.insert(extracted)
            }
        }

        var incomplete: [String: AgentToolCall] = [:]

        for message in session.messages where message.role == .assistant {
            for call in message.toolCalls ?? [] where !call.id.isEmpty && !answered.contains(call.id) {
                incomplete[call.id] = call
            }
        }

        if let assistantMessageId,
           let uiAssistant = uiMessages.first(where: { $0.id == assistantMessageId }) {
            for call in uiAssistant.toolCalls ?? [] where !call.id.isEmpty && !answered.contains(call.id) {
                incomplete[call.id] = call
            }
        }

        for message in uiMessages where message.role == .tool {
            guard let toolCallId = message.toolCallId, !toolCallId.isEmpty,
                  !answered.contains(toolCallId),
                  incomplete[toolCallId] == nil else { continue }
            guard let call = message.toolCalls?.first else { continue }
            if call.status == .preparing || call.status == .running {
                incomplete[toolCallId] = call
            }
        }

        return incomplete.values.sorted { $0.id < $1.id }
    }

    private static func extractToolCallId(_ content: String?) -> String? {
        guard let content else { return nil }
        for line in content.split(whereSeparator: \.isNewline) {
            let text = String(line)
            if text.lowercased().hasPrefix("toolcallid:") {
                let value = text.dropFirst("toolcallid:".count).trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }
}
