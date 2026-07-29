import Foundation

/// Wraps BuiltinToolRouter + MCP tools; optional search-mode stub when tool count exceeds threshold.
nonisolated final class McpDelegatingToolRouter: ToolRouter, @unchecked Sendable {
    private let builtin: BuiltinToolRouter
    private let extraTools: [any AgentTool]
    private let searchSettings: McpSearchSettings
    private let mcpRegistry: McpRegistry?
    private let staticMcpTools: [any AgentTool]

    init(
        builtin: BuiltinToolRouter = BuiltinToolRouter(),
        extraTools: [any AgentTool] = [],
        mcpTools: [any AgentTool] = [],
        mcpRegistry: McpRegistry? = nil,
        searchSettings: McpSearchSettings = .init()
    ) {
        self.builtin = builtin
        self.extraTools = extraTools
        self.searchSettings = searchSettings
        self.mcpRegistry = mcpRegistry
        self.staticMcpTools = mcpTools
    }

    private var resolvedMcpTools: [any AgentTool] {
        if let mcpRegistry {
            return mcpRegistry.makeAgentTools()
        }
        return staticMcpTools
    }

    var tools: [any AgentTool] {
        let mcp = resolvedMcpTools
        let useSearch = McpDelegatingToolRouter.shouldUseSearchMode(
            mcpToolCount: mcp.count,
            search: searchSettings
        )
        if useSearch {
            let searchTool = McpSearchTool(catalog: mcp, settings: searchSettings)
            return builtin.tools + extraTools + [searchTool]
        }
        return builtin.tools + extraTools + mcp
    }

    func tool(named name: String) -> (any AgentTool)? {
        tools.first { $0.name == name }
    }

    static func shouldUseSearchMode(mcpToolCount: Int, search: McpSearchSettings) -> Bool {
        guard search.enabled else { return false }
        switch search.mode.lowercased() {
        case "always", "on":
            return mcpToolCount > 0
        case "never", "off":
            return false
        default:
            return mcpToolCount > search.autoThresholdToolCount
        }
    }
}

/// Stub search tool: keyword filter over MCP tool names/descriptions; returns matching qualified names.
nonisolated struct McpSearchTool: AgentTool {
    let name = "mcp_search"
    private let catalog: [any AgentTool]
    private let settings: McpSearchSettings

    init(catalog: [any AgentTool], settings: McpSearchSettings) {
        self.catalog = catalog
        self.settings = settings
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Search available MCP tools by keyword. Returns matching tool names and descriptions.",
            parameters: [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Search keywords"] as [String: Any],
                    "top_k": ["type": "integer", "description": "Max results"] as [String: Any],
                ] as [String: Any],
                "required": ["query"],
            ]
        )
    }

    func invoke(arguments: String, context: AgentRunContext) async throws -> String {
        _ = context
        let args = try ToolJSON.object(from: arguments)
        guard let query = args["query"] as? String, !query.isEmpty else {
            throw AgentToolError.invalidArguments("query is required")
        }
        let topK = min(
            settings.topKMax,
            max(1, (args["top_k"] as? Int) ?? settings.topKDefault)
        )
        let tokens = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let scored: [(score: Int, tool: any AgentTool)] = catalog.compactMap { tool in
            let hay = "\(tool.name) \(tool.definition.description)".lowercased()
            let score = tokens.reduce(0) { partial, token in
                partial + (hay.contains(token) ? 1 : 0)
            }
            return score > 0 ? (score, tool) : nil
        }
        .sorted { $0.score > $1.score }

        let hits = Array(scored.prefix(topK))
        if hits.isEmpty {
            return "No MCP tools matched query: \(query)"
        }
        return hits.map { hit in
            "- \(hit.tool.name): \(hit.tool.definition.description)"
        }.joined(separator: "\n")
    }
}
