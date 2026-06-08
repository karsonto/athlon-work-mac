import Foundation

/// Tool that reads specific lines from a memory file.
struct MemoryGetTool: AgentTool {
    let longTermMemory: ILongTermMemory
    let name = "memory_get"
    let description = "Read specific lines from a memory file. Use after memory_search to pull full context around matched lines."
    let parametersSchema: [String: String] = [
        "path": "Relative path to the memory file (e.g., MEMORY.md or 2026-04-01.md)",
        "start_line": "Start line number (1-based, inclusive)",
        "end_line": "End line number (1-based, inclusive)"
    ]

    func invoke(arguments: [String: String]) async throws -> String {
        guard let path = arguments["path"], !path.isEmpty else {
            throw ToolError.missingArgument("path", tool: name)
        }
        guard let startLineStr = arguments["start_line"], let startLine = Int(startLineStr), startLine >= 1 else {
            throw ToolError.missingArgument("start_line", tool: name)
        }
        guard let endLineStr = arguments["end_line"], let endLine = Int(endLineStr), endLine >= startLine else {
            throw ToolError.missingArgument("end_line", tool: name)
        }

        let content: String
        if path == "MEMORY.md" {
            content = (try? await longTermMemory.readCurated()) ?? ""
        } else {
            content = (try? await longTermMemory.readDailyFile(relativePath: path)) ?? ""
        }

        let lines = content.components(separatedBy: .newlines)
        let start = max(0, startLine - 1)
        let end = min(lines.count, endLine)
        guard start < end else {
            throw ToolError.failed("Line range out of bounds", detail: "File has \(lines.count) lines")
        }

        let selected = lines[start..<end]
        let output = selected.enumerated().map { "\(startLine + $0.offset)|\($0.element)" }.joined(separator: "\n")
        return output
    }
}
