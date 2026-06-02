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
struct AgentToolCall: Identifiable, Codable {
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
    var isStreaming: Bool
    var isReasoningStreaming: Bool

    // View-model derived properties
    var isUser: Bool { role == .user }
    var isTool: Bool { role == .tool }
    var isCompaction: Bool { role == .compaction }
    var isCollapsibleCard: Bool { isTool || isCompaction }
    var hasReasoning: Bool { !reasoningContent.isEmpty }
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
        self.isStreaming = isStreaming
        self.isReasoningStreaming = isReasoningStreaming
    }
}
