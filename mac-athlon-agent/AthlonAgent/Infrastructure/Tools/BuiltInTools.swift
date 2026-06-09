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
        executeCommandRegistry: ExecuteCommandProcessRegistry? = nil,
        longTermMemory: ILongTermMemory? = nil,
        subAgentTurnRunner: SubAgentTurnRunner? = nil,
        activeSessionContext: ActiveAgentSessionContext? = nil,
        storage: FileStorageService? = nil,
        subAgentSessionStore: SubAgentSessionStore? = nil,
        subAgentPromptOrchestrator: SubAgentSystemPromptOrchestrator? = nil
    ) -> (router: CompositeToolRouter, subAgentTool: SubAgentTool?) {
        let guard_ = WorkspaceGuard(workspaceService: workspaceService, settings: settings)
        if let sessionWorkspacePath {
            let trimmed = sessionWorkspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                guard_.sessionRootPath = trimmed
            }
        }
        let skillLoader = SkillResourceLoader(skillService: skillService)

        var localTools: [any AgentTool] = [
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

        var memoryTools: [any AgentTool] = []
        if let longTermMemory {
            memoryTools = [
                MemorySearchTool(longTermMemory: longTermMemory),
                MemoryGetTool(longTermMemory: longTermMemory)
            ]
        }
        localTools.append(contentsOf: memoryTools)

        var subAgentTool: SubAgentTool?
        if settings.subAgent.enabled,
           let subAgentTurnRunner,
           let activeSessionContext,
           let storage,
           let subAgentSessionStore,
           let subAgentPromptOrchestrator {
            let childRouter = ChildAgentToolRouter(localTools: localTools, mcpRegistry: mcpRegistry)
            let tool = SubAgentTool(
                settings: settings,
                storage: storage,
                sessionStore: subAgentSessionStore,
                childToolRouter: childRouter,
                subAgentPromptOrchestrator: subAgentPromptOrchestrator,
                activeSessionContext: activeSessionContext,
                turnExecutor: subAgentTurnRunner
            )
            subAgentTool = tool
            localTools.append(tool)
        }

        let router = CompositeToolRouter(localTools: localTools, mcpRegistry: mcpRegistry)
        return (router, subAgentTool)
    }

    static func toolNames() -> [String] {
        [
            "file_list", "file_read", "file_write", "file_edit",
            "grep_files", "glob_files", "execute_command",
            "load_skill_through_path",
            "memory_search", "memory_get",
            "call_assistant"
        ]
    }

    static func isBuiltIn(_ toolName: String) -> Bool {
        toolNames().contains { $0.caseInsensitiveCompare(toolName) == .orderedSame }
            || toolName.caseInsensitiveCompare(AppSettings.default.subAgent.toolName) == .orderedSame
    }
}
