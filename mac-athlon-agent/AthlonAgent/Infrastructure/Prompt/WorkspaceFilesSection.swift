import Foundation

/// Injects AGENTS.md and knowledge/ catalog before each reasoning iteration.
struct WorkspaceFilesSection: IEnvironmentPromptSection {
    let order = 400
    let placement: PromptSectionPlacement = .preCall

    func append(to builder: inout String, context: EnvironmentPromptContext) {
        WorkspacePromptLoader.appendWorkspaceFiles(to: &builder, context: context)
    }
}
