import Foundation

enum ContextBudgetCalculator {
    static func compute(
        environmentPrompt: String,
        tools: [ToolDefinition],
        messages: [ChatMessage],
        compactionSettings: ContextCompactionSettings,
        modelSettings: ModelSettings,
        calibrationMultiplier: Double = 1.0
    ) -> ContextBudgetSnapshot {
        let dynamic = compactionSettings.dynamicCompaction
        let totalWindow = max(1, compactionSettings.contextWindowTokens)
        let reservedOutput = modelSettings.maxTokens > 0
            ? modelSettings.maxTokens
            : dynamic.defaultReservedOutputTokens

        let systemTokens = ContextTokenEstimator.estimateTextTokens(environmentPrompt, calibrationMultiplier: calibrationMultiplier)
        let toolsTokens = estimateToolsTokens(tools, calibrationMultiplier: calibrationMultiplier)
        let margin = Int(floor(Double(totalWindow) * dynamic.safetyMarginRatio))
        let fixedOverhead = systemTokens + toolsTokens + margin
        let historyBudget = max(512, totalWindow - reservedOutput - fixedOverhead)

        let conversation = filterConversation(messages)
        let estimatedHistory = ContextTokenEstimator.estimate(
            conversation,
            includeReasoningInModelContext: compactionSettings.includeReasoningInModelContext,
            calibrationMultiplier: calibrationMultiplier
        )
        let utilization = historyBudget > 0 ? Double(estimatedHistory) / Double(historyBudget) : 1.0

        return ContextBudgetSnapshot(
            totalWindow: totalWindow,
            reservedOutput: reservedOutput,
            fixedOverhead: fixedOverhead,
            historyBudget: historyBudget,
            estimatedHistory: estimatedHistory,
            utilization: utilization
        )
    }

    static func recomputeHistory(
        snapshot: ContextBudgetSnapshot,
        messages: [ChatMessage],
        compactionSettings: ContextCompactionSettings,
        calibrationMultiplier: Double = 1.0
    ) -> ContextBudgetSnapshot {
        let conversation = filterConversation(messages)
        let estimatedHistory = ContextTokenEstimator.estimate(
            conversation,
            includeReasoningInModelContext: compactionSettings.includeReasoningInModelContext,
            calibrationMultiplier: calibrationMultiplier
        )
        return snapshot.withHistoryEstimate(estimatedHistory, historyBudget: snapshot.historyBudget)
    }

    private static func estimateToolsTokens(_ tools: [ToolDefinition], calibrationMultiplier: Double) -> Int {
        guard !tools.isEmpty else { return 0 }
        var total = 0
        for tool in tools {
            total += ContextTokenEstimator.estimateTextTokens(tool.name, calibrationMultiplier: calibrationMultiplier)
            total += ContextTokenEstimator.estimateTextTokens(tool.description, calibrationMultiplier: calibrationMultiplier)
            total += ContextTokenEstimator.estimateTextTokens(tool.source ?? "", calibrationMultiplier: calibrationMultiplier)
            if let parameters = tool.parameters {
                for (key, value) in parameters {
                    total += ContextTokenEstimator.estimateTextTokens(key, calibrationMultiplier: calibrationMultiplier)
                    if let stringValue = value as? String {
                        total += ContextTokenEstimator.estimateTextTokens(stringValue, calibrationMultiplier: calibrationMultiplier)
                    }
                }
            }
        }
        total += ContextTokenEstimator.estimateTextTokens("schema-overhead", calibrationMultiplier: calibrationMultiplier)
        return total
    }

    private static func filterConversation(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.filter { $0.role != .compaction }
    }
}
