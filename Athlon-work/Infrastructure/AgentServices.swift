import Foundation

/// Composition root for agent runtime dependencies.
nonisolated enum AgentServices {
    struct Bundle: Sendable {
        let paths: AppPathProviding
        let storage: FileStorageService
        let keychain: KeychainCredentialStore
        let builtinRouter: BuiltinToolRouter
        let router: any ToolRouter
        let runtime: AgentRuntime
        let mcpRegistry: McpRegistry
        let skillCatalog: SkillCatalog
        let knowledgeStore: KnowledgeStore
        let memory: FileLongTermMemory
        let subAgentManager: SubAgentSessionManager

        func loadSettings() throws -> AppSettings {
            try storage.loadSettings()
        }

        func saveSettings(_ settings: AppSettings) throws {
            try storage.saveSettings(settings)
        }

        /// Reconnect MCP servers after settings change (call from UI Task).
        func refreshMcp(settings: AppSettings) async {
            await mcpRegistry.connect(settings: settings)
        }
    }

    static func make(
        paths: AppPathProviding = AppPathProvider(),
        keychain: KeychainCredentialStore = KeychainCredentialStore(),
        urlSession: URLSession = .shared
    ) throws -> Bundle {
        try paths.ensureCreated()
        let storage = FileStorageService(paths: paths)
        let settings = (try? storage.loadSettings()) ?? AppSettings()

        let modelClient = OpenAICompatibleChatModelClient(session: urlSession) {
            try keychain.loadModelAPIKey()
        }

        let mcpRegistry = McpRegistry()
        let skillCatalog = SkillCatalog(paths: paths)
        let knowledgeStore = KnowledgeStore(paths: paths, settings: settings.knowledge)
        try? knowledgeStore.ensureReady()
        let memory = FileLongTermMemory(paths: paths)
        let subAgentManager = SubAgentSessionManager(paths: paths, storage: storage)

        let builtin = BuiltinToolRouter()
        var extraTools: [any AgentTool] = []

        if settings.knowledge.enabled {
            let search = KnowledgeSearchService(store: knowledgeStore)
            extraTools.append(KnowledgeSearchTool(searchService: search))
        }
        if settings.memory.enabled {
            extraTools.append(MemorySearchTool(memory: memory))
            extraTools.append(MemoryGetTool(memory: memory))
        }
        if settings.subAgent.enabled {
            let spawn: any AgentTool = SessionsSpawnTool(manager: subAgentManager)
            let send: any AgentTool = SessionsSendTool(manager: subAgentManager)
            let list: any AgentTool = SessionsListTool(manager: subAgentManager)
            let history: any AgentTool = SessionsHistoryTool(manager: subAgentManager)
            extraTools.append(contentsOf: [spawn, send, list, history])
        }

        // MCP tools resolve dynamically from mcpRegistry after connect().
        let router = McpDelegatingToolRouter(
            builtin: builtin,
            extraTools: extraTools,
            mcpTools: [],
            mcpRegistry: mcpRegistry,
            searchSettings: settings.mcpSearch
        )

        let pipeline = ToolInvocationPipeline(router: router) {
            (try? storage.loadSettings()) ?? AppSettings()
        }

        let middleware: [any TurnMiddleware] = [
            CompactionTurnMiddleware(),
            ToolStormTurnMiddleware(),
            PostTurnMemoryMiddleware(memory: memory),
        ]

        let runtime = AgentRuntime(
            storage: storage,
            modelClient: modelClient,
            router: router,
            pipeline: pipeline,
            middleware: middleware,
            settingsProvider: {
                (try? storage.loadSettings()) ?? AppSettings()
            }
        )

        return Bundle(
            paths: paths,
            storage: storage,
            keychain: keychain,
            builtinRouter: builtin,
            router: router,
            runtime: runtime,
            mcpRegistry: mcpRegistry,
            skillCatalog: skillCatalog,
            knowledgeStore: knowledgeStore,
            memory: memory,
            subAgentManager: subAgentManager
        )
    }

    /// Build a fresh router including currently connected MCP tools (used after MCP connect).
    static func makeRouter(
        settings: AppSettings,
        paths: AppPathProviding,
        mcpRegistry: McpRegistry,
        knowledgeStore: KnowledgeStore,
        memory: FileLongTermMemory,
        subAgentManager: SubAgentSessionManager,
        builtin: BuiltinToolRouter = BuiltinToolRouter()
    ) -> McpDelegatingToolRouter {
        var extraTools: [any AgentTool] = []
        if settings.knowledge.enabled {
            extraTools.append(KnowledgeSearchTool(searchService: KnowledgeSearchService(store: knowledgeStore)))
        }
        if settings.memory.enabled {
            extraTools.append(MemorySearchTool(memory: memory))
            extraTools.append(MemoryGetTool(memory: memory))
        }
        if settings.subAgent.enabled {
            let spawn: any AgentTool = SessionsSpawnTool(manager: subAgentManager)
            let send: any AgentTool = SessionsSendTool(manager: subAgentManager)
            let list: any AgentTool = SessionsListTool(manager: subAgentManager)
            let history: any AgentTool = SessionsHistoryTool(manager: subAgentManager)
            extraTools.append(contentsOf: [spawn, send, list, history])
        }
        return McpDelegatingToolRouter(
            builtin: builtin,
            extraTools: extraTools,
            mcpTools: mcpRegistry.makeAgentTools(),
            searchSettings: settings.mcpSearch
        )
    }
}
