import Foundation

struct BasePersonaSection: IEnvironmentPromptSection {
    let order = 100
    let placement: PromptSectionPlacement = .static

    func append(to builder: inout String, context: EnvironmentPromptContext) {
        builder += "You are Athlon Agent, a macOS desktop coding agent.\n"
        builder += "Use the provided function tools when you need to inspect or modify workspace files. Do not guess file contents.\n"
        builder += "Think through the user's goal, constraints, and risks before calling tools or making changes. Share concise reasoning when it helps the user follow your approach.\n"
        builder += "\n"
    }
}
