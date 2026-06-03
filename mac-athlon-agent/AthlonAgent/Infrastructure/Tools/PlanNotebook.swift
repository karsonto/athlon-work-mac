import Foundation

protocol AgentSessionContext: AnyObject {
    var sessionId: String? { get }
}

enum SubTaskJsonParser {
    private struct DTO: Decodable {
        let name: String?
        let description: String?
        let expectedOutcome: String?
        let expected_outcome: String?
        let files: [String]?

        enum CodingKeys: String, CodingKey {
            case name, description, expectedOutcome, expected_outcome, files
        }

        var resolvedExpectedOutcome: String? {
            expectedOutcome ?? expected_outcome
        }
    }

    static func parse(_ json: String) throws -> [SubTaskInput] {
        guard !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolError.failed("Invalid subtasks", detail: "subtasks must be a non-empty JSON array.")
        }
        guard let data = json.data(using: .utf8) else {
            throw ToolError.failed("Invalid subtasks", detail: "subtasks must be valid UTF-8 JSON.")
        }
        let items = try JSONDecoder().decode([DTO].self, from: data)
        guard !items.isEmpty else {
            throw ToolError.failed("Invalid subtasks", detail: "subtasks must contain at least one subtask object.")
        }
        return try items.enumerated().map { index, item in
            guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                throw ToolError.failed("Invalid subtasks", detail: "subtasks[\(index)] requires a non-empty 'name'.")
            }
            return SubTaskInput(
                name: name,
                description: item.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                expectedOutcome: item.resolvedExpectedOutcome?.trimmingCharacters(in: .whitespacesAndNewlines),
                files: item.files ?? []
            )
        }
    }
}

struct PlanOperationResult {
    let success: Bool
    let message: String
}

final class PlanNotebook {
    private var plans: [String: AgentPlan] = [:]
    private let settings: PlanSettings
    private let workspaceGuard: WorkspaceGuard
    private weak var sessionManager: SessionManager?

    init(settings: PlanSettings, workspaceGuard: WorkspaceGuard, sessionManager: SessionManager? = nil) {
        self.settings = settings
        self.workspaceGuard = workspaceGuard
        self.sessionManager = sessionManager
    }

    func getCurrent(sessionId: String) -> AgentPlan? {
        if let cached = plans[sessionId] {
            return cached
        }
        if let session = sessionManager?.getSession(sessionId), let plan = session.plan {
            plans[sessionId] = plan
            return plan
        }
        return nil
    }

    func createPlan(sessionId: String, request: CreatePlanRequest) -> PlanOperationResult {
        guard !sessionId.isEmpty else {
            return PlanOperationResult(success: false, message: "No active session.")
        }
        if let validationError = PlanValidation.validateCreateRequest(request, settings: settings) {
            return validationError
        }

        let previous = plans[sessionId]?.name
        let plan = PlanValidation.toPlan(request, phase: .draft)
        persist(sessionId: sessionId, plan: plan)

        var message = previous == nil
            ? "Plan '\(plan.name)' created successfully."
            : "The current plan named '\(previous!)' is replaced by the newly created plan named '\(plan.name)'."
        message += appendSyncNote(syncPlanFile(plan))
        return PlanOperationResult(success: true, message: message)
    }

    func approvePlan(sessionId: String) -> PlanOperationResult {
        guard !sessionId.isEmpty else {
            return PlanOperationResult(success: false, message: "No active session.")
        }
        guard var plan = getCurrent(sessionId: sessionId) else {
            return PlanOperationResult(success: false, message: "There is no active plan. Call create_plan first.")
        }
        guard plan.phase == .draft else {
            return PlanOperationResult(success: false, message: "The plan is already approved.")
        }
        guard !plan.subtasks.isEmpty else {
            return PlanOperationResult(success: false, message: "The plan has no subtasks.")
        }

        for index in plan.subtasks.indices {
            if plan.subtasks[index].status == .inProgress || plan.subtasks[index].status == .done {
                plan.subtasks[index].status = .pending
            }
        }
        plan.subtasks[0].status = .inProgress
        plan.phase = .approved
        persist(sessionId: sessionId, plan: plan)

        var message =
            "Plan '\(plan.name)' approved. Subtask (at index 0) named '\(plan.subtasks[0].name)' is now in progress."
        message += appendSyncNote(syncPlanFile(plan))
        return PlanOperationResult(success: true, message: message)
    }

    func finishSubtask(sessionId: String, subtaskIndex: Int, outcome: String) -> PlanOperationResult {
        guard !sessionId.isEmpty else {
            return PlanOperationResult(success: false, message: "No active session.")
        }
        guard var plan = getCurrent(sessionId: sessionId) else {
            return PlanOperationResult(success: false, message: "There is no active plan. Call create_plan first.")
        }
        guard plan.phase == .approved else {
            return PlanOperationResult(
                success: false,
                message: "The plan is not approved yet. Review the plan and click Build before calling finish_subtask."
            )
        }
        guard subtaskIndex >= 0, subtaskIndex < plan.subtasks.count else {
            return PlanOperationResult(
                success: false,
                message: "Invalid subtask_idx '\(subtaskIndex)'. Must be between 0 and \(plan.subtasks.count - 1)."
            )
        }
        for index in 0..<subtaskIndex {
            let previous = plan.subtasks[index]
            if previous.status != .done && previous.status != .abandoned {
                return PlanOperationResult(
                    success: false,
                    message: "Cannot finish subtask at index \(subtaskIndex) because the previous subtask "
                        + "(at index \(index)) named '\(previous.name)' is not done yet. Finish previous subtasks first."
                )
            }
        }
        guard !outcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return PlanOperationResult(success: false, message: "subtask_outcome is required.")
        }

        plan.subtasks[subtaskIndex].status = .done
        plan.subtasks[subtaskIndex].outcome = outcome.trimmingCharacters(in: .whitespacesAndNewlines)

        var message: String
        if subtaskIndex + 1 < plan.subtasks.count {
            plan.subtasks[subtaskIndex + 1].status = .inProgress
            let current = plan.subtasks[subtaskIndex]
            let next = plan.subtasks[subtaskIndex + 1]
            message = "Subtask (at index \(subtaskIndex)) named '\(current.name)' is marked as done successfully. "
                + "The next subtask (at index \(subtaskIndex + 1)) named '\(next.name)' is activated."
        } else {
            let current = plan.subtasks[subtaskIndex]
            message = "Subtask (at index \(subtaskIndex)) named '\(current.name)' is marked as done successfully."
        }

        persist(sessionId: sessionId, plan: plan)
        message += appendSyncNote(syncPlanFile(plan))
        return PlanOperationResult(success: true, message: message)
    }

    func getPlanMarkdown(sessionId: String, detailed: Bool = true) -> String {
        guard !sessionId.isEmpty else { return "No active session." }
        guard let plan = getCurrent(sessionId: sessionId) else {
            return "There is no active plan. Call create_plan first."
        }
        return PlanMarkdownFormatter.toMarkdown(plan, detailed: detailed)
    }

    func clear(sessionId: String) {
        plans.removeValue(forKey: sessionId)
        sessionManager?.updatePlan(nil, for: sessionId)
        if let path = planFilePath(), FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private func persist(sessionId: String, plan: AgentPlan) {
        plans[sessionId] = plan
        sessionManager?.updatePlan(plan, for: sessionId)
    }

    @discardableResult
    private func syncPlanFile(_ plan: AgentPlan) -> String {
        guard let path = planFilePath() else { return "not_written" }
        let markdown = PlanMarkdownFormatter.toMarkdown(plan, detailed: true) + "\n"
        try? markdown.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private func planFilePath() -> String? {
        guard let root = workspaceGuard.tryGetWorkspaceRoot() else { return nil }
        let fileName = settings.planFileName.isEmpty ? "plan.md" : settings.planFileName
        return (root as NSString).appendingPathComponent(fileName)
    }

    private func appendSyncNote(_ syncResult: String) -> String {
        syncResult == "not_written"
            ? " (plan kept in session memory only; no workspace configured for plan.md sync.)"
            : " (Synced to \(syncResult).)"
    }
}

enum PlanToolBase {
    static func requireSessionId(_ context: AgentSessionContext) -> String? {
        guard let sessionId = context.sessionId, !sessionId.isEmpty else { return nil }
        return sessionId
    }
}
