import Foundation

/// Injects MEMORY.md into the system prompt wrapped in <long_term_memory> XML tags.
/// Priority 40 (runs after base sections).
struct MemoryPromptContributor {
    let priority: Int = 40
    private let longTermMemory: ILongTermMemory

    init(longTermMemory: ILongTermMemory) {
        self.longTermMemory = longTermMemory
    }

    /// Appends memory content to the builder. Returns true if content was added.
    func append(to builder: inout String) -> Bool {
        guard let memoryContent = try? longTermMemory.readCurated(),
              !memoryContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }

        builder += "\n<long_term_memory>\n"
        builder += memoryContent
        builder += "\n</long_term_memory>\n"
        return true
    }
}
