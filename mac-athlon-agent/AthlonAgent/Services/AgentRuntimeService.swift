import Foundation
import Combine

// MARK: - Agent Runtime Service
/// Core service for chat completions, streaming SSE responses, tool call handling, and context compaction.
class AgentRuntimeService: ObservableObject {
    @Published var isRunning = false
    @Published var isStreaming = false
    @Published var error: String?
    @Published var currentReasoning: String = ""
    @Published var currentToolCalls: [AgentToolCall] = []

    private var cancellables = Set<AnyCancellable>()
    private var session: URLSession!
    private var activeTask: URLSessionDataTask?

    // Configuration
    private let apiEndpoint: String
    private let apiKey: String
    private let model: String
    private let maxTokens: Int
    private let streamingEnabled: Bool

    // Context compaction threshold
    private let maxContextMessages = 40
    private let compactionTriggerCount = 50

    init(settings: AppSettings) {
        self.apiEndpoint = settings.model.endpoint
        self.apiKey = settings.model.apiKey
        self.model = settings.model.modelName
        self.maxTokens = settings.model.maxTokens
        self.streamingEnabled = settings.model.enableStreaming

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)
    }

    func reconfigure(settings: AppSettings) {
        // Called when settings change
    }

    // MARK: - Send Message (Streaming)
    func sendMessage(
        messages: [ChatMessage],
        systemPrompt: String,
        tools: [ToolDefinition]?,
        onChunk: @escaping (String) -> Void,
        onToolCall: @escaping (AgentToolCall) -> Void,
        onReasoningChunk: @escaping (String) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard !isRunning else {
            error = "已有运行中的对话"
            return
        }

        isRunning = true
        isStreaming = true
        error = nil
        currentReasoning = ""
        currentToolCalls = []

        let request = buildRequest(
            messages: messages,
            systemPrompt: systemPrompt,
            tools: tools,
            stream: true
        )

        let dataTask = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.isStreaming = false
                    self.error = error.localizedDescription
                    completion(.failure(error))
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.isStreaming = false
                    self.error = "无响应数据"
                    completion(.failure(NSError(domain: "Athlon", code: -1)))
                }
                return
            }

            self.parseSSEStream(
                data: data,
                onChunk: { chunk in
                    DispatchQueue.main.async { onChunk(chunk) }
                },
                onToolCall: { toolCall in
                    DispatchQueue.main.async {
                        self.currentToolCalls.append(toolCall)
                        onToolCall(toolCall)
                    }
                },
                onReasoningChunk: { reasoning in
                    DispatchQueue.main.async {
                        self.currentReasoning += reasoning
                        onReasoningChunk(reasoning)
                    }
                },
                completion: { result in
                    DispatchQueue.main.async {
                        self.isRunning = false
                        self.isStreaming = false
                        switch result {
                        case .success(let text):
                            completion(.success(text))
                        case .failure(let err):
                            self.error = err.localizedDescription
                            completion(.failure(err))
                        }
                    }
                }
            )
        }

        activeTask = dataTask
        dataTask.resume()
    }

    // MARK: - Stop Agent
    func stop() {
        activeTask?.cancel()
        activeTask = nil
        isRunning = false
        isStreaming = false
    }

    // MARK: - Build Request
    private func buildRequest(
        messages: [ChatMessage],
        systemPrompt: String,
        tools: [ToolDefinition]?,
        stream: Bool
    ) -> URLRequest {
        guard let url = URL(string: apiEndpoint) else {
            fatalError("无效的 API 端点: \(apiEndpoint)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 300

        // Build payload
        var payload: [String: Any] = [
            "model": model,
            "messages": buildMessagesPayload(messages: messages, systemPrompt: systemPrompt),
            "max_tokens": maxTokens,
            "stream": stream
        ]

        if let tools = tools, !tools.isEmpty {
            payload["tools"] = tools.map { $0.dictionary }
            payload["tool_choice"] = "auto"
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])
        return request
    }

    private func buildMessagesPayload(messages: [ChatMessage], systemPrompt: String) -> [[String: Any]] {
        var result: [[String: Any]] = []

        // System prompt
        if !systemPrompt.isEmpty {
            result.append([
                "role": "system",
                "content": systemPrompt
            ])
        }

        // Conversation messages
        for msg in messages {
            var entry: [String: Any] = [
                "role": msg.role.apiValue,
                "content": msg.content
            ]

            // Attach tool calls
            if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                entry["tool_calls"] = toolCalls.map { tc in
                    [
                        "id": tc.id,
                        "type": "function",
                        "function": [
                            "name": tc.name,
                            "arguments": tc.arguments
                        ]
                    ]
                }
            }

            // Attach tool results
            if msg.role == .tool, let toolCallId = msg.toolCallId {
                entry["tool_call_id"] = toolCallId
            }

            result.append(entry)
        }

        return result
    }

    // MARK: - SSE Stream Parsing
    private func parseSSEStream(
        data: Data,
        onChunk: @escaping (String) -> Void,
        onToolCall: @escaping (AgentToolCall) -> Void,
        onReasoningChunk: @escaping (String) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let text = String(data: data, encoding: .utf8) else {
            completion(.failure(NSError(domain: "Athlon", code: -2, userInfo: [NSLocalizedDescriptionKey: "无法解码响应数据"])))
            return
        }

        let lines = text.components(separatedBy: "\n")
        var fullContent = ""
        var pendingToolCalls: [String: AgentToolCall] = [:]

        for line in lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))

            if jsonStr == "[DONE]" {
                continue
            }

            guard let jsonData = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any] else {
                continue
            }

            // Content chunk
            if let content = delta["content"] as? String {
                fullContent += content
                onChunk(content)
            }

            // Reasoning content (DeepSeek-style)
            if let reasoningContent = delta["reasoning_content"] as? String {
                onReasoningChunk(reasoningContent)
            }

            // Tool calls in delta
            if let toolCallDeltas = delta["tool_calls"] as? [[String: Any]] {
                for tcDelta in toolCallDeltas {
                    let idx = tcDelta["index"] as? Int ?? 0
                    let tcId = tcDelta["id"] as? String ?? "tc_\(idx)"
                    let function = tcDelta["function"] as? [String: Any]
                    let name = function?["name"] as? String ?? ""
                    let arguments = function?["arguments"] as? String ?? ""

                    if var existing = pendingToolCalls[tcId] {
                        existing.name += name
                        existing.arguments += arguments
                        pendingToolCalls[tcId] = existing
                    } else {
                        let tc = AgentToolCall(
                            id: tcId,
                            name: name,
                            arguments: arguments,
                            argumentsStreaming: "",
                            status: .none
                        )
                        pendingToolCalls[tcId] = tc
                    }
                }
            }

            // Finish reason - finalize pending tool calls
            if let finishReason = choices.first?["finish_reason"] as? String,
               finishReason == "tool_calls" {
                for (_, tc) in pendingToolCalls {
                    let finalized = AgentToolCall(
                        id: tc.id,
                        name: tc.name.trimmingCharacters(in: .whitespaces),
                        arguments: tc.arguments.trimmingCharacters(in: .whitespaces),
                        argumentsStreaming: "",
                        status: .none
                    )
                    onToolCall(finalized)
                }
            }
        }

        // Emit any remaining tool calls (only if not already emitted via finish_reason)
        if !pendingToolCalls.keys.isEmpty {
            // Remaining tool calls already emitted via finish_reason
        }

        completion(.success(fullContent))
    }

    // MARK: - Non-Streaming Send
    func sendMessageSync(
        messages: [ChatMessage],
        systemPrompt: String,
        tools: [ToolDefinition]?,
        completion: @escaping (Result<AgentResponse, Error>) -> Void
    ) {
        guard !isRunning else { return }
        isRunning = true

        let request = buildRequest(
            messages: messages,
            systemPrompt: systemPrompt,
            tools: tools,
            stream: false
        )

        let dataTask = session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isRunning = false
            }

            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "Athlon", code: -3)))
                }
                return
            }

            let result = AgentResponse.from(json: json)
            DispatchQueue.main.async { completion(.success(result)) }
        }

        dataTask.resume()
    }

    // MARK: - Build Tool Result Message
    func buildToolResultMessage(toolCall: AgentToolCall, result: String) -> ChatMessage {
        ChatMessage(
            id: UUID().uuidString,
            role: .tool,
            content: result,
            createdAt: Date(),
            toolCallId: toolCall.id
        )
    }

    // MARK: - Context Compaction
    /// Check if context needs compaction and build a summarization prompt if needed.
    func needsCompaction(messages: [ChatMessage]) -> Bool {
        messages.count > compactionTriggerCount
    }

    func buildCompactedMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
        guard messages.count > maxContextMessages else { return messages }

        // Keep system message + last N messages
        let systemMsgs = messages.filter { $0.role == .system }
        let nonSystemMsgs = messages.filter { $0.role != .system }

        // Keep most recent messages
        let recentCount = maxContextMessages - systemMsgs.count
        let recent = Array(nonSystemMsgs.suffix(recentCount))

        // Add compaction summary as system message
        let removedCount = nonSystemMsgs.count - recentCount
        let compactionNote = ChatMessage(
            id: "compaction_\(UUID().uuidString)",
            role: .system,
            content: "[上下文已压缩: \(removedCount) 条较早消息已移除，保留最后 \(recentCount) 条消息]",
            createdAt: Date()
        )

        return systemMsgs + [compactionNote] + recent
    }
}

// MARK: - Tool Definition
struct ToolDefinition {
    let name: String
    let description: String
    let parameters: [String: Any]?

    var dictionary: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": parameters ?? [
                    "type": "object",
                    "properties": [:],
                    "required": []
                ]
            ]
        ]
    }

    static func from(json: [String: Any]) -> ToolDefinition? {
        guard let function = json["function"] as? [String: Any],
              let name = function["name"] as? String else { return nil }
        return ToolDefinition(
            name: name,
            description: function["description"] as? String ?? "",
            parameters: function["parameters"] as? [String: Any]
        )
    }
}

// MARK: - Agent Response (non-streaming)
struct AgentResponse {
    let content: String
    let toolCalls: [AgentToolCall]
    let finishReason: String
    let usage: [String: Int]

    static func from(json: [String: Any]) -> AgentResponse {
        var content = ""
        var toolCalls: [AgentToolCall] = []
        var finishReason = "stop"
        var usage: [String: Int] = [:]

        if let choices = json["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any] {
            content = message["content"] as? String ?? ""

            if let tcs = message["tool_calls"] as? [[String: Any]] {
                for tc in tcs {
                    if let function = tc["function"] as? [String: Any] {
                        toolCalls.append(AgentToolCall(
                            id: tc["id"] as? String ?? UUID().uuidString,
                            name: function["name"] as? String ?? "",
                            arguments: function["arguments"] as? String ?? "{}",
                            argumentsStreaming: "",
                            status: .none
                        ))
                    }
                }
            }

            finishReason = choices.first?["finish_reason"] as? String ?? "stop"
        }

        if let u = json["usage"] as? [String: Any] {
            for (key, value) in u {
                usage[key] = value as? Int ?? 0
            }
        }

        return AgentResponse(content: content, toolCalls: toolCalls, finishReason: finishReason, usage: usage)
    }
}

// MARK: - System Prompt Builder
struct SystemPromptBuilder {
    static func build(
        workspaceRoot: String?,
        files: [String],
        mcpTools: [String],
        skills: [String],
        date: Date
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.dateFormat = "yyyy-MM-dd EEEE HH:mm"
        dateFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")

        let dateStr = dateFormatter.string(from: date)
        let host = Host.current().localizedName ?? "macOS"

        var prompt = ""
        prompt += "You are Athlon Agent, a macOS desktop coding agent.\n"
        prompt += "Use the provided function tools when you need to inspect or modify workspace files. Do not guess file contents.\n"
        prompt += "Think through the user's goal, constraints, and risks before calling tools or making changes. Share concise reasoning when it helps the user follow your approach.\n\n"

        prompt += "Host: \(host) | \(dateStr) | \(NSFullUserName())\n"

        if let root = workspaceRoot {
            prompt += "Workspace root: \(root)\n"
        }

        if !files.isEmpty {
            prompt += "\nWorkspace files:\n"
            for file in files.prefix(30) {
                prompt += "- \(file)\n"
            }
            if files.count > 30 {
                prompt += "... and \(files.count - 30) more files\n"
            }
        }

        prompt += "\n"
        prompt += "Mermaid diagrams in chat:\n"
        prompt += "- When a diagram clarifies the answer better than prose alone, include one or more fenced ```mermaid code blocks\n"
        prompt += "- In Athlon Agent the chat shows Mermaid as source code, not inline graphics. Tell the user they can right-click the message and choose \"查看 Mermaid 图表\" for an offline rendered preview.\n"

        return prompt
    }
}
