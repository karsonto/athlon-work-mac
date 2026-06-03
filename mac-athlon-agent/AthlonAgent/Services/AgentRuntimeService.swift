import Foundation
import Combine

// MARK: - Tool Definition

struct ToolDefinition {
    let name: String
    let description: String
    let parameters: [String: Any]?
    let source: String?

    init(name: String, description: String, parameters: [String: Any]?, source: String? = "native") {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.source = source
    }

    var dictionary: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": parameters ?? [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
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

// MARK: - Agent Runtime Service

/// UI-facing facade that delegates to `AgentRuntime` for the full tool loop.
@MainActor
final class AgentRuntimeService: ObservableObject {
    @Published var isRunning = false
    @Published var isStreaming = false
    @Published var error: String?
    @Published var currentReasoning: String = ""
    @Published var currentToolCalls: [AgentToolCall] = []

    private var settings: AppSettings
    private var runtime: AgentRuntime?
    private var activeTask: Task<Void, Never>?

    private weak var workspaceService: WorkspaceService?
    private weak var skillService: SkillService?
    private weak var sessionManager: SessionManager?
    private weak var mcpClientService: McpClientService?
    private weak var executeCommandRegistry: ExecuteCommandProcessRegistry?
    private weak var planNotebook: PlanNotebook?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func configureDependencies(
        workspaceService: WorkspaceService,
        skillService: SkillService,
        sessionManager: SessionManager,
        mcpClientService: McpClientService,
        executeCommandRegistry: ExecuteCommandProcessRegistry,
        planNotebook: PlanNotebook
    ) {
        self.workspaceService = workspaceService
        self.skillService = skillService
        self.sessionManager = sessionManager
        self.mcpClientService = mcpClientService
        self.executeCommandRegistry = executeCommandRegistry
        self.planNotebook = planNotebook
    }

    func reconfigure(settings: AppSettings) {
        self.settings = settings
        runtime = nil
    }

    func stop() {
        activeTask?.cancel()
        activeTask = nil
        isRunning = false
        isStreaming = false
    }

    func sendTurn(
        session: AgentSession,
        streamingAssistantId: String,
        onSessionUpdated: @escaping (AgentSession) -> Void,
        onMessage: @escaping (ChatMessage) -> Void,
        onToolStarted: @escaping (AgentToolCall) -> Void,
        onStreamingAssistantTarget: @escaping (String) -> Void,
        onStreamingAssistantUpdate: @escaping (_ messageId: String, _ content: String, _ reasoning: String) -> Void,
        completion: @escaping (Result<AgentSession, Error>) -> Void
    ) {
        guard !isRunning else {
            error = "已有运行中的对话"
            return
        }
        guard let workspaceService, let skillService, let sessionManager else {
            error = "Agent 依赖未配置"
            completion(.failure(NSError(domain: "Athlon", code: -10, userInfo: [
                NSLocalizedDescriptionKey: "Agent 依赖未配置"
            ])))
            return
        }

        isRunning = true
        isStreaming = true
        error = nil
        currentReasoning = ""
        currentToolCalls = []

        let sessionContext = DefaultAgentSessionContext(sessionId: session.id)
        let sessionWorkspace = session.activeWorkspace?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveSessionWorkspace = (sessionWorkspace?.isEmpty == false)
            ? sessionWorkspace
            : workspaceService.rootPath
        let toolRouter = BuiltInTools.makeAll(
            workspaceService: workspaceService,
            settings: settings,
            skillService: skillService,
            sessionContext: sessionContext,
            sessionManager: sessionManager,
            mcpRegistry: mcpClientService!.registryProvider,
            sessionWorkspacePath: effectiveSessionWorkspace,
            executeCommandRegistry: executeCommandRegistry,
            planNotebook: planNotebook
        )

        let agentRuntime = runtime ?? AgentRuntime.makeDefault(
            settings: settings,
            toolRouter: toolRouter,
            skillsProvider: { [weak skillService, weak self] in
                guard let skillService, let self else { return [] }
                return skillService.availableSkillInfos(settings: self.settings)
            }
        )
        runtime = agentRuntime

        var streamingAssistantId: String? = streamingAssistantId
        var streamingContent = ""
        var streamingReasoning = ""

        activeTask = Task {
            do {
                let callbacks = AgentTurnCallbacks(
                    onSessionUpdated: { updated in
                        await MainActor.run { onSessionUpdated(updated) }
                    },
                    onMessage: { message in
                        await MainActor.run {
                            onMessage(message)
                            // Persisted assistant rows are synced via AppState; do not repoint or
                            // re-stream from `onMessage` (that raced with tool sealing and caused
                            // content to land on a different message id than the active stream target).
                        }
                    },
                    onToolStarted: { toolCall in
                        await MainActor.run {
                            self.currentToolCalls.append(toolCall)
                            onToolStarted(toolCall)
                        }
                    },
                    onStreamingAssistantTarget: { id in
                        await MainActor.run {
                            streamingAssistantId = id
                            // Fresh buffers per model iteration; UI merges segments onto one bubble after tools.
                            streamingContent = ""
                            streamingReasoning = ""
                            onStreamingAssistantTarget(id)
                        }
                    },
                    onAssistantTextDelta: { delta in
                        await MainActor.run {
                            let merged = Self.mergeStreamingSnapshot(
                                current: streamingContent,
                                incoming: delta
                            )
                            guard merged != streamingContent else { return }
                            streamingContent = merged
                            if let id = streamingAssistantId {
                                onStreamingAssistantUpdate(id, streamingContent, streamingReasoning)
                            }
                        }
                    },
                    onAssistantReasoningDelta: { delta in
                        await MainActor.run {
                            let merged = Self.mergeStreamingSnapshot(
                                current: streamingReasoning,
                                incoming: delta
                            )
                            guard merged != streamingReasoning else { return }
                            streamingReasoning = merged
                            self.currentReasoning = streamingReasoning
                            if let id = streamingAssistantId {
                                onStreamingAssistantUpdate(id, streamingContent, streamingReasoning)
                            }
                        }
                    },
                    onAssistantToolCallDelta: { _ in }
                )

                let updated = try await agentRuntime.sendAsync(
                    session: session,
                    assistantMessageId: streamingAssistantId,
                    callbacks: callbacks
                )

                await MainActor.run {
                    self.isRunning = false
                    self.isStreaming = false
                    completion(.success(updated))
                }
            } catch {
                await MainActor.run {
                    self.isRunning = false
                    self.isStreaming = false
                    if Self.isCancellationError(error) {
                        completion(.failure(CancellationError()))
                    } else {
                        self.error = error.localizedDescription
                        completion(.failure(error))
                    }
                }
            }
        }
    }

    private static func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }
        if ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError { return true }
        return false
    }

    /// Providers may send token deltas or full cumulative snapshots; never double-append snapshots.
    private static func mergeStreamingSnapshot(current: String, incoming: String) -> String {
        guard !incoming.isEmpty else { return current }
        if current.isEmpty { return incoming }
        if incoming == current { return current }
        if incoming.hasPrefix(current) { return incoming }
        if current.hasPrefix(incoming) { return current }
        return current + incoming
    }
}
