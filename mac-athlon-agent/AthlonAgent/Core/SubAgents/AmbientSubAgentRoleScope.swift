import Foundation

enum AmbientSubAgentRoleScope {
    @TaskLocal static var currentRole: String?

    static func withRole<T>(_ role: String, operation: () async throws -> T) async rethrows -> T {
        try await $currentRole.withValue(role, operation: operation)
    }
}
