import Foundation

enum AmbientSystemPromptOrchestratorScope {
    @TaskLocal static var current: (any PromptOrchestrating)?

    static func withOrchestrator<T>(
        _ orchestrator: any PromptOrchestrating,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await $current.withValue(orchestrator, operation: operation)
    }
}
