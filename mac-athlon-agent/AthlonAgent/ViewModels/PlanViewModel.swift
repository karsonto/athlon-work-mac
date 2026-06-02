import Foundation
import Combine

// MARK: - Plan View Model
/// Manages plan state, subtask lifecycle, and plan-related UI logic.
class PlanViewModel: ObservableObject {
    @Published var plan: AgentPlan?
    @Published var isPlanActive = false
    @Published var canAutoContinue = true

    private let sessionManager: SessionManager
    private let sessionId: String

    private var cancellables = Set<AnyCancellable>()

    init(sessionManager: SessionManager, sessionId: String) {
        self.sessionManager = sessionManager
        self.sessionId = sessionId
        loadPlan()
    }

    // MARK: - Load
    func loadPlan() {
        if let session = sessionManager.getSession(sessionId) {
            self.plan = session.plan
            self.isPlanActive = session.plan != nil
        }
    }

    // MARK: - Create Plan
    func createPlan(name: String, description: String, expectedOutcome: String, subtaskDefs: [(name: String, description: String, expectedOutcome: String)]) {
        let subtasks = subtaskDefs.enumerated().map { idx, def in
            PlanSubtask(
                id: UUID().uuidString,
                index: idx,
                name: def.name,
                description: def.description,
                expectedOutcome: def.expectedOutcome,
                status: idx == 0 ? .inProgress : .pending,
                outcome: nil
            )
        }

        let newPlan = AgentPlan(
            id: UUID().uuidString,
            name: name,
            description: description,
            expectedOutcome: expectedOutcome,
            subtasks: subtasks,
            createdAt: Date()
        )

        self.plan = newPlan
        self.isPlanActive = true
        sessionManager.updatePlan(newPlan, for: sessionId)
    }

    // MARK: - Update Subtask
    func updateSubtaskStatus(_ subtaskId: String, to status: PlanSubtaskStatus, outcome: String? = nil) {
        guard var plan = plan else { return }

        if let idx = plan.subtasks.firstIndex(where: { $0.id == subtaskId }) {
            plan.subtasks[idx].status = status
            if let outcome = outcome {
                plan.subtasks[idx].outcome = outcome
            }
        }

        // If marking as done, activate next pending
        if status == .done {
            activateNextSubtask(in: &plan)
        }

        // Check if all done
        if plan.subtasks.allSatisfy({ $0.status == .done || $0.status == .abandoned }) {
            isPlanActive = false
        }

        self.plan = plan
        sessionManager.updatePlan(plan, for: sessionId)
    }

    func markCurrentSubtaskDone(outcome: String) {
        guard let current = plan?.subtasks.first(where: { $0.status == .inProgress }) else { return }
        updateSubtaskStatus(current.id, to: .done, outcome: outcome)
    }

    private func activateNextSubtask(in plan: inout AgentPlan) {
        if let nextIdx = plan.subtasks.firstIndex(where: { $0.status == .pending }) {
            plan.subtasks[nextIdx].status = .inProgress
        }
    }

    // MARK: - Abandon Subtask
    func abandonSubtask(_ subtaskId: String) {
        updateSubtaskStatus(subtaskId, to: .abandoned)
    }

    // MARK: - Plan Progress
    var progress: PlanProgress {
        guard let plan = plan, !plan.subtasks.isEmpty else {
            return PlanProgress(done: 0, total: 0, percent: 0)
        }
        let done = plan.subtasks.filter { $0.status == .done || $0.status == .abandoned }.count
        let total = plan.subtasks.count
        return PlanProgress(
            done: done,
            total: total,
            percent: Double(done) / Double(total)
        )
    }

    var currentSubtask: PlanSubtask? {
        plan?.subtasks.first { $0.status == .inProgress }
    }

    var remainingSubtasks: [PlanSubtask] {
        plan?.subtasks.filter { $0.status == .pending } ?? []
    }

    // MARK: - Clear Plan
    func clearPlan() {
        plan = nil
        isPlanActive = false
        sessionManager.updatePlan(nil as AgentPlan?, for: sessionId)
    }

    // MARK: - Auto-Continue
    func setAutoContinue(_ enabled: Bool) {
        canAutoContinue = enabled
    }
}

struct PlanProgress {
    let done: Int
    let total: Int
    let percent: Double
}
