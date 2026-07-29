import Foundation

nonisolated struct AgentTurnCoordinator {
    private let modelClient: AgentModelClient
    private let defaultMaxRoundsFallback = 32

    init(modelClient: AgentModelClient) {
        self.modelClient = modelClient
    }

    func callModel(
        messages: [[String: Any]],
        tools: [[String: Any]]?,
        settings: ModelSettings,
        onDelta: @escaping @Sendable (ModelDelta) -> Void,
        allowOverflowRetry: Bool = true
    ) async throws -> ModelCompletion {
        do {
            return try await modelClient.complete(
                messages: messages,
                tools: tools,
                settings: settings,
                onDelta: onDelta
            )
        } catch let error as AgentModelClientError where error.isContextOverflow && allowOverflowRetry {
            // One overflow retry: drop oldest non-system messages (keep system + last half).
            let compacted = Self.compactForOverflowRetry(messages)
            return try await modelClient.complete(
                messages: compacted,
                tools: tools,
                settings: settings,
                onDelta: onDelta
            )
        }
    }

    static func resolveMaxRounds(_ settings: AppSettings) -> Int {
        settings.agentTurn.maxModelToolRounds ?? 32
    }

    private static func compactForOverflowRetry(_ messages: [[String: Any]]) -> [[String: Any]] {
        guard messages.count > 4 else { return messages }
        let system = messages.filter { ($0["role"] as? String) == "system" }
        let rest = messages.filter { ($0["role"] as? String) != "system" }
        let keep = Array(rest.suffix(max(2, rest.count / 2)))
        return system + [["role": "system", "content": "(Earlier conversation truncated after context overflow.)"]] + keep
    }
}
