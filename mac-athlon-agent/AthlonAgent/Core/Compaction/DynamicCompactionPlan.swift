import Foundation

struct DynamicCompactionPlan: Equatable {
    let pressure: ContextPressureLevel
    let applyTruncateArgs: Bool
    let applyPrefixReEvict: Bool
    let applyConversationCompact: Bool
    let keepTokenBudget: Int
    let mustPreserveAppendix: String?

    func withPressure(_ pressure: ContextPressureLevel) -> DynamicCompactionPlan {
        DynamicCompactionPlan(
            pressure: pressure,
            applyTruncateArgs: applyTruncateArgs,
            applyPrefixReEvict: applyPrefixReEvict,
            applyConversationCompact: applyConversationCompact,
            keepTokenBudget: keepTokenBudget,
            mustPreserveAppendix: mustPreserveAppendix
        )
    }

    func withAppliedFlags(truncateApplied: Bool, reEvictApplied: Bool) -> DynamicCompactionPlan {
        DynamicCompactionPlan(
            pressure: pressure,
            applyTruncateArgs: truncateApplied,
            applyPrefixReEvict: reEvictApplied,
            applyConversationCompact: applyConversationCompact,
            keepTokenBudget: keepTokenBudget,
            mustPreserveAppendix: mustPreserveAppendix
        )
    }

    static func create(
        pressure: ContextPressureLevel,
        budget: ContextBudgetSnapshot,
        conversation: [ChatMessage],
        settings: ContextCompactionSettings,
        force: Bool
    ) -> DynamicCompactionPlan {
        let dynamic = settings.dynamicCompaction
        if !dynamic.enabled {
            return DynamicCompactionPlan(
                pressure: pressure,
                applyTruncateArgs: false,
                applyPrefixReEvict: false,
                applyConversationCompact: ContextPressureEvaluator.shouldCompact(
                    budget: budget,
                    conversation: conversation,
                    settings: settings,
                    pressure: pressure,
                    force: force
                ),
                keepTokenBudget: 0,
                mustPreserveAppendix: nil
            )
        }

        let applyTruncate = ContextPressureEvaluator.shouldApplyTruncateArgs(
            budget: budget,
            conversation: conversation,
            settings: settings,
            pressure: pressure,
            force: force
        )
        let applyReEvict = ContextPressureEvaluator.shouldApplyPrefixReEvict(
            budget: budget,
            conversation: conversation,
            settings: settings,
            pressure: pressure,
            force: force
        )
        let applyCompact = ContextPressureEvaluator.shouldCompact(
            budget: budget,
            conversation: conversation,
            settings: settings,
            pressure: pressure,
            force: force
        )
        let keepTokenBudget = ContextPressureEvaluator.resolveKeepTokenBudget(
            budget: budget,
            pressure: pressure,
            conversation: conversation,
            settings: settings,
            includesConversationCompact: applyCompact || force
        )

        var mustPreserve: String?
        if dynamic.enableSemanticCutoff, applyCompact {
            mustPreserve = SemanticCutoffPlanner.buildMustPreserveAppendix(
                conversation: conversation,
                settings: settings,
                keepTokenBudget: keepTokenBudget
            )
        }

        return DynamicCompactionPlan(
            pressure: pressure,
            applyTruncateArgs: applyTruncate,
            applyPrefixReEvict: applyReEvict,
            applyConversationCompact: applyCompact,
            keepTokenBudget: keepTokenBudget,
            mustPreserveAppendix: mustPreserve
        )
    }
}
