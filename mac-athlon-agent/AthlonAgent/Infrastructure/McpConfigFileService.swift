import Foundation

enum McpConfigFileService {
    static let fileName = "mcp.json"

    static func path(_ paths: AppPathProvider = .shared) -> String {
        (paths.configPath as NSString).appendingPathComponent(fileName)
    }

    static func loadServers(_ paths: AppPathProvider = .shared) -> [McpServerSettings] {
        let filePath = path(paths)
        guard FileManager.default.fileExists(atPath: filePath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              let text = String(data: data, encoding: .utf8),
              let config = ClaudeDesktopMcpConfigMapper.parse(text) else {
            return []
        }
        return ClaudeDesktopMcpConfigMapper.toSettingsList(config)
    }

    static func saveServers(_ servers: [McpServerSettings], paths: AppPathProvider = .shared) throws {
        paths.ensureCreated()
        let config = ClaudeDesktopMcpConfigMapper.fromSettingsList(servers)
        let text = try ClaudeDesktopMcpConfigMapper.serialize(config)
        try writeAtomic(path: path(paths), contents: text)
    }

    private static func writeAtomic(path: String, contents: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let tempURL = url.deletingLastPathComponent().appendingPathComponent(".mcp.json.tmp")
        try contents.write(to: tempURL, atomically: true, encoding: .utf8)
        if FileManager.default.fileExists(atPath: path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: url)
        }
    }
}
