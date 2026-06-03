import Foundation

// MARK: - Context Compaction Settings (AgentScope-aligned defaults)

struct ContextCompactionSettings: Codable, Equatable {
    var contextWindowTokens: Int = 256_000
    /// When > 0 with contextWindowTokens, compaction also triggers when estimated
    /// history tokens reach contextWindowTokens * compactTriggerRatio (max with triggerTokens).
    var compactTriggerRatio: Double = 0.7
    var triggerMessages: Int = 50
    var triggerTokens: Int = 80_000
    var keepMessages: Int = 20
    var keepTokens: Int = 0
    var offloadBeforeCompact: Bool = true
    /// When false (default), assistant reasoning is omitted from token estimates.
    var includeReasoningInModelContext: Bool = false
    var summaryPrompt: String = ConversationCompactionDefaults.defaultSummaryPrompt
    var maxConversationCharsForSummary: Int = 200_000
    var summaryMaxTokens: Int = 4_096
    var truncateArgs: TruncateArgsSettings = TruncateArgsSettings()
    var toolResultEviction: ToolResultEvictionSettings = ToolResultEvictionSettings()

    enum CodingKeys: String, CodingKey {
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
    }
}

struct TruncateArgsSettings: Codable, Equatable {
    var enabled: Bool = true
    var triggerMessages: Int = 25
    var triggerTokens: Int = 40_000
    var keepMessages: Int = 20
    var keepTokens: Int = 0
    var maxArgLength: Int = 2_000
    var truncationText: String = "...(argument truncated)"
}

struct ToolResultEvictionSettings: Codable, Equatable {
    var enabled: Bool = true
    var maxResultChars: Int = 80_000
    var previewChars: Int = 2_000
    var excludedToolNames: [String] = [
        "file_write",
        "file_edit",
        "grep_files",
        "glob_files",
        "file_list"
    ]
}
