import Foundation

enum SemanticCutoffPlanner {
    static func determineCutoffIndex(
        conversation: [ChatMessage],
        settings: ContextCompactionSettings,
        keepTokenBudget: Int
    ) -> Int {
        if conversation.isEmpty || keepTokenBudget <= 0 { return 0 }

        let protectedStart = findProtectedTailStart(conversation)
        let tokenKeepStart = findTokenBasedTailStart(
            conversation,
            keepTokenBudget: keepTokenBudget,
            includeReasoningInModelContext: settings.includeReasoningInModelContext
        )
        let rawCutoff = min(protectedStart, tokenKeepStart)
        return ConversationCutoffPlanner.findSafeCutoffPoint(conversation, cutoffIndex: rawCutoff)
    }

    static func buildMustPreserveAppendix(
        conversation: [ChatMessage],
        settings: ContextCompactionSettings,
        keepTokenBudget: Int
    ) -> String? {
        if !settings.dynamicCompaction.enableSemanticCutoff || conversation.isEmpty {
            return nil
        }

        let cutoff = determineCutoffIndex(
            conversation: conversation,
            settings: settings,
            keepTokenBudget: keepTokenBudget
        )
        if cutoff <= 0 { return nil }

        var lines = ["<must_preserve>", "The following facts from earlier history MUST appear in your summary:"]
        for index in 0..<cutoff {
            let message = conversation[index]
            guard SemanticMessageScorer.shouldPreserveInSummary(message) else { continue }
            lines.append("- [\(message.role.rawValue)] \(truncateForAppendix(message.content))")
        }
        lines.append("</must_preserve>")
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func findProtectedTailStart(_ conversation: [ChatMessage]) -> Int {
        for index in stride(from: conversation.count - 1, through: 0, by: -1) {
            if conversation[index].role == .user { return index }
        }
        return conversation.count
    }

    private static func findTokenBasedTailStart(
        _ conversation: [ChatMessage],
        keepTokenBudget: Int,
        includeReasoningInModelContext: Bool
    ) -> Int {
        var tokensKept = 0
        for index in stride(from: conversation.count - 1, through: 0, by: -1) {
            tokensKept += ContextTokenEstimator.estimateMessage(
                conversation[index],
                includeReasoningInModelContext: includeReasoningInModelContext
            )
            if tokensKept > keepTokenBudget {
                return min(conversation.count, index + 1)
            }
        }
        return 0
    }

    private static func truncateForAppendix(_ content: String?) -> String {
        guard let content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "(empty)"
        }
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.count <= 240 { return normalized }
        return String(normalized.prefix(240)) + "..."
    }
}
