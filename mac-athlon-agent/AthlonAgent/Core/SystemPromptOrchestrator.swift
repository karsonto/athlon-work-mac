import Foundation

struct FrozenSystemPrompt: Equatable {
    let text: String
}

struct EnvironmentPromptContext {
    let session: AgentSession
    let workspaceRoot: String?
    let workspaceName: String?
    let ignorePatterns: [String]
    let tools: [ToolDefinition]
    let host: MacAgentHostEnvironment
    let promptSettings: PromptSettings

    var hasWorkspace: Bool {
        guard let workspaceRoot else { return false }
        return !workspaceRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Builds system prompts aligned with WPF `SystemPromptOrchestrator`.
struct SystemPromptOrchestrator {
    let settings: AppSettings
    private let sections: [IEnvironmentPromptSection]
    private let preReasoningContributors: [IPreReasoningPromptContributor]

    init(
        settings: AppSettings,
        sections: [IEnvironmentPromptSection] = [],
        preReasoningContributors: [IPreReasoningPromptContributor] = []
    ) {
        self.settings = settings
        self.sections = sections
        self.preReasoningContributors = preReasoningContributors.sorted { $0.priority < $1.priority }
    }

    func prepareForTurn(session: AgentSession, tools: [ToolDefinition]) -> FrozenSystemPrompt {
        let context = makeContext(session: session, tools: tools)
        var builder = ""
        appendSections(&builder, context: context, placement: .static)
        appendSections(&builder, context: context, placement: .preCall)
        return FrozenSystemPrompt(text: formatPrompt(builder))
    }

    func buildForReasoningIteration(
        frozen: FrozenSystemPrompt,
        session: AgentSession,
        tools: [ToolDefinition]
    ) async -> String {
        guard !preReasoningContributors.isEmpty else { return frozen.text }
        var result = frozen.text
        let context = makeContext(session: session, tools: tools)
        for contributor in preReasoningContributors {
            await contributor.append(to: &result, context: context)
        }
        return formatPrompt(result)
    }

    private func appendSections(
        _ builder: inout String,
        context: EnvironmentPromptContext,
        placement: PromptSectionPlacement
    ) {
        for section in sections.filter({ $0.placement == placement }).sorted(by: { $0.order < $1.order }) {
            section.append(to: &builder, context: context)
        }
    }

    private func makeContext(session: AgentSession, tools: [ToolDefinition]) -> EnvironmentPromptContext {
        let workspace = resolveWorkspace(session)
        return EnvironmentPromptContext(
            session: session,
            workspaceRoot: workspace?.rootPath,
            workspaceName: workspace?.name,
            ignorePatterns: workspace?.ignorePatterns ?? settings.workspaceIgnore.directoryNames,
            tools: tools,
            host: MacAgentHostEnvironment(),
            promptSettings: settings.prompt
        )
    }

    private struct ResolvedWorkspace {
        let name: String
        let rootPath: String
        let ignorePatterns: [String]
    }

    private func resolveWorkspace(_ session: AgentSession) -> ResolvedWorkspace? {
        if let active = session.activeWorkspace, !active.isEmpty {
            let rootPath = URL(fileURLWithPath: active).standardizedFileURL.path
            let name = (rootPath as NSString).lastPathComponent
            let match = settings.workspaces.first {
                !$0.rootPath.isEmpty
                    && URL(fileURLWithPath: $0.rootPath).standardizedFileURL.path == rootPath
            }
            let patterns = match?.ignorePatterns ?? settings.workspaceIgnore.directoryNames
            return ResolvedWorkspace(name: name, rootPath: rootPath, ignorePatterns: patterns)
        }
        guard let configured = settings.workspaces.first(where: { !$0.rootPath.isEmpty }) else { return nil }
        let rootPath = URL(fileURLWithPath: configured.rootPath).standardizedFileURL.path
        return ResolvedWorkspace(
            name: configured.name,
            rootPath: rootPath,
            ignorePatterns: configured.ignorePatterns ?? settings.workspaceIgnore.directoryNames
        )
    }

    private func formatPrompt(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}
