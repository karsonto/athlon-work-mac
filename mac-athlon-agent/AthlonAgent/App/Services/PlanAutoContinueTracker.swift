import Foundation

/// Tracks completed plan auto-continue rounds per session.
final class PlanAutoContinueTracker {
    private var completedRounds: [String: Int] = [:]
    private let lock = NSLock()

    func get(_ sessionId: String) -> Int {
        guard !sessionId.isEmpty else { return 0 }
        lock.lock()
        defer { lock.unlock() }
        return completedRounds[sessionId, default: 0]
    }

    @discardableResult
    func increment(_ sessionId: String) -> Int {
        guard !sessionId.isEmpty else { return 0 }
        lock.lock()
        defer { lock.unlock() }
        let next = completedRounds[sessionId, default: 0] + 1
        completedRounds[sessionId] = next
        return next
    }

    func reset(_ sessionId: String) {
        guard !sessionId.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        completedRounds.removeValue(forKey: sessionId)
    }
}
