import Foundation

/// Triggers session compaction manually using the existing compaction infrastructure.
final class SessionCompactionService: ISessionCompactionService {
    private let compactor: ConversationCompactor

    init(compactor: ConversationCompactor) {
        self.compactor = compactor
    }

    func compact(session: AgentSession) async -> String? {
        AgentFileLogger.log("Manual compaction triggered via /compact", category: "Compaction")
        let result = await compactor.compactIfNeeded(
            session: session,
            kind: .manualCompact,
            force: true,
            emitAudit: true
        )
        if result.compacted {
            AgentFileLogger.log("Manual compaction completed", category: "Compaction")
            return "Compaction completed."
        } else {
            AgentFileLogger.log("Manual compaction skipped — no compaction needed", category: "Compaction")
            return nil
        }
    }
}
