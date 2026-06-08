import Foundation

/// Service that can trigger session compaction manually.
protocol ISessionCompactionService {
    /// Runs compaction on the current session's messages.
    func compact(session: AgentSession) async -> String?
}
