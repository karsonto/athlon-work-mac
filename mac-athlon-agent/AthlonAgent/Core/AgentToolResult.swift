import Foundation

struct ToolResult: Equatable {
    let succeeded: Bool
    let summary: String
    let content: String?
    let error: String?

    static func success(summary: String, content: String? = nil) -> ToolResult {
        ToolResult(succeeded: true, summary: summary, content: content, error: nil)
    }

    static func failure(summary: String, error: String) -> ToolResult {
        ToolResult(succeeded: false, summary: summary, content: nil, error: error)
    }
}

enum AgentRuntimeToolFormatting {
    static func formatToolResult(
        _ call: AgentToolCall,
        _ result: ToolResult,
        displayNotes: ToolExecutionDisplayNotes? = nil
    ) -> String {
        let status = result.succeeded ? "succeeded" : "failed"
        var lines = [
            "ToolCallId: \(call.id)",
            "Tool `\(call.name)` \(status).",
            ""
        ]
        lines.append("Arguments (model):")
        lines.append(formatArgumentsDict(AssistantToolCallsCodec.parseArguments(call.arguments)))
        if let displayNotes {
            if displayNotes.normalizedArguments != AssistantToolCallsCodec.parseArguments(call.arguments) {
                lines.append("")
                lines.append("Arguments (normalized):")
                lines.append(formatArgumentsDict(displayNotes.normalizedArguments))
            }
            if let resolved = displayNotes.resolvedFullPath {
                lines.append("")
                lines.append("Resolved path:")
                lines.append(resolved)
            }
        }
        lines.append(contentsOf: [
            "",
            "Summary: \(result.summary)",
            "",
            result.content ?? result.error ?? ""
        ])
        return lines.joined(separator: "\n")
    }

    private static func formatArgumentsDict(_ dict: [String: String]) -> String {
        if dict.isEmpty { return "(none)" }
        return dict.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "\n")
    }
}
