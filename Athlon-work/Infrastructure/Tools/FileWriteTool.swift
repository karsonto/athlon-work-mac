import Foundation

nonisolated struct FileWriteTool: AgentTool {
    let name = "file_write"
    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Write (create or overwrite) a text file in the workspace.",
            parameters: [
                "type": "object",
                "properties": [
                    "path": ["type": "string"] as [String: Any],
                    "content": ["type": "string"] as [String: Any],
                ] as [String: Any],
                "required": ["path", "content"],
            ]
        )
    }

    func invoke(arguments: String, context: AgentRunContext) async throws -> String {
        let args = try ToolJSON.object(from: arguments)
        guard let path = args["path"] as? String, !path.isEmpty else {
            throw AgentToolError.invalidArguments("path is required")
        }
        let content = (args["content"] as? String) ?? ""
        let guard_ = WorkspaceGuard(workspaceRoot: context.workspaceRoot, ignorePatterns: context.ignorePatterns)
        let resolved = try guard_.resolve(path)
        let dir = (resolved as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try content.write(toFile: resolved, atomically: true, encoding: .utf8)
        return "Wrote \(content.utf8.count) bytes to \(guard_.relativePath(for: resolved))"
    }
}
