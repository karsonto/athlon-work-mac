import Foundation

nonisolated enum FileStorageError: Error, LocalizedError {
    case encodingFailed
    case decodingFailed(String)
    case io(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "Failed to encode JSON"
        case .decodingFailed(let detail): return "Failed to decode JSON: \(detail)"
        case .io(let detail): return detail
        }
    }
}

/// File-backed settings + session storage aligned with Windows `FileStorageService`.
nonisolated final class FileStorageService: @unchecked Sendable {
    private let paths: AppPathProviding
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let compactEncoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()

    init(paths: AppPathProviding = AppPathProvider()) {
        self.paths = paths
        self.fileManager = .default
        self.encoder = JSONEncoder.athlonCamelCase
        self.compactEncoder = JSONEncoder.athlonCamelCaseCompact
        self.decoder = JSONDecoder.athlon
    }

    var rootPath: String { paths.rootPath }
    var settingsPath: String {
        (paths.configPath as NSString).appendingPathComponent("settings.json")
    }

    func ensureDirectories() throws {
        try paths.ensureCreated()
    }

    // MARK: - Settings

    func saveSettings(_ settings: AppSettings) throws {
        try ensureDirectories()
        var copy = settings
        copy.model.legacyApiKeyCredentialName = nil
        let data = try encoder.encode(copy)
        try atomicWrite(data, to: settingsPath)
    }

    func loadSettings() throws -> AppSettings {
        try ensureDirectories()
        guard fileManager.fileExists(atPath: settingsPath) else {
            let defaults = AppSettings()
            try saveSettings(defaults)
            return defaults
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
        do {
            return try decoder.decode(AppSettings.self, from: data)
        } catch {
            throw FileStorageError.decodingFailed(error.localizedDescription)
        }
    }

    // MARK: - Sessions

    func sessionDirectory(for sessionId: String) -> String {
        if let nested = SessionDirectoryLayout.tryFindNestedSubAgentDirectory(
            sessionsPath: paths.sessionsPath,
            subSessionId: sessionId
        ) {
            return nested
        }
        return SessionDirectoryLayout.sessionDirectory(
            sessionsPath: paths.sessionsPath,
            sessionId: sessionId
        )
    }

    func saveSession(_ session: AgentSession) throws {
        lock.lock()
        defer { lock.unlock() }
        let dir = sessionDirectory(for: session.id)
        try SessionDirectoryLayout.ensureSessionLogDirectories(at: dir)
        var persisted = session
        // Keep session.json lighter; conversation lives in conversation.jsonl.
        persisted.messages = nil
        let data = try encoder.encode(persisted)
        let path = (dir as NSString).appendingPathComponent(SessionDirectoryLayout.sessionFileName)
        try atomicWrite(data, to: path)
    }

    func loadSession(id: String) throws -> AgentSession? {
        let dir = sessionDirectory(for: id)
        let path = (dir as NSString).appendingPathComponent(SessionDirectoryLayout.sessionFileName)
        guard fileManager.fileExists(atPath: path) else { return nil }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        var session = try decoder.decode(AgentSession.self, from: data)
        let messages = try loadConversationMessages(sessionId: id)
        session.messages = messages
        return session
    }

    func appendConversationMessage(sessionId: String, message: ChatMessage) throws {
        lock.lock()
        defer { lock.unlock() }
        let dir = sessionDirectory(for: sessionId)
        try SessionDirectoryLayout.ensureSessionLogDirectories(at: dir)
        let path = (dir as NSString).appendingPathComponent(SessionDirectoryLayout.conversationFileName)
        let data = try compactEncoder.encode(message)
        guard var line = String(data: data, encoding: .utf8) else {
            throw FileStorageError.encodingFailed
        }
        line.append("\n")
        if !fileManager.fileExists(atPath: path) {
            fileManager.createFile(atPath: path, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: path) else {
            throw FileStorageError.io("Unable to open \(path)")
        }
        defer { try? handle.close() }
        try handle.seekToEnd()
        if let bytes = line.data(using: .utf8) {
            try handle.write(contentsOf: bytes)
        }
    }

    func loadConversationMessages(sessionId: String) throws -> [ChatMessage] {
        let dir = sessionDirectory(for: sessionId)
        let path = (dir as NSString).appendingPathComponent(SessionDirectoryLayout.conversationFileName)
        guard fileManager.fileExists(atPath: path) else { return [] }
        let text = try String(contentsOfFile: path, encoding: .utf8)
        var messages: [ChatMessage] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
            if let message = try? decoder.decode(ChatMessage.self, from: data) {
                messages.append(message)
            }
        }
        return messages
    }

    func listSessions() throws -> [SessionIndexEntry] {
        try ensureDirectories()
        let nested = SessionDirectoryLayout.collectNestedSubAgentSessionIds(sessionsPath: paths.sessionsPath)
        let jsonPaths = SessionDirectoryLayout.enumerateTopLevelSessionJsonPaths(sessionsPath: paths.sessionsPath)
        var entries: [SessionIndexEntry] = []
        for jsonPath in jsonPaths {
            let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
            guard let session = try? decoder.decode(AgentSession.self, from: data) else { continue }
            let dir = (jsonPath as NSString).deletingLastPathComponent
            let entry = SessionIndexEntry(
                id: session.id,
                title: session.title,
                path: dir,
                updatedAt: session.updatedAt,
                messageCount: nil,
                activeWorkspace: session.activeWorkspace
            )
            if SessionDirectoryLayout.isEligibleForSessionMenu(
                sessionsPath: paths.sessionsPath,
                entry: entry,
                nestedSubAgentSessionIds: nested
            ) {
                entries.append(entry)
            }
        }
        return entries.sorted { $0.updatedAt > $1.updatedAt }
    }

    func deleteSession(id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let dir = sessionDirectory(for: id)
        if fileManager.fileExists(atPath: dir) {
            try fileManager.removeItem(atPath: dir)
        }
    }

    // MARK: - Helpers

    private func atomicWrite(_ data: Data, to path: String) throws {
        let directory = (path as NSString).deletingLastPathComponent
        try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let temp = (directory as NSString).appendingPathComponent(".\(UUID().uuidString).tmp")
        try data.write(to: URL(fileURLWithPath: temp), options: .atomic)
        if fileManager.fileExists(atPath: path) {
            _ = try fileManager.replaceItemAt(URL(fileURLWithPath: path), withItemAt: URL(fileURLWithPath: temp))
        } else {
            try fileManager.moveItem(atPath: temp, toPath: path)
        }
    }
}
