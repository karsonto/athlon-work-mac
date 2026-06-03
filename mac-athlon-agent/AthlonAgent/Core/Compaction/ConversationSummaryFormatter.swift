import Foundation

enum ConversationSummaryFormatter {
    private static let maxToolResultChars = 500

    static func formatMessages(_ messages: [ChatMessage]) -> String {
        messages.map(formatMessage).joined(separator: "\n\n")
    }

    private static func formatMessage(_ message: ChatMessage) -> String {
        switch message.role {
        case .user:
            return "Human: \(message.content)"
        case .assistant:
            return formatAssistant(message)
        case .tool:
            return formatTool(message)
        default:
            return "\(message.role.rawValue): \(message.content)"
        }
    }

    private static func formatAssistant(_ message: ChatMessage) -> String {
        var parts = ["AI: \(message.content)"]
        if let calls = AssistantToolCallsCodec.deserializeToolCalls(from: message), !calls.isEmpty {
            for call in calls {
                let args = truncate(formatArguments(call.arguments), maxChars: maxToolResultChars)
                parts.append("[tool_call: \(call.name)(\(args))]")
            }
        }
        return parts.joined(separator: "\n")
    }

    private static func formatTool(_ message: ChatMessage) -> String {
        "Tool: [tool_result] \(truncate(message.content, maxChars: maxToolResultChars))"
    }

    private static func formatArguments(_ arguments: [String: String]) -> String {
        guard !arguments.isEmpty else { return "" }
        return arguments
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
    }

    private static func truncate(_ value: String?, maxChars: Int) -> String {
        guard let value, !value.isEmpty else { return "" }
        if value.count <= maxChars { return value }
        return String(value.prefix(maxChars)) + "..."
    }
}
