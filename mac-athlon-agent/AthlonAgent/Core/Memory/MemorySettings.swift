import Foundation

struct MemorySettings: Codable, Equatable {
    var enabled: Bool = true
    /// Minimum gap between two consolidation runs.
    var consolidationMinGapMinutes: Int = 30
    /// Daily files older than this many days are archived.
    var dailyFileRetentionDays: Int = 90
    /// Max tokens for the consolidated MEMORY.md (fed to LLM as token budget).
    var maxMemoryTokens: Int = 4000
    /// Max tokens for the flush/summary LLM call output.
    var summaryMaxTokens: Int = 1024
    /// Max characters of conversation to include in flush prompt.
    var maxFlushConversationChars: Int = 80_000
    /// Subdirectory name under the app data root.
    var memoryDirName: String = "memory"
    /// Name of the curated memory file.
    var curatedFileName: String = "MEMORY.md"
    /// Name of the consolidation watermark file.
    var watermarkFileName: String = ".consolidation_state"
    /// Names of memory directories/files excluded from workspace tools.
    var excludePatterns: [String] = ["memory/", "MEMORY.md"]

    enum CodingKeys: String, CodingKey {
        case enabled
        case consolidationMinGapMinutes = "consolidation_min_gap_minutes"
        case dailyFileRetentionDays = "daily_file_retention_days"
        case summaryMaxTokens = "summary_max_tokens"
        case maxMemoryTokens = "max_memory_tokens"
        case maxFlushConversationChars = "max_flush_conversation_chars"
        case memoryDirName = "memory_dir_name"
        case curatedFileName = "curated_file_name"
        case watermarkFileName = "watermark_file_name"
        case excludePatterns = "exclude_patterns"
    }

    var consolidationMinGap: TimeInterval {
        TimeInterval(consolidationMinGapMinutes * 60)
    }
}
