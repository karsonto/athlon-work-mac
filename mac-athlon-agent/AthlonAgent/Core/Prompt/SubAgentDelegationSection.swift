import Foundation

/// Instructs the model on how to delegate sub-tasks to child assistants.
struct SubAgentDelegationSection: IEnvironmentPromptSection {
    let order = 50
    let placement: PromptSectionPlacement = .static
    private let settings: AppSettings

    init(settings: AppSettings = AppSettings.default) {
        self.settings = settings
    }

    func append(to builder: inout String, context: EnvironmentPromptContext) {
        guard settings.subAgent.enabled else { return }
        builder += "## Delegating sub-tasks\n"
        builder += "Use `call_assistant` when a focused sub-run with tools and memory helps (research, multi-step file work, isolated experiments).\n"
        builder += "- **New session:** provide `role` (who the child is, boundaries, output style) and `message` (this turn's task, paths, acceptance criteria).\n"
        builder += "- **Continue:** pass `session_id` from the prior tool result and a new `message`; `role` is optional (updates the child's role if provided).\n"
        builder += "- You may name a skill in `message` or let the child use `load_skill_through_path` from the skills list.\n"
        builder += "- Wait for the tool result; summarize for the user. The child cannot spawn nested agents.\n"
        builder += "\n"
    }
}
