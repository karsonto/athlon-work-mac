import Foundation

/// Parsed / formatted fields for chat tool cards (aligned with WPF `ChatMessageViewModel` tool UI).
struct ToolCallDisplayInfo: Equatable {
    var toolCallId: String?
    var toolName: String
    var header: String
    var argumentsText: String
    var summary: String
    var detail: String
    var status: ToolCallDisplayStatus

    var hasArguments: Bool {
        !argumentsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && argumentsText != "(无参数)"
    }
}

enum ToolCallDisplay {
    static func from(message: ChatMessage) -> ToolCallDisplayInfo {
        var info: ToolCallDisplayInfo
        if let call = message.toolCalls?.first {
            let argsText = formatArgumentsJson(call.arguments)
            let streamingArgs = call.argumentsStreaming.trimmingCharacters(in: .whitespacesAndNewlines)
            let argumentsText = argsText == "(无参数)" && !streamingArgs.isEmpty
                ? streamingArgs
                : argsText
            info = ToolCallDisplayInfo(
                toolCallId: message.toolCallId ?? call.id,
                toolName: call.name,
                header: headerLine(toolName: call.name, status: call.status),
                argumentsText: argumentsText,
                summary: call.resultSummary ?? "",
                detail: call.resultDetail ?? message.content,
                status: call.status
            )
        } else {
            info = parsePersistedContent(message.content, toolCallId: message.toolCallId)
        }

        if !info.hasArguments {
            let parsed = parsePersistedContent(message.content, toolCallId: message.toolCallId)
            if parsed.hasArguments {
                info.argumentsText = parsed.argumentsText
            }
            if info.summary.isEmpty { info.summary = parsed.summary }
            if info.toolName.isEmpty { info.toolName = parsed.toolName }
            if info.header == "工具调用" { info.header = parsed.header }
        }
        return info
    }

    static func formatArgumentsJson(_ argumentsJson: String) -> String {
        formatArgumentsDict(AssistantToolCallsCodec.parseArguments(argumentsJson))
    }

    static func formatArgumentsDict(_ arguments: [String: String]) -> String {
        if arguments.isEmpty { return "(无参数)" }
        return arguments
            .sorted { $0.key < $1.key }
            .map { key, value in
                let displayValue = key.caseInsensitiveCompare(ToolPathNormalizer.pathArgumentName) == .orderedSame
                    ? ToolPathNormalizer.forModel(value)
                    : value
                return "\(key) = \(displayValue)"
            }
            .joined(separator: "\n")
    }

    static func headerLine(toolName: String, status: ToolCallDisplayStatus) -> String {
        let statusWord: String = {
            switch status {
            case .failed: return "failed"
            case .succeeded, .none: return "succeeded"
            case .running, .preparing: return "running"
            case .cancelled: return "cancelled"
            }
        }()
        return "Tool `\(toolName)` \(statusWord)."
    }

    private static func parsePersistedContent(_ content: String, toolCallId: String?) -> ToolCallDisplayInfo {
        var info = ToolCallDisplayInfo(
            toolCallId: toolCallId,
            toolName: "",
            header: "工具调用",
            argumentsText: "",
            summary: "",
            detail: content.trimmingCharacters(in: .whitespacesAndNewlines),
            status: .succeeded
        )

        let lines = content.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        var collectingModelArgs = false
        var modelArgLines: [String] = []

        for lineSub in lines {
            let line = String(lineSub)
            if line.hasPrefix("ToolCallId:") {
                info.toolCallId = String(line.dropFirst("ToolCallId:".count)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("Arguments (model):") || line.hasPrefix("Arguments (normalized):") {
                collectingModelArgs = line.hasPrefix("Arguments (model):")
                modelArgLines.removeAll()
                continue
            }
            if line.hasPrefix("Arguments:") {
                collectingModelArgs = true
                let inline = String(line.dropFirst("Arguments:".count)).trimmingCharacters(in: .whitespaces)
                if !inline.isEmpty {
                    info.argumentsText = formatArgumentsFromPersistedLine(inline)
                    collectingModelArgs = false
                }
                continue
            }
            if collectingModelArgs {
                if line.trimmingCharacters(in: .whitespaces).isEmpty
                    || line.hasPrefix("Summary:")
                    || line.hasPrefix("Resolved path:")
                    || line.hasPrefix("Arguments (") {
                    collectingModelArgs = false
                    if !modelArgLines.isEmpty {
                        info.argumentsText = modelArgLines.joined(separator: "\n")
                    }
                    if line.hasPrefix("Summary:") {
                        info.summary = String(line.dropFirst("Summary:".count)).trimmingCharacters(in: .whitespaces)
                    }
                    continue
                }
                modelArgLines.append(line)
                continue
            }
            if line.hasPrefix("Tool `") {
                info.header = line.trimmingCharacters(in: .whitespaces)
                info.toolName = parseToolName(from: info.header)
                info.status = parseStatus(from: info.header)
                continue
            }
            if line.hasPrefix("Summary:") {
                info.summary = String(line.dropFirst("Summary:".count)).trimmingCharacters(in: .whitespaces)
            }
        }

        if collectingModelArgs, !modelArgLines.isEmpty {
            info.argumentsText = modelArgLines.joined(separator: "\n")
        }

        if info.toolName.isEmpty, !content.isEmpty, content.count < 80, !content.contains("\n") {
            info.toolName = content.trimmingCharacters(in: .whitespacesAndNewlines)
            info.header = headerLine(toolName: info.toolName, status: info.status)
        }

        return info
    }

    private static func parseToolName(from header: String) -> String {
        guard let start = header.range(of: "Tool `") else { return "" }
        let after = header[start.upperBound...]
        guard let end = after.firstIndex(of: "`") else { return "" }
        return String(after[..<end])
    }

    private static func parseStatus(from header: String) -> ToolCallDisplayStatus {
        let lower = header.lowercased()
        if lower.contains("failed") { return .failed }
        if lower.contains("cancelled") { return .cancelled }
        if lower.contains("running") || lower.contains("preparing") { return .running }
        return .succeeded
    }

    private static func formatArgumentsFromPersistedLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.caseInsensitiveCompare("(none)") == .orderedSame {
            return "(无参数)"
        }
        if !trimmed.contains(";") {
            return trimmed.replacingOccurrences(of: "=", with: " = ", options: .literal, range: nil)
        }
        return trimmed
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { segment in
                segment.contains(" = ") ? segment : segment.replacingOccurrences(of: "=", with: " = ")
            }
            .joined(separator: "\n")
    }
}
