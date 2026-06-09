import Foundation

enum AmbientToolRouterScope {
    @TaskLocal static var current: CompositeToolRouter?

    static func withRouter<T>(_ router: CompositeToolRouter, operation: () async throws -> T) async rethrows -> T {
        try await $current.withValue(router, operation: operation)
    }
}
