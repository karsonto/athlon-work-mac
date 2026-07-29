import Foundation

nonisolated struct FileReadTool: AgentTool {
    let name = "file_read"
    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Read a text file from the workspace with optional line offset/limit.",
            parameters: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "File path within the workspace"] as [String: Any],
                    "offset": ["type": "integer", "description": "1-based start line (default 1)"] as [String: Any],
                    "limit": ["type": "integer", "description": "Max lines to return"] as [String: Any],
                ] as [String: Any],
                "required": ["path"],
            ]
        )
    }

    func invoke(arguments: String, context: AgentRunContext) async throws -> String {
        let args = try ToolJSON.object(from: arguments)
        guard let path = args["path"] as? String, !path.isEmpty else {
            throw AgentToolError.invalidArguments("path is required")
        }
        let offset = max(1, (args["offset"] as? Int) ?? 1)
        let settings = context.settings.fileRead
        let requestedLimit = (args["limit"] as? Int) ?? settings.defaultLineLimit
        let limit = min(max(1, requestedLimit), settings.maxLinesPerCall)

        let guard_ = WorkspaceGuard(workspaceRoot: context.workspaceRoot, ignorePatterns: context.ignorePatterns)
        let resolved = try guard_.resolve(path)
        let attrs = try FileManager.default.attributesOfItem(atPath: resolved)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        if size > settings.maxFileBytes {
            throw AgentToolError.executionFailed("File exceeds maxFileBytes (\(settings.maxFileBytes))")
        }

        let text = try String(contentsOfFile: resolved, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let start = min(offset - 1, lines.count)
        let end = min(start + limit, lines.count)
        var sliced = lines[start..<end].enumerated().map { index, line -> String in
            var content = String(line)
            if content.count > settings.maxLineChars {
                content = String(content.prefix(settings.maxLineChars)) + "…"
            }
            return "\(start + index + 1)|\(content)"
        }.joined(separator: "\n")

        if sliced.count > settings.maxResponseChars {
            sliced = String(sliced.prefix(settings.maxResponseChars)) + "\n…(truncated)"
        }

        var header = "path: \(guard_.relativePath(for: resolved))"
        if settings.countTotalLines {
            header += "\ntotal_lines: \(lines.count)"
        }
        header += "\nshowing: \(start + 1)-\(end)\n\n"
        return header + sliced
    }
}
