import Foundation

/// Defines the persona for sub-agent sessions.
struct SubAgentPersonaSection: IEnvironmentPromptSection {
    let order = 50
    let placement: PromptSectionPlacement = .static

    func append(to builder: inout String, context: EnvironmentPromptContext) {
        guard let role = AmbientSubAgentRoleScope.currentRole?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !role.isEmpty else { return }

        builder += role
        builder += "\n\n"
        builder += "You are invoked by the parent agent via call_assistant.\n"
        builder += "Do not call call_assistant or delegate to other agents.\n"
        builder += "Use file tools, MCP tools, and load_skill_through_path when needed.\n"
        builder += "Deliver a clear, self-contained result the parent agent can synthesize.\n"
        builder += "\n"
    }
}
