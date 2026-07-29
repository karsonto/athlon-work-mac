import Foundation

/// Serializes `AgentStreamEvent` and related UI helpers to AG-UI JSON for `handleEvent`.
nonisolated enum ChatEventSerializer {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static func serialize(_ streamEvent: AgentStreamEvent) -> String {
        switch streamEvent {
        case let .runStarted(sessionId, runId):
            return serializeAgui("RUN_STARTED", ["threadId": sessionId, "runId": runId])
        case let .runFinished(sessionId, runId):
            return serializeAgui("RUN_FINISHED", ["threadId": sessionId, "runId": runId])
        case let .textMessageStart(messageId, role):
            return serializeAgui("TEXT_MESSAGE_START", ["messageId": messageId, "role": role])
        case let .textMessageContent(messageId, delta):
            return serializeAgui("TEXT_MESSAGE_CONTENT", ["messageId": messageId, "delta": delta])
        case let .textMessageEnd(messageId):
            return serializeAgui("TEXT_MESSAGE_END", ["messageId": messageId])
        case let .reasoningMessageStart(messageId, role):
            return serializeAgui("REASONING_MESSAGE_START", ["messageId": messageId, "role": role])
        case let .reasoningMessageContent(messageId, delta):
            return serializeAgui("REASONING_MESSAGE_CONTENT", ["messageId": messageId, "delta": delta])
        case let .reasoningMessageEnd(messageId):
            return serializeAgui("REASONING_MESSAGE_END", ["messageId": messageId])
        case let .toolCallStart(toolCallId, toolName, _):
            return serializeAgui("TOOL_CALL_START", ["toolCallId": toolCallId, "toolCallName": toolName])
        case let .toolCallArgs(toolCallId, delta):
            return serializeAgui("TOOL_CALL_ARGS", ["toolCallId": toolCallId, "delta": delta])
        case let .toolCallEnd(toolCallId):
            return serializeAgui("TOOL_CALL_END", ["toolCallId": toolCallId, "status": "running"])
        case let .toolCallResult(toolCallId, content, messageId):
            return serializeAgui("TOOL_CALL_RESULT", [
                "toolCallId": toolCallId,
                "content": content,
                "messageId": messageId,
                "status": parseToolStatus(from: content),
            ])
        case let .toolCallOutput(toolCallId, delta):
            return serializeAgui("TOOL_CALL_OUTPUT", ["toolCallId": toolCallId, "delta": delta])
        case .chatMessageAppended, .clearEmptyAssistantPlaceholder, .usageRecorded, .contextHygieneApplied:
            return "{}"
        }
    }

    static func serializeResetTimeline() -> String {
        serializeAgui("RESET_TIMELINE", [:] as [String: String])
    }

    static func serializeUserMessage(
        messageId: String,
        content: String,
        images: [ImageAttachment] = []
    ) -> String {
        var payload: [String: Any] = [
            "messageId": messageId,
            "content": content,
        ]
        if !images.isEmpty {
            payload["images"] = images.compactMap { image -> [String: String]? in
                guard let url = image.dataUrl, !url.isEmpty else { return nil }
                return [
                    "fileName": image.fileName,
                    "mimeType": image.mimeType,
                    "url": url,
                ]
            }
        }
        return serializeAgui("USER_MESSAGE", payload)
    }

    static func serializeToolApprovalRequest(
        toolCallId: String,
        toolName: String,
        arguments: String
    ) -> String {
        serializeAgui("TOOL_APPROVAL_REQUEST", [
            "toolCallId": toolCallId,
            "toolName": toolName,
            "arguments": arguments,
        ])
    }

    static func serializeToolApprovalResolved(toolCallId: String, approved: Bool) -> String {
        serializeAgui("TOOL_APPROVAL_RESOLVED", [
            "toolCallId": toolCallId,
            "approved": approved,
        ])
    }

    static func serializeEventsToJsonArray(_ eventJsonStrings: [String]) -> String {
        guard !eventJsonStrings.isEmpty else { return "[]" }
        var objects: [Any] = []
        for eventJson in eventJsonStrings {
            guard let data = eventJson.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }
            objects.append(object)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: objects, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    static func serializeStaticAssistantHTML(
        messageId: String,
        markdown: String,
        html: String? = nil,
        createIfMissing: Bool = true
    ) -> String {
        serializeAgui("STATIC_ASSISTANT_HTML", [
            "messageId": messageId,
            "markdown": markdown,
            "html": html ?? escapeMinimalHTML(markdown),
            "createIfMissing": createIfMissing,
        ] as [String: Any])
    }

    /// Live streaming assistant markdown (omit pre-rendered `html`; WebView renders via `marked`).
    static func serializeStreamingAssistantHTML(
        messageId: String,
        markdown: String,
        streaming: Bool = true
    ) -> String {
        let payload: [String: Any] = [
            "messageId": messageId,
            "markdownB64": Data(markdown.utf8).base64EncodedString(),
            "createIfMissing": true,
            "streaming": streaming,
        ]
        return serializeAgui("STATIC_ASSISTANT_HTML", payload)
    }

    /// Build a simple AG-UI replay sequence from persisted conversation messages.
    static func buildReplayEvents(
        from messages: [ChatMessage],
        showToolCalls: Bool = true,
        includeReset: Bool = true
    ) -> [String] {
        var events: [String] = []
        if includeReset {
            events.append(serializeResetTimeline())
        }

        for message in messages {
            switch message.role {
            case .user:
                events.append(serializeUserMessage(messageId: message.id, content: message.content))
            case .assistant:
                if let toolCalls = message.toolCalls, showToolCalls {
                    for call in toolCalls {
                        events.append(serializeAgui("TOOL_CALL_START", [
                            "toolCallId": call.id,
                            "toolCallName": call.name,
                        ] as [String: Any]))
                        if !call.arguments.isEmpty && call.arguments != "{}" {
                            events.append(serializeAgui("TOOL_CALL_ARGS", [
                                "toolCallId": call.id,
                                "delta": call.arguments,
                            ] as [String: Any]))
                        }
                        events.append(serializeAgui("TOOL_CALL_END", [
                            "toolCallId": call.id,
                            "status": "succeeded",
                        ] as [String: Any]))
                    }
                }
                if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    events.append(serializeStaticAssistantHTML(
                        messageId: message.id,
                        markdown: message.content
                    ))
                }
            case .tool:
                guard showToolCalls else { continue }
                let toolCallId = message.toolCallId ?? message.id
                events.append(serializeAgui("TOOL_CALL_START", [
                    "toolCallId": toolCallId,
                    "toolCallName": "tool",
                ] as [String: Any]))
                events.append(serializeAgui("TOOL_CALL_END", [
                    "toolCallId": toolCallId,
                    "status": parseToolStatus(from: message.content),
                ] as [String: Any]))
                events.append(serializeAgui("TOOL_CALL_RESULT", [
                    "toolCallId": toolCallId,
                    "content": message.content,
                    "messageId": message.id,
                    "status": parseToolStatus(from: message.content),
                ] as [String: Any]))
            case .system, .summary, .compaction:
                continue
            }
        }
        return events
    }

    // MARK: - Internals

    private static func escapeMinimalHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br/>")
    }


    private static func serializeAgui(_ type: String, _ payload: [String: Any]) -> String {
        var merged: [String: Any] = ["type": type]
        for (key, value) in payload {
            merged[key] = value
        }
        guard JSONSerialization.isValidJSONObject(merged),
              let data = try? JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{\"type\":\"\(type)\"}"
        }
        return string
    }

    private static func parseToolStatus(from content: String) -> String {
        let lowered = content.lowercased()
        if lowered.contains("status: failed") || lowered.contains("\"status\":\"failed\"") {
            return "failed"
        }
        if lowered.contains("status: cancelled") || lowered.contains("\"status\":\"cancelled\"") {
            return "cancelled"
        }
        if lowered.contains("status: preparing") {
            return "preparing"
        }
        if lowered.contains("awaiting_approval") {
            return "awaiting_approval"
        }
        if lowered.contains("approval_denied") {
            return "approval_denied"
        }
        if lowered.contains("status: running") {
            return "running"
        }
        return "succeeded"
    }
}
