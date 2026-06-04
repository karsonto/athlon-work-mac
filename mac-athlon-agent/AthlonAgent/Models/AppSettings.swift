import Foundation

// MARK: - App Settings
struct AppSettings: Codable {
    var model: ModelSettings
    var mcpServers: [McpServerSettings]
    var skills: [SkillSettings]
    var workspaceIgnore: WorkspaceIgnoreSettings
    var workspaces: [WorkspaceSettings]
    var appearance: AppearanceSettings
    var ui: UiSettings
    var logging: LoggingSettings
    var contextCompaction: ContextCompactionSettings
    var prompt: PromptSettings
    var agentTurn: AgentTurnSettings
    var fileRead: FileReadSettings
    var toolPermissions: ToolPermissionSettings

    init(
        model: ModelSettings,
        mcpServers: [McpServerSettings],
        skills: [SkillSettings],
        workspaceIgnore: WorkspaceIgnoreSettings,
        workspaces: [WorkspaceSettings],
        appearance: AppearanceSettings,
        ui: UiSettings = UiSettings(),
        logging: LoggingSettings = LoggingSettings(),
        contextCompaction: ContextCompactionSettings = ContextCompactionSettings(),
        prompt: PromptSettings = PromptSettings(),
        agentTurn: AgentTurnSettings = AgentTurnSettings(),
        fileRead: FileReadSettings = FileReadSettings(),
        toolPermissions: ToolPermissionSettings = ToolPermissionSettings()
    ) {
        self.model = model
        self.mcpServers = mcpServers
        self.skills = skills
        self.workspaceIgnore = workspaceIgnore
        self.workspaces = workspaces
        self.appearance = appearance
        self.ui = ui
        self.logging = logging
        self.contextCompaction = contextCompaction
        self.prompt = prompt
        self.agentTurn = agentTurn
        self.fileRead = fileRead
        self.toolPermissions = toolPermissions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(ModelSettings.self, forKey: .model)
        mcpServers = try container.decodeIfPresent([McpServerSettings].self, forKey: .mcpServers) ?? []
        skills = try container.decodeIfPresent([SkillSettings].self, forKey: .skills) ?? []
        workspaceIgnore = try container.decodeIfPresent(WorkspaceIgnoreSettings.self, forKey: .workspaceIgnore)
            ?? WorkspaceIgnoreSettings()
        workspaces = try container.decodeIfPresent([WorkspaceSettings].self, forKey: .workspaces) ?? []
        appearance = try container.decodeIfPresent(AppearanceSettings.self, forKey: .appearance)
            ?? AppearanceSettings()
        ui = try container.decodeIfPresent(UiSettings.self, forKey: .ui) ?? UiSettings()
        logging = try container.decodeIfPresent(LoggingSettings.self, forKey: .logging) ?? LoggingSettings()
        contextCompaction = try container.decodeIfPresent(ContextCompactionSettings.self, forKey: .contextCompaction)
            ?? ContextCompactionSettings()
        prompt = try container.decodeIfPresent(PromptSettings.self, forKey: .prompt) ?? PromptSettings()
        agentTurn = try container.decodeIfPresent(AgentTurnSettings.self, forKey: .agentTurn) ?? AgentTurnSettings()
        fileRead = try container.decodeIfPresent(FileReadSettings.self, forKey: .fileRead) ?? FileReadSettings()
        toolPermissions = try container.decodeIfPresent(ToolPermissionSettings.self, forKey: .toolPermissions)
            ?? ToolPermissionSettings()
    }

    private enum CodingKeys: String, CodingKey {
        case model, mcpServers, skills, workspaceIgnore, workspaces, appearance, ui, logging
        case contextCompaction, prompt, agentTurn, fileRead, toolPermissions
    }

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
    static let apiKeySecretName = "model-api-key"

    var provider: String = "openai"
    var endpoint: String = "https://api.openai.com/v1"
    var modelName: String = "gpt-4o"
    var maxTokens: Int = 0
    var enableStreaming: Bool = true
    var streamingIdleTimeoutSeconds: Int = 90
    var apiKey: String = ""
}

// MARK: - MCP Server Settings
struct McpServerSettings: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var transportType: String = "stdio"
    var url: String = ""
    var command: String
    var args: [String]
    var enabled: Bool
    var env: [String: String]?
    var headers: [String: String] = [:]
    var workingDirectory: String = ""

    init(
        id: String = UUID().uuidString,
        name: String,
        transportType: String = "stdio",
        url: String = "",
        command: String,
        args: [String],
        enabled: Bool,
        env: [String: String]? = nil,
        headers: [String: String] = [:],
        workingDirectory: String = ""
    ) {
        self.id = id
        self.name = name
        self.transportType = transportType
        self.url = url
        self.command = command
        self.args = args
        self.enabled = enabled
        self.env = env
        self.headers = headers
        self.workingDirectory = workingDirectory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decode(String.self, forKey: .name)
        transportType = try container.decodeIfPresent(String.self, forKey: .transportType) ?? "stdio"
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        command = try container.decode(String.self, forKey: .command)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        enabled = try container.decode(Bool.self, forKey: .enabled)
        env = try container.decodeIfPresent([String: String].self, forKey: .env)
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory) ?? ""
    }
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

// MARK: - UI Settings
struct UiSettings: Codable {
    var theme: String = "Dark"
    var fontSize: Double = 14
    var contextSidebarVisible: Bool = true
    var contextSidebarWidth: Double = 300
    var navigationSidebarWidth: Double = 220
    var editorPaneWidth: Double = 480
    var composerHeight: Double = 168
}

// MARK: - Logging Settings
struct LoggingSettings: Codable {
    var directory: String = ""
    var minimumLevel: String = "Information"
    var retainedDays: Int = 14
    var maxFileSizeBytes: Int64 = 10 * 1024 * 1024
}

// MARK: - Prompt Settings
struct PromptSettings: Codable {
    var maxAgentsMdChars: Int = 4_000
    var maxKnowledgeMdChars: Int = 1_500
    var maxKnowledgeCatalogEntries: Int = 50
}

// MARK: - Agent Turn Settings
struct AgentTurnSettings: Codable, Equatable {
    var timeoutMinutes: Int = AgentTurnSettings.defaultTimeoutMinutes

    static let minTimeoutMinutes = 1
    static let maxTimeoutMinutes = 180
    static let defaultTimeoutMinutes = 30

    func resolveTurnTimeout() -> TimeInterval? {
        guard timeoutMinutes > 0 else { return nil }
        let clamped = min(max(timeoutMinutes, Self.minTimeoutMinutes), Self.maxTimeoutMinutes)
        return TimeInterval(clamped * 60)
    }

    func resolveTurnTimeoutMinutes() -> Int {
        guard let timeout = resolveTurnTimeout() else { return 0 }
        return Int(timeout / 60)
    }
}
