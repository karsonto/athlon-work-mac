import Foundation

nonisolated enum ModelMessagesForApiBuilder {
    /// Converts persisted chat messages (+ system prompt) into OpenAI chat message dictionaries.
    static func build(
        systemPrompt: String,
        messages: [ChatMessage],
        includeReasoning: Bool = false
    ) -> [[String: Any]] {
        var api: [[String: Any]] = []
        if !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            api.append(["role": "system", "content": systemPrompt])
        }

        for message in messages {
            switch message.role {
            case .system, .summary, .compaction:
                let content = message.content
                if !content.isEmpty {
                    api.append(["role": "system", "content": content])
                }
            case .user:
                api.append(["role": "user", "content": message.content])
            case .assistant:
                var entry: [String: Any] = [
                    "role": "assistant",
                    "content": message.content,
                ]
                if includeReasoning, let reasoning = message.reasoning, !reasoning.isEmpty {
                    entry["reasoning_content"] = reasoning
                }
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    entry["tool_calls"] = toolCalls.map { call -> [String: Any] in
                        [
                            "id": call.id,
                            "type": "function",
                            "function": [
                                "name": call.name,
                                "arguments": call.arguments,
                            ] as [String: Any],
                        ]
                    }
                    // OpenAI expects content null/empty when only tool_calls; keep content string if present.
                    if message.content.isEmpty {
                        entry["content"] = NSNull()
                    }
                }
                api.append(entry)
            case .tool:
                var entry: [String: Any] = [
                    "role": "tool",
                    "content": message.content,
                ]
                if let toolCallId = message.toolCallId {
                    entry["tool_call_id"] = toolCallId
                }
                api.append(entry)
            }
        }
        return api
    }
}
