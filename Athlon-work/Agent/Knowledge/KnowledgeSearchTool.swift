import Foundation

nonisolated struct KnowledgeSearchTool: AgentTool {
    let name = "knowledge_search"
    private let searchService: KnowledgeSearchService

    init(searchService: KnowledgeSearchService) {
        self.searchService = searchService
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Search the local knowledge base by keyword and return matching snippets.",
            parameters: [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Search query"] as [String: Any],
                    "top_k": ["type": "integer", "description": "Max hits"] as [String: Any],
                ] as [String: Any],
                "required": ["query"],
            ]
        )
    }

    func invoke(arguments: String, context: AgentRunContext) async throws -> String {
        let args = try ToolJSON.object(from: arguments)
        guard let query = args["query"] as? String, !query.isEmpty else {
            throw AgentToolError.invalidArguments("query is required")
        }
        var searchSettings = context.settings.knowledge.search
        if let topK = args["top_k"] as? Int {
            searchSettings.topK = max(1, topK)
        }
        let hits = try searchService.search(query: query, settings: searchSettings)
        if hits.isEmpty {
            return "No knowledge hits for: \(query)"
        }
        return hits.enumerated().map { idx, hit in
            """
            [\(idx + 1)] \(hit.title) (score=\(String(format: "%.2f", hit.score)))
            source: \(hit.sourcePath)
            \(hit.snippet)
            """
        }.joined(separator: "\n\n")
    }
}
