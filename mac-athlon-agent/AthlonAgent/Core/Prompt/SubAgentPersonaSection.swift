import Foundation

/// Defines the persona for sub-agent sessions.
struct SubAgentPersonaSection: IEnvironmentPromptSection {
    let order = 60
    let placement: PromptSectionPlacement = .static

    func append(to builder: inout String, context: EnvironmentPromptContext) {
        builder += "## Sub-Agent Persona\n"
        builder += "When assigned as a sub-agent (via call_assistant), follow the role description provided by the parent. "
        builder += "Complete the task within scope, use the same file and tool rules, and report results back concisely.\n"
        builder += "\n"
    }
}
