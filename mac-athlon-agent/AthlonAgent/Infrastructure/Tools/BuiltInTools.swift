import Foundation

/// Factory for built-in native agent tools (ported from WPF `Athlon.Agent.Infrastructure`).
enum BuiltInTools {
    static func makeAll(
        workspaceService: WorkspaceService,
        settings: AppSettings,
        skillService: SkillService,
        sessionManager: SessionManager? = nil,
        mcpRegistry: McpRegistryProviding,
        sessionWorkspacePath: String? = nil,
        executeCommandRegistry: ExecuteCommandProcessRegistry? = nil
    ) -> CompositeToolRouter {
        let guard_ = WorkspaceGuard(workspaceService: workspaceService, settings: settings)
        if let sessionWorkspacePath {
            let trimmed = sessionWorkspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                guard_.sessionRootPath = trimmed
            }
        }
        let skillLoader = SkillResourceLoader(skillService: skillService)

        let tools: [any AgentTool] = [
            FileListTool(guard: guard_),
            FileReadTool(guard: guard_, fileReadSettings: settings.fileRead),
            FileWriteTool(guard: guard_),
            FileEditTool(guard: guard_),
            GrepFilesTool(guard: guard_),
            GlobFilesTool(guard: guard_),
            ExecuteCommandTool(
                permissions: settings.toolPermissions,
                workspaceGuard: guard_,
                processRegistry: executeCommandRegistry
            ),
            LoadSkillThroughPathTool(loader: skillLoader)
        ]

        return CompositeToolRouter(localTools: tools, mcpRegistry: mcpRegistry)
    }

    static func toolNames() -> [String] {
        [
            "file_list", "file_read", "file_write", "file_edit",
            "grep_files", "glob_files", "execute_command",
            "load_skill_through_path"
        ]
    }

    static func isBuiltIn(_ toolName: String) -> Bool {
        toolNames().contains { $0.caseInsensitiveCompare(toolName) == .orderedSame }
    }
}
