import XCTest
@testable import AthlonAgent

private final class MockMcpRegistry: McpRegistryProviding {
    func getStatuses() async -> [McpServerStatus] { [] }

    func listToolDefinitions() async -> [ToolDefinition] {
        [
            ToolDefinition(
                name: "filesystem__list",
                description: "List files",
                parameters: [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string"]
                    ]
                ],
                source: "mcp"
            )
        ]
    }

    func refresh(servers: [McpServerSettings], workspaceRoot: String?) async {}

    func invoke(serverName: String, toolName: String, args: [String: String]) async -> ToolResult {
        .success(summary: "ok", content: "{}")
    }

    func shutdownAll() async {}
}

final class CompositeToolRouterTests: XCTestCase {
    func testListToolDefinitions_includesLocalAndMcpSorted() async {
        let (router, _) = BuiltInTools.makeAll(
            workspaceService: WorkspaceService(),
            settings: .default,
            skillService: SkillService(),
            mcpRegistry: MockMcpRegistry(),
            executeCommandRegistry: ExecuteCommandProcessRegistry()
        )

        let tools = await router.listToolDefinitions()
        // Default settings: 8 core locals (no memory/sub-agent) + 1 MCP mock.
        XCTAssertGreaterThanOrEqual(tools.count, 9)
        XCTAssertNil(tools.first { $0.name == "create_plan" })
        XCTAssertNil(tools.first { $0.name == "get_plan" })
        XCTAssertNil(tools.first { $0.name == "finish_subtask" })

        let mcpTool = tools.first { $0.name == "filesystem__list" }
        XCTAssertNotNil(mcpTool)
        let properties = mcpTool?.parameters?["properties"] as? [String: Any]
        XCTAssertNotNil(properties)
        XCTAssertFalse((properties ?? [:]).isEmpty)

        let names = tools.map(\.name)
        XCTAssertEqual(names, names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }
}
