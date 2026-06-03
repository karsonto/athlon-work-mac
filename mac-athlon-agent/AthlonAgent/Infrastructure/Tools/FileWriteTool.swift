import Foundation

struct FileWriteTool: AgentTool {
    let name = "file_write"
    let description = "Create or overwrite a file with backup."
    let parametersSchema: [String: String] = [
        "path": "Path to the file (relative to workspace or absolute)",
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
        try AtomicFile.writeText(content, to: fullPath)
        let fileName = (fullPath as NSString).lastPathComponent
        return ToolResultFormatter.success("Wrote \(content.count) chars to \(fileName)")
    }
}
