import Foundation

struct FileReadTool: AgentTool {
    let name = "file_read"
    let description =
        "Read file content with line numbers (N|line) for display. Large files require offset/limit; "
        + "use grep_files to locate content first. Do not use N| prefixes in file_edit old_text."
    let parametersSchema: [String: String] = [
        "path": "Path to the file (relative to workspace or absolute)",
        "offset": "Optional 0-indexed start line. Default: 0",
        "limit": "Optional max lines (default 500, max 2000)",
        "start_line": "Optional 1-indexed start line",
        "end_line": "Optional 1-indexed end line (inclusive)"
    ]

    private let guard_: WorkspaceGuard
    private let fileReadSettings: FileReadSettings

    init(guard workspaceGuard: WorkspaceGuard, fileReadSettings: FileReadSettings) {
        self.guard_ = workspaceGuard
        self.fileReadSettings = fileReadSettings
    }

    func invoke(arguments: [String: String]) async throws -> String {
        let path = try ToolArguments.normalizedPath(arguments, tool: name)
        let fullPath = try guard_.normalize(path)
        guard FileManager.default.fileExists(atPath: fullPath) else {
            throw ToolError.notFound("File not found: \(fullPath)")
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: fullPath)
        let fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        if fileSize > fileReadSettings.maxFileBytes {
            throw ToolError.failed(
                "File too large",
                detail: "File exceeds \(fileReadSettings.maxFileBytes) bytes — use grep_files to search, or read with offset/limit in smaller chunks"
            )
        }

        let selection = FileReadLineReader.resolveSelection(arguments, settings: fileReadSettings)
        let read = try FileReadLineReader.read(fullPath: fullPath, selection: selection, settings: fileReadSettings)
        let fileName = (fullPath as NSString).lastPathComponent
        let summary = FileReadLineReader.buildSummary(fileName: fileName, result: read)
        let content = read.linesReturned == 0 && read.body.isEmpty ? "(no lines in range)" : read.body
        return ToolResultFormatter.success(summary, content: content)
    }
}
