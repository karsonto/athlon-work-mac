import Foundation

enum EnvironmentPromptSections {
    static func makeAll(
        settings: AppSettings,
        host: MacAgentHostEnvironment = MacAgentHostEnvironment(),
        skillsProvider: @escaping () -> [AvailableSkillInfo] = { [] }
    ) -> [IEnvironmentPromptSection] {
        [
            SubAgentPersonaSection(),
            BasePersonaSection(),
            HostEnvironmentSection(),
            EncodingPolicySection(),
            WorkspacePolicySection(),
            WorkspaceFilesSection(),
            FileToolsPolicySection(),
            ToolsPolicySection(),
            SubAgentDelegationSection(settings: settings),
            SkillsSection(skillsProvider: skillsProvider),
            ProductGuidanceSection(),
        ]
    }
}
