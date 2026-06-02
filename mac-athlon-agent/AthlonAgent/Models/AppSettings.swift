import Foundation

// MARK: - App Settings
struct AppSettings: Codable {
    var model: ModelSettings
    var mcpServers: [McpServerSettings]
    var skills: [SkillSettings]
    var workspaceIgnore: WorkspaceIgnoreSettings
    var workspaces: [WorkspaceSettings]
    var appearance: AppearanceSettings

    static let `default` = AppSettings(
        model: ModelSettings(),
        mcpServers: [],
        skills: [],
        workspaceIgnore: WorkspaceIgnoreSettings(),
        workspaces: [],
        appearance: AppearanceSettings()
    )
}

// MARK: - Model Settings
struct ModelSettings: Codable {
    var provider: String = "openai"
    var endpoint: String = "https://api.openai.com/v1"
    var modelName: String = "gpt-4o"
    var maxTokens: Int = 0
    var enableStreaming: Bool = true
    var apiKey: String = ""
}

// MARK: - MCP Server Settings
struct McpServerSettings: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var command: String
    var args: [String]
    var enabled: Bool
    var env: [String: String]?
}

// MARK: - Skill Settings
struct SkillSettings: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var enabled: Bool
    var path: String?
}

// MARK: - Workspace Ignore
struct WorkspaceIgnoreSettings: Codable {
    var directoryNames: [String] = [
        "node_modules", "dist", ".next", "build", "bin", "obj",
        ".git", ".svn", "__pycache__", ".venv", "venv",
        ".idea", ".vs", ".vscode", "target", "Debug", "Release"
    ]
}

// MARK: - Workspace Settings
struct WorkspaceSettings: Identifiable, Codable {
    var id: String = UUID().uuidString
    var rootPath: String
    var name: String
    var ignorePatterns: [String]?
}

// MARK: - Appearance Settings
struct AppearanceSettings: Codable {
    var theme: String = "dark"
    var fontSize: Double = 14.0
}
