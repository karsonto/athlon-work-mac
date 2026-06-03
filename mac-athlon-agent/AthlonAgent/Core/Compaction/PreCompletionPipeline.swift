import Foundation

struct PreCompletionPipeline: PreCompletionPipelineRunning {
    let conversationCompactor: ConversationCompacting
    let logger: CompactionLogging

    init(
        conversationCompactor: ConversationCompacting,
        logger: CompactionLogging = NoOpCompactionLogger()
    ) {
        self.conversationCompactor = conversationCompactor
        self.logger = logger
    }

    func run(session: AgentSession, options: PreCompletionOptions? = nil) async -> AgentSession {
        let opts = options ?? .default
        if !opts.allowConversationCompact {
            return session
        }

        let compactResult = await conversationCompactor.compactIfNeeded(
            session: session,
            kind: opts.compactionKind,
            force: opts.forceConversationCompact,
            emitAudit: opts.emitCompactionAudit
        )

        if compactResult.compacted {
            logger.information("Conversation compact applied for session \(session.id)")
        }

        return compactResult.session
    }
}
