import Foundation

// MARK: - Root settings (no SSO / License)

nonisolated struct AppSettings: Codable, Hashable, Sendable {
    var model: ModelSettings = .init()
    var toolPermissions: ToolPermissionSettings = .init()
    var mcpServers: [McpServerSettings] = []
    var mcpSearch: McpSearchSettings = .init()
    var skills: [SkillSettings] = []
    var workspaces: [WorkspaceSettings] = []
    var knowledge: KnowledgeSettings = .init()
    var ui: UiSettings = .init()
    var logging: LoggingSettings = .init()
    var contextCompaction: ContextCompactionSettings = .init()
    var prompt: PromptSettings = .init()
    var agentTurn: AgentTurnSettings = .init()
    var workspaceIgnore: WorkspaceIgnoreSettings = .init()
    var fileRead: FileReadSettings = .init()
    var subAgent: SubAgentSettings = .init()
    var parallelToolExecution: ParallelToolExecutionSettings = .init()
    var memory: MemorySettings = .init()
    var schedule: ScheduleSettings = .init()
    var update: UpdateSettings = .init()
    var trainingData: TrainingDataSettings = .init()
    var behaviorReport: BehaviorReportSettings? = BehaviorReportSettings()

    enum CodingKeys: String, CodingKey {
        case model
        case toolPermissions
        case mcpServers
        case mcpSearch
        case skills
        case workspaces
        case knowledge
        case ui
        case logging
        case contextCompaction
        case prompt
        case agentTurn
        case workspaceIgnore
        case fileRead
        case subAgent
        case parallelToolExecution
        case memory
        case schedule
        case update
        case trainingData
        case behaviorReport
    }

    init() {}
}

// MARK: - Nested settings

nonisolated struct ModelSettings: Codable, Hashable, Sendable {
    static let apiKeySecretName = "model-api-key"

    var provider: String = "OpenAI-Compatible"
    var endpoint: String = "https://api.openai.com/v1"
    var modelName: String = "gpt-4.1-mini"
    var maxTokens: Int?
    var enableStreaming: Bool = true
    var streamingIdleTimeoutSeconds: Int = 90
    var legacyApiKeyCredentialName: String?

    enum CodingKeys: String, CodingKey {
        case provider
        case endpoint
        case modelName
        case maxTokens
        case enableStreaming
        case streamingIdleTimeoutSeconds
        case legacyApiKeyCredentialName = "apiKeyCredentialName"
    }
}

nonisolated struct ToolPermissionSettings: Codable, Hashable, Sendable {
    var approvalEnabled: Bool = false
    var askBeforeEveryCommand: Bool = true
    var fileScopePolicy: String = "AskOutsideWorkspace"
    var commandAllowList: [String] = ["git", "dotnet", "python", "node", "npm"]
    var commandDenyList: [String] = ["format", "del /s", "rmdir /s", "Remove-Item -Recurse"]

    enum CodingKeys: String, CodingKey {
        case approvalEnabled
        case askBeforeEveryCommand
        case fileScopePolicy
        case commandAllowList
        case commandDenyList
    }
}

nonisolated struct McpServerSettings: Codable, Hashable, Sendable, Identifiable {
    var id: String { name }
    var name: String = "filesystem"
    var enabled: Bool = true
    var transportType: String = "stdio"
    var url: String = ""
    var command: String = "npx"
    var args: [String] = []
    var env: [String: String] = [:]
    var headers: [String: String] = [:]
    var workingDirectory: String = ""
    var toolCallTimeoutSeconds: Int = 120

    enum CodingKeys: String, CodingKey {
        case name
        case enabled
        case transportType
        case url
        case command
        case args
        case env
        case headers
        case workingDirectory
        case toolCallTimeoutSeconds
    }
}

nonisolated struct McpSearchSettings: Codable, Hashable, Sendable {
    var enabled: Bool = true
    var mode: String = "auto"
    var autoThresholdToolCount: Int = 12
    var autoThresholdSchemaChars: Int = 80_000
    var autoHysteresisToolCount: Int = 3
    var autoHysteresisSchemaChars: Int = 10_000
    var topKDefault: Int = 8
    var topKMax: Int = 20
    var minScore: Double = 0.5

    enum CodingKeys: String, CodingKey {
        case enabled
        case mode
        case autoThresholdToolCount
        case autoThresholdSchemaChars
        case autoHysteresisToolCount
        case autoHysteresisSchemaChars
        case topKDefault
        case topKMax
        case minScore
    }
}

nonisolated struct SkillSettings: Codable, Hashable, Sendable, Identifiable {
    var id: String { name.isEmpty ? path : name }
    var name: String = ""
    var enabled: Bool = true
    var path: String = ""

    enum CodingKeys: String, CodingKey {
        case name
        case enabled
        case path
    }
}

nonisolated struct SshWorkspaceSettings: Codable, Hashable, Sendable {
    var host: String = ""
    var port: Int = 22
    var username: String = ""
    var authMode: String = "password"
    var privateKeyPath: String?

    enum CodingKeys: String, CodingKey {
        case host
        case port
        case username
        case authMode
        case privateKeyPath
    }

    static func passwordSecretName(workspaceId: String) -> String { "ssh-password:\(workspaceId)" }
    static func keyPassphraseSecretName(workspaceId: String) -> String { "ssh-key-passphrase:\(workspaceId)" }
}

nonisolated struct WorkspaceSettings: Codable, Hashable, Sendable, Identifiable {
    var id: String = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    var name: String = ""
    var kind: String = "local"
    var rootPath: String = ""
    var ignorePatterns: [String] = []
    var ssh: SshWorkspaceSettings?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case rootPath
        case ignorePatterns
        case ssh
    }
}

nonisolated struct KnowledgeEmbeddingSettings: Codable, Hashable, Sendable {
    static let apiKeySecretName = "knowledge-embedding-api-key"
    var provider: String = "OpenAI-Compatible"
    var endpoint: String = "https://api.openai.com/v1"
    var model: String = "text-embedding-3-small"
    var dimension: Int = 1536
    var batchSize: Int = 16

    enum CodingKeys: String, CodingKey {
        case provider
        case endpoint
        case model
        case dimension
        case batchSize
    }
}

nonisolated struct KnowledgeChunkSettings: Codable, Hashable, Sendable {
    var targetChars: Int = 4000
    var overlapChars: Int = 600
    var maxChars: Int = 6000

    enum CodingKeys: String, CodingKey {
        case targetChars
        case overlapChars
        case maxChars
    }
}

nonisolated struct KnowledgeSearchSettings: Codable, Hashable, Sendable {
    var topK: Int = 8
    var minScore: Double = 0.25
    var maxContentCharsPerHit: Int = 1200

    enum CodingKeys: String, CodingKey {
        case topK
        case minScore
        case maxContentCharsPerHit
    }
}

nonisolated struct KnowledgeSettings: Codable, Hashable, Sendable {
    /// When true, registers `knowledge_search` and enables Knowledge UI ingest.
    var enabled: Bool = false
    var directoryName: String = "knowledge-base"
    var databaseFileName: String = "knowledge.db"
    var embedding: KnowledgeEmbeddingSettings = .init()
    var chunking: KnowledgeChunkSettings = .init()
    var search: KnowledgeSearchSettings = .init()

    enum CodingKeys: String, CodingKey {
        case enabled
        case directoryName
        case databaseFileName
        case embedding
        case chunking
        case search
    }
}

nonisolated struct UiSettings: Codable, Hashable, Sendable {
    var language: String = "zh-CN"
    var theme: String = "Dark"
    var fontSize: Double = 14
    var contextSidebarVisible: Bool = false
    var navigationSidebarVisible: Bool = true
    var contextSidebarWidth: Double = 300
    var navigationSidebarWidth: Double = 260
    var editorPaneWidth: Double = 480
    var composerHeight: Double = 156
    var showToolCalls: Bool = true

    enum CodingKeys: String, CodingKey {
        case language
        case theme
        case fontSize
        case contextSidebarVisible
        case navigationSidebarVisible
        case contextSidebarWidth
        case navigationSidebarWidth
        case editorPaneWidth
        case composerHeight
        case showToolCalls
    }
}

nonisolated struct LoggingSettings: Codable, Hashable, Sendable {
    var directory: String = ""
    var minimumLevel: String = "Information"
    var retainedDays: Int = 14
    var maxFileSizeBytes: Int64 = 10 * 1024 * 1024

    enum CodingKeys: String, CodingKey {
        case directory
        case minimumLevel
        case retainedDays
        case maxFileSizeBytes
    }
}

nonisolated struct TruncateArgsSettings: Codable, Hashable, Sendable {
    var enabled: Bool = true
    var triggerMessages: Int = 25
    var triggerTokens: Int = 40_000
    var keepMessages: Int = 20
    var keepTokens: Int = 0
    var maxArgLength: Int = 2_000
    var truncationText: String = "...(argument truncated)"

    enum CodingKeys: String, CodingKey {
        case enabled
        case triggerMessages
        case triggerTokens
        case keepMessages
        case keepTokens
        case maxArgLength
        case truncationText
    }
}

nonisolated struct ToolResultEvictionSettings: Codable, Hashable, Sendable {
    var enabled: Bool = true
    var maxResultChars: Int = 80_000
    var previewChars: Int = 2_000
    var excludedToolNames: [String] = ["file_write", "file_edit", "grep_files", "glob_files", "file_list"]

    enum CodingKeys: String, CodingKey {
        case enabled
        case maxResultChars
        case previewChars
        case excludedToolNames
    }
}

nonisolated struct DynamicCompactionSettings: Codable, Hashable, Sendable {
    var enabled: Bool = false
    var targetUtilization: Double = 0.80
    var postCompactionUtilization: Double = 0.30
    var safetyMarginRatio: Double = 0.08
    var defaultReservedOutputTokens: Int = 8192
    var truncateLeadRatio: Double = 0.90
    var overflowPostCompactionUtilization: Double = 0.20
    var enableSemanticCutoff: Bool = true
    var enableUsageCalibration: Bool = true
    var usageCalibrationAlpha: Double = 0.15

    enum CodingKeys: String, CodingKey {
        case enabled
        case targetUtilization
        case postCompactionUtilization
        case safetyMarginRatio
        case defaultReservedOutputTokens
        case truncateLeadRatio
        case overflowPostCompactionUtilization
        case enableSemanticCutoff
        case enableUsageCalibration
        case usageCalibrationAlpha
    }
}

nonisolated struct RequestHistoryHygieneSettings: Codable, Hashable, Sendable {
    var enabled: Bool = true
    var maxToolResultLines: Int = 320
    var maxToolResultBytes: Int = 32 * 1024
    var maxToolResultTokens: Int = 8_000
    var maxToolArgumentStringBytes: Int = 8 * 1024
    var maxToolArgumentStringTokens: Int = 2_000
    var maxArrayItems: Int = 80

    enum CodingKeys: String, CodingKey {
        case enabled
        case maxToolResultLines
        case maxToolResultBytes
        case maxToolResultTokens
        case maxToolArgumentStringBytes
        case maxToolArgumentStringTokens
        case maxArrayItems
    }
}

nonisolated enum ToolStormScope: String, Codable, Sendable {
    case turn = "Turn"
    case session = "Session"
}

nonisolated struct ToolStormSettings: Codable, Hashable, Sendable {
    var enabled: Bool = true
    var scope: ToolStormScope = .turn
    var windowSize: Int = 8
    var threshold: Int = 3

    enum CodingKeys: String, CodingKey {
        case enabled
        case scope
        case windowSize
        case threshold
    }
}

nonisolated struct ContextCompactionSettings: Codable, Hashable, Sendable {
    var enabled: Bool = false
    var contextWindowTokens: Int = 65_535
    var compactTriggerRatio: Double = 0.7
    var triggerMessages: Int = 50
    var triggerTokens: Int = 80_000
    var keepMessages: Int = 20
    var keepTokens: Int = 0
    var offloadBeforeCompact: Bool = true
    var includeReasoningInModelContext: Bool = false
    var summaryPrompt: String = ""
    var maxConversationCharsForSummary: Int = 200_000
    var summaryMaxTokens: Int = 4_096
    var truncateArgs: TruncateArgsSettings = .init()
    var toolResultEviction: ToolResultEvictionSettings = .init()
    var dynamicCompaction: DynamicCompactionSettings = .init()
    var requestHistoryHygiene: RequestHistoryHygieneSettings = .init()
    var toolStorm: ToolStormSettings = .init()

    enum CodingKeys: String, CodingKey {
        case enabled
        case contextWindowTokens
        case compactTriggerRatio
        case triggerMessages
        case triggerTokens
        case keepMessages
        case keepTokens
        case offloadBeforeCompact
        case includeReasoningInModelContext
        case summaryPrompt
        case maxConversationCharsForSummary
        case summaryMaxTokens
        case truncateArgs
        case toolResultEviction
        case dynamicCompaction
        case requestHistoryHygiene
        case toolStorm
    }
}

nonisolated struct PromptSettings: Codable, Hashable, Sendable {
    var maxAgentsMdChars: Int = 8000
    var maxContributingMdChars: Int = 4000
    var maxKnowledgeMdChars: Int = 1500
    var maxKnowledgeCatalogEntries: Int = 50

    enum CodingKeys: String, CodingKey {
        case maxAgentsMdChars
        case maxContributingMdChars
        case maxKnowledgeMdChars
        case maxKnowledgeCatalogEntries
    }
}

nonisolated struct AgentTurnSettings: Codable, Hashable, Sendable {
    /// Single user-message agent loop timeout in minutes. `0` disables.
    var timeoutMinutes: Int = 0
    /// Max model↔tool rounds per turn (`nil` = unlimited / runtime default).
    var maxModelToolRounds: Int? = nil

    enum CodingKeys: String, CodingKey {
        case timeoutMinutes
        case maxModelToolRounds
    }
}

nonisolated struct WorkspaceIgnoreSettings: Codable, Hashable, Sendable {
    var directoryNames: [String] = WorkspaceIgnoreDefaults.builtIn

    enum CodingKeys: String, CodingKey {
        case directoryNames
    }
}

nonisolated enum WorkspaceIgnoreDefaults {
    static let builtIn: [String] = [
        ".git", ".svn", ".hg",
        "bin", "obj", "target",
        "node_modules", "bower_components",
        "dist", "build", "out", ".next", ".nuxt", ".output", ".svelte-kit",
        "coverage", ".nyc_output",
        ".turbo", ".vite", ".parcel-cache",
        ".vs", "artifacts", "publish",
        "__pycache__", ".pytest_cache", "venv", ".venv",
    ]
}

nonisolated struct FileReadSettings: Codable, Hashable, Sendable {
    var maxFileBytes: Int64 = 2 * 1024 * 1024
    var defaultLineLimit: Int = 500
    var maxLinesPerCall: Int = 2_000
    var maxResponseChars: Int = 32_768
    var maxLineChars: Int = 10_240
    var countTotalLines: Bool = true

    enum CodingKeys: String, CodingKey {
        case maxFileBytes
        case defaultLineLimit
        case maxLinesPerCall
        case maxResponseChars
        case maxLineChars
        case countTotalLines
    }
}

nonisolated struct SubAgentSettings: Codable, Hashable, Sendable {
    var enabled: Bool = true
    var maxToolRounds: Int = 16
    var maxNestingDepth: Int = 2
    var maxConcurrentSubAgents: Int = 10
    var defaultSyncTimeoutSeconds: Int = 30
    var maxSyncTimeoutSeconds: Int = 3600
    var maxPendingCompletionsPerParent: Int = 20

    /// Alias for `maxNestingDepth` (Phase 0 checklist naming).
    var maxDepth: Int {
        get { maxNestingDepth }
        set { maxNestingDepth = newValue }
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case maxToolRounds
        case maxNestingDepth
        case maxConcurrentSubAgents
        case defaultSyncTimeoutSeconds
        case maxSyncTimeoutSeconds
        case maxPendingCompletionsPerParent
    }
}

nonisolated struct ParallelToolExecutionSettings: Codable, Hashable, Sendable {
    var enabled: Bool = true
    var maxDegreeOfParallelism: Int = 4

    enum CodingKeys: String, CodingKey {
        case enabled
        case maxDegreeOfParallelism
    }
}

nonisolated enum MemoryInlinePromptMode: String, Codable, Sendable {
    case none = "None"
    case preview = "Preview"
    case full = "Full"
}

nonisolated struct MemorySettings: Codable, Hashable, Sendable {
    var enabled: Bool = false
    var consolidationMinGapSeconds: Double = 30 * 60
    var dailyFileRetentionDays: Int = 90
    var maxMemoryTokens: Int = 4000
    var summaryMaxTokens: Int = 1024
    var maxFlushConversationChars: Int = 80_000
    var memoryDirName: String = "memory"
    var curatedFileName: String = "MEMORY.md"
    var watermarkFileName: String = ".consolidation_state"
    var excludePatterns: [String] = ["memory/", "MEMORY.md"]
    var inlinePromptMode: MemoryInlinePromptMode = .none
    var maxInlineMemoryChars: Int = 800

    enum CodingKeys: String, CodingKey {
        case enabled
        case consolidationMinGapSeconds = "consolidationMinGap"
        case dailyFileRetentionDays
        case maxMemoryTokens
        case summaryMaxTokens
        case maxFlushConversationChars
        case memoryDirName
        case curatedFileName
        case watermarkFileName
        case excludePatterns
        case inlinePromptMode
        case maxInlineMemoryChars
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        if let seconds = try? c.decode(Double.self, forKey: .consolidationMinGapSeconds) {
            consolidationMinGapSeconds = seconds
        } else if let text = try? c.decode(String.self, forKey: .consolidationMinGapSeconds) {
            consolidationMinGapSeconds = Self.parseTimeSpanSeconds(text) ?? (30 * 60)
        } else {
            consolidationMinGapSeconds = 30 * 60
        }
        dailyFileRetentionDays = try c.decodeIfPresent(Int.self, forKey: .dailyFileRetentionDays) ?? 90
        maxMemoryTokens = try c.decodeIfPresent(Int.self, forKey: .maxMemoryTokens) ?? 4000
        summaryMaxTokens = try c.decodeIfPresent(Int.self, forKey: .summaryMaxTokens) ?? 1024
        maxFlushConversationChars = try c.decodeIfPresent(Int.self, forKey: .maxFlushConversationChars) ?? 80_000
        memoryDirName = try c.decodeIfPresent(String.self, forKey: .memoryDirName) ?? "memory"
        curatedFileName = try c.decodeIfPresent(String.self, forKey: .curatedFileName) ?? "MEMORY.md"
        watermarkFileName = try c.decodeIfPresent(String.self, forKey: .watermarkFileName) ?? ".consolidation_state"
        excludePatterns = try c.decodeIfPresent([String].self, forKey: .excludePatterns) ?? ["memory/", "MEMORY.md"]
        inlinePromptMode = try c.decodeIfPresent(MemoryInlinePromptMode.self, forKey: .inlinePromptMode) ?? .none
        maxInlineMemoryChars = try c.decodeIfPresent(Int.self, forKey: .maxInlineMemoryChars) ?? 800
    }

    private static func parseTimeSpanSeconds(_ text: String) -> Double? {
        let parts = text.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return nil }
        if parts.count == 3 {
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        }
        if parts.count == 2 {
            return parts[0] * 60 + parts[1]
        }
        return parts[0]
    }
}

nonisolated struct ScheduledTask: Codable, Hashable, Sendable, Identifiable {
    var id: String = UUID().uuidString
    var title: String = ""
    var enabled: Bool = true
    var prompt: String = ""
    var workspaceRoot: String = ""
    var model: String = "auto"
    var mode: String = "agent"
    var kind: String = "daily"
    var everyMinutes: Int = 60
    var timeOfDay: String = "09:00"
    var atTime: String = ""
    var createdAt: String = ""
    var updatedAt: String = ""
    var nextRunAt: String = ""
    var lastRunAt: String = ""
    var lastRunEndedAt: String = ""
    var lastStatus: String = "idle"
    var lastMessage: String = ""
    var lastThreadId: String = ""

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case enabled
        case prompt
        case workspaceRoot
        case model
        case mode
        case kind
        case everyMinutes
        case timeOfDay
        case atTime
        case createdAt
        case updatedAt
        case nextRunAt
        case lastRunAt
        case lastRunEndedAt
        case lastStatus
        case lastMessage
        case lastThreadId
    }
}

nonisolated struct ScheduleSettings: Codable, Hashable, Sendable {
    var enabled: Bool = false
    var defaultWorkspaceRoot: String = ""
    var model: String = "auto"
    var mode: String = "agent"
    var promptPrefix: String = ""
    var keepAwake: Bool = false
    var tasks: [ScheduledTask] = []

    enum CodingKeys: String, CodingKey {
        case enabled
        case defaultWorkspaceRoot
        case model
        case mode
        case promptPrefix
        case keepAwake
        case tasks
    }
}

nonisolated struct UpdateSettings: Codable, Hashable, Sendable {
    var enabled: Bool = true
    var baseUrl: String = ""

    enum CodingKeys: String, CodingKey {
        case enabled
        case baseUrl
    }
}

nonisolated struct TrainingDataSettings: Codable, Hashable, Sendable {
    var enabled: Bool = false
    var outputDirectory: String?
    var sampleRate: Double = 1.0

    enum CodingKeys: String, CodingKey {
        case enabled
        case outputDirectory
        case sampleRate
    }
}

/// Optional stub — behavior report upload (no SSO).
nonisolated struct BehaviorReportSettings: Codable, Hashable, Sendable {
    var enabled: Bool = false
    var baseUrl: String = ""
    var uploadIntervalMinutes: Int = 10

    enum CodingKeys: String, CodingKey {
        case enabled
        case baseUrl
        case uploadIntervalMinutes
    }
}
