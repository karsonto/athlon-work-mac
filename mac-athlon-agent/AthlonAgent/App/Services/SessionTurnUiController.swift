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
    /// Incremented at the start of each turn; stale finalize callbacks must not reset state.
    private(set) var turnEpoch = 0

    init(sessionId: String, appState: AppState) {
        self.sessionId = sessionId
        self.appState = appState
        self.streamingCoalescer = StreamingUiCoalescer { [weak self] in
            self?.applyPendingStreamingSnapshot()
        }
    }

    func resetForTurn() {
        turnEpoch += 1
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

    /// Reserves an id for the runtime and shows a streaming placeholder while waiting for tokens.
    func reserveAssistantMessageId() -> String {
        if let assistantMessageId { return assistantMessageId }
        let id = UUID().uuidString
        assistantMessageId = id
        ensureStreamingAssistantVisible()
        return id
    }

    /// Switches the live streaming bubble to the assistant message id for the current model iteration.
    @MainActor
    func adoptAssistantMessageId(_ id: String) {
        if let appState, let previous = assistantMessageId, previous != id {
            var updated = appState.messages
            for index in updated.indices {
                var message = updated[index]
                guard message.role == .assistant, message.id != id else { continue }
                guard message.isStreaming || message.isReasoningStreaming else { continue }
                message.isStreaming = false
                message.isReasoningStreaming = false
                message = message.withPromotedAnswer()
                updated[index] = message
            }
            appState.messages = updated
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
        guard let appState else { return }
        let message = ChatMessage(
            id: UUID().uuidString,
            role: .user,
            content: input,
            createdAt: Date(),
            imageAttachments: imageAttachments.isEmpty ? nil : imageAttachments
        )
        appState.appendMessage(message, sessionId: sessionId)
    }

    @MainActor
    private func ensureStreamingAssistantVisible() {
        guard let appState, let id = assistantMessageId else { return }

        if let index = appState.messages.firstIndex(where: { $0.id == id }) {
            var updated = appState.messages
            var message = updated[index]
            message.isStreaming = true
            if index < updated.count - 1 {
                updated.remove(at: index)
                updated.append(message)
            } else {
                updated[index] = message
            }
            appState.messages = updated
            assistantVisibleInUI = true
            return
        }

        guard !assistantVisibleInUI else { return }
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

    /// Seals a streaming assistant segment at a tool boundary (WPF `ReleaseAssistantBubble`).
    @MainActor
    private func releaseAssistantBubble(messageId: String) {
        guard let appState else { return }
        guard let index = appState.messages.firstIndex(where: { $0.id == messageId }) else {
            if assistantMessageId == messageId {
                assistantVisibleInUI = false
            }
            return
        }

        var updated = appState.messages
        var message = updated[index]
        let hasContent = !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !message.reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if !hasContent {
            updated.remove(at: index)
            appState.messages = updated
            assistantVisibleInUI = false
            return
        }

        message.isStreaming = false
        message.isReasoningStreaming = false
        updated[index] = message
        appState.messages = updated
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

    func processStreamEvent(_ event: AgentStreamEvent) {
        switch event {
        case .textMessageStart(let messageId, _):
            adoptAssistantMessageId(messageId)
        case .textMessageContent(_, let delta):
            let wasEmpty = streamingBuffer.isEmpty
            streamingBuffer = Self.mergeDeltaBuffer(current: streamingBuffer, delta: delta)
            if wasEmpty { streamingCoalescer?.flushNow() } else { streamingCoalescer?.scheduleFlush() }
        case .reasoningMessageContent(_, let delta):
            let wasEmpty = streamingReasoningBuffer.isEmpty
            streamingReasoningBuffer = Self.mergeDeltaBuffer(current: streamingReasoningBuffer, delta: delta)
            if wasEmpty { streamingCoalescer?.flushNow() } else { streamingCoalescer?.scheduleFlush() }
        case .textMessageEnd(let messageId):
            streamingCoalescer?.flushNow()
            releaseAssistantBubble(messageId: messageId)
        case .reasoningMessageEnd(let messageId):
            streamingCoalescer?.flushNow()
            releaseAssistantBubble(messageId: messageId)
        case .toolCallStart(let toolCallId, let toolName, _):
            appendToolCall(AgentToolCall(
                id: toolCallId,
                name: toolName,
                arguments: "{}",
                argumentsStreaming: "",
                status: .preparing
            ))
        case .toolCallArgs(let toolCallId, let delta):
            appendStreamingToolArguments(toolCallId: toolCallId, delta: delta)
        case .toolCallEnd(let toolCallId):
            finalizeStreamingToolCall(toolCallId: toolCallId)
        case .clearEmptyAssistantPlaceholder:
            clearEmptyStreamingAssistant()
        case .runFinished:
            streamingCoalescer?.cancel()
            appState?.onModelRunFinished(sessionId: sessionId)
        case .chatMessageAppended(let message):
            handleChatMessageAppended(message)
        default:
            break
        }
    }

    private static func mergeDeltaBuffer(current: String, delta: String) -> String {
        guard !delta.isEmpty else { return current }
        if current.isEmpty { return delta }
        if delta.hasPrefix(current) { return delta }
        if current.hasPrefix(delta) { return current }
        return current + delta
    }

    @MainActor
    private func handleChatMessageAppended(_ message: ChatMessage) {
        guard let appState else { return }
        if message.role == .compaction {
            clearEmptyStreamingAssistant()
            appState.appendMessage(message, sessionId: sessionId)
            return
        }
        if message.role == .tool {
            appState.upsertToolMessage(message, sessionId: sessionId)
            return
        }
        if !appState.messages.contains(where: { $0.id == message.id }) {
            appState.appendMessage(message, sessionId: sessionId)
        }
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
        guard appState.isSessionTurnActive(sessionId) else { return }
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

    @MainActor
    private func appendStreamingToolArguments(toolCallId: String, delta: String) {
        guard let appState, !delta.isEmpty else { return }
        var updated = appState.messages
        guard let index = updated.firstIndex(where: { message in
            message.toolCallId == toolCallId
                || message.toolCalls?.contains(where: { $0.id == toolCallId }) == true
        }) else { return }

        var message = updated[index]
        guard var calls = message.toolCalls,
              let callIndex = calls.firstIndex(where: { $0.id == toolCallId }) else { return }

        var call = calls[callIndex]
        call.argumentsStreaming = Self.mergeDeltaBuffer(current: call.argumentsStreaming, delta: delta)
        call.status = .preparing
        calls[callIndex] = call
        message.toolCalls = calls
        message.content = ToolCallDisplay.headerLine(toolName: call.name, status: .preparing)
        updated[index] = message
        appState.messages = updated
    }

    @MainActor
    private func finalizeStreamingToolCall(toolCallId: String) {
        guard let appState else { return }
        var updated = appState.messages
        guard let index = updated.firstIndex(where: { message in
            message.toolCalls?.contains(where: { $0.id == toolCallId }) == true
        }) else { return }

        var message = updated[index]
        guard var calls = message.toolCalls,
              let callIndex = calls.firstIndex(where: { $0.id == toolCallId }) else { return }

        var call = calls[callIndex]
        let argsJson = call.argumentsStreaming.isEmpty ? call.arguments : call.argumentsStreaming
        let parsed = OpenAiChatModelClient.parseArguments(argsJson)
        call.arguments = AssistantToolCallsCodec.serializeArguments(parsed)
        call.argumentsStreaming = ""
        call.status = .running
        call.resultSummary = "执行中…"
        calls[callIndex] = call
        message.toolCalls = calls
        message.content = ToolCallDisplay.headerLine(toolName: call.name, status: .running)
        updated[index] = message
        appState.messages = updated
    }

    /// Must run synchronously on the main thread — tool completion can arrive before UI row exists.
    func appendToolCall(_ toolCall: AgentToolCall) {
        guard let appState else { return }
        if appState.messages.contains(where: { message in
            message.toolCallId == toolCall.id
                || message.toolCalls?.contains(where: { $0.id == toolCall.id }) == true
        }) {
            return
        }
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
        var updated = appState.messages
        for index in updated.indices {
            var message = updated[index]
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
            updated[index] = message
        }
        appState.messages = updated
    }

    func finalizeTurn(
        fullText: String,
        cancelled: Bool,
        timedOut: Bool,
        errorMessage: String?,
        reconciledMessages: [ChatMessage] = [],
        activeEpoch: Int
    ) {
        guard let appState else { return }
        guard activeEpoch == turnEpoch else { return }
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
                    let content: String
                    if !resolvedText.isEmpty {
                        content = resolvedText
                    } else if cancelled {
                        content = "（已停止）"
                    } else if let errorMessage, !errorMessage.isEmpty {
                        content = errorMessage
                    } else {
                        content = ""
                    }
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
        } else if let errorMessage, let assistantId = assistantMessageId, assistantVisibleInUI {
            appState.updateMessageContent(
                sessionId: self.sessionId,
                messageId: assistantId,
                content: cancelled || timedOut
                    ? (timedOut ? "生成超时（\(errorMessage)）" : "已停止：\(errorMessage)")
                    : errorMessage,
                isStreaming: false
            )
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

        appState.clearStreamingFlags(sessionId: self.sessionId)
    }

    /// Runs after the session runner is removed from `SessionTurnHost`.
    func completeTurnUI(activeEpoch: Int) {
        guard activeEpoch == turnEpoch else { return }
        appState?.finishTurnUI(sessionId: sessionId)
    }
}
