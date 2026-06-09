import Foundation

/// Chat UI timeline ordering for session hydrate/reconcile (aligned with WPF `ChatTimelineOrder`).
enum ChatTimelineOrder {
    /// Sorts persisted messages by `createdAt` for display rebuild. Live streaming uses append order instead.
    static func orderForDisplay(_ messages: [ChatMessage], pinToEndMessageId: String? = nil) -> [ChatMessage] {
        guard messages.count > 1 else { return messages }
        var ordered = messages.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.createdAt != rhs.element.createdAt {
                    return lhs.element.createdAt < rhs.element.createdAt
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)

        guard let pinId = pinToEndMessageId,
              let index = ordered.firstIndex(where: { $0.id == pinId }) else {
            return ordered
        }
        let pinned = ordered.remove(at: index)
        ordered.append(pinned)
        return ordered
    }
}
