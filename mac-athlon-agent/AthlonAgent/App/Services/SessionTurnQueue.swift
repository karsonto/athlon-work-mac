import Foundation

struct QueuedTurnPayload: Identifiable, Equatable {
    let queueId: String
    let sessionId: String
    let userInput: String
    let imageAttachments: [ImageAttachment]
    let ui: SessionTurnUiController

    var id: String { queueId }

    static func == (lhs: QueuedTurnPayload, rhs: QueuedTurnPayload) -> Bool {
        lhs.queueId == rhs.queueId && lhs.sessionId == rhs.sessionId && lhs.userInput == rhs.userInput
    }
}

/// Per-session FIFO queue for user turns while a session is busy.
final class SessionTurnQueue {
    private var queues: [String: [QueuedTurnPayload]] = [:]
    private let lock = NSLock()

    func enqueue(_ payload: QueuedTurnPayload) {
        lock.lock()
        defer { lock.unlock() }
        var queue = queues[payload.sessionId, default: []]
        queue.append(payload)
        queues[payload.sessionId] = queue
    }

    func dequeue(sessionId: String) -> QueuedTurnPayload? {
        lock.lock()
        defer { lock.unlock() }
        guard var queue = queues[sessionId], !queue.isEmpty else { return nil }
        let item = queue.removeFirst()
        if queue.isEmpty {
            queues.removeValue(forKey: sessionId)
        } else {
            queues[sessionId] = queue
        }
        return item
    }

    func requeueFront(_ payload: QueuedTurnPayload) {
        lock.lock()
        defer { lock.unlock() }
        var queue = queues[payload.sessionId, default: []]
        queue.insert(payload, at: 0)
        queues[payload.sessionId] = queue
    }

    func remove(sessionId: String, queueId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard var queue = queues[sessionId] else { return false }
        let before = queue.count
        queue.removeAll { $0.queueId == queueId }
        guard queue.count != before else { return false }
        if queue.isEmpty {
            queues.removeValue(forKey: sessionId)
        } else {
            queues[sessionId] = queue
        }
        return true
    }

    func clear(sessionId: String) {
        lock.lock()
        defer { lock.unlock() }
        queues.removeValue(forKey: sessionId)
    }

    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        queues.removeAll()
    }

    func count(sessionId: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return queues[sessionId]?.count ?? 0
    }

    func snapshot(sessionId: String) -> [QueuedTurnPayload] {
        lock.lock()
        defer { lock.unlock() }
        return queues[sessionId] ?? []
    }

    func hasQueuedTurns(sessionId: String) -> Bool {
        count(sessionId: sessionId) > 0
    }

    func hasAnyQueuedTurns() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return queues.values.contains { !$0.isEmpty }
    }
}
