import Foundation

protocol McpToolInvoking: AnyObject {
    func invokeMcpTool(serverName: String, toolName: String, arguments: [String: String]) async throws -> String
}

final class ToolRouter {
    private let tools: [String: any AgentTool]

    init(tools: [any AgentTool]) {
        var map: [String: any AgentTool] = [:]
        for tool in tools {
            map[tool.name.lowercased()] = tool
        }
        self.tools = map
    }

    func listTools() -> [any AgentTool] {
        tools.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func invoke(toolName: String, arguments: [String: String]) async throws -> String {
        guard let tool = tools[toolName.lowercased()] else {
            throw ToolError.failed("Tool not found", detail: "No tool named '\(toolName)' is registered.")
        }
        return try await tool.invoke(arguments: arguments)
    }
}
