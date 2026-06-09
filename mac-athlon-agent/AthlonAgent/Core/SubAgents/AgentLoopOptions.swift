import Foundation

struct AgentLoopOptions {
    var maxModelToolRounds: Int?
}

enum AgentLoopOptionsScope {
    @TaskLocal static var current: AgentLoopOptions?

    static func withValue<T>(_ options: AgentLoopOptions, operation: () async throws -> T) async rethrows -> T {
        try await $current.withValue(options, operation: operation)
    }
}
