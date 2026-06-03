import Foundation

struct ToolResultEvictor: ToolResultEvicting {
    let settings: ContextCompactionSettings
    let storage: CompactionStorageProviding

    func evictIfNeeded(
        sessionId: String,
        toolCall: AgentToolCall,
        result: ToolResult,
        formattedToolContent: String
    ) async -> String {
        let cfg = settings.toolResultEviction
        if !cfg.enabled {
            return formattedToolContent
        }

        if cfg.excludedToolNames.contains(where: { $0.caseInsensitiveCompare(toolCall.name) == .orderedSame }) {
            return formattedToolContent
        }

        let rawContent = result.content ?? ""
        if rawContent.count <= cfg.maxResultChars {
            return formattedToolContent
        }

        let path: String
        do {
            path = try await storage.saveEvictedToolResult(
                sessionId: sessionId,
                toolCallId: toolCall.id,
                content: rawContent
            )
        } catch {
            return formattedToolContent
        }

        let preview = buildPreview(rawContent, previewChars: cfg.previewChars)
        let placeholder = """
        [Tool result evicted - \(rawContent.count) chars]
        Archived at: \(path)
        Preview:
        \(preview)
        """

        return AgentRuntimeToolFormatting.formatToolResult(
            toolCall,
            .success(summary: result.summary, content: placeholder)
        )
    }

    private func buildPreview(_ content: String, previewChars: Int) -> String {
        if content.count <= previewChars * 2 {
            return content
        }
        let head = String(content.prefix(previewChars))
        let tail = String(content.suffix(previewChars))
        return head + "\n...\n" + tail
    }
}
