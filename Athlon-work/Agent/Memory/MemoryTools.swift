import Foundation

nonisolated struct MemorySearchTool: AgentTool {
    let name = "memory_search"
    private let memory: FileLongTermMemory

    init(memory: FileLongTermMemory) {
        self.memory = memory
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Search long-term MEMORY.md and daily notes for the current workspace.",
            parameters: [
                "type": "object",
                "properties": [
                    "query": ["type": "string"] as [String: Any],
                    "max_hits": ["type": "integer"] as [String: Any],
                ] as [String: Any],
                "required": ["query"],
            ]
        )
    }

    func invoke(arguments: String, context: AgentRunContext) async throws -> String {
        guard context.settings.memory.enabled else {
            return "Memory is disabled in settings."
        }
        let args = try ToolJSON.object(from: arguments)
        guard let query = args["query"] as? String, !query.isEmpty else {
            throw AgentToolError.invalidArguments("query is required")
        }
        let maxHits = max(1, (args["max_hits"] as? Int) ?? 8)
        let hits = try memory.search(
            workspaceRoot: context.workspaceRoot,
            settings: context.settings.memory,
            query: query,
            maxHits: maxHits
        )
        if hits.isEmpty { return "No memory hits for: \(query)" }
        return hits.map { "- \($0.path)\n  \($0.snippet)" }.joined(separator: "\n")
    }
}

nonisolated struct MemoryGetTool: AgentTool {
    let name = "memory_get"
    private let memory: FileLongTermMemory

    init(memory: FileLongTermMemory) {
        self.memory = memory
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Read a memory file (MEMORY.md or a daily note path returned by memory_search).",
            parameters: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Absolute path under memory/"] as [String: Any],
                    "max_chars": ["type": "integer"] as [String: Any],
                ] as [String: Any],
                "required": ["path"],
            ]
        )
    }

    func invoke(arguments: String, context: AgentRunContext) async throws -> String {
        guard context.settings.memory.enabled else {
            return "Memory is disabled in settings."
        }
        let args = try ToolJSON.object(from: arguments)
        guard let path = args["path"] as? String, !path.isEmpty else {
            throw AgentToolError.invalidArguments("path is required")
        }
        let root = memory.projectDirectory(workspaceRoot: context.workspaceRoot, settings: context.settings.memory)
        let standardized = (path as NSString).standardizingPath
        let allowedRoot = (root as NSString).standardizingPath
        guard standardized.hasPrefix(allowedRoot) else {
            throw AgentToolError.pathOutsideWorkspace(path)
        }
        let maxChars = max(500, (args["max_chars"] as? Int) ?? 8_000)
        return try memory.get(path: standardized, maxChars: maxChars)
    }
}
