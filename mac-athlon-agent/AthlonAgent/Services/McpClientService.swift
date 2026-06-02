import Foundation
import Combine

// MARK: - MCP Client Service
/// Manages MCP (Model Context Protocol) server connections, tool discovery, and runtime status.
class McpClientService: ObservableObject {
    @Published var servers: [McpServerItem] = []
    @Published var connectionStates: [String: McpConnectionState] = [:]

    private let mcpDir: URL

    init(configDirectory: URL? = nil) {
        if let dir = configDirectory {
            self.mcpDir = dir
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.mcpDir = appSupport.appendingPathComponent("AthlonAgent/MCP")
        }
        ensureDirectory()
        loadServers()
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: mcpDir, withIntermediateDirectories: true)
    }

    // MARK: - CRUD
    func loadServers() {
        let fileURL = mcpDir.appendingPathComponent("mcp_servers.json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            servers = defaultServers
            saveServers()
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            servers = try JSONDecoder().decode([McpServerItem].self, from: data)
        } catch {
            servers = defaultServers
        }
    }

    func saveServers() {
        let fileURL = mcpDir.appendingPathComponent("mcp_servers.json")
        do {
            let data = try JSONEncoder().encode(servers)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("MCP save error: \(error)")
        }
    }

    func addServer(_ server: McpServerItem) {
        servers.append(server)
        saveServers()
    }

    func removeServer(_ id: String) {
        servers.removeAll { $0.id == id }
        connectionStates.removeValue(forKey: id)
        saveServers()
    }

    func toggleServer(_ id: String) {
        if let idx = servers.firstIndex(where: { $0.id == id }) {
            servers[idx].isEnabled.toggle()
            saveServers()
        }
    }

    // MARK: - Connection Management
    func connect(to serverId: String) {
        connectionStates[serverId] = .connecting
        // Simulate connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.connectionStates[serverId] = .connected
            // Discover tools
            if let server = self?.servers.first(where: { $0.id == serverId }) {
                self?.discoverTools(for: server)
            }
        }
    }

    func disconnect(from serverId: String) {
        connectionStates[serverId] = .disconnected
    }

    private func discoverTools(for server: McpServerItem) {
        // In production, this calls the MCP server's list_tools method
        // For now, populate with configured tools
        if let idx = servers.firstIndex(where: { $0.id == server.id }) {
            // MCP protocol discovery would happen here
        }
    }

    // MARK: - Tool Execution
    func executeTool(serverId: String, toolName: String, arguments: [String: Any], completion: @escaping (Result<String, Error>) -> Void) {
        // In production: call MCP server's call_tool method
        // For now, return a placeholder
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            completion(.success("Tool \(toolName) executed successfully"))
        }
    }

    // MARK: - State Helpers
    func connectionState(for serverId: String) -> McpConnectionState {
        connectionStates[serverId] ?? .disconnected
    }

    var connectedServers: [McpServerItem] {
        servers.filter { connectionStates[$0.id] == .connected }
    }

    var allAvailableTools: [String] {
        var tools: [String] = []
        for server in servers where server.isEnabled {
            tools.append(contentsOf: server.toolNames)
        }
        return tools
    }

    // MARK: - Defaults
    private var defaultServers: [McpServerItem] {
        [
            McpServerItem(
                id: "filesystem",
                name: "filesystem",
                summary: "Local file system access via MCP",
                toolNames: ["read_file", "write_file", "list_directory", "search_files"],
                isEnabled: true,
                isStatusHealthy: false,
                isStatusError: false
            ),
            McpServerItem(
                id: "web-search",
                name: "web-search",
                summary: "Web search capabilities via Brave Search API",
                toolNames: ["brave_web_search", "brave_local_search"],
                isEnabled: false,
                isStatusHealthy: false,
                isStatusError: false
            )
        ]
    }
}

// MARK: - Connection State
enum McpConnectionState: String {
    case disconnected = "未连接"
    case connecting = "连接中"
    case connected = "已连接"
    case error = "错误"

    var isConnected: Bool { self == .connected }
    var isActive: Bool { self == .connected || self == .connecting }
}
