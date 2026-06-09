import Foundation

/// Injects MEMORY.md into the system prompt (aligned with WPF `MemoryPromptContributor`).
struct MemoryPromptContributor: IPreReasoningPromptContributor {
    let priority = 40
    private let longTermMemory: ILongTermMemory
    private let settings: MemorySettings

    init(longTermMemory: ILongTermMemory, settings: MemorySettings) {
        self.longTermMemory = longTermMemory
        self.settings = settings
    }

    func append(to builder: inout String, context: EnvironmentPromptContext) async {
        guard settings.enabled else { return }

        guard let memoryContent = try? await longTermMemory.readCurated(),
              !memoryContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        builder += "\n## Long-Term Memory\n\n"
        builder += "Below is the consolidated long-term memory from previous sessions. Use it to recall user preferences, past decisions, and persistent context.\n\n"
        builder += "<long_term_memory>\n"
        builder += memoryContent.trimmingCharacters(in: .whitespacesAndNewlines)
        builder += "\n</long_term_memory>\n"
    }
}
