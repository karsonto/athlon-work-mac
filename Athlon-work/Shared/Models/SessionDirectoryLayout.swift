import Foundation

/// On-disk layout helpers for `~/.athlon-agent/sessions`.
///
/// Top-level chats live at `sessions/{id}/`.
/// Sub-agent transcripts live under `sessions/{parent}/subagents/default/{id}/`.
nonisolated enum SessionDirectoryLayout {
    static let sessionsFolderName = "sessions"
    static let subAgentsFolder = "subagents"
    static let subAgentKind = "default"

    static let sessionFileName = "session.json"
    static let conversationFileName = "conversation.jsonl"
    static let indexFileName = "index.json"
    static let toolCallsFolderName = "tool-calls"
    static let toolCallsLogFileName = "calls.jsonl"
    static let attemptsFileName = "attempts.jsonl"
    static let summariesFolderName = "summaries"
    static let transcriptsFolderName = "transcripts"
    static let evictedFolderName = "evicted"
    static let httpFolderName = "http"

    static func sessionDirectory(sessionsPath: String, sessionId: String) -> String {
        (sessionsPath as NSString).appendingPathComponent(sessionId)
    }

    static func sessionJsonPath(sessionsPath: String, sessionId: String) -> String {
        (sessionDirectory(sessionsPath: sessionsPath, sessionId: sessionId) as NSString)
            .appendingPathComponent(sessionFileName)
    }

    static func conversationJsonlPath(sessionsPath: String, sessionId: String) -> String {
        (sessionDirectory(sessionsPath: sessionsPath, sessionId: sessionId) as NSString)
            .appendingPathComponent(conversationFileName)
    }

    static func subAgentDirectory(
        sessionsPath: String,
        parentSessionId: String,
        subSessionId: String,
        kind: String = subAgentKind
    ) -> String {
        let parent = sessionDirectory(sessionsPath: sessionsPath, sessionId: parentSessionId) as NSString
        let subAgents = parent.appendingPathComponent(subAgentsFolder) as NSString
        let kindDir = subAgents.appendingPathComponent(kind) as NSString
        return kindDir.appendingPathComponent(subSessionId)
    }

    static func isTopLevelSessionDirectory(sessionsPath: String, sessionDirectory: String) -> Bool {
        let normalizedRoot = (sessionsPath as NSString).standardizingPath
        let normalizedDir = (sessionDirectory as NSString).standardizingPath
        let parent = (normalizedDir as NSString).deletingLastPathComponent
        return parent.caseInsensitiveCompare(normalizedRoot) == .orderedSame
    }

    static func collectNestedSubAgentSessionIds(sessionsPath: String) -> Set<String> {
        var ids = Set<String>()
        let fm = FileManager.default
        guard let parentDirs = try? fm.contentsOfDirectory(atPath: sessionsPath) else {
            return ids
        }
        for parentName in parentDirs {
            let parentDir = (sessionsPath as NSString).appendingPathComponent(parentName) as NSString
            let subAgentsRoot = (parentDir.appendingPathComponent(subAgentsFolder) as NSString)
                .appendingPathComponent(subAgentKind)
            guard let nested = try? fm.contentsOfDirectory(atPath: subAgentsRoot) else { continue }
            for name in nested where !name.isEmpty {
                ids.insert(name)
            }
        }
        return ids
    }

    static func tryFindNestedSubAgentDirectory(sessionsPath: String, subSessionId: String) -> String? {
        let fm = FileManager.default
        guard let parentDirs = try? fm.contentsOfDirectory(atPath: sessionsPath) else {
            return nil
        }
        for parentName in parentDirs {
            let nested = subAgentDirectory(
                sessionsPath: sessionsPath,
                parentSessionId: parentName,
                subSessionId: subSessionId
            )
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: nested, isDirectory: &isDir), isDir.boolValue {
                return nested
            }
        }
        return nil
    }

    static func isNestedSubAgentSessionId(sessionsPath: String, sessionId: String) -> Bool {
        tryFindNestedSubAgentDirectory(sessionsPath: sessionsPath, subSessionId: sessionId) != nil
    }

    static func enumerateTopLevelSessionJsonPaths(sessionsPath: String) -> [String] {
        let fm = FileManager.default
        guard let sessionDirs = try? fm.contentsOfDirectory(atPath: sessionsPath) else {
            return []
        }
        return sessionDirs.compactMap { name in
            let json = sessionJsonPath(sessionsPath: sessionsPath, sessionId: name)
            return fm.fileExists(atPath: json) ? json : nil
        }
    }

    static func isEligibleForSessionMenu(
        sessionsPath: String,
        entry: SessionIndexEntry,
        nestedSubAgentSessionIds: Set<String>? = nil
    ) -> Bool {
        let nested = nestedSubAgentSessionIds ?? collectNestedSubAgentSessionIds(sessionsPath: sessionsPath)
        return isTopLevelSessionDirectory(sessionsPath: sessionsPath, sessionDirectory: entry.path)
            && !nested.contains(entry.id)
    }

    static func ensureSessionLogDirectories(at sessionDir: String) throws {
        let fm = FileManager.default
        let subfolders = [
            toolCallsFolderName,
            summariesFolderName,
            transcriptsFolderName,
            evictedFolderName,
            httpFolderName,
        ]
        try fm.createDirectory(atPath: sessionDir, withIntermediateDirectories: true)
        for name in subfolders {
            try fm.createDirectory(
                atPath: (sessionDir as NSString).appendingPathComponent(name),
                withIntermediateDirectories: true
            )
        }
    }
}
