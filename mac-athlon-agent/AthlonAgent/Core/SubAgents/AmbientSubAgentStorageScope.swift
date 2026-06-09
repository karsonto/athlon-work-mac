import Foundation

/// Redirects session file I/O for a sub-agent run to
/// `{sessions}/{parentId}/subagents/default/{subSessionId}/`.
enum AmbientSubAgentStorageScope {
    struct SubAgentStorageContext: Equatable {
        let parentSessionId: String
        let subSessionId: String
    }

    @TaskLocal static var current: SubAgentStorageContext?

    static func withStorage<T>(
        parentSessionId: String,
        subSessionId: String,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await $current.withValue(
            SubAgentStorageContext(parentSessionId: parentSessionId, subSessionId: subSessionId),
            operation: operation
        )
    }

    static func isSubAgentSessionPath(_ sessionJsonPath: String) -> Bool {
        let parts = sessionJsonPath.split(separator: "/").map(String.init)
            + sessionJsonPath.split(separator: "\\").map(String.init)
        return parts.contains { $0.caseInsensitiveCompare("subagents") == .orderedSame }
    }

    static func resolveSessionDirectory(sessionsPath: String, sessionId: String) -> String {
        if let context = current,
           context.subSessionId == sessionId {
            return (sessionsPath as NSString).appendingPathComponent(context.parentSessionId)
                .appending("/subagents/default/\(context.subSessionId)")
        }
        return (sessionsPath as NSString).appendingPathComponent(sessionId)
    }
}
