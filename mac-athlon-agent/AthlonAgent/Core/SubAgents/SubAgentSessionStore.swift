import Foundation

protocol SubAgentSessionStore: AnyObject {
    func load(parentSessionId: String, subSessionId: String) async throws -> SubAgentSessionBundle?
    func save(parentSessionId: String, subSessionId: String, bundle: SubAgentSessionBundle) async throws
}
