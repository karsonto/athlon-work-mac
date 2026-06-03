import Foundation

struct FileEditTool: AgentTool {
    let name = "file_edit"
    let description =
        "Replace exact text in a workspace file (with backup). old_text must match disk content exactly — not file_read's N|line prefixes."
    let parametersSchema: [String: String] = [
        "path": ToolPathDescriptions.workspaceRelativePath,
        "old_text": "Exact substring from the file (no line-number prefixes)",
        "new_text": "Replacement",
        "replace_all": "Optional true to replace all occurrences"
    ]
    private let guard_: WorkspaceGuard

    init(guard workspaceGuard: WorkspaceGuard) {
        self.guard_ = workspaceGuard
    }

    func invoke(arguments: [String: String]) async throws -> String {
        let path = try ToolArguments.normalizedPath(arguments, tool: name)
        let oldText = try ToolArguments.required(arguments, name: "old_text", tool: name)
        let newText = try ToolArguments.required(arguments, name: "new_text", tool: name)
        let fullPath = try guard_.normalize(path)
        guard guard_.isInsideWorkspace(fullPath) else {
            throw ToolError.outsideWorkspace(fullPath)
        }

        let content = try String(contentsOfFile: fullPath, encoding: .utf8)
        let replaceAll = arguments["replace_all"]?.lowercased() == "true"
        let match = FileEditMatcher.tryMatch(content: content, oldText: oldText, replaceAll: replaceAll)

        switch match.status {
        case .notFound:
            throw ToolError.failed("Text not found", detail: FileEditMatcher.buildNotFoundMessage(oldText))
        case .notUnique:
            throw ToolError.failed("Text is not unique", detail: "old_text must match exactly once unless replace_all is true.")
        case .found:
            break
        }

        let effectiveNewText = FileEditMatcher.resolveNewText(originalOldText: oldText, originalNewText: newText, match: match)
        let updated = FileEditMatcher.applyReplace(
            content: content,
            matchedOldText: match.matchedOldText,
            newText: effectiveNewText,
            replaceAll: replaceAll
        )
        try AtomicFile.writeText(updated, to: fullPath)
        let count = replaceAll ? match.occurrences : 1
        let fileName = (fullPath as NSString).lastPathComponent
        return ToolResultFormatter.success("Edited \(fileName) (\(count) replacement(s))")
    }
}
