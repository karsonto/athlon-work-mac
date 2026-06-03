import Foundation

/// Bridges assistant tool calls for compaction (argument dictionaries ↔ JSON string on `AgentToolCall`).
enum AssistantToolCallsCodec {
    static func deserialize(from message: ChatMessage) -> [AgentToolCall]? {
        guard let toolCalls = message.toolCalls, !toolCalls.isEmpty else { return nil }
        return toolCalls
    }

    static func deserializeToolCalls(from message: ChatMessage) -> [CompactionToolCallRecord]? {
        guard let calls = message.toolCalls, !calls.isEmpty else { return nil }
        return calls.map { call in
            CompactionToolCallRecord(
                id: call.id,
                name: call.name,
                arguments: parseArguments(call.arguments)
            )
        }
    }

    static func apply(calls: [CompactionToolCallRecord], to message: ChatMessage) -> ChatMessage {
        var updated = message
        updated.toolCalls = calls.map { record in
            AgentToolCall(
                id: record.id,
                name: record.name,
                arguments: serializeArguments(record.arguments),
                argumentsStreaming: "",
                status: .none
            )
        }
        return updated
    }

    static func parseArguments(_ json: String) -> [String: String] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return trimmed.isEmpty ? [:] : ["_raw": json]
        }

        var result: [String: String] = [:]
        for (key, value) in object {
            if let text = value as? String {
                result[key] = text
            } else if let nested = value as? [String: Any],
                      let nestedData = try? JSONSerialization.data(withJSONObject: nested),
                      let nestedText = String(data: nestedData, encoding: .utf8) {
                result[key] = nestedText
            } else if let nested = value as? [Any],
                      let nestedData = try? JSONSerialization.data(withJSONObject: nested),
                      let nestedText = String(data: nestedData, encoding: .utf8) {
                result[key] = nestedText
            } else {
                result[key] = String(describing: value)
            }
        }
        return result
    }

    static func serializeArguments(_ arguments: [String: String]) -> String {
        guard !arguments.isEmpty else { return "{}" }
        guard let data = try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return text
    }
}

struct CompactionToolCallRecord: Equatable {
    let id: String
    let name: String
    let arguments: [String: String]
}
