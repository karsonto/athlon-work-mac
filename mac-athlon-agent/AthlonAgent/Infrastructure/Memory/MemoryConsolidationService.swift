import Foundation

/// Periodically merges daily ledgers into a curated, deduplicated, size-bounded MEMORY.md.
/// Uses a watermark (.consolidation_state) to process only new daily files.
final class MemoryConsolidationService {
    private let longTermMemory: ILongTermMemory
    private let modelClient: OpenAiChatModelClient
    private let settings: MemorySettings

    private let consolidationPromptTemplate = """
You are a memory consolidation assistant. You own the curated long-term memory file MEMORY.md. Your job is to merge new daily ledger entries into MEMORY.md while keeping it concise, deduplicated, and high-signal.

You are given two inputs:
1. The current MEMORY.md content (the existing curated long-term memory).
2. New daily ledger entries that have been appended since the last consolidation.

Rules:
- MEMORY.md is the single source of truth for cross-day, cross-session knowledge. Keep it stable and authoritative.
- Daily ledger entries are stream-of-consciousness flush logs — they may be noisy, redundant with MEMORY.md, or redundant with each other. Promote only what is durable and reusable.
- Deduplicate: if a new entry restates something MEMORY.md already covers, skip it.
- Merge related facts: combine entries about the same topic into cohesive paragraphs with clear section headers.
- Update or remove stale information when new entries supersede it.
- Keep total output within %d tokens (approximately %d characters); prioritize recent and frequently-referenced information when trimming.

Output the COMPLETE new MEMORY.md content (not just a diff). Use markdown.
"""

    init(longTermMemory: ILongTermMemory,
         modelClient: OpenAiChatModelClient,
         settings: MemorySettings) {
        self.longTermMemory = longTermMemory
        self.modelClient = modelClient
        self.settings = settings
    }

    /// Runs a single consolidation cycle. No-op if no new daily files exist.
    func consolidate() async {
        guard settings.enabled else { return }

        let readWatermark = (try? await longTermMemory.readWatermark()) ?? Date.distantPast
        let watermark = readWatermark == Date(timeIntervalSinceReferenceDate: 0) ? Date.distantPast : readWatermark

        let dailyFiles: [String]
        do {
            dailyFiles = try await longTermMemory.listDailyFilesAfter(watermark: watermark)
        } catch {
            AgentFileLogger.log("consolidation: failed to list daily files — \(error.localizedDescription)", category: "Memory")
            return
        }

        guard !dailyFiles.isEmpty else {
            AgentFileLogger.log("consolidation: no fresh daily entries since \(watermark) — skipping", category: "Memory")
            return
        }

        let runStart = Date()
        let currentMemory = (try? await longTermMemory.readCurated()) ?? ""
        let dailyEntries = await readDailyEntries(fileNames: dailyFiles)

        let maxChars = settings.maxMemoryTokens * 4
        let systemPrompt = String(format: consolidationPromptTemplate, settings.maxMemoryTokens, maxChars)

        var userContent = "Current MEMORY.md:\n"
        userContent += currentMemory.isEmpty ? "(empty)" : currentMemory
        userContent += "\n\nNew daily ledger entries to merge"
        if watermark > Date.distantPast {
            let formatter = ISO8601DateFormatter()
            userContent += " (since \(formatter.string(from: watermark)))"
        }
        userContent += ":\n\n\(dailyEntries)"

        let request = AgentModelRequest(
            messages: [
                .init(role: "system", text: systemPrompt),
                .init(role: "user", text: userContent)
            ],
            tools: [],
            allowToolCalls: false,
            maxTokens: settings.summaryMaxTokens * 4
        )

        let response: AgentModelResponse
        do {
            response = try await modelClient.complete(request)
        } catch {
            AgentFileLogger.log("consolidation: LLM call failed — \(error.localizedDescription)", category: "Memory")
            return
        }

        let consolidated = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !consolidated.isEmpty else {
            AgentFileLogger.log("consolidation: produced empty output, skipping", category: "Memory")
            return
        }

        do {
            try await longTermMemory.writeCurated(consolidated)
            try await longTermMemory.writeWatermark(runStart)
            AgentFileLogger.log("consolidation: MEMORY.md written (\(consolidated.count) chars), watermark advanced to \(runStart)", category: "Memory")
        } catch {
            AgentFileLogger.log("consolidation: failed to save — \(error.localizedDescription)", category: "Memory")
        }
    }

    private func readDailyEntries(fileNames: [String]) async -> String {
        var result = ""
        for name in fileNames {
            if let content = try? await longTermMemory.readDailyFile(relativePath: name), !content.isEmpty {
                result += "### \(name)\n\(content.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
            }
        }
        return result
    }
}
