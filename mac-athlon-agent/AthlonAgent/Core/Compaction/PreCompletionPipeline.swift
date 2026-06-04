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
        guard opts.allowConversationCompact else { return session }

        let cfg = settings
        if !cfg.dynamicCompaction.enabled || runtimeContext == nil {
            return await runLegacy(session: session, options: opts)
        }

        guard let runtimeContext else { return session }

        var budget = runtimeContext.budget
        var workingSession = session
        var conversation = Self.conversationMessages(workingSession.messages)
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
            let (truncated, changed) = truncateArgsService.applyToMessages(
                workingSession.messages,
                settings: cfg,
                keepTokenBudgetOverride: plan.keepTokenBudget > 0 ? plan.keepTokenBudget : nil
            )
            if changed {
                truncateApplied = true
                workingSession = workingSession.withMessages(truncated)
                conversation = Self.conversationMessages(workingSession.messages)
                budget = ContextBudgetCalculator.recomputeHistory(
                    snapshot: budget,
                    messages: workingSession.messages,
                    compactionSettings: cfg,
                    calibrationMultiplier: runtimeContext.calibrationMultiplier
                )
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
                conversation = Self.conversationMessages(workingSession.messages)
                budget = ContextBudgetCalculator.recomputeHistory(
                    snapshot: budget,
                    messages: workingSession.messages,
                    compactionSettings: cfg,
                    calibrationMultiplier: runtimeContext.calibrationMultiplier
                )
            }
        }

        guard plan.applyConversationCompact else { return workingSession }

        pressure = ContextPressureEvaluator.evaluate(
            budget: budget,
            settings: cfg.dynamicCompaction,
            forceOverflow: runtimeContext.forceOverflow
        )
        plan.pressure = pressure

        let compactResult = await conversationCompactor.compactIfNeeded(
            session: workingSession,
            request: CompactionExecutionRequest(
                kind: opts.compactionKind,
                force: force,
                emitAudit: opts.emitCompactionAudit,
                runtimeContext: CompactionRuntimeContext(
                    budget: budget,
                    environmentPrompt: runtimeContext.environmentPrompt,
                    tools: runtimeContext.tools,
                    calibrationMultiplier: runtimeContext.calibrationMultiplier,
                    pressureOverride: runtimeContext.pressureOverride
                ),
                plan: DynamicCompactionPlan(
                    pressure: plan.pressure,
                    applyTruncateArgs: truncateApplied,
                    applyPrefixReEvict: reEvictApplied,
                    applyConversationCompact: plan.applyConversationCompact,
                    keepTokenBudget: plan.keepTokenBudget,
                    mustPreserveAppendix: plan.mustPreserveAppendix
                )
            )
        )

        if compactResult.compacted {
            logger.information(
                "Dynamic compaction applied for session \(session.id) at pressure \(plan.pressure.rawValue)"
            )
        }

        return compactResult.session
    }

    private func runLegacy(session: AgentSession, options: PreCompletionOptions) async -> AgentSession {
        let compactResult = await conversationCompactor.compactIfNeeded(
            session: session,
            request: CompactionExecutionRequest(
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

    private static func conversationMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.filter { $0.role != .compaction }
    }
}
