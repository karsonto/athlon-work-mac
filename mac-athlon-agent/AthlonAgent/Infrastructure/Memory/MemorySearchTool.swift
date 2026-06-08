import Foundation

/// Tool that searches through long-term memory files for relevant information.
struct MemorySearchTool: AgentTool {
    let longTermMemory: ILongTermMemory
    let name = "memory_search"
    let description = "Search through long-term memory files (MEMORY.md and memory/*.md) for relevant information. Use before answering questions about prior work, decisions, dates, people, preferences, or todos."
    let parametersSchema: [String: String] = [
        "query": "Keywords to search for in memory files"
    ]

    func invoke(arguments: [String: String]) async throws -> String {
        guard let query = arguments["query"], !query.isEmpty else {
            throw ToolError.missingArgument("query", tool: name)
        }

        let filePaths = (try? await longTermMemory.listAllMemoryFilePaths()) ?? []
        var matches: [(file: String, line: Int, content: String)] = []

        for relativePath in filePaths {
            let content: String
            if relativePath == "MEMORY.md" {
                content = (try? await longTermMemory.readCurated()) ?? ""
            } else {
                content = (try? await longTermMemory.readDailyFile(relativePath: relativePath)) ?? ""
            }
            let lines = content.components(separatedBy: .newlines)
            for (i, line) in lines.enumerated() {
                if line.localizedCaseInsensitiveContains(query) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    matches.append((relativePath, i + 1, trimmed))
                }
            }
        }

        if matches.isEmpty {
            return "No matches found for query: \(query)"
        }

        let output = matches.prefix(50).map { "\($0.file):\($0.line)|\($0.content)" }.joined(separator: "\n")
        return "Found \(matches.count) match(es):\n\(output)"
    }
}
