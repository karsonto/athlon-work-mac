import Foundation

protocol ActiveAgentSessionContext: AnyObject {
    var sessionId: String? { get }
    func setSession(_ sessionId: String?)
    func withSession<T>(_ sessionId: String, operation: () async throws -> T) async rethrows -> T
}

final class DefaultActiveAgentSessionContext: ActiveAgentSessionContext {
    @TaskLocal private static var ambientSessionId: String?
    private var currentSessionId: String?

    var sessionId: String? { Self.ambientSessionId ?? currentSessionId }

    func setSession(_ sessionId: String?) {
        currentSessionId = sessionId
    }

    func withSession<T>(_ sessionId: String, operation: () async throws -> T) async rethrows -> T {
        try await Self.$ambientSessionId.withValue(sessionId, operation: operation)
    }
}
