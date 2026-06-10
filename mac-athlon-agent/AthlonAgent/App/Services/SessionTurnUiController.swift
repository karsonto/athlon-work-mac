import Foundation

/// Per-session UI bridge for parallel turns (messages + streaming buffers).
/// Aligned with WPF `SessionStreamingUiContext`: one assistant bubble per model iteration.
@MainActor
final class SessionTurnUiController {
    let sessionId: String
    private weak var appState: AppState?

    private var activeAssistantBubbles: [String] = []
    private var assistantMessageId: String?
    private var pendingTextMessageId: String?
    private var pendingReasoningMessageId: String?
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
        activeAssistantBubbles = []
        assistantMessageId = nil
        pendingTextMessageId = nil
        pendingReasoningMessageId = nil
    }

    @MainActor
    func captureEndSnapshot(
        session: AgentSession,
        wasCancelled: Bool,
        timedOut: Bool,
        errorMessage: String?
    ) -> SessionTurnEndSnapshot {
        streamingCoalescer?.flushNow()

        var assistantContent: String? = streamingBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : streamingBuffer
        var assistantReasoning: String? = streamingReasoningBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : streamingReasoningBuffer

        if let appState, let activeId = activeAssistantMessageId {
            let uiMessage = appState.messages.first(where: { $0.id == activeId })
            let persisted = session.messages.first(where: { $0.id == activeId })
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
            assistantMessageId: activeAssistantMessageId,
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

    /// Updates composer status while API context is being assembled (no placeholder bubble yet).
    @MainActor
    func prepareModelRequest() {
        if let appState, sessionId == appState.activeSessionId {
            appState.composerStatusMessage = "正在准备上下文…"
        }
    }

    /// Prepares a streaming assistant bubble before tokens arrive (WPF: `EnsureAssistantBubble` on round start).
    @MainActor
    func beginModelIteration(messageId: String) {
        let isNewIteration = assistantMessageId != messageId
        if isNewIteration {
            streamingBuffer = ""
            streamingReasoningBuffer = ""
            pendingTextMessageId = messageId
            pendingReasoningMessageId = nil
        }
        if let appState, sessionId == appState.activeSessionId {
            appState.composerStatusMessage = "正在请求模型…"
        }
        adoptAssistantMessageId(messageId)
    }

    /// Drops or seals a pre-token placeholder when a model round ends without streamed text.
    @MainActor
    func releaseAssistantPlaceholder(messageId: String) {
        releaseAssistantBubble(messageId: messageId)
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
            activeAssistantBubbles.removeAll { $0 == previous }
        }
        assistantMessageId = id
        ensureStreamingAssistantVisible(for: id)
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
    private func ensureStreamingAssistantVisible(for messageId: String? = nil) {
        guard let appState else { return }
        guard let id = messageId ?? assistantMessageId else { return }

        if !activeAssistantBubbles.contains(id) {
            activeAssistantBubbles.append(id)
        }

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
            return
        }

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
        activeAssistantBubbles.removeAll { $0 == messageId }
        if assistantMessageId == messageId {
            assistantMessageId = activeAssistantBubbles.last
        }

        guard let index = appState.messages.firstIndex(where: { $0.id == messageId }) else {
            return
        }

        var updated = appState.messages
        var message = updated[index]
        let hasContent = !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !message.reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if !hasContent {
            updated.remove(at: index)
            appState.messages = updated
            return
        }

        message.isStreaming = false
        message.isReasoningStreaming = false
        updated[index] = message
        appState.messages = updated
    }

    @MainActor
    private func removeEmptyActiveAssistantBubbles() {
        guard let appState else { return }
        for messageId in activeAssistantBubbles {
            guard let message = appState.messages.first(where: { $0.id == messageId }),
                  message.content.isEmpty,
                  message.reasoningContent.isEmpty else { continue }
            appState.removeMessage(sessionId: sessionId, messageId: messageId)
            activeAssistantBubbles.removeAll { $0 == messageId }
            if assistantMessageId == messageId {
                assistantMessageId = activeAssistantBubbles.last
            }
        }
    }

    func processStreamEvent(_ event: AgentStreamEvent) {
        switch event {
        case .textMessageStart(let messageId, _):
            beginTextStreaming(messageId: messageId)
        case .textMessageContent(let messageId, let delta):
            beginTextStreaming(messageId: messageId)
            let wasEmpty = streamingBuffer.isEmpty
            streamingBuffer = Self.mergeDeltaBuffer(current: streamingBuffer, delta: delta)
            if wasEmpty { streamingCoalescer?.flushNow() } else { streamingCoalescer?.scheduleFlush() }
        case .reasoningMessageStart(let messageId, _):
            beginReasoningStreaming(messageId: messageId)
        case .reasoningMessageContent(let messageId, let delta):
            beginReasoningStreaming(messageId: messageId)
            let wasEmpty = streamingReasoningBuffer.isEmpty
            streamingReasoningBuffer = Self.mergeDeltaBuffer(current: streamingReasoningBuffer, delta: delta)
            if wasEmpty { streamingCoalescer?.flushNow() } else { streamingCoalescer?.scheduleFlush() }
        case .textMessageEnd(let messageId):
            streamingCoalescer?.flushNow()
            releaseAssistantBubble(messageId: messageId)
            if pendingTextMessageId == messageId {
                pendingTextMessageId = nil
                streamingBuffer = ""
            }
        case .reasoningMessageEnd(let messageId):
            streamingCoalescer?.flushNow()
            releaseAssistantBubble(messageId: messageId)
            if pendingReasoningMessageId == messageId {
                pendingReasoningMessageId = nil
                streamingReasoningBuffer = ""
            }
        case .toolCallStart(let toolCallId, let toolName, _):
            if let id = assistantMessageId {
                releaseAssistantBubble(messageId: id)
            }
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
            removeEmptyActiveAssistantBubbles()
        case .runFinished:
            streamingCoalescer?.cancel()
            appState?.onModelRunFinished(sessionId: sessionId)
        case .chatMessageAppended(let message):
            handleChatMessageAppended(message)
        default:
            break
        }
    }

    private func beginTextStreaming(messageId: String) {
        if pendingTextMessageId != messageId {
            streamingBuffer = ""
            pendingTextMessageId = messageId
        }
        adoptAssistantMessageId(messageId)
    }

    private func beginReasoningStreaming(messageId: String) {
        if pendingReasoningMessageId != messageId {
            streamingReasoningBuffer = ""
            pendingReasoningMessageId = messageId
        }
        adoptAssistantMessageId(messageId)
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
            removeEmptyActiveAssistantBubbles()
            appState.appendMessage(message, sessionId: sessionId)
            return
        }
        if message.role == .tool {
            appState.upsertToolMessage(message, sessionId: sessionId)
            return
        }
        if message.role == .assistant, message.isAssistantToolCallsOnly {
            return
        }
        if message.role == .assistant,
           let activeId = activeAssistantMessageId,
           activeId == message.id,
           appState.messages.contains(where: { $0.id == message.id }) {
            var assistant = message.withPromotedAnswer()
            assistant.isStreaming = false
            assistant.isReasoningStreaming = false
            assistant.toolCalls = nil
            appState.syncAssistantMessage(sessionId: sessionId, message: assistant)
            activeAssistantBubbles.removeAll { $0 == message.id }
            if assistantMessageId == message.id {
                assistantMessageId = activeAssistantBubbles.last
            }
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

        let textMessageId = pendingTextMessageId ?? assistantMessageId
        let reasoningMessageId = pendingReasoningMessageId ?? textMessageId

        if let textMessageId {
            ensureStreamingAssistantVisible(for: textMessageId)

            if !streamingBuffer.isEmpty {
                appState.updateMessageContent(sessionId: sessionId, messageId: textMessageId, content: streamingBuffer)
                if sessionId == appState.activeSessionId {
                    appState.composerStatusMessage = ""
                }
            }
        }

        if let reasoningMessageId, !streamingReasoningBuffer.isEmpty {
            ensureStreamingAssistantVisible(for: reasoningMessageId)
            let hasAnswer = !(appState.messages.first(where: { $0.id == reasoningMessageId })?.content
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? false)
                || !streamingBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            appState.setReasoningContent(
                sessionId: sessionId,
                messageId: reasoningMessageId,
                content: streamingReasoningBuffer,
                isReasoningStreaming: !hasAnswer
            )
            if sessionId == appState.activeSessionId {
                appState.composerStatusMessage = hasAnswer ? "" : "模型思考中…"
            }
        }
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
        activeAssistantBubbles = []
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
        } else {
            for messageId in activeAssistantBubbles {
                releaseAssistantBubble(messageId: messageId)
            }
            activeAssistantBubbles = []
            pendingTextMessageId = nil
            pendingReasoningMessageId = nil
            streamingBuffer = ""
            streamingReasoningBuffer = ""
        }

        if !reconciledMessages.isEmpty {
            for message in reconciledMessages {
                appState.appendMessage(message, sessionId: sessionId)
            }
        } else if let errorMessage {
            if let activeId = activeAssistantMessageId,
               appState.messages.contains(where: { $0.id == activeId }) {
                appState.updateMessageContent(
                    sessionId: sessionId,
                    messageId: activeId,
                    content: cancelled || timedOut
                        ? (timedOut ? "生成超时（\(errorMessage)）" : "已停止：\(errorMessage)")
                        : errorMessage,
                    isStreaming: false
                )
            } else {
                appState.appendMessage(
                    ChatMessage(
                        id: UUID().uuidString,
                        role: .system,
                        content: cancelled || timedOut
                            ? (timedOut ? "生成超时（\(errorMessage)）" : "已停止：\(errorMessage)")
                            : "错误: \(errorMessage)",
                        createdAt: Date()
                    ),
                    sessionId: sessionId
                )
            }
        }

        if !cancelled, errorMessage == nil, reconciledMessages.isEmpty {
            let sessionMessages = appState.sessionManager.getSession(sessionId)?.messages ?? []
            applyPersistedAssistantMessages(sessionMessages)
        }

        appState.clearStreamingFlags(sessionId: sessionId)
    }

    @MainActor
    private func applyPersistedAssistantMessages(_ messages: [ChatMessage]) {
        guard let appState else { return }
        for message in messages where message.role == .assistant && message.shouldShowInChatTimeline {
            let normalized = message.withPromotedAnswer()
            guard normalized.hasDisplayContent || normalized.hasReasoning else { continue }
            var finalMessage = normalized
            finalMessage.isStreaming = false
            finalMessage.isReasoningStreaming = false
            finalMessage.toolCalls = nil
            if appState.messages.contains(where: { $0.id == finalMessage.id }) {
                appState.syncAssistantMessage(sessionId: sessionId, message: finalMessage)
            } else {
                appState.appendMessage(finalMessage, sessionId: sessionId)
            }
        }
    }

    /// Runs after the session runner is removed from `SessionTurnHost`.
    func completeTurnUI(activeEpoch: Int) {
        guard activeEpoch == turnEpoch else { return }
        appState?.finishTurnUI(sessionId: sessionId)
    }

    private var activeAssistantMessageId: String? {
        assistantMessageId ?? activeAssistantBubbles.last
    }
}
