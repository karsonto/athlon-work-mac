import Foundation

/// Maps `sessionId` → `SessionTurnUIController` with a small LRU cap.
@MainActor
final class SessionUICache {
    private static let maxCachedSessions = 8

    private var controllers: [String: SessionTurnUIController] = [:]
    private var lru: [String] = []

    weak var sharedBridge: ChatWebViewBridge? {
        didSet {
            for controller in controllers.values {
                controller.attach(bridge: sharedBridge)
            }
        }
    }

    func getOrCreate(sessionId: String) -> SessionTurnUIController {
        if let existing = controllers[sessionId] {
            touch(sessionId)
            existing.attach(bridge: sharedBridge)
            return existing
        }
        let controller = SessionTurnUIController(sessionId: sessionId, bridge: sharedBridge)
        controllers[sessionId] = controller
        touch(sessionId)
        evictIfNeeded()
        return controller
    }

    func tryGet(sessionId: String) -> SessionTurnUIController? {
        controllers[sessionId]
    }

    func remove(sessionId: String) {
        if let controller = controllers.removeValue(forKey: sessionId) {
            controller.release()
        }
        lru.removeAll { $0 == sessionId }
    }

    func setDisplayed(sessionId: String?) {
        for (id, controller) in controllers {
            controller.setDisplayed(id == sessionId)
        }
    }

    private func touch(_ sessionId: String) {
        lru.removeAll { $0 == sessionId }
        lru.insert(sessionId, at: 0)
    }

    private func evictIfNeeded() {
        while lru.count > Self.maxCachedSessions {
            guard let evict = lru.popLast() else { break }
            if let controller = controllers.removeValue(forKey: evict) {
                controller.release()
            }
        }
    }
}
