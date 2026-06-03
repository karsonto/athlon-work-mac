import Foundation

// MARK: - Agent Tool Protocol

/// Built-in agent tool contract aligned with WPF `IAgentTool`.
protocol AgentTool {
    var name: String { get }
    var description: String { get }
    var parametersSchema: [String: String] { get }
    var requiresApproval: Bool { get }
    func invoke(arguments: [String: String]) async throws -> String
}

extension AgentTool {
    var requiresApproval: Bool { false }

    /// OpenAI-compatible tool definition for chat completions.
    func toToolDefinition() -> ToolDefinition {
        var properties: [String: Any] = [:]
        var required: [String] = []
        for (key, desc) in parametersSchema.sorted(by: { $0.key < $1.key }) {
            properties[key] = ["type": "string", "description": desc]
            if !desc.lowercased().contains("optional") {
                required.append(key)
            }
        }
        return ToolDefinition(
            name: name,
            description: description,
            parameters: [
                "type": "object",
                "properties": properties,
                "required": required
            ]
        )
    }
}

// MARK: - Tool Errors

enum ToolError: LocalizedError {
    case missingArgument(String, tool: String)
    case invalidPath(String, tool: String)
    case outsideWorkspace(String)
    case notFound(String)
    case denied(String)
    case failed(String, detail: String)

    var errorDescription: String? {
        switch self {
        case .missingArgument(let arg, let tool):
            return "\(tool) requires `\(arg)`."
        case .invalidPath(let message, let tool):
            return "\(tool): \(message)"
        case .outsideWorkspace(let path):
            return "Outside workspace: \(path)"
        case .notFound(let message):
            return message
        case .denied(let message):
            return message
        case .failed(let summary, let detail):
            return detail.isEmpty ? summary : "\(summary)\n\(detail)"
        }
    }
}

// MARK: - Tool Result Formatting

enum ToolResultFormatter {
    static func success(_ summary: String, content: String? = nil) -> String {
        guard let content, !content.isEmpty else { return summary }
        if summary.isEmpty { return content }
        return "\(summary)\n\n\(content)"
    }
}
