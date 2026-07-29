import Foundation

// MARK: - Tool definition (OpenAI tools[] schema)

nonisolated struct ToolDefinition: Sendable, Hashable {
    var name: String
    var description: String
    /// JSON Schema object for `parameters`.
    var parameters: [String: Any]

    static func == (lhs: ToolDefinition, rhs: ToolDefinition) -> Bool {
        lhs.name == rhs.name && lhs.description == rhs.description
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(description)
    }

    func asOpenAITool() -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": parameters,
            ] as [String: Any],
        ]
    }
}

// MARK: - Run context / callbacks

nonisolated struct AgentRunContext: Sendable {
    var sessionId: String
    var workspaceRoot: String
    var ignorePatterns: [String]
    var settings: AppSettings
}

nonisolated struct AgentTurnCallbacks: Sendable {
    var onStreamEvent: @Sendable (AgentStreamEvent) -> Void
    var onToolApprovalRequested: @Sendable (ToolCall) async -> Bool

    nonisolated init(
        onStreamEvent: @escaping @Sendable (AgentStreamEvent) -> Void = { _ in },
        onToolApprovalRequested: @escaping @Sendable (ToolCall) async -> Bool = { _ in true }
    ) {
        self.onStreamEvent = onStreamEvent
        self.onToolApprovalRequested = onToolApprovalRequested
    }
}

// MARK: - Tool / router protocols

nonisolated protocol AgentTool: Sendable {
    var name: String { get }
    var definition: ToolDefinition { get }
    func invoke(arguments: String, context: AgentRunContext) async throws -> String
}

nonisolated protocol ToolRouter: Sendable {
    var tools: [any AgentTool] { get }
    func tool(named name: String) -> (any AgentTool)?
    func openAIToolSchemas() -> [[String: Any]]
}

extension ToolRouter {
    func openAIToolSchemas() -> [[String: Any]] {
        tools.map { $0.definition.asOpenAITool() }
    }

    func tool(named name: String) -> (any AgentTool)? {
        tools.first { $0.name == name }
    }
}

nonisolated enum AgentToolError: Error, LocalizedError {
    case unknownTool(String)
    case invalidArguments(String)
    case approvalDenied(String)
    case pathOutsideWorkspace(String)
    case executionFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case let .unknownTool(name): return "Unknown tool: \(name)"
        case let .invalidArguments(detail): return "Invalid tool arguments: \(detail)"
        case let .approvalDenied(name): return "Tool approval denied: \(name)"
        case let .pathOutsideWorkspace(path): return "Path outside workspace: \(path)"
        case let .executionFailed(detail): return detail
        case .cancelled: return "Tool execution cancelled"
        }
    }
}

nonisolated enum AgentRuntimeError: Error, LocalizedError {
    case sessionNotFound(String)
    case maxToolRoundsExceeded(Int)
    case toolStormDetected(String)
    case turnFailed(String)

    var errorDescription: String? {
        switch self {
        case let .sessionNotFound(id): return "Session not found: \(id)"
        case let .maxToolRoundsExceeded(n): return "Exceeded max model↔tool rounds (\(n))"
        case let .toolStormDetected(detail): return "Tool storm detected: \(detail)"
        case let .turnFailed(detail): return detail
        }
    }
}
