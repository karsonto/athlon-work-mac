import Foundation

struct FileWriteTool: AgentTool {
    let name = "file_write"
    let description = "Create or overwrite a workspace file with backup."
    let parametersSchema: [String: String] = [
        "path": ToolPathDescriptions.workspaceRelativePath,
        "content": "New content"
    ]
    private let guard_: WorkspaceGuard

    init(guard workspaceGuard: WorkspaceGuard) {
        self.guard_ = workspaceGuard
    }

    func invoke(arguments: [String: String]) async throws -> String {
        let path = try ToolArguments.normalizedPath(arguments, tool: name)
        let content = try ToolArguments.required(arguments, name: "content", tool: name)
        let fullPath = try guard_.normalize(path)
        guard guard_.isInsideWorkspace(fullPath) else {
            throw ToolError.outsideWorkspace(fullPath)
        }
        try AtomicFile.writeText(content, to: fullPath)
        let fileName = (fullPath as NSString).lastPathComponent
        return ToolResultFormatter.success("Wrote \(content.count) chars to \(fileName)")
    }
}
