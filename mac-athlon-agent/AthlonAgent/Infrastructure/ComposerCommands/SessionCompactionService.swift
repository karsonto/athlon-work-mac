import Foundation

/// Manual /compact handler aligned with WPF `SessionCompactionService`.
final class SessionCompactionService: ISessionCompactionService {
    private let preCompletionPipeline: PreCompletionPipeline
    private let toolRouter: CompositeToolRouter
    private let systemPromptOrchestrator: any PromptOrchestrating
    private let tokenEstimatorCalibrator: TokenEstimatorCalibrating
    private let storage: FileStorageService
    private let settings: AppSettings
    private let skillsProvider: () -> [AvailableSkillInfo]

    init(
        preCompletionPipeline: PreCompletionPipeline,
        toolRouter: CompositeToolRouter,
        systemPromptOrchestrator: any PromptOrchestrating,
        tokenEstimatorCalibrator: TokenEstimatorCalibrating,
        storage: FileStorageService,
        settings: AppSettings,
        skillsProvider: @escaping () -> [AvailableSkillInfo]
    ) {
        self.preCompletionPipeline = preCompletionPipeline
        self.toolRouter = toolRouter
        self.systemPromptOrchestrator = systemPromptOrchestrator
        self.tokenEstimatorCalibrator = tokenEstimatorCalibrator
        self.storage = storage
        self.settings = settings
        self.skillsProvider = skillsProvider
    }

    func compact(session: AgentSession) async -> String? {
        AgentFileLogger.log("Manual compaction triggered via /compact", category: "Compaction")

        let activeRouter = AmbientToolRouterScope.current ?? toolRouter
        let activePrompt = AmbientSystemPromptOrchestratorScope.current ?? systemPromptOrchestrator
        let tools = await activeRouter.listToolDefinitions()
        let frozenPrompt = activePrompt.prepareForTurn(session: session, tools: tools)
        let environmentPrompt = await activePrompt.buildForReasoningIteration(
            frozen: frozenPrompt,
            session: session,
            tools: tools
        )

        var runtimeContext: CompactionRuntimeContext?
        if settings.contextCompaction.dynamicCompaction.enabled {
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
                pressureOverride: .normal
            )
        }

        let messageIdsBefore = Set(session.messages.map(\.id))
        var updated = await preCompletionPipeline.run(
            session: session,
            options: .manualForceCompact,
            runtimeContext: runtimeContext
        )
        updated = await persistCompactionAudits(session: updated, messageIdsBefore: messageIdsBefore)

        let compacted = detectManualCompaction(messageIdsBefore: messageIdsBefore, messages: updated.messages)
        if compacted {
            AgentFileLogger.log("Manual compaction completed", category: "Compaction")
            return "已手动压缩上下文。"
        }

        AgentFileLogger.log("Manual compaction skipped — no compaction needed", category: "Compaction")
        return nil
    }

    private func detectManualCompaction(messageIdsBefore: Set<String>, messages: [ChatMessage]) -> Bool {
        for message in messages where !messageIdsBefore.contains(message.id) {
            if message.role == .compaction,
               message.content.localizedCaseInsensitiveContains("manualcompact") {
                return true
            }
        }
        return messages.count < messageIdsBefore.count
    }

    private func persistCompactionAudits(
        session: AgentSession,
        messageIdsBefore: Set<String>
    ) async -> AgentSession {
        var persistedNew = false
        for message in session.messages where !messageIdsBefore.contains(message.id) {
            persistedNew = true
            try? await storage.appendConversationMessage(sessionId: session.id, message: message)
            try? await storage.saveSession(session)
        }
        if !persistedNew {
            try? await storage.saveSession(session)
        }
        return session
    }
}
