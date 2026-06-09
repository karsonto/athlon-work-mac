import Foundation

struct AgentTurnCallbacks {
    var onSessionUpdated: (@Sendable (AgentSession) async -> Void)?
    var onMessage: (@Sendable (ChatMessage) async -> Void)?
    var onToolStarted: (@Sendable (AgentToolCall) async -> Void)?
    var onStreamEvent: (@Sendable (AgentStreamEvent) async -> Void)?
    /// Fired before each model completion so UI streaming targets the correct assistant message id.
    var onStreamingAssistantTarget: (@Sendable (String) async -> Void)?
    var onAssistantTextDelta: (@Sendable (String) async -> Void)?
    var onAssistantReasoningDelta: (@Sendable (String) async -> Void)?
    var onAssistantToolCallDelta: (@Sendable (StreamingToolCallDelta) async -> Void)?
}

/// Core agent loop ported from WPF `AgentRuntime.cs`.
final class AgentRuntime: @unchecked Sendable {
    private let modelClient: AgentChatModelClient
    private let storage: FileStorageService
    private let toolRouter: CompositeToolRouter
    private let systemPromptOrchestrator: SystemPromptOrchestrator
    private let preCompletionPipeline: PreCompletionPipeline
    private let toolResultEvictor: ToolResultEvictor
    private let tokenEstimatorCalibrator: TokenEstimatorCalibrating
    private let settings: AppSettings
    private let skillsProvider: () -> [AvailableSkillInfo]
    private let longTermMemory: ILongTermMemory?
    private let postTurnMemoryProcessor: IPostTurnMemoryProcessor?

    init(
        settings: AppSettings,
        modelClient: AgentChatModelClient,
        storage: FileStorageService,
        toolRouter: CompositeToolRouter,
        systemPromptOrchestrator: SystemPromptOrchestrator,
        preCompletionPipeline: PreCompletionPipeline,
        toolResultEvictor: ToolResultEvictor,
        tokenEstimatorCalibrator: TokenEstimatorCalibrating,
        skillsProvider: @escaping () -> [AvailableSkillInfo],
        longTermMemory: ILongTermMemory? = nil,
        postTurnMemoryProcessor: IPostTurnMemoryProcessor? = nil
    ) {
        self.settings = settings
        self.modelClient = modelClient
        self.storage = storage
        self.toolRouter = toolRouter
        self.systemPromptOrchestrator = systemPromptOrchestrator
        self.preCompletionPipeline = preCompletionPipeline
        self.toolResultEvictor = toolResultEvictor
        self.tokenEstimatorCalibrator = tokenEstimatorCalibrator
        self.skillsProvider = skillsProvider
        self.longTermMemory = longTermMemory
        self.postTurnMemoryProcessor = postTurnMemoryProcessor
    }

    static func makeDefault(
        settings: AppSettings,
        toolRouter: CompositeToolRouter,
        skillsProvider: @escaping () -> [AvailableSkillInfo],
        longTermMemory: ILongTermMemory? = nil,
        postTurnMemoryProcessor: IPostTurnMemoryProcessor? = nil
    ) -> AgentRuntime {
        let storage = FileStorageService()
        let modelClient = OpenAiChatModelClient(settings: settings)
        let compactor = ConversationCompactor(
            settings: settings.contextCompaction,
            modelClient: modelClient,
            storage: storage
        )
        let calibrator = TokenEstimatorCalibrator(settings: settings)
        let pipeline = PreCompletionPipeline(
            conversationCompactor: compactor,
            settings: settings.contextCompaction
        )
        let evictor = ToolResultEvictor(settings: settings.contextCompaction, storage: storage)
        var orchestrator = SystemPromptOrchestrator(
            settings: settings,
            sections: [
                SubAgentDelegationSection(settings: settings),
                SubAgentPersonaSection(),
                EncodingPolicySection(),
                WorkspaceFilesSection(),
                SkillsSection(skillsProvider: skillsProvider)
            ]
        )
        if let longTermMemory {
            orchestrator.postProcessPrompt = { prompt in
                _ = await MemoryPromptContributor(longTermMemory: longTermMemory).append(to: &prompt)
            }
        }
        return AgentRuntime(
            settings: settings,
            modelClient: modelClient,
            storage: storage,
            toolRouter: toolRouter,
            systemPromptOrchestrator: orchestrator,
            preCompletionPipeline: pipeline,
            toolResultEvictor: evictor,
            tokenEstimatorCalibrator: calibrator,
            skillsProvider: skillsProvider,
            longTermMemory: longTermMemory,
            postTurnMemoryProcessor: postTurnMemoryProcessor
        )
    }

    func sendAsync(
        session: AgentSession,
        assistantMessageId: String? = nil,
        callbacks: AgentTurnCallbacks? = nil
    ) async throws -> AgentSession {
        guard let userMessage = session.messages.last(where: { $0.role == .user }) else {
            throw NSError(domain: "Athlon", code: -11, userInfo: [
                NSLocalizedDescriptionKey: "No user message in session"
            ])
        }

        var workingSession = session

        let activeRouter = resolveToolRouter()
        let activePrompt = resolvePromptOrchestrator()
        let tools = await activeRouter.listToolDefinitions()
        let frozenPrompt = activePrompt.prepareForTurn(
            session: workingSession,
            tools: tools
        )

        var modelToolRound = 0
        let maxModelToolRounds = AgentLoopOptionsScope.current?.maxModelToolRounds

        /// One assistant message id for the entire user turn (WPF: single streaming assistant per turn).
        let turnAssistantId: String = {
            if let assistantMessageId, !assistantMessageId.isEmpty { return assistantMessageId }
            return UUID().uuidString
        }()

        let runId = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let streamAdapter = AgentStreamAdapter(sessionId: workingSession.id, runId: runId)
        await publishStreamEvents(callbacks, streamAdapter.createRunStarted())

        if Self.shouldListWorkspaceFiles(userMessage.content),
           tools.contains(where: { $0.name.caseInsensitiveCompare("file_list") == .orderedSame }) {
            let toolCall = AgentToolCall(
                id: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
                name: "file_list",
                arguments: "{}",
                argumentsStreaming: "",
                status: .preparing
            )
            if let onToolStarted = callbacks?.onToolStarted {
                await onToolStarted(toolCall)
            }
            workingSession = try await invokeToolAndPersist(
                session: workingSession,
                parentMessageId: userMessage.id,
                toolCall: toolCall,
                streamAdapter: streamAdapter,
                callbacks: callbacks
            )
        }

        while true {
            try Task.checkCancellation()

            var environmentPrompt = await activePrompt.buildForReasoningIteration(
                frozen: frozenPrompt,
                session: workingSession,
                tools: tools
            )
            workingSession = await runPreCompletionPipeline(
                session: workingSession,
                callbacks: callbacks,
                options: .agentLoop,
                environmentPrompt: environmentPrompt,
                tools: tools
            )
            environmentPrompt = await activePrompt.buildForReasoningIteration(
                frozen: frozenPrompt,
                session: workingSession,
                tools: tools
            )

            if let onTarget = callbacks?.onStreamingAssistantTarget {
                await onTarget(turnAssistantId)
            }

            let modelMessages = Self.buildModelMessages(
                environmentPrompt: environmentPrompt,
                history: workingSession.messages,
                includeReasoningInModelContext: Self.shouldIncludeReasoningInModelContext(settings: settings)
            )

            let completion = try await completeWithOverflowRetry(
                session: workingSession,
                callbacks: callbacks,
                streamAdapter: streamAdapter,
                assistantMessageId: turnAssistantId,
                modelMessages: modelMessages,
                tools: tools,
                frozenPrompt: frozenPrompt,
                environmentPrompt: environmentPrompt
            )
            workingSession = completion.session
            let response = completion.response

            if response.toolCalls.isEmpty {
                if !streamAdapter.state.hasStartedTextMessage(turnAssistantId),
                   !response.content.isEmpty {
                    await publishStreamEvents(
                        callbacks,
                        streamAdapter.onTextDelta(messageId: turnAssistantId, delta: response.content)
                    )
                }
                if !streamAdapter.state.hasStartedReasoningMessage(turnAssistantId),
                   let reasoning = response.reasoningContent,
                   !reasoning.isEmpty {
                    await publishStreamEvents(
                        callbacks,
                        streamAdapter.onReasoningDelta(messageId: turnAssistantId, delta: reasoning)
                    )
                }
                let assistant = ChatMessage(
                    id: turnAssistantId,
                    role: .assistant,
                    content: response.content,
                    reasoningContent: response.reasoningContent ?? "",
                    parentMessageId: userMessage.id
                )
                workingSession = workingSession.withMessage(assistant)
                await persistMessage(session: workingSession, message: assistant)
                if let onMessage = callbacks?.onMessage {
                    await onMessage(assistant)
                }
                await publishStreamEvents(callbacks, streamAdapter.finishRun())
                try? await storage.saveSession(workingSession)
                // Fire-and-forget: flush turn messages to daily memory ledger
                if let processor = postTurnMemoryProcessor {
                    Task {
                        let recentCount = min(workingSession.messages.count, 20)
                        let turnMessages = Array(workingSession.messages.suffix(recentCount))
                        _ = try? await processor.processTurn(messages: turnMessages)
                    }
                }
                return workingSession
            }

            let assistantWithToolCalls = ChatMessage(
                id: turnAssistantId,
                role: .assistant,
                content: response.content,
                reasoningContent: response.reasoningContent ?? "",
                toolCalls: response.toolCalls,
                parentMessageId: userMessage.id
            )
            workingSession = workingSession.withMessage(assistantWithToolCalls)
            await persistMessage(session: workingSession, message: assistantWithToolCalls)
            if let onMessage = callbacks?.onMessage {
                await onMessage(assistantWithToolCalls)
            }
            await publishStreamEvents(
                callbacks,
                streamAdapter.onAssistantRoundCompleted(assistantWithToolCalls)
            )

            for toolCall in response.toolCalls {
                if let onToolStarted = callbacks?.onToolStarted {
                    await onToolStarted(toolCall)
                }
                workingSession = try await invokeToolAndPersist(
                    session: workingSession,
                    parentMessageId: userMessage.id,
                    toolCall: toolCall,
                    streamAdapter: streamAdapter,
                    callbacks: callbacks
                )
            }

            modelToolRound += 1
            if let maxModelToolRounds, maxModelToolRounds > 0, modelToolRound >= maxModelToolRounds {
                let notice = ChatMessage(
                    id: turnAssistantId,
                    role: .assistant,
                    content: "(Sub-agent reached the maximum tool round limit of \(maxModelToolRounds).)",
                    createdAt: Date(),
                    parentMessageId: userMessage.id
                )
                workingSession = workingSession.withMessage(notice)
                await persistMessage(session: workingSession, message: notice)
                if let onMessage = callbacks?.onMessage {
                    await onMessage(notice)
                }
                await publishStreamEvents(callbacks, streamAdapter.finishRun())
                try? await storage.saveSession(workingSession)
                return workingSession
            }
        }
    }

    private func completeWithOverflowRetry(
        session: AgentSession,
        callbacks: AgentTurnCallbacks?,
        streamAdapter: AgentStreamAdapter,
        assistantMessageId: String,
        modelMessages: [AgentModelMessage],
        tools: [ToolDefinition],
        frozenPrompt: FrozenSystemPrompt,
        environmentPrompt: String
    ) async throws -> (session: AgentSession, response: AgentModelResponse) {
        do {
            let response = try await modelClient.completeChat(
                AgentModelRequest(messages: modelMessages, tools: tools),
                onTextDelta: { [weak self] delta in
                    guard let self else { return }
                    await self.publishStreamEvents(
                        callbacks,
                        streamAdapter.onTextDelta(messageId: assistantMessageId, delta: delta)
                    )
                },
                onReasoningDelta: { [weak self] delta in
                    guard let self else { return }
                    await self.publishStreamEvents(
                        callbacks,
                        streamAdapter.onReasoningDelta(messageId: assistantMessageId, delta: delta)
                    )
                },
                onToolCallDelta: { [weak self] delta in
                    guard let self else { return }
                    await self.publishStreamEvents(
                        callbacks,
                        streamAdapter.onToolCallDelta(messageId: assistantMessageId, delta: delta)
                    )
                }
            )
            observeModelUsage(
                session: session,
                environmentPrompt: environmentPrompt,
                tools: tools,
                response: response
            )
            SessionHttpLogService.log(
                sessionId: session.id,
                requestSummary: [
                    "messageCount": modelMessages.count,
                    "toolCount": tools.count,
                    "model": settings.model.modelName
                ],
                responseSummary: [
                    "contentLength": response.content.count,
                    "toolCallCount": response.toolCalls.count,
                    "hasReasoning": !(response.reasoningContent ?? "").isEmpty
                ]
            )
            return (session, response)
        } catch let error as OpenAiModelClientError {
            if case .contextLengthExceeded = error {
                return try await retryWithCompaction(
                    session: session,
                    callbacks: callbacks,
                    streamAdapter: streamAdapter,
                    assistantMessageId: assistantMessageId,
                    frozenPrompt: frozenPrompt,
                    tools: tools,
                    environmentPrompt: environmentPrompt
                )
            }
            throw error
        } catch {
            if Self.isContextLengthError(error) {
                return try await retryWithCompaction(
                    session: session,
                    callbacks: callbacks,
                    streamAdapter: streamAdapter,
                    assistantMessageId: assistantMessageId,
                    frozenPrompt: frozenPrompt,
                    tools: tools,
                    environmentPrompt: environmentPrompt
                )
            }
            throw error
        }
    }

    private func observeModelUsage(
        session: AgentSession,
        environmentPrompt: String,
        tools: [ToolDefinition],
        response: AgentModelResponse
    ) {
        guard let promptTokens = response.usage?.promptTokens, promptTokens > 0 else { return }
        let multiplier = tokenEstimatorCalibrator.getMultiplier(sessionId: session.id)
        let budget = ContextBudgetCalculator.compute(
            environmentPrompt: environmentPrompt,
            tools: tools,
            messages: session.messages,
            compactionSettings: settings.contextCompaction,
            modelSettings: settings.model,
            calibrationMultiplier: multiplier
        )
        let estimatedPromptTokens = budget.fixedOverhead + budget.estimatedHistory
        tokenEstimatorCalibrator.observe(
            sessionId: session.id,
            estimatedPromptTokens: estimatedPromptTokens,
            actualPromptTokens: promptTokens
        )
    }

    /// Runs forced compaction and retries the model completion.
    private func retryWithCompaction(
        session: AgentSession,
        callbacks: AgentTurnCallbacks?,
        streamAdapter: AgentStreamAdapter,
        assistantMessageId: String,
        frozenPrompt: FrozenSystemPrompt,
        tools: [ToolDefinition],
        environmentPrompt: String
    ) async throws -> (session: AgentSession, response: AgentModelResponse) {
        let updated = await runPreCompletionPipeline(
            session: session,
            callbacks: callbacks,
            options: .forceCompact,
            environmentPrompt: environmentPrompt,
            tools: tools,
            pressureOverride: .overflow
        )
        let refreshedPrompt = await resolvePromptOrchestrator().buildForReasoningIteration(
            frozen: frozenPrompt,
            session: updated,
            tools: tools
        )
        let retryMessages = Self.buildModelMessages(
            environmentPrompt: refreshedPrompt,
            history: updated.messages,
            includeReasoningInModelContext: Self.shouldIncludeReasoningInModelContext(settings: settings)
        )
        let response = try await modelClient.completeChat(
            AgentModelRequest(messages: retryMessages, tools: tools),
            onTextDelta: { [weak self] delta in
                guard let self else { return }
                await self.publishStreamEvents(
                    callbacks,
                    streamAdapter.onTextDelta(messageId: assistantMessageId, delta: delta)
                )
            },
            onReasoningDelta: { [weak self] delta in
                guard let self else { return }
                await self.publishStreamEvents(
                    callbacks,
                    streamAdapter.onReasoningDelta(messageId: assistantMessageId, delta: delta)
                )
            },
            onToolCallDelta: { [weak self] delta in
                guard let self else { return }
                await self.publishStreamEvents(
                    callbacks,
                    streamAdapter.onToolCallDelta(messageId: assistantMessageId, delta: delta)
                )
            }
        )
        observeModelUsage(
            session: updated,
            environmentPrompt: refreshedPrompt,
            tools: tools,
            response: response
        )
        return (updated, response)
    }

    private func publishStreamEvents(
        _ callbacks: AgentTurnCallbacks?,
        _ events: [AgentStreamEvent]
    ) async {
        guard let callbacks, !events.isEmpty else { return }
        for event in events {
            if let onStreamEvent = callbacks.onStreamEvent {
                await onStreamEvent(event)
            }
            switch event {
            case .textMessageContent(_, let delta):
                if let onText = callbacks.onAssistantTextDelta {
                    await onText(delta)
                }
            case .reasoningMessageContent(_, let delta):
                if let onReasoning = callbacks.onAssistantReasoningDelta {
                    await onReasoning(delta)
                }
            case .textMessageStart(let messageId, _):
                if let onTarget = callbacks.onStreamingAssistantTarget {
                    await onTarget(messageId)
                }
            default:
                break
            }
        }
    }

    /// Built-in tools run without prompts; `execute_command` can opt in via settings.
    /// Commands matching `commandDenyList` always require approval regardless of `askBeforeEveryCommand`.
    private func shouldRequestToolApproval(toolName: String, arguments: [String: String] = [:]) -> Bool {
        if BuiltInTools.isBuiltIn(toolName) {
            guard toolName.caseInsensitiveCompare("execute_command") == .orderedSame else { return false }
            if let command = arguments["command"] {
                for deny in settings.toolPermissions.commandDenyList {
                    if command.localizedCaseInsensitiveContains(deny) {
                        return true
                    }
                }
            }
            return settings.toolPermissions.askBeforeEveryCommand
        }
        return resolveToolRouter().requiresApproval(toolName: toolName)
    }

    private func invokeToolAndPersist(
        session: AgentSession,
        parentMessageId: String?,
        toolCall: AgentToolCall,
        streamAdapter: AgentStreamAdapter,
        callbacks: AgentTurnCallbacks?
    ) async throws -> AgentSession {
        try Task.checkCancellation()
        let started = Date()
        var result: ToolResult
        let rawArgs = AssistantToolCallsCodec.parseArguments(toolCall.arguments)
        var args = ToolPathNormalizer.normalizePathArguments(rawArgs)
        if let root = session.activeWorkspace?.trimmingCharacters(in: .whitespacesAndNewlines),
           !root.isEmpty,
           let path = args[ToolPathNormalizer.pathArgumentName] {
            args[ToolPathNormalizer.pathArgumentName] = ToolPathNormalizer.resolveRelativeToWorkspaceRoot(
                path,
                workspaceRoot: root
            )
        }
        let displayNotes = ToolExecutionDisplayNotes.build(
            rawArguments: rawArgs,
            normalizedArguments: args,
            workspaceRoot: session.activeWorkspace
        )

        do {
            if shouldRequestToolApproval(toolName: toolCall.name, arguments: args) {
                let capturedArgs = args
                let approved = await MainActor.run {
                    ToolApprovalGate.requestApproval(
                        toolName: toolCall.name,
                        arguments: capturedArgs,
                        askBeforeEveryCommand: true
                    )
                }
                guard approved else {
                    AuditLogService.log(action: "tool.denied", detail: ["tool": toolCall.name])
                    result = .failure(summary: "工具已取消", error: "用户拒绝了工具执行。")
                    return try await persistToolResult(
                        session: session,
                        parentMessageId: parentMessageId,
                        toolCall: toolCall,
                        result: result,
                        displayNotes: displayNotes,
                        streamAdapter: streamAdapter,
                        callbacks: callbacks
                    )
                }
                AuditLogService.log(action: "tool.approved", detail: ["tool": toolCall.name])
            }

            let output = try await resolveToolRouter().invoke(toolName: toolCall.name, arguments: args)
            result = .success(summary: "Tool completed", content: output)
        } catch {
            result = .failure(summary: "Tool invocation failed", error: error.localizedDescription)
        }
        return try await persistToolResult(
            session: session,
            parentMessageId: parentMessageId,
            toolCall: toolCall,
            result: result,
            displayNotes: displayNotes,
            streamAdapter: streamAdapter,
            callbacks: callbacks,
            started: started
        )
    }

    private func persistToolResult(
        session: AgentSession,
        parentMessageId: String?,
        toolCall: AgentToolCall,
        result: ToolResult,
        displayNotes: ToolExecutionDisplayNotes? = nil,
        streamAdapter: AgentStreamAdapter,
        callbacks: AgentTurnCallbacks?,
        started: Date = Date()
    ) async throws -> AgentSession {
        let durationMs = Int64(Date().timeIntervalSince(started) * 1000)

        try? await storage.appendToolCallLog(
            sessionId: session.id,
            toolCallId: toolCall.id,
            toolName: toolCall.name,
            arguments: AssistantToolCallsCodec.parseArguments(toolCall.arguments),
            succeeded: result.succeeded,
            summary: result.summary,
            content: result.content,
            error: result.error,
            durationMs: durationMs
        )

        var content = AgentRuntimeToolFormatting.formatToolResult(toolCall, result, displayNotes: displayNotes)
        content = await toolResultEvictor.evictIfNeeded(
            sessionId: session.id,
            toolCall: toolCall,
            result: result,
            formattedToolContent: content
        )

        let toolMessage = ChatMessage(
            role: .tool,
            content: content,
            parentMessageId: parentMessageId,
            toolCallId: toolCall.id
        )
        let updated = session.withMessage(toolMessage)
        await publishStreamEvents(
            callbacks,
            streamAdapter.onToolResult(toolMessage: toolMessage, toolCall: toolCall)
        )
        if let onMessage = callbacks?.onMessage {
            await onMessage(toolMessage)
        }
        await persistMessage(session: updated, message: toolMessage)
        return updated
    }

    private func runPreCompletionPipeline(
        session: AgentSession,
        callbacks: AgentTurnCallbacks?,
        options: PreCompletionOptions,
        environmentPrompt: String = "",
        tools: [ToolDefinition] = [],
        pressureOverride: ContextPressureLevel = .normal
    ) async -> AgentSession {
        let idsBefore = Set(session.messages.map(\.id))
        var runtimeContext: CompactionRuntimeContext?
        if settings.contextCompaction.dynamicCompaction.enabled, !environmentPrompt.isEmpty {
            let multiplier = tokenEstimatorCalibrator.getMultiplier(sessionId: session.id)
            let budget = ContextBudgetCalculator.compute(
                environmentPrompt: environmentPrompt,
                tools: tools,
                messages: session.messages,
                compactionSettings: settings.contextCompaction,
                modelSettings: settings.model,
                calibrationMultiplier: multiplier
            )
            runtimeContext = CompactionRuntimeContext(
                budget: budget,
                environmentPrompt: environmentPrompt,
                tools: tools,
                calibrationMultiplier: multiplier,
                pressureOverride: pressureOverride
            )
        }
        let compacted = await preCompletionPipeline.run(
            session: session,
            options: options,
            runtimeContext: runtimeContext
        )
        return await persistCompactionAudits(
            session: compacted,
            messageIdsBefore: idsBefore,
            callbacks: callbacks
        )
    }

    private func persistCompactionAudits(
        session: AgentSession,
        messageIdsBefore: Set<String>,
        callbacks: AgentTurnCallbacks?
    ) async -> AgentSession {
        let structureChanged = Self.hasCompactionStructureChange(
            session: session,
            messageIdsBefore: messageIdsBefore
        )
        if structureChanged, let onSessionUpdated = callbacks?.onSessionUpdated {
            await onSessionUpdated(session)
        }

        var persistedNew = false
        for message in session.messages where !messageIdsBefore.contains(message.id) {
            persistedNew = true
            await publishStreamEvents(callbacks, [.chatMessageAppended(message)])
            if let onMessage = callbacks?.onMessage {
                await onMessage(message)
            }
            await persistMessage(session: session, message: message)
        }

        // Only persist when compaction actually changed the session. A full saveSession on every
        // model iteration (when nothing changed) caused SessionWriteLock contention / hangs.
        if persistedNew || structureChanged {
            try? await storage.saveSession(session)
        }
        return session
    }

    private func persistMessage(session: AgentSession, message: ChatMessage) async {
        try? await storage.appendConversationMessage(sessionId: session.id, message: message)
    }

    private static func hasCompactionStructureChange(session: AgentSession, messageIdsBefore: Set<String>) -> Bool {
        var hasAudit = false
        var hasSummary = false
        for message in session.messages where !messageIdsBefore.contains(message.id) {
            if message.role == .compaction { hasAudit = true }
            if SummaryMessageBuilder.isSummaryMessage(message) { hasSummary = true }
        }
        return hasAudit || hasSummary || session.messages.count < messageIdsBefore.count
    }

    static func shouldIncludeReasoningInModelContext(settings: AppSettings) -> Bool {
        if settings.contextCompaction.includeReasoningInModelContext { return true }
        return settings.model.modelName.lowercased().contains("deepseek-v4")
    }

    static func buildModelMessages(
        environmentPrompt: String,
        history: [ChatMessage],
        includeReasoningInModelContext: Bool
    ) -> [AgentModelMessage] {
        var messages: [AgentModelMessage] = [AgentModelMessage(role: "system", text: environmentPrompt)]
        var index = 0
        while index < history.count {
            let message = history[index]
            switch message.role {
            case .compaction:
                index += 1
            case .user:
                if SummaryMessageBuilder.isSummaryMessage(message) {
                    messages.append(AgentModelMessage(role: "user", text: "History summary: \(message.content)"))
                } else {
                    messages.append(AgentModelMessage(role: "user", content: OpenAiChatModelClient.buildUserContent(from: message)))
                }
                index += 1
            case .assistant:
                index = appendAssistantModelMessages(
                    messages: &messages,
                    history: history,
                    assistantIndex: index,
                    includeReasoningInModelContext: includeReasoningInModelContext
                ) + 1
            case .tool:
                messages.append(AgentModelMessage(role: "user", text: formatToolResultAsUserContent(message.content)))
                index += 1
            case .system:
                messages.append(AgentModelMessage(role: "user", text: message.content))
                index += 1
            }
        }
        return messages
    }

    private static func appendAssistantModelMessages(
        messages: inout [AgentModelMessage],
        history: [ChatMessage],
        assistantIndex: Int,
        includeReasoningInModelContext: Bool
    ) -> Int {
        let message = history[assistantIndex]
        let reasoning = includeReasoningInModelContext ? message.reasoningContent : nil
        guard let toolCalls = message.toolCalls, !toolCalls.isEmpty else {
            messages.append(
                AgentModelMessage(
                    role: "assistant",
                    content: .text(message.content),
                    reasoningContent: reasoning?.isEmpty == false ? reasoning : nil
                )
            )
            return assistantIndex
        }

        var scanIndex = assistantIndex + 1
        var toolMessages: [ChatMessage] = []
        while scanIndex < history.count {
            switch history[scanIndex].role {
            case .tool:
                toolMessages.append(history[scanIndex])
                scanIndex += 1
            case .compaction:
                scanIndex += 1
            default:
                break
            }
        }

        var toolByCallId: [String: ChatMessage] = [:]
        for toolMessage in toolMessages {
            if let toolCallId = extractToolCallId(toolMessage.content) {
                toolByCallId[toolCallId] = toolMessage
            }
        }

        messages.append(
            AgentModelMessage(
                role: "assistant",
                content: .text(message.content),
                toolCalls: toolCalls,
                reasoningContent: reasoning?.isEmpty == false ? reasoning : nil
            )
        )

        let consumed = Set(toolCalls.map(\.id))
        for toolCall in toolCalls {
            let content = toolByCallId[toolCall.id]?.content
                ?? "Tool did not run or the result was not recorded."
            messages.append(
                AgentModelMessage(
                    role: "tool",
                    content: .text(content),
                    toolCallId: toolCall.id
                )
            )
        }

        for toolMessage in toolMessages {
            if let toolCallId = extractToolCallId(toolMessage.content), consumed.contains(toolCallId) {
                continue
            }
            messages.append(AgentModelMessage(role: "user", text: formatToolResultAsUserContent(toolMessage.content)))
        }

        return scanIndex - 1
    }

    private static func formatToolResultAsUserContent(_ content: String) -> String {
        "[Tool output]\n\(content)"
    }

    private static func extractToolCallId(_ content: String) -> String? {
        for line in content.components(separatedBy: .newlines) {
            let prefix = "ToolCallId:"
            if line.lowercased().hasPrefix(prefix.lowercased()) {
                let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    private static func shouldListWorkspaceFiles(_ userInput: String) -> Bool {
        let input = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let terms = [
            "有哪些文件", "什么文件", "文件列表", "目录下", "目录里", "工作区文件",
            "list files", "what files", "which files"
        ]
        return terms.contains { input.localizedCaseInsensitiveContains($0) }
    }

    private static func isContextLengthError(_ error: Error) -> Bool {
        var current: Error? = error
        while let value = current {
            if OpenAiChatModelClient.isContextLengthError(value.localizedDescription) {
                return true
            }
            current = value as NSError?
            if let nsError = value as NSError?, let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                current = underlying
            } else {
                break
            }
        }
        return false
    }

    private func resolveToolRouter() -> CompositeToolRouter {
        AmbientToolRouterScope.current ?? toolRouter
    }

    private func resolvePromptOrchestrator() -> any PromptOrchestrating {
        AmbientSystemPromptOrchestratorScope.current ?? systemPromptOrchestrator
    }
}

extension AgentSession {
    func withMessage(_ message: ChatMessage) -> AgentSession {
        var copy = self
        if let index = copy.messages.firstIndex(where: { $0.id == message.id }) {
            copy.messages[index] = message
        } else {
            copy.messages.append(message)
        }
        copy.updatedAt = Date()
        return copy
    }
}
