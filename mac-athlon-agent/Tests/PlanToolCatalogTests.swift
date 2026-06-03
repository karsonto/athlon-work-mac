import XCTest
@testable import AthlonAgent

final class PlanToolCatalogTests: XCTestCase {
    private func tool(_ name: String) -> ToolDefinition {
        ToolDefinition(name: name, description: name, parameters: nil, source: "native")
    }

    func testPlanMode_filtersMutatingAndFinishSubtask() {
        let tools = [
            tool("file_list"), tool("file_write"), tool("execute_command"),
            tool("create_plan"), tool("get_plan"), tool("finish_subtask")
        ]
        let filtered = PlanToolCatalog.filterForSession(tools, mode: .plan, plan: nil)
        let names = Set(filtered.map(\.name))
        XCTAssertTrue(names.contains("file_list"))
        XCTAssertTrue(names.contains("create_plan"))
        XCTAssertFalse(names.contains("file_write"))
        XCTAssertFalse(names.contains("execute_command"))
        XCTAssertFalse(names.contains("finish_subtask"))
    }

    func testAgentMode_withApprovedPlan_includesExecutionTools() {
        let plan = PlanValidation.toPlan(
            CreatePlanRequest(
                name: "P",
                description: "d",
                expectedOutcome: "e",
                overview: String(repeating: "a", count: 200),
                subtasks: [
                    SubTaskInput(name: "s", description: String(repeating: "b", count: 40), expectedOutcome: String(repeating: "c", count: 20), files: [])
                ],
                architecture: nil,
                mermaid: nil,
                testingStrategy: nil,
                outOfScope: nil
            ),
            phase: .approved
        )
        let tools = [
            tool("file_list"), tool("create_plan"), tool("get_plan"), tool("finish_subtask")
        ]
        let filtered = PlanToolCatalog.filterForSession(tools, mode: .agent, plan: plan)
        let names = Set(filtered.map(\.name))
        XCTAssertTrue(names.contains("file_list"))
        XCTAssertTrue(names.contains("get_plan"))
        XCTAssertTrue(names.contains("finish_subtask"))
        XCTAssertFalse(names.contains("create_plan"))
    }
}
