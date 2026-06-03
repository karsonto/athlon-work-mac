import Foundation

// MARK: - Tool Call Display Status
enum ToolCallDisplayStatus: String, Codable {
    case none = "None"
    case preparing = "Preparing"
    case running = "Running"
    case succeeded = "Succeeded"
    case failed = "Failed"
    case cancelled = "Cancelled"

    var statusLabel: String {
        switch self {
        case .preparing: "准备中…"
        case .running: "执行中…"
        case .succeeded: "已完成 ✓"
        case .failed: "失败 ✗"
        case .cancelled: "已取消"
        case .none: ""
        }
    }

    var isTerminal: Bool {
        self == .succeeded || self == .failed || self == .cancelled
    }
}

// MARK: - Agent Tool Call
struct AgentToolCall: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var arguments: String
    var argumentsStreaming: String
    var status: ToolCallDisplayStatus
    var resultDetail: String?
    var resultSummary: String?
    var errorMessage: String?
    var startedAt: Date?
    var completedAt: Date?

    var isArgumentsStreaming: Bool { !argumentsStreaming.isEmpty }
    var showStatusLabel: Bool { status != .none }
}

// MARK: - Chat Message
struct ChatMessage: Identifiable, Codable {
    let id: String
    let role: MessageRole
    var content: String
    var reasoningContent: String
    var createdAt: Date
    var imageAttachments: [ImageAttachment]?
    var toolCalls: [AgentToolCall]?
    var parentMessageId: String?
    var toolCallId: String?
    var isStreaming: Bool
    var isReasoningStreaming: Bool

    // View-model derived properties
    var isUser: Bool { role == .user }
    var isTool: Bool { role == .tool }
    var isCompaction: Bool { role == .compaction }
    var isCollapsibleCard: Bool { isTool || isCompaction }
    /// Aligned with WPF `HasReasoning` — any non-empty reasoning stream.
    var hasReasoning: Bool {
        !reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Text shown in the assistant answer bubble (`Content` in WPF, separate from reasoning fold).
    var displayContent: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return Self.extractAnswerFromThinking(reasoningContent)
    }

    var hasDisplayContent: Bool { !displayContent.isEmpty }

    /// Assistant message that only carries `tool_calls` for the API — hidden in chat UI (WPF `IsAssistantToolCallsOnly`).
    var isAssistantToolCallsOnly: Bool {
        role == .assistant
            && !(toolCalls?.isEmpty ?? true)
            && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var shouldShowInChatTimeline: Bool { !isAssistantToolCallsOnly }

    /// Moves answer-only `reasoningContent` into `content` (DeepSeek / providers that stream the reply on the reasoning channel).
    func withPromotedAnswer() -> ChatMessage {
        var message = self
        let trimmedContent = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReasoning = message.reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedContent.isEmpty, !trimmedReasoning.isEmpty else { return message }

        if Self.containsThinkingMarkers(trimmedReasoning) {
            let answer = Self.extractAnswerFromThinking(trimmedReasoning)
            guard !answer.isEmpty else { return message }
            message.content = answer
            let thinking = Self.extractThinkingOnly(trimmedReasoning)
            message.reasoningContent = thinking
            return message
        }

        message.content = trimmedReasoning
        message.reasoningContent = ""
        return message
    }

    static func extractAnswerFromThinkingForPromotion(_ text: String) -> String {
        extractAnswerFromThinking(text)
    }

    static func containsThinkingMarkers(_ text: String) -> Bool {
        let lower = text.lowercased()
        let markers = [
            "\u{3c}/redacted_thinking\u{3e}",
            "\u{3c}redacted_thinking\u{3e}",
            "`/think`",
            "`think`",
            "</thinking>",
            "<thinking>"
        ]
        return markers.contains { lower.contains($0.lowercased()) }
    }

    var isHiddenPlaceholder: Bool { false }
    var assistantTone: Bool { role.assistantTone }

    init(id: String = UUID().uuidString,
         role: MessageRole,
         content: String,
         reasoningContent: String = "",
         createdAt: Date = Date(),
         imageAttachments: [ImageAttachment]? = nil,
         toolCalls: [AgentToolCall]? = nil,
         parentMessageId: String? = nil,
         toolCallId: String? = nil,
         isStreaming: Bool = false,
         isReasoningStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoningContent = reasoningContent
        self.createdAt = createdAt
        self.imageAttachments = imageAttachments
        self.toolCalls = toolCalls
        self.parentMessageId = parentMessageId
        self.toolCallId = toolCallId
        self.isStreaming = isStreaming
        self.isReasoningStreaming = isReasoningStreaming
    }

    private static func extractAnswerFromThinking(_ text: String) -> String {
        let endTags = ["\u{3c}/redacted_thinking\u{3e}", "`/think`", "</thinking>"]
        for endTag in endTags {
            guard let range = text.range(of: endTag, options: .caseInsensitive) else { continue }
            let answer = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !answer.isEmpty { return answer }
        }
        return ""
    }

    private static func extractThinkingOnly(_ text: String) -> String {
        let endTags = ["\u{3c}/redacted_thinking\u{3e}", "`/think`", "</thinking>"]
        let startTags = ["\u{3c}redacted_thinking\u{3e}", "`think`", "<thinking>"]
        for endTag in endTags {
            guard let range = text.range(of: endTag, options: .caseInsensitive) else { continue }
            var thinking = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            for startTag in startTags where thinking.lowercased().hasPrefix(startTag.lowercased()) {
                thinking = String(thinking.dropFirst(startTag.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return thinking
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
