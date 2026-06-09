import Foundation

struct ToolsPolicySection: IEnvironmentPromptSection {
    let order = 500
    let placement: PromptSectionPlacement = .static

    func append(to builder: inout String, context: EnvironmentPromptContext) {
        builder += "Tools:\n"
        builder += "Native tools are provided via function calling. Use each tool's schema. Do not guess file contents.\n"
        builder += "\n"

        let mcpTools = context.tools.filter { $0.source?.lowercased() == "mcp" }
        if !mcpTools.isEmpty {
            builder += "Available MCP tools:\n"
            for tool in mcpTools {
                builder += "- \(tool.name): \(tool.description)\n"
            }
            builder += "\n"
        }

        builder += "For write operations, explain your intent before calling file_write or file_edit.\n"
        builder += "macOS: use bash/zsh via execute_command; execute_command defaults cwd to the workspace root when a workspace is active.\n"
        builder += "Skill scripts: use absolute paths from each skill's <files-root> inside the command string; do not use workspace-relative paths for skill files.\n"
        builder += "Quote paths that contain spaces or non-ASCII characters in shell commands (e.g. cat \"docs/报告.txt\").\n"
        builder += "When a command references a workspace file, take the path verbatim from the latest file_list/glob_files tool result — not from paraphrased assistant text.\n"
        builder += "\n"
    }
}
