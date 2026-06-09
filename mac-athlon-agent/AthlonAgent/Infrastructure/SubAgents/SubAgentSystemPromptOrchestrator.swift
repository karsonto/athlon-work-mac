import Foundation

/// Sub-agent prompt orchestrator aligned with WPF `SubAgentSystemPromptOrchestrator`.
struct SubAgentSystemPromptOrchestrator {
    private let orchestrator: SystemPromptOrchestrator

    init(
        settings: AppSettings,
        skillsProvider: @escaping () -> [AvailableSkillInfo] = { [] },
        longTermMemory: ILongTermMemory? = nil,
        skillsDirectory: String = AppPathProvider.shared.skillsPath
    ) {
        let sections: [IEnvironmentPromptSection] = [
            SubAgentPersonaSection(),
            HostEnvironmentSection(),
            EncodingPolicySection(),
            WorkspacePolicySection(),
            WorkspaceFilesSection(),
            FileToolsPolicySection(),
            ToolsPolicySection(),
            SkillsSection(skillsProvider: skillsProvider),
        ]

        var contributors: [IPreReasoningPromptContributor] = []
        if let longTermMemory {
            contributors.append(MemoryPromptContributor(longTermMemory: longTermMemory, settings: settings.memory))
        }

        self.orchestrator = SystemPromptOrchestrator(
            settings: settings,
            sections: sections,
            preReasoningContributors: contributors
        )
    }

    func prepareForTurn(
        session: AgentSession,
        tools: [ToolDefinition]
    ) -> FrozenSystemPrompt {
        orchestrator.prepareForTurn(session: session, tools: tools)
    }

    func buildForReasoningIteration(
        frozen: FrozenSystemPrompt,
        session: AgentSession,
        tools: [ToolDefinition]
    ) async -> String {
        await orchestrator.buildForReasoningIteration(frozen: frozen, session: session, tools: tools)
    }
}
