import Foundation

/// Append meaningful turn stubs to MEMORY.md + daily notes when memory is enabled.
nonisolated struct PostTurnMemoryMiddleware: TurnMiddleware {
    private let memory: FileLongTermMemory

    init(paths: AppPathProviding = AppPathProvider()) {
        self.memory = FileLongTermMemory(paths: paths)
    }

    init(memory: FileLongTermMemory) {
        self.memory = memory
    }

    func onTurnCompleted(sessionId: String, messages: [ChatMessage], context: AgentRunContext) async throws {
        let settings = context.settings.memory
        guard settings.enabled else { return }

        let lastUser = messages.last(where: { $0.role == .user })?.content ?? ""
        let lastAssistant = messages.last(where: { $0.role == .assistant })?.content ?? ""
        guard !lastUser.isEmpty || !lastAssistant.isEmpty else { return }

        try memory.appendTurnNote(
            workspaceRoot: context.workspaceRoot.isEmpty ? "default" : context.workspaceRoot,
            settings: settings,
            sessionId: sessionId,
            userSnippet: lastUser,
            assistantSnippet: lastAssistant
        )
    }
}
