import Foundation

/// Claude Desktop–compatible MCP configuration: `{ "mcpServers": { "name": { ... } } }`.
struct ClaudeDesktopMcpConfig: Codable {
    var mcpServers: [String: ClaudeDesktopMcpServerEntry]

    init(mcpServers: [String: ClaudeDesktopMcpServerEntry] = [:]) {
        self.mcpServers = mcpServers
    }
}

struct ClaudeDesktopMcpServerEntry: Codable {
    var type: String = "stdio"
    var url: String = ""
    var command: String = ""
    var args: [String] = []
    var env: [String: String] = [:]
    var headers: [String: String] = [:]
    var cwd: String = ""
    var disabled: Bool = false
}

enum ClaudeDesktopMcpConfigMapper {
    static func toSettingsList(_ config: ClaudeDesktopMcpConfig) -> [McpServerSettings] {
        config.mcpServers.compactMap { name, entry in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return McpServerSettings(
                name: trimmed,
                transportType: entry.type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "stdio" : entry.type,
                url: entry.url,
                command: entry.command,
                args: entry.args,
                enabled: !entry.disabled,
                env: entry.env.isEmpty ? nil : entry.env,
                headers: entry.headers,
                workingDirectory: entry.cwd
            )
        }
    }

    static func fromSettingsList(_ servers: [McpServerSettings]) -> ClaudeDesktopMcpConfig {
        var entries: [String: ClaudeDesktopMcpServerEntry] = [:]
        for server in servers {
            let name = server.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            var entry = ClaudeDesktopMcpServerEntry(
                type: server.transportType.isEmpty ? "stdio" : server.transportType,
                url: server.url,
                command: server.command,
                args: server.args,
                env: server.env ?? [:],
                headers: server.headers,
                disabled: !server.enabled
            )
            if !server.workingDirectory.isEmpty {
                entry.cwd = server.workingDirectory
            }
            entries[name] = entry
        }
        return ClaudeDesktopMcpConfig(mcpServers: entries)
    }

    static func parse(_ json: String) -> ClaudeDesktopMcpConfig? {
        guard let data = json.data(using: .utf8) else { return nil }
        if json.contains("mcpServers") {
            return try? JsonCodec.decode(ClaudeDesktopMcpConfig.self, from: data)
        }
        if let legacy = try? JsonCodec.decode([McpServerSettings].self, from: data) {
            return fromSettingsList(legacy)
        }
        return nil
    }

    static func serialize(_ config: ClaudeDesktopMcpConfig) throws -> String {
        let data = try JsonCodec.encode(config)
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "Athlon.MCP", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode MCP config"
            ])
        }
        return text
    }
}
