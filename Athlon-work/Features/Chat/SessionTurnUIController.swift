import Foundation

/// Per-session UI bridge: stream events → WebView, USER_MESSAGE inject, tool-approval continuations.
@MainActor
final class SessionTurnUIController {
    let sessionId: String
    weak var bridge: ChatWebViewBridge?
    var messageCount: Int = 0
    var isDisplayed: Bool = false
    var onPendingApprovalsChanged: (() -> Void)?

    private var approvalContinuations: [String: CheckedContinuation<Bool, Never>] = [:]
    private var pendingApprovalPayloads: [String: (toolName: String, arguments: String)] = [:]
    private let streamingDispatcher = StreamingMarkdownDispatcher()

    init(sessionId: String, bridge: ChatWebViewBridge? = nil) {
        self.sessionId = sessionId
        self.bridge = bridge
        streamingDispatcher.attach(bridge: bridge)
    }

    func attach(bridge: ChatWebViewBridge?) {
        self.bridge = bridge
        streamingDispatcher.attach(bridge: bridge)
        if isDisplayed {
            restorePendingApprovals()
        }
    }

    func setDisplayed(_ displayed: Bool) {
        isDisplayed = displayed
        if displayed {
            restorePendingApprovals()
        }
    }

    // MARK: - User message

    func injectUserMessage(messageId: String = UUID().uuidString.replacingOccurrences(of: "-", with: ""),
                           content: String,
                           images: [ImageAttachment] = []) {
        messageCount += 1
        guard isDisplayed, let bridge else { return }
        let json = ChatEventSerializer.serializeUserMessage(messageId: messageId, content: content, images: images)
        bridge.dispatchJSON(json)
    }

    // MARK: - Stream events

    func handleStreamEvent(_ event: AgentStreamEvent) {
        switch event {
        case .chatMessageAppended, .clearEmptyAssistantPlaceholder, .usageRecorded, .contextHygieneApplied:
            return
        case let .textMessageContent(messageId, delta):
            guard isDisplayed else { return }
            streamingDispatcher.append(messageId: messageId, delta: delta)
            return
        case let .textMessageEnd(messageId):
            if isDisplayed {
                streamingDispatcher.finish(messageId: messageId)
            } else {
                streamingDispatcher.reset()
            }
            return
        case .runStarted:
            streamingDispatcher.reset()
        default:
            break
        }
        dispatchSerializedEvent(event)
    }

    private func dispatchSerializedEvent(_ event: AgentStreamEvent) {
        guard isDisplayed, let bridge else { return }
        let json = ChatEventSerializer.serialize(event)
        guard json != "{}" else { return }
        bridge.dispatchJSON(json)
    }

    // MARK: - Tool approval

    /// Suspends until `resolveToolApproval` is called for `toolCallId`.
    func requestToolApproval(_ call: ToolCall) async -> Bool {
        let arguments = call.arguments
        pendingApprovalPayloads[call.id] = (call.name, arguments)

        if isDisplayed, let bridge {
            let request = ChatEventSerializer.serializeToolApprovalRequest(
                toolCallId: call.id,
                toolName: call.name,
                arguments: arguments
            )
            bridge.dispatchJSON(request)
        }

        return await withCheckedContinuation { continuation in
            if let existing = approvalContinuations.removeValue(forKey: call.id) {
                // Should not happen; fail closed by denying the duplicate waiter.
                existing.resume(returning: false)
            }
            approvalContinuations[call.id] = continuation
            onPendingApprovalsChanged?()
        }
    }

    @discardableResult
    func resolveToolApproval(toolCallId: String, approved: Bool) -> Bool {
        guard let continuation = approvalContinuations.removeValue(forKey: toolCallId) else {
            return false
        }
        pendingApprovalPayloads.removeValue(forKey: toolCallId)
        if isDisplayed, let bridge {
            bridge.dispatchJSON(
                ChatEventSerializer.serializeToolApprovalResolved(toolCallId: toolCallId, approved: approved)
            )
        }
        continuation.resume(returning: approved)
        onPendingApprovalsChanged?()
        return true
    }

    var pendingApprovalIds: [String] {
        Array(approvalContinuations.keys)
    }

    var hasPendingApprovals: Bool {
        !approvalContinuations.isEmpty
    }

    private func restorePendingApprovals() {
        guard let bridge else { return }
        for (toolCallId, payload) in pendingApprovalPayloads {
            let request = ChatEventSerializer.serializeToolApprovalRequest(
                toolCallId: toolCallId,
                toolName: payload.toolName,
                arguments: payload.arguments
            )
            bridge.dispatchJSON(request)
        }
    }

    // MARK: - Hydration

    func hydrate(messages: [ChatMessage], showToolCalls: Bool = true) {
        messageCount = messages.filter { $0.role == .user || $0.role == .assistant }.count
        guard isDisplayed, let bridge else { return }
        let events = ChatEventSerializer.buildReplayEvents(from: messages, showToolCalls: showToolCalls)
        let array = ChatEventSerializer.serializeEventsToJsonArray(events)
        bridge.replayEventsJSON(array)
    }

    func resetTimeline() {
        messageCount = 0
        streamingDispatcher.reset()
        bridge?.clearPendingScripts()
        guard isDisplayed, let bridge else { return }
        bridge.dispatchJSON(ChatEventSerializer.serializeResetTimeline())
    }

    func release() {
        for (_, continuation) in approvalContinuations {
            continuation.resume(returning: false)
        }
        approvalContinuations.removeAll()
        pendingApprovalPayloads.removeAll()
        streamingDispatcher.reset()
        messageCount = 0
        isDisplayed = false
        bridge = nil
    }
}
