import Foundation

struct ConversationCompactor: ConversationCompacting {
    let settings: ContextCompactionSettings
    let modelClient: AgentModelClientProviding
    let storage: CompactionStorageProviding
    let truncateArgsService: TruncateArgsService
    let planProvider: PlanProviding
    let logger: CompactionLogging

    init(
        settings: ContextCompactionSettings,
        modelClient: AgentModelClientProviding,
        storage: CompactionStorageProviding,
        truncateArgsService: TruncateArgsService = TruncateArgsService(),
        planProvider: PlanProviding? = nil,
        logger: CompactionLogging = NoOpCompactionLogger()
    ) {
        self.settings = settings
        self.modelClient = modelClient
        self.storage = storage
        self.truncateArgsService = truncateArgsService
        self.planProvider = planProvider ?? SessionPlanProvider()
        self.logger = logger
    }

    func compactIfNeeded(
        session: AgentSession,
        request: CompactionExecutionRequest
    ) async -> ConversationCompactResult {
        let cfg = settings
        var conversation = conversationMessages(from: session.messages)
        if conversation.isEmpty {
            return ConversationCompactResult(session: session, compacted: false)
        }

        var truncateArgsApplied = false
        if !cfg.dynamicCompaction.enabled || request.runtimeContext == nil {
            let (truncatedMessages, changed) = truncateArgsService.applyToMessages(session.messages, settings: cfg)
            conversation = truncatedMessages.filter { $0.role != .compaction }
            truncateArgsApplied = changed
        } else if request.plan?.applyTruncateArgs == true {
            truncateArgsApplied = true
        }

        let estimatedTokens = ContextTokenEstimator.estimate(
            conversation,
            includeReasoningInModelContext: cfg.includeReasoningInModelContext,
            calibrationMultiplier: request.runtimeContext?.calibrationMultiplier ?? 1.0
        )

        let shouldCompact: Bool
        if let runtime = request.runtimeContext {
            shouldCompact = ContextPressureEvaluator.shouldCompact(
                budget: runtime.budget,
                conversation: conversation,
                settings: cfg,
                pressure: request.plan?.pressure ?? .normal,
                force: request.force
            )
        } else {
            shouldCompact = ConversationCutoffPlanner.shouldCompact(
                conversation,
                estimatedTokens: estimatedTokens,
                settings: cfg,
                force: request.force
            )
        }

        if !shouldCompact {
            return ConversationCompactResult(session: session, compacted: false)
        }

        let keepTokenBudget = request.plan?.keepTokenBudget
        let cutoff = ConversationCutoffPlanner.determineCutoffIndex(
            conversation,
            estimatedTokens: estimatedTokens,
            settings: cfg,
            keepTokenBudgetOverride: keepTokenBudget.flatMap { $0 > 0 ? $0 : nil }
        )
        if cutoff <= 0 {
            logger.debug("Compaction triggered but safe cutoff is 0 — skipping")
            return ConversationCompactResult(session: session, compacted: false)
        }

        let prefix = SummaryMessageBuilder.filterSummaryMessages(Array(conversation.prefix(cutoff)))
        let tail = Array(conversation.dropFirst(cutoff))
        let originalCount = conversation.count
        let tokensBefore = estimatedTokens

        var transcriptPath: String?
        if cfg.offloadBeforeCompact {
            do {
                transcriptPath = try await storage.saveTranscript(
                    sessionId: session.id,
                    messages: session.messages
                )
            } catch {
                logger.error(error, "Failed to save transcript for session \(session.id)")
            }
        }

        let plan = planProvider.currentPlan(sessionId: session.id) ?? session.plan
        var formatted = ConversationSummaryFormatter.formatMessages(prefix)
        if formatted.count > cfg.maxConversationCharsForSummary {
            formatted = String(formatted.suffix(cfg.maxConversationCharsForSummary))
        }

        let planAppendix = CompactionPlanContextBuilder.buildSummaryPromptAppendix(plan)
        let mustPreserve = request.plan?.mustPreserveAppendix
        let promptBody = buildSummaryPrompt(
            template: cfg.summaryPrompt,
            formattedMessages: formatted,
            planAppendix: planAppendix,
            mustPreserveAppendix: mustPreserve
        )

        var summary: String
        do {
            let summaryResponse = try await modelClient.complete(
                AgentModelRequest(
                    messages: [AgentModelMessage(role: "user", text: promptBody)],
                    allowToolCalls: false,
                    maxTokens: cfg.summaryMaxTokens
                )
            )
            summary = summaryResponse.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if summary.isEmpty {
                summary = "(Summary unavailable)"
            }
        } catch {
            logger.error(error, "Summarization LLM call failed for session \(session.id)")
            summary = "(Summarization failed: \(error.localizedDescription))"
        }

        summary = CompactionPlanContextBuilder.enrichSummaryText(summary, plan: plan)
        let summaryMessage = SummaryMessageBuilder.createSummaryPlaceholder(
            summaryText: summary,
            transcriptPath: transcriptPath
        )

        var compactMessages: [ChatMessage] = []
        let auditKind: CompactionKind = request.kind == .manualCompact ? .manualCompact : .conversationCompact

        var layers: [CompactionLayer] = [.conversationCompact]
        if truncateArgsApplied { layers.insert(.truncateArgs, at: 0) }
        if request.plan?.applyPrefixReEvict == true { layers.insert(.toolResultEviction, at: 0) }

        let pressure = request.plan?.pressure
        let utilization = request.runtimeContext?.budget.totalUtilization

        if request.emitAudit {
            let tokensAfterPreview = ContextTokenEstimator.estimate(
                [summaryMessage] + tail,
                includeReasoningInModelContext: cfg.includeReasoningInModelContext,
                calibrationMultiplier: request.runtimeContext?.calibrationMultiplier ?? 1.0
            )
            let auditContent: String
            if auditKind == .manualCompact {
                auditContent = CompactionMessageContent.createManualCompact(
                    tokensBefore: tokensBefore,
                    tokensAfter: tokensAfterPreview,
                    originalMessageCount: originalCount,
                    transcriptPath: transcriptPath ?? "",
                    summaryPreview: summary,
                    layers: layers,
                    pressureLevel: pressure,
                    utilization: utilization
                )
            } else {
                let strategy: CompactionStrategy = {
                    if request.force { return .forceCompact }
                    if request.kind == .manualCompact { return .manualCompact }
                    return .conversationCompact
                }()
                auditContent = CompactionMessageContent.createConversationCompact(
                    tokensBefore: tokensBefore,
                    tokensAfter: tokensAfterPreview,
                    originalMessageCount: originalCount,
                    transcriptPath: transcriptPath,
                    summaryPreview: summary,
                    strategy: strategy,
                    layers: layers,
                    pressureLevel: pressure,
                    utilization: utilization
                )
            }
            compactMessages.append(CompactionMessageContent.createCompactionMessage(auditContent))
        }

        compactMessages.append(summaryMessage)
        compactMessages.append(contentsOf: tail)

        let contextSummary = ContextSummary(
            id: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            sessionId: session.id,
            content: summary,
            originalMessageCount: originalCount,
            createdAt: Date()
        )
        do {
            try await storage.saveContextSummary(contextSummary)
        } catch {
            logger.error(error, "Failed to save context summary for session \(session.id)")
        }

        let updatedSession = session.withMessages(compactMessages)
        logger.information(
            "Compacted session \(session.id) from \(originalCount) to \(updatedSession.messages.count) messages"
        )

        return ConversationCompactResult(session: updatedSession, compacted: true)
    }

    private func buildSummaryPrompt(
        template: String,
        formattedMessages: String,
        planAppendix: String?,
        mustPreserveAppendix: String?
    ) -> String {
        var body = template
        let mustPreserve = mustPreserveAppendix?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        body = body.replacingOccurrences(of: "{must_preserve}", with: mustPreserve)

        if let planAppendix, !planAppendix.isEmpty {
            body = body.replacingOccurrences(
                of: "{messages}",
                with: planAppendix + "\n\n<conversation_history>\n" + formattedMessages + "\n</conversation_history>"
            )
        } else {
            body = body.replacingOccurrences(of: "{messages}", with: formattedMessages)
        }
        return body
    }

    private func conversationMessages(from messages: [ChatMessage]) -> [ChatMessage] {
        messages.filter { $0.role != .compaction }
    }
}
