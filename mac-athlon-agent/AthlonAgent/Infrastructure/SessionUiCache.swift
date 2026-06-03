import Foundation

struct SessionUiState: Equatable {
    var reasoningCollapsed: Bool = false
    var scrollAnchorMessageId: String?
}

/// Per-session UI state preserved when switching sessions (aligned with WPF `SessionUiCache`).
final class SessionUiCache {
    private var states: [String: SessionUiState] = [:]

    func get(_ sessionId: String) -> SessionUiState {
        states[sessionId] ?? SessionUiState()
    }

    func set(_ sessionId: String, state: SessionUiState) {
        states[sessionId] = state
    }

    func remove(_ sessionId: String) {
        states.removeValue(forKey: sessionId)
    }
}
