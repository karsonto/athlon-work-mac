import Foundation

struct SessionIndexEntry: Codable, Equatable {
    let id: String
    let title: String
    let path: String
    let updatedAt: Date
}

enum SessionWriteLock {
    private static var locks: [String: NSLock] = [:]
    private static let registryLock = NSLock()

    static func withLock<T>(_ sessionId: String, _ body: () throws -> T) rethrows -> T {
        let lock = lock(for: sessionId)
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private static func lock(for sessionId: String) -> NSLock {
        registryLock.lock()
        defer { registryLock.unlock() }
        if locks[sessionId] == nil {
            locks[sessionId] = NSLock()
        }
        return locks[sessionId]!
    }
}

enum SessionMarkdownWriter {
    static func writeConversation(_ session: AgentSession) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = [
            "# \(session.title)",
            "",
            "- Session: `\(session.id)`",
            "- Created: `\(formatter.string(from: session.createdAt))`",
            "- Updated: `\(formatter.string(from: session.updatedAt))`",
            ""
        ]

        for message in session.messages {
            let roleLabel = message.role == .compaction ? "Compaction" : message.role.rawValue
            lines.append("## \(roleLabel) - \(formatter.string(from: message.createdAt))")
            lines.append("")
            if let attachments = message.imageAttachments, !attachments.isEmpty {
                let names = attachments.map(\.fileName).joined(separator: ", ")
                lines.append("附图: \(names)")
                lines.append("")
            }
            lines.append(message.content)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    static func writeSummary(_ summary: ContextSummary) -> String {
        let formatter = ISO8601DateFormatter()
        return """
        # Context Summary

        - Session: `\(summary.sessionId)`
        - Created: `\(formatter.string(from: summary.createdAt))`
        - Original messages: `\(summary.originalMessageCount)`

        \(summary.content)

        """
    }
}

/// File-backed persistence aligned with WPF `FileStorageService` (~/.athlon-agent).
final class FileStorageService: CompactionStorageProviding, @unchecked Sendable {
    private let paths: AppPathProvider
    private let indexLock = NSLock()

    init(paths: AppPathProvider = .shared) {
        self.paths = paths
        paths.ensureCreated()
    }

    var rootPath: String { paths.rootPath }

    // MARK: - Session persistence

    func saveSession(_ session: AgentSession) throws {
        try saveSessionSync(session)
    }

    func saveSession(_ session: AgentSession) async throws {
        try saveSessionSync(session)
    }

    func saveSessionSync(_ session: AgentSession) throws {
        try SessionWriteLock.withLock(session.id) {
            ensureSessionDirectories(session.id)
            let sessionDir = paths.sessionDirectory(session.id)

            let sessionPath = (sessionDir as NSString).appendingPathComponent("session.json")
            try writeJSON(session, to: sessionPath)

            let markdownPath = (sessionDir as NSString).appendingPathComponent("conversation.md")
            try writeText(SessionMarkdownWriter.writeConversation(session), to: markdownPath)

            syncConversationJsonl(sessionId: session.id, messages: session.messages)
        }

        try refreshIndex()
    }

    func loadSession(_ sessionId: String) throws -> AgentSession? {
        let sessionPath = (paths.sessionDirectory(sessionId) as NSString).appendingPathComponent("session.json")
        guard FileManager.default.fileExists(atPath: sessionPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: sessionPath)) else {
            return nil
        }

        var session = try JsonCodec.decode(AgentSession.self, from: data)
        if session.messages.isEmpty {
            session.messages = try loadConversationDisplay(sessionId)
        }
        return session
    }

    func loadAllSessions() throws -> [AgentSession] {
        let entries = try listSessionIndexEntries()
        var sessions: [AgentSession] = []
        for entry in entries {
            if let session = try loadSession(entry.id) {
                sessions.append(session)
            }
        }
        return sessions
    }

    func deleteSession(_ sessionId: String) throws {
        let sessionDir = paths.sessionDirectory(sessionId)
        if FileManager.default.fileExists(atPath: sessionDir) {
            try FileManager.default.removeItem(atPath: sessionDir)
        }
        try refreshIndex()
    }

    func appendConversationMessageSync(sessionId: String, message: ChatMessage) throws {
        try SessionWriteLock.withLock(sessionId) {
            ensureSessionDirectories(sessionId)
            let path = conversationDisplayPath(sessionId)
            let line = try JsonCodec.encodeLine(message)
            try appendLine(line, to: path)
        }
    }

    func appendConversationMessage(sessionId: String, message: ChatMessage) async throws {
        try appendConversationMessageSync(sessionId: sessionId, message: message)
    }

    func loadConversationDisplay(_ sessionId: String) throws -> [ChatMessage] {
        let path = conversationDisplayPath(sessionId)
        guard FileManager.default.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return []
        }

        var byId: [String: ChatMessage] = [:]
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let message = try? JsonCodec.decode(ChatMessage.self, from: data) else {
                continue
            }
            byId[message.id] = message
        }

        return byId.values.sorted { $0.createdAt < $1.createdAt }
    }

    func clearConversationDisplay(_ sessionId: String) throws {
        try SessionWriteLock.withLock(sessionId) {
            let path = conversationDisplayPath(sessionId)
            if FileManager.default.fileExists(atPath: path) {
                try writeText("", to: path)
            }
        }
    }

    func appendToolCallLog(
        sessionId: String,
        toolCallId: String,
        toolName: String,
        arguments: [String: String],
        succeeded: Bool,
        summary: String,
        content: String?,
        error: String?,
        durationMs: Int64
    ) async throws {
        try appendToolCallLogSync(
            sessionId: sessionId,
            toolCallId: toolCallId,
            toolName: toolName,
            arguments: arguments,
            succeeded: succeeded,
            summary: summary,
            content: content,
            error: error,
            durationMs: durationMs
        )
    }

    func appendToolCallLogSync(
        sessionId: String,
        toolCallId: String,
        toolName: String,
        arguments: [String: String],
        succeeded: Bool,
        summary: String,
        content: String?,
        error: String?,
        durationMs: Int64
    ) throws {
        guard !sessionId.isEmpty else { return }
        try SessionWriteLock.withLock(sessionId) {
            ensureSessionDirectories(sessionId)
            let toolCallsDir = (paths.sessionDirectory(sessionId) as NSString).appendingPathComponent("tool-calls")
            try FileManager.default.createDirectory(atPath: toolCallsDir, withIntermediateDirectories: true)
            let path = (toolCallsDir as NSString).appendingPathComponent("calls.jsonl")
            let payload: [String: Any] = [
                "time": ISO8601DateFormatter().string(from: Date()),
                "toolCallId": toolCallId,
                "toolName": toolName,
                "arguments": arguments,
                "succeeded": succeeded,
                "summary": summary,
                "content": content ?? "",
                "error": error ?? "",
                "durationMs": durationMs
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            guard let line = String(data: data, encoding: .utf8) else { return }
            try appendLine(line, to: path)
        }
    }

    // MARK: - CompactionStorageProviding

    func saveTranscript(sessionId: String, messages: [ChatMessage]) async throws -> String {
        try SessionWriteLock.withLock(sessionId) {
            ensureSessionDirectories(sessionId)
            let transcriptDir = (paths.sessionDirectory(sessionId) as NSString).appendingPathComponent("transcripts")
            try FileManager.default.createDirectory(atPath: transcriptDir, withIntermediateDirectories: true)

            let timestamp = Int(Date().timeIntervalSince1970)
            let path = (transcriptDir as NSString).appendingPathComponent("transcript_\(timestamp).jsonl")
            let body = try messages.map { try JsonCodec.encodeLine($0) }.joined(separator: "\n") + "\n"
            try writeText(body, to: path)
            return path
        }
    }

    func saveContextSummary(_ summary: ContextSummary) async throws {
        let summaryDir = (paths.sessionDirectory(summary.sessionId) as NSString).appendingPathComponent("summaries")
        try FileManager.default.createDirectory(atPath: summaryDir, withIntermediateDirectories: true)
        let path = (summaryDir as NSString).appendingPathComponent("\(summary.id).md")
        try writeText(SessionMarkdownWriter.writeSummary(summary), to: path)
    }

    func saveEvictedToolResult(sessionId: String, toolCallId: String, content: String) async throws -> String {
        try SessionWriteLock.withLock(sessionId) {
            let evictedDir = (paths.sessionDirectory(sessionId) as NSString).appendingPathComponent("evicted")
            try FileManager.default.createDirectory(atPath: evictedDir, withIntermediateDirectories: true)
            let path = (evictedDir as NSString).appendingPathComponent("\(toolCallId).txt")
            try writeText(content, to: path)
            return path
        }
    }

    // MARK: - Index

    func refreshIndex() throws {
        indexLock.lock()
        defer { indexLock.unlock() }

        let entries = try listSessionIndexEntries()
        let indexPath = (paths.sessionsPath as NSString).appendingPathComponent("index.json")
        try writeJSON(entries, to: indexPath)
    }

    private func listSessionIndexEntries() throws -> [SessionIndexEntry] {
        guard FileManager.default.fileExists(atPath: paths.sessionsPath) else {
            return []
        }

        var result: [String: SessionIndexEntry] = [:]
        let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: paths.sessionsPath),
            includingPropertiesForKeys: nil
        )

        while let url = enumerator?.nextObject() as? URL {
            guard url.lastPathComponent == "session.json" else { continue }
            guard let data = try? Data(contentsOf: url),
                  let session = try? JsonCodec.decode(AgentSession.self, from: data) else {
                continue
            }

            let entry = SessionIndexEntry(
                id: session.id,
                title: session.title,
                path: url.deletingLastPathComponent().path,
                updatedAt: session.updatedAt
            )

            if let existing = result[session.id] {
                if session.updatedAt > existing.updatedAt {
                    result[session.id] = entry
                }
            } else {
                result[session.id] = entry
            }
        }

        return result.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Helpers

    private func conversationDisplayPath(_ sessionId: String) -> String {
        (paths.sessionDirectory(sessionId) as NSString).appendingPathComponent("conversation.jsonl")
    }

    private func ensureSessionDirectories(_ sessionId: String) {
        let sessionDir = paths.sessionDirectory(sessionId)
        try? FileManager.default.createDirectory(atPath: sessionDir, withIntermediateDirectories: true)
        for sub in ["tool-calls", "summaries", "transcripts", "evicted", "http"] {
            try? FileManager.default.createDirectory(
                atPath: (sessionDir as NSString).appendingPathComponent(sub),
                withIntermediateDirectories: true
            )
        }
    }

    private func syncConversationJsonl(sessionId: String, messages: [ChatMessage]) {
        let path = conversationDisplayPath(sessionId)
        let body = (try? messages.map { try JsonCodec.encodeLine($0) }.joined(separator: "\n")) ?? ""
        let text = body.isEmpty ? "" : body + "\n"
        try? writeText(text, to: path)
    }

    private func writeJSON<T: Encodable>(_ value: T, to path: String) throws {
        let data = try JsonCodec.encode(value)
        try writeAtomic(path: path, data: data)
    }

    private func writeText(_ text: String, to path: String) throws {
        guard let data = text.data(using: .utf8) else { return }
        try writeAtomic(path: path, data: data)
    }

    private func appendLine(_ line: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = (line + "\n").data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } else {
            try writeText(line + "\n", to: path)
        }
    }

    private func writeAtomic(path: String, data: Data) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let tempURL = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).tmp")
        try data.write(to: tempURL, options: .atomic)
        if FileManager.default.fileExists(atPath: path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: url)
        }
    }
}
