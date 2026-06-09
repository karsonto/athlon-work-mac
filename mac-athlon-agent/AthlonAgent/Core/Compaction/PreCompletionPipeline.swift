import Foundation

struct PreCompletionPipeline: PreCompletionPipelineRunning {
    let conversationCompactor: ConversationCompacting
    let truncateArgsService: TruncateArgsService
    let settings: ContextCompactionSettings
    let logger: CompactionLogging

    init(
        conversationCompactor: ConversationCompacting,
        truncateArgsService: TruncateArgsService = TruncateArgsService(),
        settings: ContextCompactionSettings,
        logger: CompactionLogging = NoOpCompactionLogger()
    ) {
        self.conversationCompactor = conversationCompactor
        self.truncateArgsService = truncateArgsService
        self.settings = settings
        self.logger = logger
    }

    func run(
        session: AgentSession,
        options: PreCompletionOptions? = nil,
        runtimeContext: CompactionRuntimeContext? = nil
    ) async -> AgentSession {
        let opts = options ?? .default
        if !opts.allowConversationCompact {
            return session
        }

        let cfg = settings
        if !cfg.dynamicCompaction.enabled || runtimeContext == nil {
            return await runLegacy(session: session, options: opts)
        }

        guard var runtimeContext else { return session }
        var budget = runtimeContext.budget
        var workingSession = session
        var conversation = conversationMessages(from: workingSession.messages)
        if conversation.isEmpty { return session }

        let force = opts.forceConversationCompact || runtimeContext.forceOverflow
        var pressure = ContextPressureEvaluator.evaluate(
            budget: budget,
            settings: cfg.dynamicCompaction,
            forceOverflow: runtimeContext.forceOverflow
        )
        var plan = DynamicCompactionPlan.create(
            pressure: pressure,
            budget: budget,
            conversation: conversation,
            settings: cfg,
            force: force
        )

        var truncateApplied = false
        var reEvictApplied = false

        if plan.applyTruncateArgs, opts.allowTruncateArgs {
            let (truncatedMessages, changed) = truncateArgsService.applyToMessages(
                workingSession.messages,
                settings: cfg,
                keepTokenBudgetOverride: plan.keepTokenBudget > 0 ? plan.keepTokenBudget : nil
            )
            if changed {
                truncateApplied = true
                workingSession = workingSession.withMessages(truncatedMessages)
                conversation = conversationMessages(from: workingSession.messages)
                budget = ContextBudgetCalculator.recomputeHistory(
                    snapshot: budget,
                    messages: workingSession.messages,
                    compactionSettings: cfg,
                    calibrationMultiplier: runtimeContext.calibrationMultiplier
                )
                runtimeContext.budget = budget
            }
        }

        if plan.applyPrefixReEvict {
            let prefixCutoff = ConversationCutoffPlanner.determineTruncateArgsCutoffFromKeepBudget(
                conversation,
                keepTokenBudget: plan.keepTokenBudget,
                includeReasoningInModelContext: cfg.includeReasoningInModelContext
            )
            let (updatedMessages, changed) = PrefixToolResultReEvictor.apply(
                messages: workingSession.messages,
                settings: cfg,
                prefixCutoffExclusive: prefixCutoff
            )
            if changed {
                reEvictApplied = true
                workingSession = workingSession.withMessages(updatedMessages)
                conversation = conversationMessages(from: workingSession.messages)
                budget = ContextBudgetCalculator.recomputeHistory(
                    snapshot: budget,
                    messages: workingSession.messages,
                    compactionSettings: cfg,
                    calibrationMultiplier: runtimeContext.calibrationMultiplier
                )
                runtimeContext.budget = budget
            }
        }

        if !plan.applyConversationCompact {
            return workingSession
        }

        pressure = ContextPressureEvaluator.evaluate(
            budget: budget,
            settings: cfg.dynamicCompaction,
            forceOverflow: runtimeContext.forceOverflow
        )
        plan = plan.withPressure(pressure)

        let compactResult = await conversationCompactor.compactIfNeeded(
            session: workingSession,
            request: CompactionExecutionRequest(
                kind: opts.compactionKind,
                force: force,
                emitAudit: opts.emitCompactionAudit,
                runtimeContext: runtimeContext,
                plan: plan.withAppliedFlags(
                    truncateApplied: truncateApplied,
                    reEvictApplied: reEvictApplied
                )
            )
        )

        if compactResult.compacted {
            logger.information(
                "Dynamic compaction applied for session \(session.id) at pressure \(plan.pressure)"
            )
        }

        return compactResult.session
    }

    private func runLegacy(session: AgentSession, options: PreCompletionOptions) async -> AgentSession {
        let compactResult = await conversationCompactor.compactIfNeeded(
            session: session,
            request: CompactionExecutionRequest.legacy(
                kind: options.compactionKind,
                force: options.forceConversationCompact,
                emitAudit: options.emitCompactionAudit
            )
        )
        if compactResult.compacted {
            logger.information("Conversation compact applied for session \(session.id)")
        }
        return compactResult.session
    }

    private func conversationMessages(from messages: [ChatMessage]) -> [ChatMessage] {
        messages.filter { $0.role != .compaction }
    }
}
