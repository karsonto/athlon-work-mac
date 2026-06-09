import Foundation

final class SubAgentTool: AgentTool, ExcludedFromChildAgentToolkit {
    let name: String
    let description: String
    let parametersSchema: [String: String]

    private let settings: AppSettings
    private let storage: FileStorageService
    private let sessionStore: SubAgentSessionStore
    private let childToolRouter: ChildAgentToolRouter
    private let subAgentPromptOrchestrator: SubAgentSystemPromptOrchestrator
    private let activeSessionContext: ActiveAgentSessionContext
    private weak var turnExecutor: SubAgentTurnExecuting?

    init(
        settings: AppSettings,
        storage: FileStorageService,
        sessionStore: SubAgentSessionStore,
        childToolRouter: ChildAgentToolRouter,
        subAgentPromptOrchestrator: SubAgentSystemPromptOrchestrator,
        activeSessionContext: ActiveAgentSessionContext,
        turnExecutor: SubAgentTurnExecuting?
    ) {
        let subAgent = settings.subAgent
        self.settings = settings
        self.storage = storage
        self.sessionStore = sessionStore
        self.childToolRouter = childToolRouter
        self.subAgentPromptOrchestrator = subAgentPromptOrchestrator
        self.activeSessionContext = activeSessionContext
        self.turnExecutor = turnExecutor
        self.name = subAgent.toolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "call_assistant"
            : subAgent.toolName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.description = subAgent.description
        self.parametersSchema = [
            "role": "Who the child agent is: responsibilities, boundaries, and output style. Required for a new session_id; optional when continuing (updates saved role).",
            "message": "Task instruction for this sub-agent turn.",
            "session_id": "Optional. Omit to start a new sub-session; pass the id from a prior result to continue."
        ]
    }

    func bindTurnExecutor(_ executor: SubAgentTurnExecuting) {
        turnExecutor = executor
    }

    func invoke(arguments: [String: String]) async throws -> String {
        let subAgent = settings.subAgent
        guard subAgent.enabled else {
            throw ToolError.failed("Sub-agent disabled", detail: "Sub-agent tool is disabled in settings.")
        }

        guard let parentSessionId = activeSessionContext.sessionId,
              !parentSessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolError.failed("No parent session", detail: "call_assistant requires an active parent agent session.")
        }

        if subAgent.maxNestingDepth > 0,
           SubAgentExecutionScope.currentDepth >= subAgent.maxNestingDepth {
            throw ToolError.failed(
                "Nesting limit",
                detail: "Sub-agent nesting depth limit (\(subAgent.maxNestingDepth)) reached."
            )
        }

        guard let message = arguments["message"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            throw ToolError.failed("Missing message", detail: "Required parameter: message")
        }

        let sessionIdArg = arguments["session_id"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let roleArg = arguments["role"]?.trimmingCharacters(in: .whitespacesAndNewlines)

        let subSessionId: String
        if let sessionIdArg, !sessionIdArg.isEmpty {
            subSessionId = sessionIdArg
        } else {
            subSessionId = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }

        var bundle: SubAgentSessionBundle?
        if let sessionIdArg, !sessionIdArg.isEmpty {
            bundle = try await sessionStore.load(parentSessionId: parentSessionId, subSessionId: subSessionId)
            if bundle == nil {
                throw ToolError.failed(
                    "Unknown session_id",
                    detail: "No sub-agent session '\(subSessionId)' for this parent."
                )
            }
        }

        let role = resolveRole(bundle: bundle, roleArg: roleArg)
        guard !role.isEmpty else {
            throw ToolError.failed(
                "Missing role",
                detail: "Provide role when starting a new sub-agent session, or pass session_id for an existing session with saved role."
            )
        }

        let session: AgentSession
        if let existing = bundle?.session {
            session = existing
        } else {
            session = createSubSession(parentSessionId: parentSessionId, subSessionId: subSessionId)
        }
        bundle = SubAgentSessionBundle(session: session, role: role)

        guard let turnExecutor else {
            throw ToolError.failed("Sub-agent unavailable", detail: "Sub-agent turn executor is not configured.")
        }

        let childComposite = childToolRouter.asCompositeRouter()

        return try await SubAgentExecutionScope.withDepth {
            try await AmbientToolRouterScope.withRouter(childComposite) {
                                try await AmbientSystemPromptOrchestratorScope.withOrchestrator(
                                    subAgentPromptOrchestrator
                                ) {
                    try await AmbientSubAgentRoleScope.withRole(role) {
                        try await AmbientSubAgentStorageScope.withStorage(
                            parentSessionId: parentSessionId,
                            subSessionId: subSessionId
                        ) {
                            try await AgentLoopOptionsScope.withValue(
                                AgentLoopOptions(maxModelToolRounds: subAgent.maxToolRounds)
                            ) {
                                try await activeSessionContext.withSession(subSessionId) {
                                    let updated = try await turnExecutor.executeSubTurn(
                                        session: session,
                                        userInput: message
                                    )
                                    bundle = SubAgentSessionBundle(session: updated, role: role)
                                    try await sessionStore.save(
                                        parentSessionId: parentSessionId,
                                        subSessionId: subSessionId,
                                        bundle: bundle!
                                    )
                                    let responseText = extractLastAssistantText(updated)
                                        ?? "(Sub-agent finished without assistant text.)"
                                    let content = "session_id: \(subSessionId)\n\n\(responseText)"
                                    return ToolResultFormatter.success(
                                        "Sub-agent completed (session_id=\(subSessionId))",
                                        content: content
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func resolveRole(bundle: SubAgentSessionBundle?, roleArg: String?) -> String {
        if let roleArg, !roleArg.isEmpty { return roleArg }
        return bundle?.role.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func createSubSession(parentSessionId: String, subSessionId: String) -> AgentSession {
        let parent = try? storage.loadSession(parentSessionId)
        let now = Date()
        return AgentSession(
            id: subSessionId,
            title: "Sub-agent",
            messages: [],
            createdAt: now,
            updatedAt: now,
            isActive: false,
            isRunning: false,
            queuedTurnCount: 0,
            activeWorkspace: parent?.activeWorkspace,
            workspaceName: parent?.workspaceName
        )
    }

    private func extractLastAssistantText(_ session: AgentSession) -> String? {
        for message in session.messages.reversed() where message.role == .assistant {
            let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return message.content }
        }
        return nil
    }
}
