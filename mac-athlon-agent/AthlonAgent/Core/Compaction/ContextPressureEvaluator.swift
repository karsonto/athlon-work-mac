import Foundation

enum ContextPressureEvaluator {
    static func resolveTruncateThreshold(_ settings: DynamicCompactionSettings) -> Double {
        settings.targetUtilization * settings.truncateLeadRatio
    }

    static func resolveCompactThreshold(_ settings: DynamicCompactionSettings) -> Double {
        settings.targetUtilization
    }

    static func evaluate(
        budget: ContextBudgetSnapshot,
        settings: DynamicCompactionSettings,
        forceOverflow: Bool = false
    ) -> ContextPressureLevel {
        if forceOverflow { return .overflow }

        let utilization = budget.totalUtilization
        let target = settings.targetUtilization

        if utilization >= target { return .critical }
        if utilization >= resolveTruncateThreshold(settings) { return .high }
        if utilization >= target * 0.6875 { return .elevated }
        return .normal
    }

    static func resolveKeepTokenBudget(
        budget: ContextBudgetSnapshot,
        pressure: ContextPressureLevel,
        conversation: [ChatMessage],
        settings: ContextCompactionSettings,
        includesConversationCompact: Bool
    ) -> Int {
        let dynamic = settings.dynamicCompaction
        let staticKeep = resolveStaticKeepTokenBudget(conversation: conversation, settings: settings)

        if !dynamic.enabled {
            return staticKeep
        }

        if pressure != .overflow, !includesConversationCompact {
            return max(staticKeep, 512)
        }

        let keepTargetUtil = pressure == .overflow
            ? dynamic.overflowPostCompactionUtilization
            : dynamic.postCompactionUtilization
        let targetHistory = Int(floor(keepTargetUtil * Double(budget.usablePromptWindow) - Double(budget.fixedOverhead)))
        let dynamicKeep = max(512, targetHistory)
        return max(dynamicKeep, staticKeep)
    }

    static func shouldApplyTruncateArgs(
        budget: ContextBudgetSnapshot,
        conversation: [ChatMessage],
        settings: ContextCompactionSettings,
        pressure: ContextPressureLevel,
        force: Bool
    ) -> Bool {
        if force || pressure == .overflow { return true }
        if meetsStaticTruncateThreshold(conversation: conversation, settings: settings) { return true }
        return budget.totalUtilization >= resolveTruncateThreshold(settings.dynamicCompaction)
    }

    static func shouldApplyPrefixReEvict(
        budget: ContextBudgetSnapshot,
        conversation: [ChatMessage],
        settings: ContextCompactionSettings,
        pressure: ContextPressureLevel,
        force: Bool
    ) -> Bool {
        if force || pressure == .overflow || pressure == .critical {
            return shouldApplyTruncateArgs(budget: budget, conversation: conversation, settings: settings, pressure: pressure, force: force)
        }
        return shouldApplyTruncateArgs(budget: budget, conversation: conversation, settings: settings, pressure: pressure, force: force)
            && budget.totalUtilization >= resolveTruncateThreshold(settings.dynamicCompaction)
    }

    static func shouldCompact(
        budget: ContextBudgetSnapshot,
        conversation: [ChatMessage],
        settings: ContextCompactionSettings,
        pressure: ContextPressureLevel,
        force: Bool
    ) -> Bool {
        if force || pressure == .overflow { return true }

        if !settings.dynamicCompaction.enabled {
            let estimated = ContextTokenEstimator.estimate(
                conversation,
                includeReasoningInModelContext: settings.includeReasoningInModelContext
            )
            return ConversationCutoffPlanner.shouldCompact(
                conversation,
                estimatedTokens: estimated,
                settings: settings,
                force: false
            )
        }

        return budget.totalUtilization >= resolveCompactThreshold(settings.dynamicCompaction)
    }

    static func meetsStaticTruncateThreshold(conversation: [ChatMessage], settings: ContextCompactionSettings) -> Bool {
        let estimated = ContextTokenEstimator.estimate(
            conversation,
            includeReasoningInModelContext: settings.includeReasoningInModelContext
        )
        return ConversationCutoffPlanner.shouldTruncateArgs(
            conversation,
            estimatedTokens: estimated,
            settings: settings.truncateArgs
        )
    }

    static func meetsStaticCompactThreshold(conversation: [ChatMessage], settings: ContextCompactionSettings) -> Bool {
        let estimated = ContextTokenEstimator.estimate(
            conversation,
            includeReasoningInModelContext: settings.includeReasoningInModelContext
        )
        return ConversationCutoffPlanner.shouldCompact(
            conversation,
            estimatedTokens: estimated,
            settings: settings,
            force: false
        )
    }

    private static func resolveStaticKeepTokenBudget(
        conversation: [ChatMessage],
        settings: ContextCompactionSettings
    ) -> Int {
        if settings.keepTokens > 0 { return settings.keepTokens }
        if settings.keepMessages <= 0 || conversation.isEmpty { return 0 }

        let tailStart = max(0, conversation.count - settings.keepMessages)
        return ContextTokenEstimator.estimateSuffix(
            conversation,
            startIndex: tailStart,
            includeReasoningInModelContext: settings.includeReasoningInModelContext
        )
    }
}
