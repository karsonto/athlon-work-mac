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

    private var turnStreamAssistantId: String?
    private var turnStreamContent = ""
    private var turnStreamReasoning = ""

    private let workspaceService: WorkspaceService
    private let skillService: SkillService
    private let sessionManager: SessionManager
    private let mcpClientService: McpClientService
    private let executeCommandRegistry: ExecuteCommandProcessRegistry
    private let longTermMemory: ILongTermMemory?
    private let postTurnMemoryProcessor: IPostTurnMemoryProcessor?
    private let subAgentTurnRunner = SubAgentTurnRunner()
    private let activeSessionContext = DefaultActiveAgentSessionContext()
    private let subAgentSessionStore = FileSubAgentSessionStore()
    private let fileStorage = FileStorageService()

    init(
        settings: AppSettings,
        workspaceService: WorkspaceService,
        skillService: SkillService,
        sessionManager: SessionManager,
        mcpClientService: McpClientService,
        executeCommandRegistry: ExecuteCommandProcessRegistry,
        longTermMemory: ILongTermMemory? = nil,
        postTurnMemoryProcessor: IPostTurnMemoryProcessor? = nil
    ) {
        self.settings = settings
        self.workspaceService = workspaceService
        self.skillService = skillService
        self.sessionManager = sessionManager
        self.mcpClientService = mcpClientService
        self.executeCommandRegistry = executeCommandRegistry
        self.longTermMemory = longTermMemory
        self.postTurnMemoryProcessor = postTurnMemoryProcessor
    }

    func reconfigure(settings: AppSettings) {
        stop()
        self.settings = settings
        runtime = nil
    }

    func stop() {
        activeTask?.cancel()
        activeTask = nil
        isRunning = false
        isStreaming = false
        turnStreamAssistantId = nil
        turnStreamContent = ""
        turnStreamReasoning = ""
    }

    func sendTurn(
        session: AgentSession,
        onSessionUpdated: @escaping (AgentSession) -> Void,
        onMessage: @escaping (ChatMessage) -> Void,
        onToolStarted: @escaping (AgentToolCall) -> Void,
        onPreparingModelRequest: @escaping (String) -> Void = { _ in },
        onStreamingAssistantTarget: @escaping (String) -> Void,
        onStreamingAssistantUpdate: @escaping (_ messageId: String, _ content: String, _ reasoning: String) -> Void,
        onStreamEvent: @escaping (AgentStreamEvent) -> Void = { _ in },
        completion: @escaping (Result<AgentSession, Error>) -> Void
    ) {
        if isRunning {
            stop()
        }

        isRunning = true
        isStreaming = true
        error = nil
        currentReasoning = ""
        currentToolCalls = []
        turnStreamAssistantId = nil
        turnStreamContent = ""
        turnStreamReasoning = ""

        let settingsSnapshot = settings
        let sessionSnapshot = session

        AgentFileLogger.log(
            "sendTurn start session=\(session.id.prefix(8))",
            category: "Turn"
        )

        // Network + tool loop off MainActor; UI callbacks hop back explicitly.
        activeTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                guard let self else {
                    await MainActor.run {
                        completion(.failure(CancellationError()))
                    }
                    return
                }

                let built = await MainActor.run {
                    self.activeSessionContext.setSession(sessionSnapshot.id)
                    let sessionWorkspace = sessionSnapshot.activeWorkspace?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let effectiveSessionWorkspace = (sessionWorkspace?.isEmpty == false)
                        ? sessionWorkspace
                        : self.workspaceService.rootPath
                    let subAgentPrompt = SubAgentSystemPromptOrchestrator(
                        settings: settingsSnapshot,
                        skillsProvider: { [weak skillService = self.skillService, weak self] in
                            guard let skillService, let self else { return [] }
                            return skillService.availableSkillInfos(settings: self.settings)
                        },
                        longTermMemory: self.longTermMemory
                    )
                    return BuiltInTools.makeAll(
                        workspaceService: self.workspaceService,
                        settings: settingsSnapshot,
                        skillService: self.skillService,
                        sessionManager: self.sessionManager,
                        mcpRegistry: self.mcpClientService.registryProvider,
                        sessionWorkspacePath: effectiveSessionWorkspace,
                        executeCommandRegistry: self.executeCommandRegistry,
                        longTermMemory: self.longTermMemory,
                        subAgentTurnRunner: self.subAgentTurnRunner,
                        activeSessionContext: self.activeSessionContext,
                        storage: self.fileStorage,
                        subAgentSessionStore: self.subAgentSessionStore,
                        subAgentPromptOrchestrator: subAgentPrompt
                    )
                }

                let agentRuntime = await MainActor.run { () -> AgentRuntime in
                    // Rebuild each turn so tool permission toggles apply without restarting the app.
                    let runtime = AgentRuntime.makeDefault(
                        settings: settingsSnapshot,
                        toolRouter: built.router,
                        skillsProvider: { [weak skillService = self.skillService, weak self] in
                            guard let skillService, let self else { return [] }
                            return skillService.availableSkillInfos(settings: self.settings)
                        },
                        longTermMemory: self.longTermMemory,
                        postTurnMemoryProcessor: self.postTurnMemoryProcessor
                    )
                    self.runtime = runtime
                    self.subAgentTurnRunner.configure { runtime }
                    built.subAgentTool?.bindTurnExecutor(self.subAgentTurnRunner)
                    return runtime
                }

                let callbacks = AgentTurnCallbacks(
                    onSessionUpdated: { updated in
                        await MainActor.run { onSessionUpdated(updated) }
                    },
                    onMessage: { message in
                        await MainActor.run { onMessage(message) }
                    },
                    onToolStarted: { toolCall in
                        await MainActor.run { [weak self] in
                            self?.currentToolCalls.append(toolCall)
                            onToolStarted(toolCall)
                        }
                    },
                    onStreamEvent: { [weak self] event in
                        guard let self else { return }
                        // Do not block the SSE reader on MainActor UI work (DeepSeek + large tool context).
                        Task { @MainActor in
                            self.dispatchStreamEvent(
                                event,
                                onStreamingAssistantTarget: onStreamingAssistantTarget,
                                onStreamingAssistantUpdate: onStreamingAssistantUpdate,
                                onStreamEvent: onStreamEvent
                            )
                        }
                    },
                    onStreamingAssistantTarget: { id in
                        await MainActor.run { [weak self] in
                            self?.turnStreamAssistantId = id
                            onStreamingAssistantTarget(id)
                        }
                    },
                    onPreparingModelRequest: { id in
                        await MainActor.run {
                            onPreparingModelRequest(id)
                        }
                    },
                    onAssistantTextDelta: { _ in },
                    onAssistantReasoningDelta: { _ in },
                    onAssistantToolCallDelta: { _ in }
                )

                AgentFileLogger.log("sendAsync begin session=\(sessionSnapshot.id.prefix(8))", category: "Turn")

                let updated = try await agentRuntime.sendAsync(
                    session: sessionSnapshot,
                    callbacks: callbacks
                )

                await MainActor.run { [weak self] in
                    guard let self else {
                        completion(.failure(CancellationError()))
                        return
                    }
                    self.isRunning = false
                    self.isStreaming = false
                    AgentFileLogger.log("sendTurn success session=\(sessionSnapshot.id.prefix(8))", category: "Turn")
                    completion(.success(updated))
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else {
                        completion(.failure(error))
                        return
                    }
                    self.isRunning = false
                    self.isStreaming = false
                    if Self.isCancellationError(error) {
                        AgentFileLogger.log("sendTurn cancelled session=\(sessionSnapshot.id.prefix(8))", category: "Turn")
                        completion(.failure(CancellationError()))
                    } else {
                        AgentFileLogger.log(
                            "sendTurn failed session=\(sessionSnapshot.id.prefix(8)) error=\(error.localizedDescription)",
                            category: "Turn"
                        )
                        self.error = error.localizedDescription
                        completion(.failure(error))
                    }
                }
            }
        }
    }

    @MainActor
    private func dispatchStreamEvent(
        _ event: AgentStreamEvent,
        onStreamingAssistantTarget: @escaping (String) -> Void,
        onStreamingAssistantUpdate: @escaping (_ messageId: String, _ content: String, _ reasoning: String) -> Void,
        onStreamEvent: @escaping (AgentStreamEvent) -> Void
    ) {
        onStreamEvent(event)

        switch event {
        case .textMessageStart(let messageId, _):
            turnStreamAssistantId = messageId
            turnStreamContent = ""
        case .reasoningMessageStart(let messageId, _):
            turnStreamAssistantId = messageId
            turnStreamReasoning = ""
        case .textMessageContent(_, let delta):
            turnStreamContent = Self.mergeStreamingSnapshot(current: turnStreamContent, incoming: delta)
            if let id = turnStreamAssistantId {
                onStreamingAssistantUpdate(id, turnStreamContent, turnStreamReasoning)
            }
        case .reasoningMessageContent(_, let delta):
            turnStreamReasoning = Self.mergeStreamingSnapshot(current: turnStreamReasoning, incoming: delta)
            currentReasoning = turnStreamReasoning
            if let id = turnStreamAssistantId {
                onStreamingAssistantUpdate(id, turnStreamContent, turnStreamReasoning)
            }
        default:
            break
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
