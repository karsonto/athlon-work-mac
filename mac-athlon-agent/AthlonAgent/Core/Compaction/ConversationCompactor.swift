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
        kind: CompactionKind,
        force: Bool,
        emitAudit: Bool
    ) async -> ConversationCompactResult {
        let cfg = settings
        var conversation = conversationMessages(from: session.messages)
        if conversation.isEmpty {
            return ConversationCompactResult(session: session, compacted: false)
        }

        let (truncatedMessages, _) = truncateArgsService.applyToMessages(session.messages, settings: cfg)
        conversation = truncatedMessages
            .filter { $0.role != .compaction }

        let estimatedTokens = ContextTokenEstimator.estimate(
            conversation,
            includeReasoningInModelContext: cfg.includeReasoningInModelContext
        )
        if !ConversationCutoffPlanner.shouldCompact(
            conversation,
            estimatedTokens: estimatedTokens,
            settings: cfg,
            force: force
        ) {
            return ConversationCompactResult(session: session, compacted: false)
        }

        let cutoff = ConversationCutoffPlanner.determineCutoffIndex(
            conversation,
            estimatedTokens: estimatedTokens,
            settings: cfg
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
        let promptBody: String
        if let planAppendix, !planAppendix.isEmpty {
            promptBody = planAppendix + "\n\n<conversation_history>\n" + formatted + "\n</conversation_history>"
        } else {
            promptBody = formatted
        }

        let prompt = cfg.summaryPrompt.replacingOccurrences(of: "{messages}", with: promptBody)

        var summary: String
        do {
            let summaryResponse = try await modelClient.complete(
                AgentModelRequest(
                    messages: [AgentModelMessage(role: "user", text: prompt)],
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
        let auditKind: CompactionKind = kind == .manualCompact ? .manualCompact : .conversationCompact

        if emitAudit {
            let tokensAfterPreview = ContextTokenEstimator.estimate(
                [summaryMessage] + tail,
                includeReasoningInModelContext: cfg.includeReasoningInModelContext
            )
            let auditContent: String
            if auditKind == .manualCompact {
                auditContent = CompactionMessageContent.createManualCompact(
                    tokensBefore: tokensBefore,
                    tokensAfter: tokensAfterPreview,
                    originalMessageCount: originalCount,
                    transcriptPath: transcriptPath ?? "",
                    summaryPreview: summary,
                    layers: [.conversationCompact]
                )
            } else {
                let strategy: CompactionStrategy = {
                    if kind == .manualCompact { return .manualCompact }
                    if force { return .forceCompact }
                    return .conversationCompact
                }()
                auditContent = CompactionMessageContent.createConversationCompact(
                    tokensBefore: tokensBefore,
                    tokensAfter: tokensAfterPreview,
                    originalMessageCount: originalCount,
                    transcriptPath: transcriptPath,
                    summaryPreview: summary,
                    strategy: strategy,
                    layers: [.conversationCompact]
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

    private func conversationMessages(from messages: [ChatMessage]) -> [ChatMessage] {
        messages.filter { $0.role != .compaction }
    }
}
