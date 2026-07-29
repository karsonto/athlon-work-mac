import Foundation

struct QueuedTurnPayload: Identifiable, Hashable, Sendable {
    var id: String { queueId }
    var queueId: String
    var sessionId: String
    var text: String
    var images: [ImageAttachment]

    init(queueId: String = UUID().uuidString.replacingOccurrences(of: "-", with: ""),
         sessionId: String,
         text: String,
         images: [ImageAttachment] = []) {
        self.queueId = queueId
        self.sessionId = sessionId
        self.text = text
        self.images = images
    }
}

/// Limits concurrent agent turns (max 3) and holds per-session run tasks + pending queues.
@MainActor
final class SessionTurnHost {
    static let maxConcurrentTurns = 3

    private var runners: [String: Task<Void, Never>] = [:]
    private var queues: [String: [QueuedTurnPayload]] = [:]

    var runningSessionIds: [String] { Array(runners.keys) }

    func isRunning(_ sessionId: String) -> Bool {
        runners[sessionId] != nil
    }

    var activeRunnerCount: Int { runners.count }

    /// Start a turn if capacity allows and the session is idle.
    /// - Returns: `nil` on success, or an error message.
    @discardableResult
    func tryStart(
        sessionId: String,
        run: @escaping @MainActor () async -> Void,
        onFinished: (@MainActor () -> Void)? = nil
    ) -> String? {
        if runners[sessionId] != nil {
            return "当前对话正在生成，请等待完成或先停止。"
        }
        if runners.count >= Self.maxConcurrentTurns {
            return "已有 \(Self.maxConcurrentTurns) 个对话在生成，请等待或停止其中一个。"
        }

        let task = Task { @MainActor in
            await run()
            self.runners.removeValue(forKey: sessionId)
            onFinished?()
        }
        runners[sessionId] = task
        return nil
    }

    func cancel(_ sessionId: String) {
        runners[sessionId]?.cancel()
        runners.removeValue(forKey: sessionId)
    }

    func cancelAll() {
        for id in Array(runners.keys) {
            cancel(id)
        }
    }

    func enqueue(_ payload: QueuedTurnPayload) {
        var list = queues[payload.sessionId] ?? []
        list.append(payload)
        queues[payload.sessionId] = list
    }

    func dequeue(_ sessionId: String) -> QueuedTurnPayload? {
        guard var list = queues[sessionId], !list.isEmpty else { return nil }
        let first = list.removeFirst()
        if list.isEmpty {
            queues.removeValue(forKey: sessionId)
        } else {
            queues[sessionId] = list
        }
        return first
    }

    func requeueFront(_ payload: QueuedTurnPayload) {
        var list = queues[payload.sessionId] ?? []
        list.insert(payload, at: 0)
        queues[payload.sessionId] = list
    }

    @discardableResult
    func remove(sessionId: String, queueId: String) -> Bool {
        guard var list = queues[sessionId] else { return false }
        let before = list.count
        list.removeAll { $0.queueId == queueId }
        if list.count == before { return false }
        if list.isEmpty {
            queues.removeValue(forKey: sessionId)
        } else {
            queues[sessionId] = list
        }
        return true
    }

    func clearQueue(_ sessionId: String) {
        queues.removeValue(forKey: sessionId)
    }

    func queued(for sessionId: String) -> [QueuedTurnPayload] {
        queues[sessionId] ?? []
    }

    func queuedCount(for sessionId: String) -> Int {
        queues[sessionId]?.count ?? 0
    }

    func removeSession(_ sessionId: String) {
        cancel(sessionId)
        clearQueue(sessionId)
    }
}
