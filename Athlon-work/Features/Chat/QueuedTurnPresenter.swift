import Foundation
import Observation

struct QueuedTurnItem: Identifiable, Hashable, Sendable {
    var id: String { queueId }
    var queueId: String
    var sessionId: String
    var text: String
    var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 48 { return trimmed }
        return String(trimmed.prefix(48)) + "…"
    }
}

/// Exposes queued turn items for the navigation sidebar.
@Observable
@MainActor
final class QueuedTurnPresenter {
    private let turnHost: SessionTurnHost
    /// sessionId → queued items (UI mirror of host queues).
    private(set) var itemsBySession: [String: [QueuedTurnItem]] = [:]

    init(turnHost: SessionTurnHost) {
        self.turnHost = turnHost
    }

    func items(for sessionId: String) -> [QueuedTurnItem] {
        itemsBySession[sessionId] ?? []
    }

    func count(for sessionId: String) -> Int {
        items(for: sessionId).count
    }

    func enqueue(sessionId: String, text: String, images: [ImageAttachment] = []) -> QueuedTurnItem {
        let payload = QueuedTurnPayload(sessionId: sessionId, text: text, images: images)
        turnHost.enqueue(payload)
        let item = QueuedTurnItem(
            queueId: payload.queueId,
            sessionId: sessionId,
            text: text
        )
        var list = itemsBySession[sessionId] ?? []
        list.append(item)
        itemsBySession[sessionId] = list
        return item
    }

    @discardableResult
    func remove(sessionId: String, queueId: String) -> Bool {
        guard turnHost.remove(sessionId: sessionId, queueId: queueId) else { return false }
        var list = itemsBySession[sessionId] ?? []
        list.removeAll { $0.queueId == queueId }
        if list.isEmpty {
            itemsBySession.removeValue(forKey: sessionId)
        } else {
            itemsBySession[sessionId] = list
        }
        return true
    }

    func clear(sessionId: String) {
        turnHost.clearQueue(sessionId)
        itemsBySession.removeValue(forKey: sessionId)
    }

    func removeSession(_ sessionId: String) {
        clear(sessionId: sessionId)
        itemsBySession.removeValue(forKey: sessionId)
    }

    /// Pop next queued payload from host and drop its UI mirror entry.
    func dequeueNext(sessionId: String) -> QueuedTurnPayload? {
        guard let payload = turnHost.dequeue(sessionId) else { return nil }
        var list = itemsBySession[sessionId] ?? []
        list.removeAll { $0.queueId == payload.queueId }
        if list.isEmpty {
            itemsBySession.removeValue(forKey: sessionId)
        } else {
            itemsBySession[sessionId] = list
        }
        return payload
    }

    func syncFromHost(sessionId: String) {
        let payloads = turnHost.queued(for: sessionId)
        itemsBySession[sessionId] = payloads.map {
            QueuedTurnItem(queueId: $0.queueId, sessionId: $0.sessionId, text: $0.text)
        }
        if payloads.isEmpty {
            itemsBySession.removeValue(forKey: sessionId)
        }
    }
}
