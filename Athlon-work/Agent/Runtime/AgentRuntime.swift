import Foundation

/// Core agent turn loop: persist user message, stream model, invoke tools serially, finish.
nonisolated final class AgentRuntime: @unchecked Sendable {
    private let storage: FileStorageService
    private let modelClient: AgentModelClient
    private let router: ToolRouter
    private let pipeline: ToolInvocationPipeline
    private let coordinator: AgentTurnCoordinator
    private let middleware: [any TurnMiddleware]
    private let settingsProvider: @Sendable () -> AppSettings

    init(
        storage: FileStorageService,
        modelClient: AgentModelClient,
        router: ToolRouter,
        pipeline: ToolInvocationPipeline,
        middleware: [any TurnMiddleware] = [],
        settingsProvider: @escaping @Sendable () -> AppSettings
    ) {
        self.storage = storage
        self.modelClient = modelClient
        self.router = router
        self.pipeline = pipeline
        self.coordinator = AgentTurnCoordinator(modelClient: modelClient)
        self.middleware = middleware
        self.settingsProvider = settingsProvider
    }

    @discardableResult
    func runTurn(
        sessionId: String,
        userText: String,
        workspaceRoot: String? = nil,
        imageAttachments: [ImageAttachment] = [],
        callbacks: AgentTurnCallbacks = AgentTurnCallbacks()
    ) async throws -> AgentSession {
        try Task.checkCancellation()
        let settings = settingsProvider()

        guard var session = try storage.loadSession(id: sessionId) else {
            throw AgentRuntimeError.sessionNotFound(sessionId)
        }

        let root = workspaceRoot
            ?? session.activeWorkspace
            ?? settings.workspaces.first?.rootPath
            ?? FileManager.default.currentDirectoryPath

        var ignore = settings.workspaceIgnore.directoryNames
        if let ws = settings.workspaces.first(where: { $0.rootPath == root || $0.id == session.activeWorkspaceId }) {
            ignore.append(contentsOf: ws.ignorePatterns)
        }

        var context = AgentRunContext(
            sessionId: sessionId,
            workspaceRoot: root,
            ignorePatterns: ignore,
            settings: settings
        )

        let userMessage = ChatMessage(
            role: .user,
            content: userText,
            imageAttachments: imageAttachments.isEmpty ? nil : imageAttachments
        )
        try storage.appendConversationMessage(sessionId: sessionId, message: userMessage)

        var messages = try storage.loadConversationMessages(sessionId: sessionId)
        session.messages = messages
        session.activeWorkspace = root
        session.updatedAt = Date()
        try storage.saveSession(session)

        for mw in middleware {
            try await mw.onTurnStarting(sessionId: sessionId, messages: messages, context: context)
        }

        let runId = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        callbacks.onStreamEvent(.runStarted(sessionId: sessionId, runId: runId))

        let toolDefs = router.tools.map(\.definition)
        let systemPrompt = SystemPromptBuilder.build(
            workspaceRoot: root,
            tools: toolDefs,
            settings: settings
        )
        let toolSchemas = router.openAIToolSchemas()
        let maxRounds = AgentTurnCoordinator.resolveMaxRounds(settings)

        var round = 0
        var usageSnapshot = SessionUsageSnapshot.empty

        do {
            while true {
                try Task.checkCancellation()
                round += 1
                if round > maxRounds {
                    throw AgentRuntimeError.maxToolRoundsExceeded(maxRounds)
                }

                for mw in middleware {
                    try await mw.onBeforeModelRound(round: round, messages: &messages, context: context)
                }

                let apiMessages = ModelMessagesForApiBuilder.build(
                    systemPrompt: systemPrompt,
                    messages: messages,
                    includeReasoning: settings.contextCompaction.includeReasoningInModelContext
                )

                let adapter = AgentStreamAdapter()
                let completion = try await coordinator.callModel(
                    messages: apiMessages,
                    tools: toolSchemas.isEmpty ? nil : toolSchemas,
                    settings: settings.model,
                    onDelta: { delta in
                        for event in adapter.events(for: delta) {
                            callbacks.onStreamEvent(event)
                        }
                    }
                )
                for event in adapter.finishEvents() {
                    callbacks.onStreamEvent(event)
                }

                usageSnapshot.promptTokens += completion.usage.promptTokens
                usageSnapshot.completionTokens += completion.usage.completionTokens
                usageSnapshot.totalTokens += completion.usage.totalTokens
                usageSnapshot.turnCount += 1
                usageSnapshot.lastUpdatedAt = Date()
                callbacks.onStreamEvent(.usageRecorded(usageSnapshot))

                let toolCalls = completion.toolCalls.map {
                    ToolCall(id: $0.id, name: $0.name, arguments: $0.arguments)
                }

                let assistant = ChatMessage(
                    id: adapter.assistantMessageId,
                    role: .assistant,
                    content: completion.content,
                    toolCalls: toolCalls.isEmpty ? nil : toolCalls,
                    reasoning: completion.reasoning.isEmpty ? nil : completion.reasoning
                )
                try storage.appendConversationMessage(sessionId: sessionId, message: assistant)
                messages.append(assistant)
                callbacks.onStreamEvent(.chatMessageAppended(assistant))

                if toolCalls.isEmpty {
                    break
                }

                // Invoke tools serially, then continue the model loop.
                for call in toolCalls {
                    try Task.checkCancellation()
                    let result = try await pipeline.invoke(call: call, context: context, callbacks: callbacks)
                    let toolMessage = ChatMessage(
                        role: .tool,
                        content: result.output,
                        toolCallId: call.id
                    )
                    try storage.appendConversationMessage(sessionId: sessionId, message: toolMessage)
                    messages.append(toolMessage)
                    callbacks.onStreamEvent(.chatMessageAppended(toolMessage))
                }

                // Refresh settings/context each round in case permissions changed.
                context.settings = settingsProvider()
            }
        } catch is CancellationError {
            callbacks.onStreamEvent(.runFinished(sessionId: sessionId, runId: runId))
            throw CancellationError()
        } catch {
            callbacks.onStreamEvent(.runFinished(sessionId: sessionId, runId: runId))
            throw error
        }

        for mw in middleware {
            try await mw.onTurnCompleted(sessionId: sessionId, messages: messages, context: context)
        }

        session.messages = messages
        session.updatedAt = Date()
        if session.title == "New chat", let first = messages.first(where: { $0.role == .user }) {
            session.title = String(first.content.prefix(48))
        }
        try storage.saveSession(session)
        callbacks.onStreamEvent(.runFinished(sessionId: sessionId, runId: runId))
        return session
    }
}
