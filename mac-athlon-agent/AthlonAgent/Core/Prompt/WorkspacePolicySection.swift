import Foundation

struct WorkspacePolicySection: IEnvironmentPromptSection {
    let order = 300
    let placement: PromptSectionPlacement = .static

    func append(to builder: inout String, context: EnvironmentPromptContext) {
        guard context.hasWorkspace else {
            builder += "当前工作区尚未设定。\n"
            builder += "文件工具仍可使用：绝对路径将按系统路径解析；相对路径将基于当前进程目录。\n"
            builder += "如需稳定结果，请先让用户设置 Workspace，或优先使用绝对路径。\n"
            builder += "\n"
            return
        }

        builder += "Active workspace information:\n"
        builder += "In file tool arguments (path), prefer forward slashes (/), e.g. src/foo.swift, even on macOS.\n"
        builder += "Relative paths resolve from the active workspace root below; absolute paths are also allowed.\n"
        builder += "When using relative paths, use src/foo.swift. Avoid prefixing with \(context.workspaceName ?? "workspace")/.\n"
        builder += "Active workspace label: \(context.workspaceName ?? "workspace") (informational, not a path prefix).\n"
        builder += "Workspace root: \(context.workspaceRoot ?? "")\n"
        builder += "Workspace contents are intentionally not embedded in this prompt because they change often.\n"
        builder += "Use file_list to fetch a live directory listing when needed; use absolute paths for non-workspace files.\n"
        builder += "\n"
    }
}
