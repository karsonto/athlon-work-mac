import Foundation

// MARK: - Model completion types

nonisolated struct ModelToolCall: Hashable, Sendable {
    var id: String
    var name: String
    var arguments: String
}

nonisolated struct ModelUsage: Hashable, Sendable {
    var promptTokens: Int
    var completionTokens: Int
    var totalTokens: Int

    static let zero = ModelUsage(promptTokens: 0, completionTokens: 0, totalTokens: 0)
}

nonisolated struct ModelCompletion: Sendable {
    var content: String
    var reasoning: String
    var toolCalls: [ModelToolCall]
    var usage: ModelUsage
}

nonisolated enum ModelDelta: Sendable {
    case content(String)
    case reasoning(String)
    case toolCallStart(id: String, name: String, index: Int)
    case toolCallArgs(id: String, delta: String)
    case toolCallEnd(id: String)
}

nonisolated enum AgentModelClientError: Error, LocalizedError {
    case missingEndpoint
    case invalidEndpoint(String)
    case invalidResponse(Int, String)
    case decodingFailed(String)
    case cancelled
    case contextOverflow(String)

    var errorDescription: String? {
        switch self {
        case .missingEndpoint: return "模型 Endpoint 为空，请在设置中填写。"
        case let .invalidEndpoint(value): return "Endpoint 格式无效：\(value)"
        case let .invalidResponse(code, body): return "HTTP \(code): \(body.prefix(500))"
        case let .decodingFailed(detail): return "Failed to decode model response: \(detail)"
        case .cancelled: return "Model request was cancelled"
        case let .contextOverflow(detail): return "Context overflow: \(detail)"
        }
    }

    var isContextOverflow: Bool {
        if case .contextOverflow = self { return true }
        return false
    }
}

nonisolated protocol AgentModelClient: Sendable {
    func complete(
        messages: [[String: Any]],
        tools: [[String: Any]]?,
        settings: ModelSettings,
        onDelta: @escaping @Sendable (ModelDelta) -> Void
    ) async throws -> ModelCompletion
}

// MARK: - OpenAI-compatible streaming client

nonisolated final class OpenAICompatibleChatModelClient: AgentModelClient, @unchecked Sendable {
    private let session: URLSession
    private let apiKeyProvider: @Sendable () throws -> String?

    init(
        session: URLSession = .shared,
        apiKeyProvider: @escaping @Sendable () throws -> String? = { nil }
    ) {
        self.session = session
        self.apiKeyProvider = apiKeyProvider
    }

    func complete(
        messages: [[String: Any]],
        tools: [[String: Any]]?,
        settings: ModelSettings,
        onDelta: @escaping @Sendable (ModelDelta) -> Void
    ) async throws -> ModelCompletion {
        try Task.checkCancellation()

        let endpoint = settings.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty else { throw AgentModelClientError.missingEndpoint }

        guard let url = Self.resolveChatCompletionsURL(endpoint: endpoint) else {
            throw AgentModelClientError.invalidEndpoint(endpoint)
        }

        var body: [String: Any] = [
            "model": settings.modelName,
            "messages": messages,
            "stream": settings.enableStreaming,
        ]
        if let maxTokens = settings.maxTokens {
            body["max_tokens"] = maxTokens
        }
        if let tools, !tools.isEmpty {
            body["tools"] = tools
            body["tool_choice"] = "auto"
        }
        if settings.enableStreaming {
            body["stream_options"] = ["include_usage": true]
        }

        guard JSONSerialization.isValidJSONObject(body) else {
            throw AgentModelClientError.decodingFailed("Request body contains non-JSON-serializable values")
        }
        let jsonData = try JSONSerialization.data(withJSONObject: body, options: [])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = TimeInterval(max(30, settings.streamingIdleTimeoutSeconds))
        if let apiKey = try apiKeyProvider(), !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        if settings.enableStreaming {
            return try await streamCompletion(request: request, onDelta: onDelta)
        }
        return try await nonStreamingCompletion(request: request, onDelta: onDelta)
    }

    // MARK: - Streaming

    private func streamCompletion(
        request: URLRequest,
        onDelta: @escaping @Sendable (ModelDelta) -> Void
    ) async throws -> ModelCompletion {
        let (bytes, response) = try await session.bytes(for: request)
        try Task.checkCancellation()

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 4000 { break }
            }
            if isOverflowStatus(http.statusCode, body: errorBody) {
                throw AgentModelClientError.contextOverflow(errorBody)
            }
            throw AgentModelClientError.invalidResponse(http.statusCode, errorBody)
        }

        var content = ""
        var reasoning = ""
        var usage = ModelUsage.zero
        var toolBuilders: [Int: ToolCallBuilder] = [:]
        var emittedStarts = Set<Int>()
        var finishedToolIds = Set<String>()

        for try await line in bytes.lines {
            try Task.checkCancellation()
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard trimmed.hasPrefix("data:") else { continue }
            let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }

            guard let data = payload.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if let usageObj = root["usage"] as? [String: Any] {
                usage = parseUsage(usageObj)
            }

            guard let choices = root["choices"] as? [[String: Any]],
                  let choice = choices.first else {
                continue
            }

            if let finish = choice["finish_reason"] as? String,
               finish.lowercased().contains("length") {
                // Soft signal; caller may treat as overflow on empty content.
            }

            let delta = (choice["delta"] as? [String: Any]) ?? [:]

            if let text = delta["content"] as? String, !text.isEmpty {
                content += text
                onDelta(.content(text))
            }

            if let r = delta["reasoning_content"] as? String ?? delta["reasoning"] as? String, !r.isEmpty {
                reasoning += r
                onDelta(.reasoning(r))
            }

            if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                for tc in toolCalls {
                    let index = tc["index"] as? Int ?? 0
                    var builder = toolBuilders[index] ?? ToolCallBuilder(index: index)
                    if let id = tc["id"] as? String, !id.isEmpty {
                        builder.id = id
                    }
                    if let function = tc["function"] as? [String: Any] {
                        if let name = function["name"] as? String, !name.isEmpty {
                            builder.name = name
                        }
                        if let args = function["arguments"] as? String, !args.isEmpty {
                            builder.arguments += args
                            if !emittedStarts.contains(index), !builder.name.isEmpty {
                                emittedStarts.insert(index)
                                let callId = builder.resolvedId
                                onDelta(.toolCallStart(id: callId, name: builder.name, index: index))
                            }
                            if emittedStarts.contains(index) {
                                onDelta(.toolCallArgs(id: builder.resolvedId, delta: args))
                            }
                        }
                    }
                    if !emittedStarts.contains(index), !builder.name.isEmpty {
                        emittedStarts.insert(index)
                        onDelta(.toolCallStart(id: builder.resolvedId, name: builder.name, index: index))
                    }
                    toolBuilders[index] = builder
                }
            }
        }

        let ordered = toolBuilders.keys.sorted().compactMap { toolBuilders[$0] }
        for builder in ordered where !builder.name.isEmpty {
            let id = builder.resolvedId
            if !finishedToolIds.contains(id) {
                finishedToolIds.insert(id)
                if !emittedStarts.contains(builder.index) {
                    onDelta(.toolCallStart(id: id, name: builder.name, index: builder.index))
                }
                onDelta(.toolCallEnd(id: id))
            }
        }

        let calls = ordered.filter { !$0.name.isEmpty }.map {
            ModelToolCall(id: $0.resolvedId, name: $0.name, arguments: $0.arguments.isEmpty ? "{}" : $0.arguments)
        }
        return ModelCompletion(content: content, reasoning: reasoning, toolCalls: calls, usage: usage)
    }

    // MARK: - Non-streaming

    private func nonStreamingCompletion(
        request: URLRequest,
        onDelta: @escaping @Sendable (ModelDelta) -> Void
    ) async throws -> ModelCompletion {
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            if isOverflowStatus(http.statusCode, body: body) {
                throw AgentModelClientError.contextOverflow(body)
            }
            throw AgentModelClientError.invalidResponse(http.statusCode, body)
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let choice = choices.first,
              let message = choice["message"] as? [String: Any] else {
            throw AgentModelClientError.decodingFailed("Missing choices/message")
        }

        let content = message["content"] as? String ?? ""
        let reasoning = (message["reasoning_content"] as? String)
            ?? (message["reasoning"] as? String)
            ?? ""
        if !content.isEmpty { onDelta(.content(content)) }
        if !reasoning.isEmpty { onDelta(.reasoning(reasoning)) }

        var toolCalls: [ModelToolCall] = []
        if let rawCalls = message["tool_calls"] as? [[String: Any]] {
            for (index, tc) in rawCalls.enumerated() {
                let id = (tc["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "call_\(index)"
                let function = tc["function"] as? [String: Any] ?? [:]
                let name = function["name"] as? String ?? ""
                let args = function["arguments"] as? String ?? "{}"
                guard !name.isEmpty else { continue }
                onDelta(.toolCallStart(id: id, name: name, index: index))
                if !args.isEmpty { onDelta(.toolCallArgs(id: id, delta: args)) }
                onDelta(.toolCallEnd(id: id))
                toolCalls.append(ModelToolCall(id: id, name: name, arguments: args.isEmpty ? "{}" : args))
            }
        }

        let usage = parseUsage(root["usage"] as? [String: Any] ?? [:])
        return ModelCompletion(content: content, reasoning: reasoning, toolCalls: toolCalls, usage: usage)
    }

    // MARK: - Helpers

    private func parseUsage(_ obj: [String: Any]) -> ModelUsage {
        let prompt = obj["prompt_tokens"] as? Int ?? 0
        let completion = obj["completion_tokens"] as? Int ?? 0
        let total = obj["total_tokens"] as? Int ?? (prompt + completion)
        return ModelUsage(promptTokens: prompt, completionTokens: completion, totalTokens: total)
    }

    private func isOverflowStatus(_ code: Int, body: String) -> Bool {
        if code == 413 { return true }
        let lowered = body.lowercased()
        return lowered.contains("context_length")
            || lowered.contains("context length")
            || lowered.contains("maximum context")
            || lowered.contains("too many tokens")
            || lowered.contains("token limit")
    }

    /// Normalizes user-entered endpoint into a chat completions URL.
    static func resolveChatCompletionsURL(endpoint: String) -> URL? {
        var raw = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        // Common typo: missing scheme.
        if !raw.contains("://") {
            raw = "https://" + raw
        }

        if raw.hasSuffix("/") { raw.removeLast() }
        let urlString = raw.hasSuffix("/chat/completions") ? raw : raw + "/chat/completions"
        return URL(string: urlString)
    }

    private struct ToolCallBuilder {
        var index: Int
        var id: String = ""
        var name: String = ""
        var arguments: String = ""

        var resolvedId: String {
            id.isEmpty ? "call_\(index)" : id
        }
    }
}
