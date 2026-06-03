import Foundation

final class CompositeToolRouter {
    private let localRouter: ToolRouter
    private let mcpRegistry: McpRegistryProviding

    init(localTools: [any AgentTool], mcpRegistry: McpRegistryProviding) {
        self.localRouter = ToolRouter(tools: localTools)
        self.mcpRegistry = mcpRegistry
    }

    func listTools() -> [any AgentTool] {
        localRouter.listTools()
    }

    func requiresApproval(toolName: String) -> Bool {
        if BuiltInTools.isBuiltIn(toolName) { return false }
        return localRouter.listTools().first { $0.name == toolName }?.requiresApproval ?? false
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
