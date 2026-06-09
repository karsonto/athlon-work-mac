import Foundation

/// Sub-agent prompt orchestrator aligned with WPF `SubAgentSystemPromptOrchestrator`:
/// reuses parent environment sections but excludes parent-only persona, product guidance, and delegation.
struct SubAgentSystemPromptOrchestrator {
    private var orchestrator: SystemPromptOrchestrator

    init(
        settings: AppSettings,
        skillsProvider: @escaping () -> [AvailableSkillInfo] = { [] },
        longTermMemory: ILongTermMemory? = nil,
        skillsDirectory: String = AppPathProvider.shared.skillsPath
    ) {
        let sections: [IEnvironmentPromptSection] = [
            SubAgentPersonaSection(),
            EncodingPolicySection(),
            WorkspaceFilesSection(),
            SkillsSection(skillsProvider: skillsProvider),
        ]
        let filtered = sections.filter { !($0 is SubAgentDelegationSection) }
        var orch = SystemPromptOrchestrator(
            settings: settings,
            skillsDirectory: skillsDirectory,
            sections: filtered
        )
        orch.isSubAgent = true
        if let longTermMemory {
            orch.postProcessPrompt = { prompt in
                _ = await MemoryPromptContributor(longTermMemory: longTermMemory).append(to: &prompt)
            }
        }
        self.orchestrator = orch
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
