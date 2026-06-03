import Foundation

struct SessionTurnEndSnapshot {
    var assistantContent: String?
    var assistantReasoning: String?
    var incompleteToolCalls: [AgentToolCall]
    var wasCancelled: Bool
    var timedOut: Bool
    var errorMessage: String?
}

struct SessionTurnReconcileResult {
    let session: AgentSession
    let persistedMessages: [ChatMessage]
}

enum SessionTurnReconciler {
    static func reconcile(_ session: AgentSession, snapshot: SessionTurnEndSnapshot) -> SessionTurnReconcileResult {
        guard needsReconcile(snapshot) else {
            return SessionTurnReconcileResult(session: session, persistedMessages: [])
        }

        var persisted: [ChatMessage] = []
        var messages = session.messages
        let parentId = findLastUserMessageId(messages)
        var answered = buildAnsweredToolCallIds(messages)

        let incompleteTools = snapshot.incompleteToolCalls
            .filter { !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .reduce(into: [AgentToolCall]()) { acc, call in
                if !acc.contains(where: { $0.id == call.id }) { acc.append(call) }
            }
            .filter { !answered.contains($0.id) }

        let hasAssistantText = !(snapshot.assistantContent ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(snapshot.assistantReasoning ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let tailAssistant = findTailAssistantAfterLastUser(messages)

        if tailAssistant == nil, hasAssistantText || !incompleteTools.isEmpty {
            var content = snapshot.assistantContent ?? ""
            if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, snapshot.wasCancelled {
                content = "（生成已停止）"
            }
            let assistant = ChatMessage(
                role: .assistant,
                content: content,
                reasoningContent: snapshot.assistantReasoning ?? "",
                toolCalls: incompleteTools.isEmpty ? nil : incompleteTools,
                parentMessageId: parentId
            )
            messages.append(assistant)
            persisted.append(assistant)
            for call in incompleteTools { answered.insert(call.id) }
        }

        for toolCall in incompleteTools where !answered.contains(toolCall.id) {
            let toolMessage = ChatMessage(
                role: .tool,
                content: AgentRuntimeToolFormatting.formatToolResult(
                    toolCall,
                    buildInterruptedToolResult(snapshot)
                ),
                parentMessageId: parentId
            )
            messages.append(toolMessage)
            persisted.append(toolMessage)
            answered.insert(toolCall.id)
        }

        if let notice = buildTurnNotice(snapshot), !notice.isEmpty {
            let systemMessage = ChatMessage(role: .system, content: notice, parentMessageId: parentId)
            messages.append(systemMessage)
            persisted.append(systemMessage)
        }

        guard !persisted.isEmpty else {
            return SessionTurnReconcileResult(session: session, persistedMessages: [])
        }
        return SessionTurnReconcileResult(session: session.withMessages(messages), persistedMessages: persisted)
    }

    private static func needsReconcile(_ snapshot: SessionTurnEndSnapshot) -> Bool {
        snapshot.wasCancelled || snapshot.timedOut || !(snapshot.errorMessage ?? "").isEmpty
    }

    private static func buildInterruptedToolResult(_ snapshot: SessionTurnEndSnapshot) -> ToolResult {
        if let error = snapshot.errorMessage, !error.isEmpty {
            return .failure(summary: "工具未完成", error: "模型调用失败，工具未执行完成：\(error)")
        }
        if snapshot.timedOut {
            return .failure(summary: "工具未完成", error: "本回合因超时被自动停止，工具未执行完成。")
        }
        return .failure(
            summary: "工具未完成",
            error: "上次对话在工具执行或生成时被用户停止。可继续发送消息让助手接着处理。"
        )
    }

    private static func buildTurnNotice(_ snapshot: SessionTurnEndSnapshot) -> String? {
        if let error = snapshot.errorMessage, !error.isEmpty { return error }
        if snapshot.timedOut { return "本回合已超过配置的超时时间，已自动停止。" }
        if snapshot.wasCancelled { return "生成已停止。" }
        return nil
    }

    private static func findLastUserMessageId(_ messages: [ChatMessage]) -> String? {
        messages.last(where: { $0.role == .user })?.id
    }

    private static func findTailAssistantAfterLastUser(_ messages: [ChatMessage]) -> ChatMessage? {
        guard let lastUserIndex = messages.lastIndex(where: { $0.role == .user }) else { return nil }
        return messages[(lastUserIndex + 1)...].first(where: { $0.role == .assistant })
    }

    private static func buildAnsweredToolCallIds(_ messages: [ChatMessage]) -> Set<String> {
        var answered = Set<String>()
        for message in messages where message.role == .tool {
            if let id = extractToolCallId(message.content) {
                answered.insert(id)
            }
        }
        return answered
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
