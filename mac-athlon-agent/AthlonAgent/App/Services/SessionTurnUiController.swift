import Foundation

/// Per-session UI bridge for parallel turns (messages + streaming buffers).
/// Aligned with WPF `SessionTurnUiController`: one streaming assistant bubble, created on first token.
@MainActor
final class SessionTurnUiController {
    let sessionId: String
    private weak var appState: AppState?

    private var assistantMessageId: String?
    private var assistantVisibleInUI = false
    private var toolPhaseSealed = false
    /// True at the start of a model iteration that follows tool execution (append next text segment).
    private var postToolContentPhase = false
    private var streamingBuffer = ""
    private var streamingReasoningBuffer = ""
    private var streamingCoalescer: StreamingUiCoalescer?

    init(sessionId: String, appState: AppState) {
        self.sessionId = sessionId
        self.appState = appState
        self.streamingCoalescer = StreamingUiCoalescer { [weak self] in
            self?.applyPendingStreamingSnapshot()
        }
    }

    func resetForTurn() {
        streamingCoalescer?.cancel()
        streamingBuffer = ""
        streamingReasoningBuffer = ""
        assistantMessageId = nil
        assistantVisibleInUI = false
        toolPhaseSealed = false
        postToolContentPhase = false
    }

    /// After tools, model snapshots are a new segment — append unless the provider sent a full cumulative string.
    private static func mergeStreamingText(existing: String, incoming: String, postToolPhase: Bool) -> String {
        let trimmedIncoming = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIncoming.isEmpty else { return existing }
        let trimmedExisting = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedExisting.isEmpty { return incoming }
        if incoming.hasPrefix(existing) || incoming == existing { return incoming }
        if existing.hasPrefix(incoming) { return existing }
        if postToolPhase {
            if trimmedIncoming == trimmedExisting { return existing }
            if trimmedExisting.hasSuffix(trimmedIncoming) { return existing }
            return trimmedExisting + "\n\n" + trimmedIncoming
        }
        return incoming
    }

    @MainActor
    func captureEndSnapshot(
        session: AgentSession,
        wasCancelled: Bool,
        timedOut: Bool,
        errorMessage: String?
    ) -> SessionTurnEndSnapshot {
        var assistantContent: String? = streamingBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : streamingBuffer
        var assistantReasoning: String? = streamingReasoningBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : streamingReasoningBuffer

        if let appState, let assistantMessageId {
            let uiMessage = appState.messages.first(where: { $0.id == assistantMessageId })
            let persisted = session.messages.first(where: { $0.id == assistantMessageId })
            if assistantContent == nil {
                assistantContent = [uiMessage?.content, persisted?.content]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first(where: { !$0.isEmpty })
            }
            if assistantReasoning == nil {
                assistantReasoning = [uiMessage?.reasoningContent, persisted?.reasoningContent]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first(where: { !$0.isEmpty })
            }
        }

        let uiMessages = appState?.messages ?? []
        let incomplete = SessionTurnSnapshotBuilder.collectIncompleteToolCalls(
            session: session,
            assistantMessageId: assistantMessageId,
            uiMessages: uiMessages
        )

        return SessionTurnEndSnapshot(
            assistantContent: assistantContent,
            assistantReasoning: assistantReasoning,
            incompleteToolCalls: incomplete,
            wasCancelled: wasCancelled,
            timedOut: timedOut,
            errorMessage: errorMessage
        )
    }

    /// Reserves an id for the runtime without showing an empty bubble.
    func reserveAssistantMessageId() -> String {
        if let assistantMessageId { return assistantMessageId }
        let id = UUID().uuidString
        assistantMessageId = id
        return id
    }

    /// Switches the live streaming bubble to the assistant message id for the current model iteration.
    @MainActor
    func adoptAssistantMessageId(_ id: String) {
        if let appState, let previous = assistantMessageId, previous != id {
            for index in appState.messages.indices {
                var message = appState.messages[index]
                guard message.role == .assistant, message.id != id else { continue }
                guard message.isStreaming || message.isReasoningStreaming else { continue }
                message.isStreaming = false
                message.isReasoningStreaming = false
                message = message.withPromotedAnswer()
                appState.messages[index] = message
            }
        }
        postToolContentPhase = toolPhaseSealed
        let sameTarget = assistantMessageId == id
        assistantMessageId = id
        assistantVisibleInUI = appState?.messages.contains(where: { $0.id == id }) ?? false
        toolPhaseSealed = false
        if !sameTarget {
            streamingBuffer = ""
            streamingReasoningBuffer = ""
        }
    }

    func addUserMessage(_ input: String, imageAttachments: [ImageAttachment] = []) {
        Task { @MainActor in
            guard let appState else { return }
            let message = ChatMessage(
                id: UUID().uuidString,
                role: .user,
                content: input,
                createdAt: Date(),
                imageAttachments: imageAttachments.isEmpty ? nil : imageAttachments
            )
            appState.appendMessage(message, sessionId: self.sessionId)
        }
    }

    @MainActor
    private func ensureStreamingAssistantVisible() {
        guard let appState, let id = assistantMessageId, !assistantVisibleInUI else { return }
        assistantVisibleInUI = true
        let message = ChatMessage(
            id: id,
            role: .assistant,
            content: streamingBuffer,
            createdAt: Date(),
            isStreaming: true
        )
        appState.appendMessage(message, sessionId: sessionId)
    }

    @MainActor
    private func clearEmptyStreamingAssistant() {
        guard let appState, let id = assistantMessageId, assistantVisibleInUI else { return }
        if let message = appState.messages.first(where: { $0.id == id }),
           message.content.isEmpty,
           message.reasoningContent.isEmpty,
           message.toolCalls?.isEmpty != false {
            appState.removeMessage(sessionId: sessionId, messageId: id)
            assistantVisibleInUI = false
        }
    }

    /// Freezes the pre-tool assistant bubble (reasoning only); final answer streams into a new message after tools.
    @MainActor
    private func sealPreToolAssistant() {
        guard let appState, let id = assistantMessageId, assistantVisibleInUI else { return }
        let reasoning = appState.messages.first(where: { $0.id == id })?.reasoningContent ?? streamingReasoningBuffer
        appState.sealAssistantBeforeTools(sessionId: sessionId, messageId: id, reasoningContent: reasoning)
        assistantVisibleInUI = true
    }

    func appendStreamingText(_ fullContent: String) {
        streamingBuffer = fullContent
        streamingCoalescer?.scheduleFlush()
    }

    func appendReasoning(_ fullReasoning: String) {
        streamingReasoningBuffer = fullReasoning
        streamingCoalescer?.scheduleFlush()
    }

    private func applyPendingStreamingSnapshot() {
        guard let appState else { return }
        if assistantMessageId == nil {
            _ = reserveAssistantMessageId()
        }
        guard let assistantId = assistantMessageId else { return }
        ensureStreamingAssistantVisible()

        let merged = Self.mergeStreamingText(
            existing: appState.messages.first(where: { $0.id == assistantId })?.content ?? "",
            incoming: streamingBuffer,
            postToolPhase: postToolContentPhase
        )
        if postToolContentPhase {
            postToolContentPhase = false
        }
        appState.updateMessageContent(sessionId: sessionId, messageId: assistantId, content: merged)

        let hasAnswer = !streamingBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let reasoning = appState.messages.first(where: { $0.id == assistantId })?.reasoningContent
            ?? streamingReasoningBuffer
        appState.setReasoningContent(
            sessionId: sessionId,
            messageId: assistantId,
            content: reasoning,
            isReasoningStreaming: !hasAnswer
        )
    }

    /// Must run synchronously on the main thread — tool completion can arrive before UI row exists.
    func appendToolCall(_ toolCall: AgentToolCall) {
        guard let appState else { return }
        if !toolPhaseSealed {
            clearEmptyStreamingAssistant()
            sealPreToolAssistant()
            toolPhaseSealed = true
            assistantVisibleInUI = true
            streamingBuffer = ""
            streamingReasoningBuffer = ""
        }

        var running = toolCall
        running.status = .running
        running.resultSummary = "执行中…"
        let message = ChatMessage(
            id: UUID().uuidString,
            role: .tool,
            content: ToolCallDisplay.headerLine(toolName: toolCall.name, status: .running),
            createdAt: Date(),
            toolCalls: [running],
            toolCallId: toolCall.id
        )
        appState.appendMessage(message, sessionId: sessionId, persist: false)
    }

    /// Immediate UI feedback when the user stops generation (before async work unwinds).
    func markTurnCancelled() {
        streamingCoalescer?.flushNow()
        guard let appState else { return }
        for index in appState.messages.indices {
            var message = appState.messages[index]
            if message.isStreaming || message.isReasoningStreaming {
                message.isStreaming = false
                message.isReasoningStreaming = false
                if message.role == .assistant,
                   message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !message.hasReasoning {
                    message.content = "（已停止）"
                }
            }
            if message.isTool, var calls = message.toolCalls {
                for idx in calls.indices where calls[idx].status == .running || calls[idx].status == .preparing {
                    calls[idx].status = .cancelled
                    calls[idx].resultSummary = "已停止"
                }
                message.toolCalls = calls
            }
            appState.messages[index] = message
        }
    }

    func finalizeTurn(
        fullText: String,
        cancelled: Bool,
        timedOut: Bool,
        errorMessage: String?,
        reconciledMessages: [ChatMessage] = []
    ) {
        Task { @MainActor in
            guard let appState else { return }
            streamingCoalescer?.flushNow()

            if cancelled {
                markTurnCancelled()
            }

            if let assistantId = self.assistantMessageId {
                let persisted = appState.sessionManager.getSession(self.sessionId)?
                    .messages.last(where: { $0.id == assistantId })
                let uiMessage = appState.messages.first(where: { $0.id == assistantId })
                let streamedText = fullText.isEmpty ? self.streamingBuffer : fullText
                let persistedText = persisted?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let uiText = uiMessage?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let resolvedText = [streamedText, persistedText, uiText]
                    .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                    ?? ""

                if self.assistantVisibleInUI {
                    if let persisted, !resolvedText.isEmpty || persisted.hasReasoning {
                        var finalMessage = persisted
                        if !resolvedText.isEmpty {
                            finalMessage.content = resolvedText
                        }
                        finalMessage.isStreaming = false
                        finalMessage.isReasoningStreaming = false
                        appState.syncAssistantMessage(sessionId: self.sessionId, message: finalMessage)
                    } else if resolvedText.isEmpty, !cancelled, errorMessage == nil {
                        appState.removeMessage(sessionId: self.sessionId, messageId: assistantId)
                    } else {
                        let content = resolvedText.isEmpty && cancelled ? "（已停止）" : resolvedText
                        appState.updateMessageContent(
                            sessionId: self.sessionId,
                            messageId: assistantId,
                            content: content,
                            isStreaming: false
                        )
                        let reasoning = appState.messages.first(where: { $0.id == assistantId })?.reasoningContent ?? ""
                        appState.setReasoningContent(
                            sessionId: self.sessionId,
                            messageId: assistantId,
                            content: reasoning,
                            isReasoningStreaming: false
                        )
                    }
                } else if !resolvedText.isEmpty {
                    let message = ChatMessage(
                        id: assistantId,
                        role: .assistant,
                        content: resolvedText,
                        createdAt: Date(),
                        isStreaming: false
                    )
                    appState.appendMessage(message, sessionId: self.sessionId)
                }
            }

            if !reconciledMessages.isEmpty {
                for message in reconciledMessages {
                    appState.appendMessage(message, sessionId: self.sessionId)
                }
            } else if let errorMessage {
                appState.appendMessage(
                    ChatMessage(
                        id: UUID().uuidString,
                        role: .system,
                        content: cancelled || timedOut
                            ? (timedOut ? "生成超时（\(errorMessage)）" : "已停止：\(errorMessage)")
                            : "错误: \(errorMessage)",
                        createdAt: Date()
                    ),
                    sessionId: self.sessionId
                )
            }

            self.resetForTurn()
            appState.finishTurnUI(sessionId: self.sessionId)
        }
    }
}
