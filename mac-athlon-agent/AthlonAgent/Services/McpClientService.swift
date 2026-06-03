import Foundation
import Combine

// MARK: - MCP Client Service
/// Mirrors `settings.mcpServers` for UI and delegates connections to `McpRegistry`.
@MainActor
final class McpClientService: ObservableObject {
    @Published var servers: [McpServerItem] = []
    @Published var connectionStates: [String: McpUiConnectionState] = [:]

    private let registry: McpRegistry

    init(registry: McpRegistry? = nil) {
        self.registry = registry ?? McpRegistry()
    }

    /// Rebuild UI items from persisted settings (single source: `config/mcp.json` via `SettingsStore`).
    func syncFromSettings(_ mcpServers: [McpServerSettings]) {
        var previousTools: [String: [String]] = [:]
        for server in servers {
            previousTools[server.name] = server.toolNames
        }

        servers = mcpServers.map { settings in
            let name = settings.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let transport = settings.transportType.isEmpty ? "stdio" : settings.transportType
            let summary: String
            if McpTransportKinds.isStreamableHttp(transport) {
                summary = settings.url.isEmpty ? "Streamable HTTP" : settings.url
            } else {
                let cmd = [settings.command] + settings.args
                summary = cmd.filter { !$0.isEmpty }.joined(separator: " ")
            }
            return McpServerItem(
                id: settings.id,
                name: name.isEmpty ? settings.id : name,
                summary: summary.isEmpty ? "MCP server" : summary,
                toolNames: previousTools[name] ?? [],
                isEnabled: settings.enabled,
                isStatusHealthy: false,
                isStatusError: false
            )
        }
    }

    // MARK: - Connection Management
    func refreshConnections(settings: [McpServerSettings], workspaceRoot: String?) {
        syncFromSettings(settings)
        Task {
            await registry.refresh(servers: settings, workspaceRoot: workspaceRoot)
            await syncStatusesFromRegistry()
        }
    }

    func connect(to serverId: String, settings: [McpServerSettings], workspaceRoot: String?) {
        connectionStates[serverId] = .connecting
        refreshConnections(settings: settings, workspaceRoot: workspaceRoot)
    }

    func disconnect(from serverId: String) {
        connectionStates[serverId] = .disconnected
    }

    private func syncStatusesFromRegistry() async {
        let statuses = await registry.getStatuses()
        var toolNamesByServer: [String: [String]] = [:]
        for status in statuses {
            let uiState: McpUiConnectionState
            switch status.state {
            case .connected: uiState = .connected
            case .connecting: uiState = .connecting
            case .error: uiState = .error
            case .disabled: uiState = .disconnected
            }
            connectionStates[status.name] = uiState
            toolNamesByServer[status.name] = status.tools.map(\.name)
        }

        for index in servers.indices {
            let name = servers[index].name
            if let tools = toolNamesByServer[name] {
                servers[index].toolNames = tools
                servers[index].isStatusHealthy = connectionStates[name] == .connected
                servers[index].isStatusError = connectionStates[name] == .error
            }
        }
    }

    // MARK: - Tool Execution
    func executeTool(
        serverId: String,
        toolName: String,
        arguments: [String: Any],
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        var args: [String: String] = [:]
        for (key, value) in arguments {
            args[key] = String(describing: value)
        }

        let serverName = servers.first(where: { $0.id == serverId || $0.name == serverId })?.name ?? serverId
        Task {
            let result = await registry.invoke(serverName: serverName, toolName: toolName, args: args)
            await MainActor.run {
                if result.succeeded {
                    completion(.success(result.content ?? result.summary))
                } else {
                    completion(.failure(NSError(
                        domain: "Athlon.MCP",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: result.error ?? result.summary]
                    )))
                }
            }
        }
    }

    // MARK: - State Helpers
    func connectionState(for serverId: String) -> McpUiConnectionState {
        connectionStates[serverId] ?? .disconnected
    }

    var connectedServers: [McpServerItem] {
        servers.filter { connectionStates[$0.id] == .connected || connectionStates[$0.name] == .connected }
    }

    var registryProvider: McpRegistryProviding { registry }
}

// MARK: - Connection State
enum McpUiConnectionState: String {
    case disconnected = "未连接"
    case connecting = "连接中"
    case connected = "已连接"
    case error = "错误"

    var isConnected: Bool { self == .connected }
    var isActive: Bool { self == .connected || self == .connecting }
}
