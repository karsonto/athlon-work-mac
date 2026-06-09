import Foundation

enum SubAgentExecutionScope {
    @TaskLocal private static var depth: Int = 0

    static var currentDepth: Int { depth }

    static func withDepth<T>(operation: () async throws -> T) async rethrows -> T {
        try await $depth.withValue(depth + 1, operation: operation)
    }
}
