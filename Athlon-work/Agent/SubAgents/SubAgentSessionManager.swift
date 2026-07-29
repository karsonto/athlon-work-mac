import Foundation

/// Spawns child sessions under `sessions/{parent}/subagents/default/{id}/`.
nonisolated final class SubAgentSessionManager: @unchecked Sendable {
    private let paths: AppPathProviding
    private let storage: FileStorageService
    private let lock = NSLock()

    init(paths: AppPathProviding = AppPathProvider(), storage: FileStorageService? = nil) {
        self.paths = paths
        self.storage = storage ?? FileStorageService(paths: paths)
    }

    func spawn(
        parentSessionId: String,
        title: String? = nil,
        settings: SubAgentSettings
    ) throws -> AgentSession {
        guard settings.enabled else {
            throw AgentToolError.executionFailed("Sub-agent is disabled in settings.")
        }
        try paths.ensureCreated()
        let nested = SessionDirectoryLayout.collectNestedSubAgentSessionIds(sessionsPath: paths.sessionsPath)
        // Rough concurrency guard: count active nested under this parent.
        let parentDir = SessionDirectoryLayout.sessionDirectory(
            sessionsPath: paths.sessionsPath,
            sessionId: parentSessionId
        )
        let subRoot = ((parentDir as NSString)
            .appendingPathComponent(SessionDirectoryLayout.subAgentsFolder) as NSString)
            .appendingPathComponent(SessionDirectoryLayout.subAgentKind)
        let existingCount = (try? FileManager.default.contentsOfDirectory(atPath: subRoot))?.count ?? 0
        if existingCount >= settings.maxConcurrentSubAgents {
            throw AgentToolError.executionFailed(
                "Max concurrent sub-agents reached (\(settings.maxConcurrentSubAgents))"
            )
        }
        _ = nested

        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let dir = SessionDirectoryLayout.subAgentDirectory(
            sessionsPath: paths.sessionsPath,
            parentSessionId: parentSessionId,
            subSessionId: id
        )
        try SessionDirectoryLayout.ensureSessionLogDirectories(at: dir)

        var session = AgentSession(id: id, title: title ?? "Sub-agent \(id.prefix(8))")
        try storage.saveSession(session)
        return session
    }

    func list(parentSessionId: String) throws -> [AgentSession] {
        let subRoot = (
            (SessionDirectoryLayout.sessionDirectory(
                sessionsPath: paths.sessionsPath,
                sessionId: parentSessionId
            ) as NSString)
            .appendingPathComponent(SessionDirectoryLayout.subAgentsFolder) as NSString
        ).appendingPathComponent(SessionDirectoryLayout.subAgentKind)

        guard let names = try? FileManager.default.contentsOfDirectory(atPath: subRoot) else {
            return []
        }
        return names.compactMap { name in
            try? storage.loadSession(id: name)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func history(subSessionId: String, maxMessages: Int = 40) throws -> [ChatMessage] {
        let messages = try storage.loadConversationMessages(sessionId: subSessionId)
        if messages.count <= maxMessages { return messages }
        return Array(messages.suffix(maxMessages))
    }

    func appendUserMessage(subSessionId: String, text: String) throws {
        let message = ChatMessage(role: .user, content: text)
        try storage.appendConversationMessage(sessionId: subSessionId, message: message)
        if var session = try storage.loadSession(id: subSessionId) {
            session.updatedAt = Date()
            try storage.saveSession(session)
        }
    }
}

// MARK: - Tools

nonisolated struct SessionsSpawnTool: AgentTool {
    let name = "sessions_spawn"
    private let manager: SubAgentSessionManager

    init(manager: SubAgentSessionManager) {
        self.manager = manager
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Spawn a nested sub-agent session under the current parent session.",
            parameters: [
                "type": "object",
                "properties": [
                    "title": ["type": "string"] as [String: Any],
                ] as [String: Any],
            ]
        )
    }

    func invoke(arguments: String, context: AgentRunContext) async throws -> String {
        let args = try ToolJSON.object(from: arguments)
        let title = args["title"] as? String
        let session = try manager.spawn(
            parentSessionId: context.sessionId,
            title: title,
            settings: context.settings.subAgent
        )
        return "spawned_session_id: \(session.id)\ntitle: \(session.title)"
    }
}

nonisolated struct SessionsSendTool: AgentTool {
    let name = "sessions_send"
    private let manager: SubAgentSessionManager

    init(manager: SubAgentSessionManager) {
        self.manager = manager
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Append a user message to a sub-agent session (queue for later / parent orchestration).",
            parameters: [
                "type": "object",
                "properties": [
                    "session_id": ["type": "string"] as [String: Any],
                    "message": ["type": "string"] as [String: Any],
                ] as [String: Any],
                "required": ["session_id", "message"],
            ]
        )
    }

    func invoke(arguments: String, context: AgentRunContext) async throws -> String {
        _ = context
        let args = try ToolJSON.object(from: arguments)
        guard let id = args["session_id"] as? String, !id.isEmpty else {
            throw AgentToolError.invalidArguments("session_id is required")
        }
        guard let message = args["message"] as? String, !message.isEmpty else {
            throw AgentToolError.invalidArguments("message is required")
        }
        try manager.appendUserMessage(subSessionId: id, text: message)
        return "queued message on session \(id) (\(message.count) chars)"
    }
}

nonisolated struct SessionsListTool: AgentTool {
    let name = "sessions_list"
    private let manager: SubAgentSessionManager

    init(manager: SubAgentSessionManager) {
        self.manager = manager
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: "List sub-agent sessions under the current parent session.",
            parameters: [
                "type": "object",
                "properties": [:] as [String: Any],
            ]
        )
    }

    func invoke(arguments: String, context: AgentRunContext) async throws -> String {
        _ = try ToolJSON.object(from: arguments)
        let sessions = try manager.list(parentSessionId: context.sessionId)
        if sessions.isEmpty { return "(no sub-agents)" }
        return sessions.map { "- \($0.id): \($0.title)" }.joined(separator: "\n")
    }
}

nonisolated struct SessionsHistoryTool: AgentTool {
    let name = "sessions_history"
    private let manager: SubAgentSessionManager

    init(manager: SubAgentSessionManager) {
        self.manager = manager
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Return recent conversation messages for a sub-agent session.",
            parameters: [
                "type": "object",
                "properties": [
                    "session_id": ["type": "string"] as [String: Any],
                    "max_messages": ["type": "integer"] as [String: Any],
                ] as [String: Any],
                "required": ["session_id"],
            ]
        )
    }

    func invoke(arguments: String, context: AgentRunContext) async throws -> String {
        _ = context
        let args = try ToolJSON.object(from: arguments)
        guard let id = args["session_id"] as? String, !id.isEmpty else {
            throw AgentToolError.invalidArguments("session_id is required")
        }
        let maxMessages = max(1, (args["max_messages"] as? Int) ?? 40)
        let messages = try manager.history(subSessionId: id, maxMessages: maxMessages)
        if messages.isEmpty { return "(empty)" }
        return messages.map { msg in
            "[\(msg.role.rawValue)] \(String(msg.content.prefix(400)))"
        }.joined(separator: "\n")
    }
}
