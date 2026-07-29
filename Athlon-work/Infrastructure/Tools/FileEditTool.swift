import Foundation

nonisolated struct FileEditTool: AgentTool {
    let name = "file_edit"
    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Replace an exact substring in a workspace file (first occurrence, or all if replace_all).",
            parameters: [
                "type": "object",
                "properties": [
                    "path": ["type": "string"] as [String: Any],
                    "old_string": ["type": "string"] as [String: Any],
                    "new_string": ["type": "string"] as [String: Any],
                    "replace_all": ["type": "boolean"] as [String: Any],
                ] as [String: Any],
                "required": ["path", "old_string", "new_string"],
            ]
        )
    }

    func invoke(arguments: String, context: AgentRunContext) async throws -> String {
        let args = try ToolJSON.object(from: arguments)
        guard let path = args["path"] as? String, !path.isEmpty else {
            throw AgentToolError.invalidArguments("path is required")
        }
        guard let old = args["old_string"] as? String, !old.isEmpty else {
            throw AgentToolError.invalidArguments("old_string is required")
        }
        let new = (args["new_string"] as? String) ?? ""
        let replaceAll = (args["replace_all"] as? Bool) ?? false

        let guard_ = WorkspaceGuard(workspaceRoot: context.workspaceRoot, ignorePatterns: context.ignorePatterns)
        let resolved = try guard_.resolve(path)
        var text = try String(contentsOfFile: resolved, encoding: .utf8)
        guard text.contains(old) else {
            throw AgentToolError.executionFailed("old_string not found in \(path)")
        }
        if replaceAll {
            text = text.replacingOccurrences(of: old, with: new)
        } else if let range = text.range(of: old) {
            text.replaceSubrange(range, with: new)
        }
        try text.write(toFile: resolved, atomically: true, encoding: .utf8)
        return "Edited \(guard_.relativePath(for: resolved))"
    }
}
