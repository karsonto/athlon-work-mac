import Foundation

/// Extracts new long-term memories from a finished conversation turn via LLM,
/// then appends them to today's daily memory ledger.
final class MemoryFlushService {
    private let longTermMemory: ILongTermMemory
    private let modelClient: OpenAiChatModelClient
    private let settings: MemorySettings

    private let flushSystemPrompt = """
You are a memory extraction assistant. Analyze the conversation below and extract important facts, decisions, preferences, and contextual information that should be remembered for future conversations.

Output ONLY the extracted memories as a markdown bullet list. Each item should be a concise, self-contained fact. Include dates, names, and specifics when available.

If there is nothing worth remembering, respond with exactly: NO_REPLY

Guidelines:
- Extract user preferences, personal information, project decisions
- Capture important technical decisions and their rationale
- Note any commitments, deadlines, or action items
- Ignore routine greetings, tool invocations, and ephemeral status updates

IMPORTANT:
- You are writing to TODAY's daily memory ledger (memory/YYYY-MM-DD.md), NOT to MEMORY.md.
- MEMORY.md is the curated long-term memory and is shown ONLY as read-only context below. Do NOT restate facts already covered by MEMORY.md or by today's earlier entries.
- Keep each bullet point independent and self-contained.
"""

    init(longTermMemory: ILongTermMemory,
         modelClient: OpenAiChatModelClient,
         settings: MemorySettings) {
        self.longTermMemory = longTermMemory
        self.modelClient = modelClient
        self.settings = settings
    }

    func flush(messages: [ChatMessage]) async -> MemoryFlushResult {
        guard settings.enabled else { return .skipped }

        let conversationText = serializeMessages(messages)
        guard !conversationText.isEmpty else { return .skipped }

        let existingMemory = (try? await longTermMemory.readCurated()) ?? ""
        let existingDaily = (try? await longTermMemory.readDaily(date: Date())) ?? ""

        var userPrompt = ""
        if !existingMemory.isEmpty {
            userPrompt += "MEMORY.md (read-only curated long-term memory — do NOT restate):\n"
            userPrompt += existingMemory + "\n\n"
        }
        if !existingDaily.isEmpty {
            userPrompt += "Today's daily ledger so far (your output will be appended after):\n"
            userPrompt += existingDaily + "\n\n"
        }
        userPrompt += "Extract NEW memories from this conversation window (skip anything already covered above):\n\n"
        userPrompt += conversationText

        let request = AgentModelRequest(
            messages: [
                .init(role: "system", text: flushSystemPrompt),
                .init(role: "user", text: userPrompt)
            ],
            tools: [],
            allowToolCalls: false,
            maxTokens: settings.summaryMaxTokens
        )

        let response: AgentModelResponse
        do {
            response = try await modelClient.complete(request)
        } catch {
            AgentFileLogger.log("Memory flush LLM call failed: \(error.localizedDescription)", category: "Memory")
            return .failed(error.localizedDescription)
        }

        let extracted = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !extracted.isEmpty, extracted != "NO_REPLY" else {
            AgentFileLogger.log("No memories to flush", category: "Memory")
            return .skipped
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let dailyEntry = "\n## Memory Flush — \(timestamp)\n\(extracted)\n"
        try? await longTermMemory.appendDaily(dailyEntry)
        AgentFileLogger.log("Flushed \(extracted.count) chars to daily memory ledger", category: "Memory")
        return .success(extracted)
    }

    private func serializeMessages(_ messages: [ChatMessage]) -> String {
        var result = ""
        for message in messages {
            if message.role == .system || message.role == .compaction { continue }
            result += "[\(message.role.apiValue)]: \(message.content)\n\n"
        }
        if result.count > 80_000 {
            result = String(result.suffix(80_000))
        }
        return result
    }
}
