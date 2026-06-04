import Foundation

// MARK: - Compaction result

struct ConversationCompactResult {
    let session: AgentSession
    let compacted: Bool
}

struct ContextSummary: Equatable, Codable {
    let id: String
    let sessionId: String
    let content: String
    let originalMessageCount: Int
    let createdAt: Date
}

// MARK: - Model completion (summarization)

enum AgentModelContentPart: Equatable {
    case text(String)
    case imageURL(String)
}

enum AgentModelContent: Equatable {
    case text(String)
    case parts([AgentModelContentPart])

    var textValue: String {
        switch self {
        case .text(let value): return value
        case .parts(let parts):
            return parts.compactMap { part in
                if case .text(let text) = part { return text }
                return nil
            }.joined(separator: "\n")
        }
    }
}

struct AgentModelMessage: Equatable {
    let role: String
    let content: AgentModelContent
    let toolCallId: String?
    let toolCalls: [AgentToolCall]?
    let reasoningContent: String?

    init(
        role: String,
        content: AgentModelContent,
        toolCallId: String? = nil,
        toolCalls: [AgentToolCall]? = nil,
        reasoningContent: String? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCallId = toolCallId
        self.toolCalls = toolCalls
        self.reasoningContent = reasoningContent
    }

    init(role: String, text: String) {
        self.init(role: role, content: .text(text))
    }
}

struct AgentModelRequest {
    let messages: [AgentModelMessage]
    let tools: [ToolDefinition]
    let allowToolCalls: Bool
    let maxTokens: Int?

    init(
        messages: [AgentModelMessage],
        tools: [ToolDefinition] = [],
        allowToolCalls: Bool = true,
        maxTokens: Int? = nil
    ) {
        self.messages = messages
        self.tools = tools
        self.allowToolCalls = allowToolCalls
        self.maxTokens = maxTokens
    }
}

struct AgentModelResponse: Equatable {
    let content: String
    let toolCalls: [AgentToolCall]
    let reasoningContent: String?
    let usage: AgentModelUsage?

    init(
        content: String,
        toolCalls: [AgentToolCall] = [],
        reasoningContent: String? = nil,
        usage: AgentModelUsage? = nil
    ) {
        self.content = content
        self.toolCalls = toolCalls
        self.reasoningContent = reasoningContent
        self.usage = usage
    }
}

struct AgentModelUsage: Equatable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
}

struct StreamingToolCallDelta: Equatable {
    let index: Int
    let id: String?
    let name: String?
    let argumentsJson: String
}

protocol AgentModelClientProviding: Sendable {
    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse
}

protocol AgentChatModelClient: AgentModelClientProviding {
    func completeChat(
        _ request: AgentModelRequest,
        onTextDelta: (@Sendable (String) async -> Void)?,
        onReasoningDelta: (@Sendable (String) async -> Void)?,
        onToolCallDelta: (@Sendable (StreamingToolCallDelta) async -> Void)?
    ) async throws -> AgentModelResponse
}

// MARK: - Storage (transcripts, summaries, evicted tool results)

protocol CompactionStorageProviding: Sendable {
    func saveTranscript(sessionId: String, messages: [ChatMessage]) async throws -> String
    func saveContextSummary(_ summary: ContextSummary) async throws
    func saveEvictedToolResult(sessionId: String, toolCallId: String, content: String) async throws -> String
}

// MARK: - Logging

protocol CompactionLogging: Sendable {
    func debug(_ message: String)
    func information(_ message: String)
    func error(_ error: Error, _ message: String)
}

struct NoOpCompactionLogger: CompactionLogging {
    func debug(_ message: String) {}
    func information(_ message: String) {}
    func error(_ error: Error, _ message: String) {}
}

// MARK: - Session helpers

extension AgentSession {
    func withMessages(_ messages: [ChatMessage]) -> AgentSession {
        var copy = self
        copy.messages = messages
        copy.updatedAt = Date()
        return copy
    }
}

protocol ConversationCompacting: Sendable {
    func compactIfNeeded(
        session: AgentSession,
        request: CompactionExecutionRequest
    ) async -> ConversationCompactResult

    func compactIfNeeded(
        session: AgentSession,
        request: CompactionExecutionRequest
    ) async -> ConversationCompactResult
}

protocol PreCompletionPipelineRunning: Sendable {
    func run(
        session: AgentSession,
        options: PreCompletionOptions?,
        runtimeContext: CompactionRuntimeContext?
    ) async -> AgentSession
}

protocol ToolResultEvicting: Sendable {
    func evictIfNeeded(
        sessionId: String,
        toolCall: AgentToolCall,
        result: ToolResult,
        formattedToolContent: String
    ) async -> String
}
