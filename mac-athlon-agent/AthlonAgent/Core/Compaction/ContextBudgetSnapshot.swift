import Foundation

struct ContextBudgetSnapshot: Equatable {
    let totalWindow: Int
    let reservedOutput: Int
    let fixedOverhead: Int
    let historyBudget: Int
    let estimatedHistory: Int
    let utilization: Double

    var estimatedTotalPrompt: Int { fixedOverhead + estimatedHistory }
    var usablePromptWindow: Int { max(1, totalWindow - reservedOutput) }
    var totalUtilization: Double { Double(estimatedTotalPrompt) / Double(usablePromptWindow) }
    var availableHistory: Int { max(0, historyBudget - estimatedHistory) }

    func withHistoryEstimate(_ estimatedHistory: Int, historyBudget: Int) -> ContextBudgetSnapshot {
        let budget = historyBudget > 0 ? historyBudget : self.historyBudget
        let util = budget > 0 ? Double(estimatedHistory) / Double(budget) : 1.0
        return ContextBudgetSnapshot(
            totalWindow: totalWindow,
            reservedOutput: reservedOutput,
            fixedOverhead: fixedOverhead,
            historyBudget: budget,
            estimatedHistory: estimatedHistory,
            utilization: util
        )
    }
}
