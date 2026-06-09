import Foundation

/// Child agent tool router: local tools excluding nested sub-agent, plus MCP.
final class ChildAgentToolRouter {
    private let localRouter: ToolRouter
    private let mcpRegistry: McpRegistryProviding

    init(localTools: [any AgentTool], mcpRegistry: McpRegistryProviding) {
        let filtered = localTools.filter { !($0 is ExcludedFromChildAgentToolkit) }
        self.localRouter = ToolRouter(tools: filtered)
        self.mcpRegistry = mcpRegistry
    }

    func listTools() -> [any AgentTool] {
        localRouter.listTools()
    }

    func listToolDefinitions() async -> [ToolDefinition] {
        var tools = localRouter.listTools().map { $0.toToolDefinition() }
        tools.append(contentsOf: await mcpRegistry.listToolDefinitions())
        return tools.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func invoke(toolName: String, arguments: [String: String]) async throws -> String {
        if let decoded = McpToolNameCodec.tryDecode(toolName) {
            let result = await mcpRegistry.invoke(
                serverName: decoded.serverName,
                toolName: decoded.toolName,
                args: arguments
            )
            if result.succeeded {
                return result.content ?? result.summary
            }
            throw ToolError.failed(result.summary, detail: result.error ?? "MCP tool failed")
        }
        return try await localRouter.invoke(toolName: toolName, arguments: arguments)
    }
}

extension ChildAgentToolRouter {
    func asCompositeRouter() -> CompositeToolRouter {
        CompositeToolRouter(localTools: listTools(), mcpRegistry: mcpRegistry)
    }
}
