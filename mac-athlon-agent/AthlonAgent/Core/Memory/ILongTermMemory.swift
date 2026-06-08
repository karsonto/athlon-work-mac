import Foundation

/// Two-layer file-based long-term memory.
/// Layer 1: memory/YYYY-MM-DD.md (append-only daily ledgers)
/// Layer 2: memory/MEMORY.md     (LLM-consolidated, deduplicated, size-bounded)
protocol ILongTermMemory: AnyObject {
    /// Reads the current curated MEMORY.md. Returns empty string if none exists.
    func readCurated() async throws -> String

    /// Appends text to today's daily ledger (memory/YYYY-MM-DD.md).
    func appendDaily(_ text: String) async throws

    /// Reads today's daily ledger. Returns empty string if none exists.
    func readDaily(date: Date) async throws -> String

    /// Lists daily ledger files modified after the given watermark (UTC).
    /// Returns file path segments relative to the memory directory (e.g. "2026-06-08.md").
    func listDailyFilesAfter(watermark: Date) async throws -> [String]

    /// Reads a daily ledger file by its relative path (e.g. "2026-06-08.md").
    func readDailyFile(relativePath: String) async throws -> String

    /// Overwrites MEMORY.md with the consolidated content.
    func writeCurated(_ content: String) async throws

    /// Reads the consolidation watermark (last successful consolidation UTC instant).
    /// Returns Date.distantPast when no watermark exists.
    func readWatermark() async throws -> Date

    /// Writes the consolidation watermark.
    func writeWatermark(_ watermark: Date) async throws

    /// Moves a daily file to the archive subdirectory.
    func archiveDailyFile(relativePath: String) async throws

    /// Lists all memory files (MEMORY.md + memory/*.md) for the search tool.
    /// Returns workspace-relative paths.
    func listAllMemoryFilePaths() async throws -> [String]
}
