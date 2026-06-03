import Foundation

enum PlanAutoContinueDefaults {
    static let continueUserMessage = """
    Auto-continue: an in-progress subtask remains on the plan. Call get_plan first. Continue only that subtask; call finish_subtask with a concrete outcome when it is done. Do not claim the overall task is complete until every subtask is done or abandoned. If the current subtask is too large for one turn, split remaining work into smaller subtasks via create_plan before proceeding.
    """
}

enum PlanAutoContinueProgress {
    static func hasInProgressSubtask(_ plan: AgentPlan?) -> Bool {
        plan?.subtasks.contains { $0.status == .inProgress } == true
    }
}

enum PlanAutoContinuePolicy {
    static func shouldScheduleContinue(
        autoContinueEnabled: Bool,
        completedAutoContinueRounds: Int,
        maxRounds: Int,
        cancelled: Bool,
        timedOut: Bool,
        error: Error?,
        plan: AgentPlan?
    ) -> Bool {
        guard autoContinueEnabled else { return false }
        guard error == nil else { return false }
        if cancelled && !timedOut { return false }
        if completedAutoContinueRounds >= maxRounds { return false }
        return PlanAutoContinueProgress.hasInProgressSubtask(plan)
    }
}
