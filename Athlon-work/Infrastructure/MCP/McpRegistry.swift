import Foundation

nonisolated struct McpServerStatus: Sendable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var enabled: Bool
    var connected: Bool
    var toolCount: Int
    var lastError: String?
}

nonisolated struct McpBoundTool: Sendable {
    var serverName: String
    var descriptor: McpToolDescriptor
    var qualifiedName: String
}

/// Connects enabled MCP servers from AppSettings and exposes tools as AgentTool wrappers.
nonisolated final class McpRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var clients: [String: any McpClient] = [:]
    private var boundTools: [McpBoundTool] = []
    private var statuses: [McpServerStatus] = []

    var serverStatuses: [McpServerStatus] {
        lock.lock(); defer { lock.unlock() }
        return statuses
    }

    var tools: [McpBoundTool] {
        lock.lock(); defer { lock.unlock() }
        return boundTools
    }

    func connect(settings: AppSettings) async {
        await disconnectAll()
        let enabled = settings.mcpServers.filter(\.enabled)
        var nextStatuses: [McpServerStatus] = []
        var nextTools: [McpBoundTool] = []
        var nextClients: [String: any McpClient] = [:]

        for server in enabled {
            guard server.transportType.lowercased() == "stdio" || server.transportType.isEmpty else {
                nextStatuses.append(
                    McpServerStatus(
                        name: server.name,
                        enabled: true,
                        connected: false,
                        toolCount: 0,
                        lastError: "transport \(server.transportType) not yet supported on macOS"
                    )
                )
                continue
            }
            let client = StdioMcpClient(settings: server)
            do {
                try await client.initialize()
                let listed = try await client.listTools()
                nextClients[server.name] = client
                for tool in listed {
                    let qualified = "mcp__\(sanitize(server.name))__\(sanitize(tool.name))"
                    nextTools.append(
                        McpBoundTool(serverName: server.name, descriptor: tool, qualifiedName: qualified)
                    )
                }
                nextStatuses.append(
                    McpServerStatus(
                        name: server.name,
                        enabled: true,
                        connected: true,
                        toolCount: listed.count,
                        lastError: nil
                    )
                )
            } catch {
                await client.close()
                nextStatuses.append(
                    McpServerStatus(
                        name: server.name,
                        enabled: true,
                        connected: false,
                        toolCount: 0,
                        lastError: error.localizedDescription
                    )
                )
            }
        }

        // Include disabled servers for UI status chips.
        for server in settings.mcpServers where !server.enabled {
            nextStatuses.append(
                McpServerStatus(
                    name: server.name,
                    enabled: false,
                    connected: false,
                    toolCount: 0,
                    lastError: nil
                )
            )
        }

        lock.lock()
        clients = nextClients
        boundTools = nextTools
        statuses = nextStatuses.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        lock.unlock()
    }

    func disconnectAll() async {
        lock.lock()
        let snapshot = Array(clients.values)
        clients.removeAll()
        boundTools.removeAll()
        statuses.removeAll()
        lock.unlock()
        for client in snapshot {
            await client.close()
        }
    }

    func call(qualifiedName: String, argumentsJSON: String) async throws -> String {
        lock.lock()
        let match = boundTools.first { $0.qualifiedName == qualifiedName }
        let client = match.flatMap { clients[$0.serverName] }
        let toolName = match?.descriptor.name
        lock.unlock()
        guard let client, let toolName else {
            throw McpClientError.toolError("Unknown MCP tool: \(qualifiedName)")
        }
        return try await client.callTool(name: toolName, argumentsJSON: argumentsJSON)
    }

    func makeAgentTools() -> [any AgentTool] {
        tools.map { bound in
            McpAgentTool(registry: self, bound: bound)
        }
    }

    private func sanitize(_ text: String) -> String {
        text.map { ch in
            ch.isLetter || ch.isNumber || ch == "_" || ch == "-" ? String(ch) : "_"
        }.joined()
    }
}

nonisolated struct McpAgentTool: AgentTool {
    private let registry: McpRegistry
    private let bound: McpBoundTool

    init(registry: McpRegistry, bound: McpBoundTool) {
        self.registry = registry
        self.bound = bound
    }

    var name: String { bound.qualifiedName }

    var definition: ToolDefinition {
        ToolDefinition(
            name: bound.qualifiedName,
            description: "[\(bound.serverName)] \(bound.descriptor.description)",
            parameters: bound.descriptor.inputSchema.isEmpty
                ? ["type": "object", "properties": [:] as [String: Any]]
                : bound.descriptor.inputSchema
        )
    }

    func invoke(arguments: String, context: AgentRunContext) async throws -> String {
        _ = context
        return try await registry.call(qualifiedName: bound.qualifiedName, argumentsJSON: arguments)
    }
}
