import Foundation

enum PlanValidation {
    static func validateCreateRequest(_ request: CreatePlanRequest, settings: PlanSettings) -> PlanOperationResult? {
        if request.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return PlanOperationResult(success: false, message: "Plan name is required.")
        }
        if request.subtasks.isEmpty {
            return PlanOperationResult(success: false, message: "At least one subtask is required.")
        }
        if request.subtasks.count > settings.maxSubtasks {
            return PlanOperationResult(
                success: false,
                message: "Cannot create plan: \(request.subtasks.count) subtasks exceeds the maximum of \(settings.maxSubtasks)."
            )
        }

        let overview = resolveOverview(request)
        if overview.count < settings.minOverviewChars {
            return PlanOperationResult(
                success: false,
                message: "overview must be at least \(settings.minOverviewChars) characters (Markdown: context, goals, key decisions)."
            )
        }

        for (index, subtask) in request.subtasks.enumerated() {
            if subtask.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return PlanOperationResult(success: false, message: "subtasks[\(index)] requires a non-empty name.")
            }
            let description = subtask.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if description.count < settings.minSubtaskDescriptionChars {
                return PlanOperationResult(
                    success: false,
                    message: "subtasks[\(index)].description must be at least \(settings.minSubtaskDescriptionChars) characters "
                        + "(concrete changes, paths, types, or commands)."
                )
            }
            let expected = subtask.expectedOutcome?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if expected.count < settings.minSubtaskExpectedOutcomeChars {
                return PlanOperationResult(
                    success: false,
                    message: "subtasks[\(index)].expected_outcome must be at least \(settings.minSubtaskExpectedOutcomeChars) characters "
                        + "(measurable acceptance criteria)."
                )
            }
        }
        return nil
    }

    static func resolveOverview(_ request: CreatePlanRequest) -> String {
        let overview = request.overview.trimmingCharacters(in: .whitespacesAndNewlines)
        if !overview.isEmpty { return overview }
        return request.description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func toPlan(_ request: CreatePlanRequest, phase: PlanPhase = .draft) -> AgentPlan {
        let subtasks = request.subtasks.enumerated().map { index, input in
            PlanSubtask(
                id: UUID().uuidString,
                index: index,
                name: input.name,
                description: input.description ?? "",
                expectedOutcome: input.expectedOutcome ?? "",
                files: input.files,
                status: index == 0 ? .inProgress : .pending,
                outcome: nil
            )
        }
        let overview = resolveOverview(request)
        return AgentPlan(
            id: UUID().uuidString,
            name: request.name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: request.description.trimmingCharacters(in: .whitespacesAndNewlines),
            expectedOutcome: request.expectedOutcome.trimmingCharacters(in: .whitespacesAndNewlines),
            overview: overview.isEmpty ? request.description : overview,
            architecture: request.architecture?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            mermaid: request.mermaid?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            testingStrategy: request.testingStrategy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            outOfScope: request.outOfScope?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            subtasks: subtasks,
            phase: phase,
            createdAt: Date()
        )
    }
}
