import Foundation

protocol McpRegistryProviding: AnyObject {
    func getStatuses() async -> [McpServerStatus]
    func listToolDefinitions() async -> [ToolDefinition]
    func refresh(servers: [McpServerSettings], workspaceRoot: String?) async
    func invoke(serverName: String, toolName: String, args: [String: String]) async -> ToolResult
    func shutdownAll() async
}

/// Manages MCP server connections via the official Swift SDK.
actor McpRegistry: McpRegistryProviding {
    private var clients: [String: SdkMcpClient] = [:]
    private var statuses: [String: McpServerStatus] = [:]
    private var toolsByServer: [String: [McpTool]] = [:]
    private var isRefreshing = false

    func getStatuses() -> [McpServerStatus] {
        statuses.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func listToolDefinitions() -> [ToolDefinition] {
        var definitions: [ToolDefinition] = []
        for (serverName, tools) in toolsByServer {
            for tool in tools {
                let encoded = (try? McpToolNameCodec.encode(serverName: serverName, toolName: tool.name)) ?? tool.name
                let description = tool.description.isEmpty
                    ? "MCP tool \(tool.name) (server: \(serverName))."
                    : tool.description
                let schemaHint = " argumentsJson: JSON for inputSchema \(tool.inputSchemaJson)"
                definitions.append(ToolDefinition(
                    name: encoded,
                    description: description + schemaHint,
                    parameters: Self.parametersForMcpTool(tool),
                    source: "mcp"
                ))
            }
        }
        return definitions.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func refresh(servers: [McpServerSettings], workspaceRoot: String?) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let enabled = Dictionary(
            uniqueKeysWithValues: servers
                .filter { $0.enabled && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isValid($0) }
                .map { ($0.name.trimmingCharacters(in: .whitespacesAndNewlines), $0) }
        )

        let existingNames = Array(clients.keys)
        for name in existingNames where enabled[name] == nil {
            await disconnectServer(name, state: .disabled)
        }

        for (name, server) in enabled {
            await reconnectServer(name: name, server: server, workspaceRoot: workspaceRoot)
        }
    }

    func invoke(serverName: String, toolName: String, args: [String: String]) async -> ToolResult {
        guard let client = clients[serverName] else {
            return .failure(
                summary: "MCP server not available",
                error: "Server '\(serverName)' is not enabled or not connected."
            )
        }

        let argumentsJson: String
        if let explicit = args["argumentsJson"], !explicit.isEmpty {
            argumentsJson = explicit
        } else if let data = try? JSONSerialization.data(withJSONObject: args),
                  let text = String(data: data, encoding: .utf8) {
            argumentsJson = text
        } else {
            argumentsJson = "{}"
        }

        do {
            let resultJson = try await client.callTool(name: toolName, argumentsJson: argumentsJson)
            statuses[serverName] = client.status

            if mcpResultIsError(resultJson) {
                return .failure(summary: "MCP tool \(toolName) failed.", error: resultJson)
            }
            return .success(summary: "MCP tool \(toolName) returned.", content: resultJson)
        } catch {
            statuses[serverName] = client.status
            return .failure(summary: "MCP tool call failed", error: error.localizedDescription)
        }
    }

    func shutdownAll() {
        let allClients = Array(clients.values)
        clients.removeAll()
        toolsByServer.removeAll()
        statuses.removeAll()
        for client in allClients {
            client.shutdown()
        }
    }

    // MARK: - Private

    private func reconnectServer(name: String, server: McpServerSettings, workspaceRoot: String?) async {
        await disconnectServer(name, state: .disabled)

        let transport = McpTransportKinds.isStreamableHttp(server.transportType)
            ? "streamable-http"
            : "stdio"
        setStatus(name: name, state: .connecting, transport: transport, tools: [], lastError: nil)

        do {
            let client = try await McpSdkClientFactory.connect(
                name: name,
                server: server,
                workspaceRoot: workspaceRoot
            )
            let tools = try await client.listTools()
            clients[name] = client
            toolsByServer[name] = tools
            statuses[name] = client.status
        } catch {
            setStatus(
                name: name,
                state: .error,
                transport: transport,
                tools: [],
                lastError: error.localizedDescription
            )
        }
    }

    private func disconnectServer(_ name: String, state: McpConnectionState) async {
        let client = clients.removeValue(forKey: name)
        toolsByServer.removeValue(forKey: name)
        client?.shutdown()

        if let transport = statuses[name]?.transport {
            setStatus(name: name, state: state, transport: transport, tools: [], lastError: nil)
        } else {
            statuses.removeValue(forKey: name)
        }
    }

    private func setStatus(
        name: String,
        state: McpConnectionState,
        transport: String,
        tools: [McpTool],
        lastError: String?
    ) {
        statuses[name] = McpServerStatus(name: name, state: state, transport: transport, tools: tools, lastError: lastError)
    }

    private func isValid(_ server: McpServerSettings) -> Bool {
        if McpTransportKinds.isStreamableHttp(server.transportType) {
            return !server.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !server.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func mcpResultIsError(_ resultJson: String) -> Bool {
        guard let data = resultJson.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let isError = json["isError"] as? Bool else {
            return false
        }
        return isError
    }

    private static func parametersForMcpTool(_ tool: McpTool) -> [String: Any] {
        if let schema = McpValueJson.objectSchema(from: tool.inputSchemaJson) {
            return schema
        }
        return [
            "type": "object",
            "properties": [
                "argumentsJson": [
                    "type": "string",
                    "description": "JSON string for MCP inputSchema"
                ] as [String: Any]
            ],
            "required": ["argumentsJson"]
        ]
    }
}
