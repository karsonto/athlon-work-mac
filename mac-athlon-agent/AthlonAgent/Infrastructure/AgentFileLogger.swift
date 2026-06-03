import Foundation

/// Append-only file logger under `~/.athlon-agent/logs/agent.log`.
enum AgentFileLogger {
    private static let lock = NSLock()

    static func log(_ message: String, category: String = "App") {
        lock.lock()
        defer { lock.unlock() }

        AppPathProvider.shared.ensureCreated()
        let path = (AppPathProvider.shared.logsPath as NSString).appendingPathComponent("agent.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [\(category)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: path) {
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }

    static func logModelCompletion(
        model: String,
        stream: Bool,
        contentLength: Int,
        reasoningLength: Int,
        toolCallCount: Int,
        usedNonStreamFallback: Bool = false,
        contentPreview: String = ""
    ) {
        let preview = contentPreview
            .replacingOccurrences(of: "\n", with: "\\n")
            .prefix(120)
        log(
            "model=\(model) stream=\(stream) contentLen=\(contentLength) reasoningLen=\(reasoningLength) tools=\(toolCallCount) fallback=\(usedNonStreamFallback) preview=\"\(preview)\"",
            category: "Model"
        )
    }

    static func logUIAssistant(
        sessionId: String,
        messageId: String,
        contentLength: Int,
        reasoningLength: Int,
        isStreaming: Bool,
        source: String
    ) {
        log(
            "session=\(sessionId.prefix(8)) msg=\(messageId.prefix(8)) contentLen=\(contentLength) reasoningLen=\(reasoningLength) streaming=\(isStreaming) source=\(source)",
            category: "UI"
        )
    }
}
