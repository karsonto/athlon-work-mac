import Foundation

struct CreatePlanTool: AgentTool {
    let name = PlanToolCatalog.createPlan
    let description =
        "Create a detailed implementation plan (Cursor-style spec). Replaces any existing session plan. "
        + "Use after researching the codebase. Each subtask needs concrete files and measurable acceptance."
    let parametersSchema: [String: String] = [
        "name": "Short plan title",
        "description": "One-sentence summary for quick reference",
        "expected_outcome": "Measurable outcome for the entire plan",
        "overview": "Required Markdown: background, goals, constraints, and key technical decisions (min ~200 chars).",
        "architecture": "Optional Markdown: components, data flow, trade-offs",
        "mermaid": "Optional Mermaid diagram source (no fences)",
        "testing_strategy": "Optional Markdown: how to verify the work",
        "out_of_scope": "Optional Markdown: what this plan explicitly excludes",
        "subtasks": """
        JSON array: name, description, expected_outcome, optional files[]. \
        Example: [{"name":"Step 1","description":"...","expected_outcome":"...","files":["src/foo.swift"]}]
        """
    ]

    private let planNotebook: PlanNotebook
    private weak var sessionContext: AgentSessionContext?

    init(planNotebook: PlanNotebook, sessionContext: AgentSessionContext) {
        self.planNotebook = planNotebook
        self.sessionContext = sessionContext
    }

    func invoke(arguments: [String: String]) async throws -> String {
        guard let sessionContext, let sessionId = PlanToolBase.requireSessionId(sessionContext) else {
            throw ToolError.failed("No session", detail: "No active agent session. Cannot use plan tools.")
        }

        let name = try ToolArguments.required(arguments, name: "name", tool: self.name)
        let description = try ToolArguments.required(arguments, name: "description", tool: self.name)
        let expectedOutcome = try ToolArguments.required(arguments, name: "expected_outcome", tool: self.name)
        let overview = try ToolArguments.required(arguments, name: "overview", tool: self.name)
        let subtasksJson = try ToolArguments.required(arguments, name: "subtasks", tool: self.name)
        let subtasks = try SubTaskJsonParser.parse(subtasksJson)

        let result = planNotebook.createPlan(
            sessionId: sessionId,
            request: CreatePlanRequest(
                name: name,
                description: description,
                expectedOutcome: expectedOutcome,
                overview: overview,
                subtasks: subtasks,
                architecture: arguments["architecture"],
                mermaid: arguments["mermaid"],
                testingStrategy: arguments["testing_strategy"],
                outOfScope: arguments["out_of_scope"]
            )
        )
        if result.success {
            return ToolResultFormatter.success(result.message, content: result.message)
        }
        throw ToolError.failed("Create plan failed", detail: result.message)
    }
}

struct GetPlanTool: AgentTool {
    let name = PlanToolCatalog.getPlan
    let description = "View the current session plan as markdown, including subtask status."
    let parametersSchema = ["detailed": "Optional: true/false for detailed subtask fields (default true)"]

    private let planNotebook: PlanNotebook
    private weak var sessionContext: AgentSessionContext?

    init(planNotebook: PlanNotebook, sessionContext: AgentSessionContext) {
        self.planNotebook = planNotebook
        self.sessionContext = sessionContext
    }

    func invoke(arguments: [String: String]) async throws -> String {
        guard let sessionContext, let sessionId = PlanToolBase.requireSessionId(sessionContext) else {
            throw ToolError.failed("No session", detail: "No active agent session. Cannot use plan tools.")
        }
        let detailed = parseDetailed(arguments)
        let markdown = planNotebook.getPlanMarkdown(sessionId: sessionId, detailed: detailed)
        let hasPlan = planNotebook.getCurrent(sessionId: sessionId) != nil
        return ToolResultFormatter.success(hasPlan ? "Current plan" : markdown, content: markdown)
    }

    private func parseDetailed(_ arguments: [String: String]) -> Bool {
        guard let value = arguments["detailed"], !value.isEmpty else { return true }
        if let parsed = Bool(value) { return parsed }
        return true
    }
}

struct FinishSubtaskTool: AgentTool {
    let name = PlanToolCatalog.finishSubtask
    let description = "Mark a subtask as done with a specific, measurable outcome. Finish subtasks in order."
    let parametersSchema: [String: String] = [
        "subtask_idx": "Zero-based index of the subtask to finish",
        "subtask_outcome": "Specific outcome achieved (data, paths, counts) — not a narrative of what you did"
    ]

    private let planNotebook: PlanNotebook
    private weak var sessionContext: AgentSessionContext?

    init(planNotebook: PlanNotebook, sessionContext: AgentSessionContext) {
        self.planNotebook = planNotebook
        self.sessionContext = sessionContext
    }

    func invoke(arguments: [String: String]) async throws -> String {
        guard let sessionContext, let sessionId = PlanToolBase.requireSessionId(sessionContext) else {
            throw ToolError.failed("No session", detail: "No active agent session. Cannot use plan tools.")
        }
        let outcome = try ToolArguments.required(arguments, name: "subtask_outcome", tool: name)
        let subtaskIndex = ToolArguments.int32(arguments, name: "subtask_idx", defaultValue: -1)
        guard subtaskIndex >= 0 else {
            throw ToolError.missingArgument("subtask_idx", tool: name)
        }

        let result = planNotebook.finishSubtask(sessionId: sessionId, subtaskIndex: subtaskIndex, outcome: outcome)
        if result.success {
            return ToolResultFormatter.success(result.message, content: result.message)
        }
        throw ToolError.failed("Finish subtask failed", detail: result.message)
    }
}
