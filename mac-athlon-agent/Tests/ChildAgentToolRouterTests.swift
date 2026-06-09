import XCTest
@testable import AthlonAgent

final class ChildAgentToolRouterTests: XCTestCase {
    func testListToolsExcludesSubAgentToolIncludesOtherLocalTools() async {
        let subAgent = StubSubAgentTool()
        let other = StubNamedTool(name: "file_list")
        let registry = StubMcpRegistry(definitions: [
            ToolDefinition(name: "mcp__srv__search", description: "mcp", parameters: [:], source: "mcp")
        ])

        let router = ChildAgentToolRouter(localTools: [subAgent, other], mcpRegistry: registry)
        let names = router.listTools().map(\.name)

        XCTAssertFalse(names.contains("call_assistant"))
        XCTAssertTrue(names.contains("file_list"))
    }

    func testListToolDefinitionsIncludesMcpTools() async {
        let registry = StubMcpRegistry(definitions: [
            ToolDefinition(name: "mcp__srv__search", description: "mcp", parameters: [:], source: "mcp")
        ])
        let router = ChildAgentToolRouter(localTools: [], mcpRegistry: registry)
        let tools = await router.listToolDefinitions()
        XCTAssertTrue(tools.contains { $0.name == "mcp__srv__search" })
    }

    func testInvokeRoutesMcpThroughSharedRegistry() async throws {
        let registry = StubMcpRegistry(definitions: [
            ToolDefinition(name: "mcp__srv__ping", description: "ping", parameters: [:], source: "mcp")
        ])
        let router = ChildAgentToolRouter(localTools: [], mcpRegistry: registry)

        let result = try await router.invoke(toolName: "mcp__srv__ping", arguments: [:])
        XCTAssertTrue(result.contains("mcp:ping"))
    }
}

private final class StubSubAgentTool: AgentTool, ExcludedFromChildAgentToolkit {
    let name = "call_assistant"
    let description = "sub"
    let parametersSchema: [String: String] = [:]

    func invoke(arguments: [String: String]) async throws -> String { "ok" }
}

private final class StubNamedTool: AgentTool {
    let name: String
    let description: String
    let parametersSchema: [String: String] = [:]

    init(name: String) {
        self.name = name
        self.description = name
    }

    func invoke(arguments: [String: String]) async throws -> String { "ok" }
}

private final class StubMcpRegistry: McpRegistryProviding {
    var definitions: [ToolDefinition]

    init(definitions: [ToolDefinition]) {
        self.definitions = definitions
    }

    func getStatuses() async -> [McpServerStatus] { [] }
    func listToolDefinitions() async -> [ToolDefinition] { definitions }
    func refresh(servers: [McpServerSettings], workspaceRoot: String?) async {}
    func invoke(serverName: String, toolName: String, args: [String: String]) async -> ToolResult {
        .success(summary: "ok", content: "mcp:\(toolName)")
    }
    func shutdownAll() async {}
}
