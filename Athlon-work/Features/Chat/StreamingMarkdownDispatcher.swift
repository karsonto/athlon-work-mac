import Foundation

/// Batches assistant text tokens and emits `STATIC_ASSISTANT_HTML` for the WebView (Windows parity).
@MainActor
final class StreamingMarkdownDispatcher {
    private var buffers: [String: String] = [:]
    private var flushTasks: [String: Task<Void, Never>] = [:]
    private weak var bridge: ChatWebViewBridge?

    func attach(bridge: ChatWebViewBridge?) {
        self.bridge = bridge
    }

    func reset() {
        for task in flushTasks.values {
            task.cancel()
        }
        flushTasks.removeAll()
        buffers.removeAll()
    }

    func append(messageId: String, delta: String) {
        guard !delta.isEmpty else { return }
        buffers[messageId, default: ""] += delta
        scheduleFlush(messageId: messageId)
    }

    func finish(messageId: String) {
        flushTasks[messageId]?.cancel()
        flushTasks.removeValue(forKey: messageId)
        flush(messageId: messageId, streaming: false)
        buffers.removeValue(forKey: messageId)
    }

    private func scheduleFlush(messageId: String) {
        guard flushTasks[messageId] == nil else { return }
        flushTasks[messageId] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            flushTasks.removeValue(forKey: messageId)
            flush(messageId: messageId, streaming: true)
            if buffers[messageId] != nil {
                scheduleFlush(messageId: messageId)
            }
        }
    }

    private func flush(messageId: String, streaming: Bool) {
        guard let markdown = buffers[messageId], !markdown.isEmpty, let bridge else { return }
        let json = ChatEventSerializer.serializeStreamingAssistantHTML(
            messageId: messageId,
            markdown: markdown,
            streaming: streaming
        )
        bridge.dispatchJSON(json)
    }
}
