import Foundation

/// Cutoff planning aligned with AgentScope ConversationCompactor.
enum ConversationCutoffPlanner {
    static func shouldCompact(
        _ messages: [ChatMessage],
        estimatedTokens: Int,
        settings: ContextCompactionSettings,
        force: Bool
    ) -> Bool {
        if messages.isEmpty { return false }
        if force { return true }
        if settings.triggerMessages > 0, messages.count >= settings.triggerMessages { return true }
        let tokenThreshold = resolveCompactTriggerTokens(settings)
        return tokenThreshold > 0 && estimatedTokens >= tokenThreshold
    }

    /// Effective token threshold: max(triggerTokens, floor(contextWindowTokens * compactTriggerRatio)).
    static func resolveCompactTriggerTokens(_ settings: ContextCompactionSettings) -> Int {
        let fixedThreshold = max(0, settings.triggerTokens)
        if settings.contextWindowTokens <= 0 || settings.compactTriggerRatio <= 0 {
            return fixedThreshold
        }
        let windowThreshold = Int(floor(Double(settings.contextWindowTokens) * settings.compactTriggerRatio))
        return max(fixedThreshold, windowThreshold)
    }

    static func shouldTruncateArgs(
        _ messages: [ChatMessage],
        estimatedTokens: Int,
        settings: TruncateArgsSettings
    ) -> Bool {
        if !settings.enabled || messages.isEmpty { return false }
        if settings.triggerMessages > 0, messages.count >= settings.triggerMessages { return true }
        return settings.triggerTokens > 0 && estimatedTokens >= settings.triggerTokens
    }

    static func determineCutoffIndex(
        _ messages: [ChatMessage],
        estimatedTokens: Int,
        settings: ContextCompactionSettings,
        keepTokenBudgetOverride: Int? = nil
    ) -> Int {
        if let keepTokenBudgetOverride, keepTokenBudgetOverride > 0, settings.dynamicCompaction.enableSemanticCutoff {
            return SemanticCutoffPlanner.determineCutoffIndex(
                conversation: messages,
                settings: settings,
                keepTokenBudget: keepTokenBudgetOverride
            )
        }

        if let keepTokenBudgetOverride, keepTokenBudgetOverride > 0 {
            let rawCutoff = determineTruncateArgsCutoffFromKeepBudget(
                messages,
                keepTokenBudget: keepTokenBudgetOverride,
                includeReasoningInModelContext: settings.includeReasoningInModelContext
            )
            return findSafeCutoffPoint(messages, cutoffIndex: rawCutoff)
        }

        let rawCutoff: Int
        if settings.keepTokens > 0 {
            rawCutoff = findTokenBasedCutoff(
                messages,
                totalTokens: estimatedTokens,
                keepTokens: settings.keepTokens,
                includeReasoningInModelContext: settings.includeReasoningInModelContext
            )
        } else {
            rawCutoff = findMessageBasedCutoff(messages, keepMessages: settings.keepMessages)
        }
        return findSafeCutoffPoint(messages, cutoffIndex: rawCutoff)
    }

    static func determineTruncateArgsCutoffFromKeepBudget(
        _ messages: [ChatMessage],
        keepTokenBudget: Int,
        includeReasoningInModelContext: Bool = false
    ) -> Int {
        if keepTokenBudget <= 0 || messages.isEmpty { return messages.count }

        var tokensKept = 0
        for index in stride(from: messages.count - 1, through: 0, by: -1) {
            let messageTokens = ContextTokenEstimator.estimateMessage(
                messages[index],
                includeReasoningInModelContext: includeReasoningInModelContext
            )
            if tokensKept + messageTokens > keepTokenBudget {
                return index + 1
            }
            tokensKept += messageTokens
        }
        return 0
    }

    static func determineTruncateArgsCutoff(
        _ messages: [ChatMessage],
        settings: TruncateArgsSettings,
        includeReasoningInModelContext: Bool = false
    ) -> Int {
        if settings.keepTokens > 0 {
            var tokensKept = 0
            for index in stride(from: messages.count - 1, through: 0, by: -1) {
                let messageTokens = ContextTokenEstimator.estimateMessage(
                    messages[index],
                    includeReasoningInModelContext: includeReasoningInModelContext
                )
                if tokensKept + messageTokens > settings.keepTokens {
                    return index + 1
                }
                tokensKept += messageTokens
            }
            return 0
        }
        return max(0, messages.count - settings.keepMessages)
    }

    static func findSafeCutoffPoint(_ messages: [ChatMessage], cutoffIndex: Int) -> Int {
        if cutoffIndex <= 0 || cutoffIndex >= messages.count { return cutoffIndex }
        if messages[cutoffIndex].role != .tool { return cutoffIndex }

        var toolCallIds: [String] = []
        var scanIndex = cutoffIndex
        while scanIndex < messages.count, messages[scanIndex].role == .tool {
            if let toolCallId = extractToolCallId(messages[scanIndex].content) {
                toolCallIds.append(toolCallId)
            }
            scanIndex += 1
        }

        if toolCallIds.isEmpty { return scanIndex }

        for index in stride(from: cutoffIndex - 1, through: 0, by: -1) {
            if messages[index].role != .assistant { continue }
            guard let calls = AssistantToolCallsCodec.deserializeToolCalls(from: messages[index]),
                  !calls.isEmpty
            else { continue }

            if calls.contains(where: { toolCallIds.contains($0.id) }) {
                return index
            }
        }

        return scanIndex
    }

    private static func findMessageBasedCutoff(_ messages: [ChatMessage], keepMessages: Int) -> Int {
        if keepMessages <= 0 || messages.count <= keepMessages { return 0 }
        return messages.count - keepMessages
    }

    private static func findTokenBasedCutoff(
        _ messages: [ChatMessage],
        totalTokens: Int,
        keepTokens: Int,
        includeReasoningInModelContext: Bool
    ) -> Int {
        if totalTokens <= keepTokens { return 0 }

        var left = 0
        var right = messages.count
        var candidate = messages.count
        let maxIter = messages.count > 0
            ? Int(floor(log2(Double(messages.count)))) + 2
            : 1

        var iteration = 0
        while iteration < maxIter, left < right {
            let mid = (left + right) / 2
            if ContextTokenEstimator.estimateSuffix(
                messages,
                startIndex: mid,
                includeReasoningInModelContext: includeReasoningInModelContext
            ) <= keepTokens {
                candidate = mid
                right = mid
            } else {
                left = mid + 1
            }
            iteration += 1
        }

        return min(candidate, messages.count - 1)
    }

    private static func extractToolCallId(_ content: String?) -> String? {
        guard let content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let prefix = "ToolCallId:"
        for line in content.split(whereSeparator: \.isNewline) {
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix(prefix.lowercased()) {
                let value = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }
}
