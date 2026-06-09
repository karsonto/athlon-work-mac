import Foundation

enum OpenAiModelClientError: LocalizedError {
    case missingApiKey
    case invalidEndpoint
    case httpError(status: Int, body: String)
    case contextLengthExceeded(String)

    var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "模型 API Key 未配置。请在 Settings > Model 中输入 API Key 并保存，或设置环境变量 OPENAI_API_KEY。"
        case .invalidEndpoint:
            return "无效的 API 端点。"
        case .httpError(let status, let body):
            return "HTTP \(status): \(body)"
        case .contextLengthExceeded(let message):
            return message
        }
    }
}

/// OpenAI-compatible chat completions client with real SSE streaming.
final class OpenAiChatModelClient: AgentChatModelClient, @unchecked Sendable {
    private let settings: ModelSettings
    private let apiKey: String
    private let session: URLSession

    init(
        settings: AppSettings,
        apiKey: String? = nil,
        session: URLSession? = nil,
        credentialStore: CredentialStoring = CredentialStore()
    ) {
        self.settings = settings.model
        if let apiKey, !apiKey.isEmpty {
            self.apiKey = apiKey
        } else if !settings.model.apiKey.isEmpty {
            self.apiKey = settings.model.apiKey
        } else if let stored = credentialStore.get(for: CredentialStore.apiKeyAccount),
                  !stored.isEmpty {
            self.apiKey = stored
        } else if let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !env.isEmpty {
            self.apiKey = env
        } else {
            self.apiKey = ""
        }

        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 300
            config.timeoutIntervalForResource = 600
            self.session = URLSession(configuration: config)
        }
    }

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        try await completeChat(request, onTextDelta: nil, onReasoningDelta: nil, onToolCallDelta: nil)
    }

    func completeChat(
        _ request: AgentModelRequest,
        onTextDelta: (@Sendable (String) async -> Void)?,
        onReasoningDelta: (@Sendable (String) async -> Void)?,
        onToolCallDelta: (@Sendable (StreamingToolCallDelta) async -> Void)?
    ) async throws -> AgentModelResponse {
        guard !apiKey.isEmpty else { throw OpenAiModelClientError.missingApiKey }

        if settings.enableStreaming {
            do {
                let streamed = try await performCompletion(
                    request,
                    stream: true,
                    onTextDelta: onTextDelta,
                    onReasoningDelta: onReasoningDelta,
                    onToolCallDelta: onToolCallDelta
                )
                if streamed.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let full = try await performCompletion(
                        request,
                        stream: false,
                        onTextDelta: onTextDelta,
                        onReasoningDelta: onReasoningDelta,
                        onToolCallDelta: onToolCallDelta
                    )
                    let merged = mergeStreamedAndFullResponse(streamed: streamed, full: full)
                    logModelResponse(merged, stream: true, usedNonStreamFallback: true)
                    return merged
                }
                logModelResponse(streamed, stream: true, usedNonStreamFallback: false)
                return streamed
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Fall back to non-streaming on failure.
            }
        }

        let response = try await performCompletion(
            request,
            stream: false,
            onTextDelta: onTextDelta,
            onReasoningDelta: onReasoningDelta,
            onToolCallDelta: onToolCallDelta
        )
        logModelResponse(response, stream: false, usedNonStreamFallback: false)
        return response
    }

    private func logModelResponse(_ response: AgentModelResponse, stream: Bool, usedNonStreamFallback: Bool) {
        AgentFileLogger.logModelCompletion(
            model: settings.modelName,
            stream: stream,
            contentLength: response.content.count,
            reasoningLength: response.reasoningContent?.count ?? 0,
            toolCallCount: response.toolCalls.count,
            usedNonStreamFallback: usedNonStreamFallback,
            contentPreview: String(response.content.prefix(200))
        )
    }

    private func performCompletion(
        _ request: AgentModelRequest,
        stream: Bool,
        onTextDelta: (@Sendable (String) async -> Void)?,
        onReasoningDelta: (@Sendable (String) async -> Void)?,
        onToolCallDelta: (@Sendable (StreamingToolCallDelta) async -> Void)?
    ) async throws -> AgentModelResponse {
        let endpoint = normalizedEndpoint(settings.endpoint)
        guard let url = URL(string: endpoint) else { throw OpenAiModelClientError.invalidEndpoint }

        let modelName = settings.modelName.lowercased()
        // Flash/chat variants do not accept thinking params; sending them can stall or return empty streams.
        let isDeepSeekThinking = !modelName.contains("flash")
            && !modelName.hasSuffix("-chat")
            && ["deepseek-v4", "deepseek-reasoner", "deepseek-r1"].contains(where: { modelName.contains($0) })

        let openAiTools: [OpenAiRequestTool]?
        if request.allowToolCalls, !request.tools.isEmpty {
            openAiTools = request.tools.map { tool in
                OpenAiRequestTool(
                    function: .init(
                        name: tool.name,
                        description: tool.description,
                        parameters: tool.parameters.map(JsonObject.init)
                    )
                )
            }
        } else {
            openAiTools = nil
        }

        let maxTokens = resolvedMaxTokens(request: request)

        let openAiRequest = OpenAiChatRequest(
            model: settings.modelName,
            messages: request.messages.map(toOpenAiMessage),
            stream: stream,
            tools: openAiTools,
            toolChoice: openAiTools != nil ? "auto" : nil,
            maxTokens: maxTokens,
            reasoningEffort: isDeepSeekThinking ? "high" : nil,
            thinking: isDeepSeekThinking ? OpenAiRequestThinking(type: "enabled", budgetTokens: nil) : nil
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONEncoder().encode(openAiRequest)

        AgentFileLogger.log(
            "model request model=\(settings.modelName) stream=\(stream) messages=\(request.messages.count) tools=\(request.tools.count)",
            category: "Model"
        )

        if stream {
            let (bytes, response) = try await session.bytes(for: urlRequest)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status >= 400 {
                var body = ""
                for try await line in bytes.lines { body += line + "\n" }
                throw mapHttpError(status: status, body: body)
            }
            return try await parseStreamingResponse(
                bytes: bytes,
                response: response,
                onTextDelta: onTextDelta,
                onReasoningDelta: onReasoningDelta,
                onToolCallDelta: onToolCallDelta
            )
        }

        let (data, response) = try await session.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: data, encoding: .utf8) ?? ""
        if status >= 400 {
            throw mapHttpError(status: status, body: body)
        }
        return try await emitParsedResponse(
            body: body,
            onTextDelta: onTextDelta,
            onReasoningDelta: onReasoningDelta,
            onToolCallDelta: onToolCallDelta
        )
    }

    private func resolvedMaxTokens(request: AgentModelRequest) -> Int? {
        if let requestMax = request.maxTokens, requestMax > 0 { return requestMax }
        if settings.maxTokens > 0 { return settings.maxTokens }
        return nil
    }

    private func normalizedEndpoint(_ endpoint: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.lowercased().hasSuffix("/chat/completions") {
            return trimmed
        }
        return trimmed + "/chat/completions"
    }

    private func mapHttpError(status: Int, body: String) -> Error {
        if Self.isContextLengthError(body) {
            return OpenAiModelClientError.contextLengthExceeded(body)
        }
        return OpenAiModelClientError.httpError(status: status, body: Self.truncate(body))
    }

    static func isContextLengthError(_ message: String) -> Bool {
        let lower = message.lowercased()
        let markers = [
            "context_length",
            "context length",
            "maximum context",
            "token limit",
            "too many tokens",
            "exceeds the model's maximum"
        ]
        return markers.contains { lower.contains($0) }
    }

    private static func truncate(_ value: String, limit: Int = 500) -> String {
        value.count <= limit ? value : String(value.prefix(limit))
    }

    private func parseStreamingResponse(
        bytes: URLSession.AsyncBytes,
        response: URLResponse,
        onTextDelta: (@Sendable (String) async -> Void)?,
        onReasoningDelta: (@Sendable (String) async -> Void)?,
        onToolCallDelta: (@Sendable (StreamingToolCallDelta) async -> Void)?
    ) async throws -> AgentModelResponse {
        let mediaType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
        if !mediaType.isEmpty && !mediaType.lowercased().contains("text/event-stream") {
            var body = ""
            for try await line in bytes.lines { body += line + "\n" }
            return try await emitParsedResponse(
                body: body,
                onTextDelta: onTextDelta,
                onReasoningDelta: onReasoningDelta,
                onToolCallDelta: onToolCallDelta
            )
        }

        var contentBuilder = ""
        var reasoningBuilder = ""
        var fallbackBuilder = ""
        var toolStates: [Int: StreamingToolCallState] = [:]
        var sawSseData = false
        var lastStreamMessage: OpenAiResponseMessage?

        // Coalesce small tokens to reduce MainActor hops during streaming.
        let coalesceThreshold = 20
        var pendingText = ""
        var pendingReasoning = ""

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else {
                fallbackBuilder += line + "\n"
                continue
            }

            let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if data.isEmpty { continue }
            sawSseData = true
            if data == "[DONE]" { break }

            guard let jsonData = data.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(OpenAiStreamChunk.self, from: jsonData),
                  let choices = chunk.choices else {
                continue
            }

            for choice in choices {
                if let message = choice.message {
                    lastStreamMessage = message
                }

                guard let delta = choice.delta else { continue }

                if let token = delta.resolvedContent, !token.isEmpty {
                    contentBuilder += token
                    let flushText = pendingText.isEmpty
                    pendingText += token
                    if flushText || pendingText.count >= coalesceThreshold {
                        if let onTextDelta { await onTextDelta(pendingText) }
                        pendingText = ""
                    }
                }

                if let reasoningToken = delta.resolvedReasoning, !reasoningToken.isEmpty {
                    reasoningBuilder += reasoningToken
                    let flushReasoning = pendingReasoning.isEmpty
                    pendingReasoning += reasoningToken
                    if flushReasoning || pendingReasoning.count >= coalesceThreshold {
                        if let onReasoningDelta { await onReasoningDelta(pendingReasoning) }
                        pendingReasoning = ""
                    }
                }

                if let deltaToolCalls = delta.toolCalls {
                    for partial in deltaToolCalls {
                        let index = partial.index
                        var state = toolStates[index] ?? StreamingToolCallState()
                        if let id = partial.id { state.id = id }
                        if let function = partial.function {
                            if let name = function.name { state.name = name }
                            if let args = function.arguments {
                                state.arguments += args
                            }
                        }
                        toolStates[index] = state
                        if let onToolCallDelta {
                            await onToolCallDelta(
                                StreamingToolCallDelta(
                                    index: index,
                                    id: state.id,
                                    name: state.name,
                                    argumentsJson: state.arguments.isEmpty ? "{}" : state.arguments
                                )
                            )
                        }
                    }
                }
            }
        }

        // Flush any remaining coalesced text to the UI.
        if !pendingText.isEmpty, let onTextDelta { await onTextDelta(pendingText) }
        if !pendingReasoning.isEmpty, let onReasoningDelta { await onReasoningDelta(pendingReasoning) }

        if !sawSseData, !fallbackBuilder.isEmpty {
            return try await emitParsedResponse(
                body: fallbackBuilder.trimmingCharacters(in: .whitespacesAndNewlines),
                onTextDelta: onTextDelta,
                onReasoningDelta: onReasoningDelta,
                onToolCallDelta: onToolCallDelta
            )
        }

        let toolCalls = toolStates.keys.sorted().map { index -> AgentToolCall in
            let state = toolStates[index]!
            let args = state.arguments.isEmpty ? "{}" : state.arguments
            return AgentToolCall(
                id: state.id?.isEmpty == false ? state.id! : UUID().uuidString.replacingOccurrences(of: "-", with: ""),
                name: state.name ?? "",
                arguments: args,
                argumentsStreaming: "",
                status: .none
            )
        }

        await flushFinalStreamMessage(
            lastStreamMessage,
            contentBuilder: &contentBuilder,
            reasoningBuilder: &reasoningBuilder,
            onTextDelta: onTextDelta,
            onReasoningDelta: onReasoningDelta
        )

        let reasoning = reasoningBuilder.isEmpty ? nil : reasoningBuilder
        return normalizeAssistantResponse(content: contentBuilder, toolCalls: toolCalls, reasoningContent: reasoning)
    }

    private func mergeStreamedAndFullResponse(streamed: AgentModelResponse, full: AgentModelResponse) -> AgentModelResponse {
        let content = full.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? streamed.content
            : full.content
        let reasoning = (full.reasoningContent?.isEmpty == false)
            ? full.reasoningContent
            : streamed.reasoningContent
        let toolCalls = full.toolCalls.isEmpty ? streamed.toolCalls : full.toolCalls
        return AgentModelResponse(content: content, toolCalls: toolCalls, reasoningContent: reasoning)
    }

    private func flushFinalStreamMessage(
        _ message: OpenAiResponseMessage?,
        contentBuilder: inout String,
        reasoningBuilder: inout String,
        onTextDelta: (@Sendable (String) async -> Void)?,
        onReasoningDelta: (@Sendable (String) async -> Void)?
    ) async {
        guard let message else { return }

        if contentBuilder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let finalContent = message.content,
           !finalContent.isEmpty {
            contentBuilder = finalContent
            if let onTextDelta { await onTextDelta(finalContent) }
        }

        if reasoningBuilder.isEmpty,
           let finalReasoning = message.reasoningContent,
           !finalReasoning.isEmpty {
            reasoningBuilder = finalReasoning
            if let onReasoningDelta { await onReasoningDelta(finalReasoning) }
        }
    }

    private func emitParsedResponse(
        body: String,
        onTextDelta: (@Sendable (String) async -> Void)?,
        onReasoningDelta: (@Sendable (String) async -> Void)?,
        onToolCallDelta: (@Sendable (StreamingToolCallDelta) async -> Void)?
    ) async throws -> AgentModelResponse {
        let parsed = try parseNonStreamingResponse(body)
        if let onReasoningDelta, let reasoning = parsed.reasoningContent, !reasoning.isEmpty {
            await onReasoningDelta(reasoning)
        }
        if let onTextDelta, !parsed.content.isEmpty {
            await onTextDelta(parsed.content)
        }
        if let onToolCallDelta {
            for (index, call) in parsed.toolCalls.enumerated() {
                await onToolCallDelta(
                    StreamingToolCallDelta(
                        index: index,
                        id: call.id,
                        name: call.name,
                        argumentsJson: call.arguments
                    )
                )
            }
        }
        return parsed
    }

    private func parseNonStreamingResponse(_ body: String) throws -> AgentModelResponse {
        guard let data = body.data(using: .utf8) else {
            throw OpenAiModelClientError.httpError(status: 0, body: Self.truncate(body))
        }
        let response: OpenAiChatResponse
        do {
            response = try JSONDecoder().decode(OpenAiChatResponse.self, from: data)
        } catch {
            throw OpenAiModelClientError.httpError(status: 0, body: Self.truncate(body))
        }
        guard let message = response.choices.first?.message else {
            throw OpenAiModelClientError.httpError(status: 0, body: Self.truncate(body))
        }
        let content = message.content ?? ""
        let toolCalls = parseToolCallsFromMessage(message)
        let reasoning = message.reasoningContent
        let usage = response.usage.map {
            AgentModelUsage(
                promptTokens: $0.promptTokens,
                completionTokens: $0.completionTokens,
                totalTokens: $0.totalTokens
            )
        }
        return normalizeAssistantResponse(
            content: content,
            toolCalls: toolCalls,
            reasoningContent: reasoning,
            usage: usage
        )
    }

    private func normalizeAssistantResponse(
        content: String,
        toolCalls: [AgentToolCall],
        reasoningContent: String?,
        usage: AgentModelUsage? = nil
    ) -> AgentModelResponse {
        var (normalizedContent, normalizedReasoning) = splitEmbeddedThinkingContent(
            content: content,
            reasoningContent: reasoningContent
        )
        if normalizedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let reasoning = normalizedReasoning,
           !reasoning.isEmpty {
            if ChatMessage.containsThinkingMarkers(reasoning) {
                let (answer, thinking) = splitEmbeddedThinkingContent(content: reasoning, reasoningContent: nil)
                if !answer.isEmpty {
                    normalizedContent = answer
                    normalizedReasoning = thinking
                }
            } else {
                normalizedContent = reasoning
                normalizedReasoning = nil
            }
        }
        return AgentModelResponse(
            content: normalizedContent,
            toolCalls: toolCalls,
            reasoningContent: normalizedReasoning,
            usage: usage
        )
    }

    private func splitEmbeddedThinkingContent(content: String, reasoningContent: String?) -> (String, String?) {
        if let reasoningContent, !reasoningContent.isEmpty {
            return (content, reasoningContent)
        }

        let endTags = ["\u{3c}/redacted_thinking\u{3e}", "`/think`"]
        let startTags = ["\u{3c}redacted_thinking\u{3e}", "`think`"]
        for endTag in endTags {
            guard let range = content.range(of: endTag, options: [.caseInsensitive]) else { continue }
            var reasoning = String(content[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let answer = String(content[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            for startTag in startTags where reasoning.lowercased().hasPrefix(startTag.lowercased()) {
                reasoning = String(reasoning.dropFirst(startTag.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return (answer, reasoning.isEmpty ? nil : reasoning)
        }
        return (content, nil)
    }

    private func parseToolCallsFromMessage(_ message: OpenAiResponseMessage) -> [AgentToolCall] {
        guard let calls = message.toolCalls else { return [] }
        return calls.map { call in
            let argsJson = call.function.arguments
            let args = Self.parseArguments(argsJson)
            return AgentToolCall(
                id: call.id,
                name: call.function.name,
                arguments: AssistantToolCallsCodec.serializeArguments(args),
                argumentsStreaming: "",
                status: .none
            )
        }
    }

    private func toOpenAiMessage(_ message: AgentModelMessage) -> OpenAiRequestMessage {
        var toolCalls: [OpenAiRequestToolCall]?
        if let calls = message.toolCalls, !calls.isEmpty {
            toolCalls = calls.map { call in
                OpenAiRequestToolCall(
                    id: call.id,
                    type: "function",
                    function: .init(name: call.name, arguments: call.arguments)
                )
            }
        }
        var reasoningContent: String?
        if message.role.lowercased() == "assistant" {
            reasoningContent = message.reasoningContent
        }
        return OpenAiRequestMessage(
            role: message.role,
            content: encodeContent(message.content),
            toolCallId: message.toolCallId,
            toolCalls: toolCalls,
            reasoningContent: reasoningContent
        )
    }

    private func encodeContent(_ content: AgentModelContent) -> OpenAiMessageContent {
        switch content {
        case .text(let text):
            return .text(text)
        case .parts(let parts):
            return .parts(parts.map { part in
                switch part {
                case .text(let text):
                    return OpenAiContentPart(type: "text", text: text, imageUrl: nil)
                case .imageURL(let url):
                    return OpenAiContentPart(type: "image_url", text: nil, imageUrl: .init(url: url, detail: nil))
                }
            })
        }
    }

    static func parseArguments(_ argumentsJson: String) -> [String: String] {
        let parsed = AssistantToolCallsCodec.parseArguments(argumentsJson)
        return ToolPathNormalizer.normalizePathArguments(parsed)
    }

    static func buildUserContent(from message: ChatMessage) -> AgentModelContent {
        guard let attachments = message.imageAttachments, !attachments.isEmpty else {
            return .text(message.content)
        }

        var parts: [AgentModelContentPart] = [.text(message.content)]
        for attachment in attachments {
            let dataUrl = attachment.dataUrl()
            if !dataUrl.isEmpty {
                parts.append(.imageURL(dataUrl))
            }
        }
        return .parts(parts)
    }
}

private struct StreamingToolCallState {
    var id: String?
    var name: String?
    var arguments: String = ""
}

extension ImageAttachment {
    func dataUrl() -> String {
        guard let data = originalData else { return "" }
        let ext = (fileName as NSString).pathExtension.lowercased()
        let mime: String
        switch ext {
        case "png": mime = "image/png"
        case "jpg", "jpeg": mime = "image/jpeg"
        case "heic": mime = "image/heic"
        case "webp": mime = "image/webp"
        case "gif": mime = "image/gif"
        default: mime = "image/png"
        }
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }
}
