import Foundation
import CryptoKit

/// Long-term memory under `memory/projects/{hash}/` with MEMORY.md + daily notes.
nonisolated final class FileLongTermMemory: @unchecked Sendable {
    private let paths: AppPathProviding
    private let fileManager: FileManager

    init(paths: AppPathProviding = AppPathProvider(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    func projectHash(for workspaceRoot: String) -> String {
        let normalized = (workspaceRoot as NSString).standardizingPath.lowercased()
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    func projectDirectory(workspaceRoot: String, settings: MemorySettings) -> String {
        let root = (paths.rootPath as NSString).appendingPathComponent(settings.memoryDirName)
        let projects = (root as NSString).appendingPathComponent("projects")
        return (projects as NSString).appendingPathComponent(projectHash(for: workspaceRoot))
    }

    func curatedPath(workspaceRoot: String, settings: MemorySettings) -> String {
        (projectDirectory(workspaceRoot: workspaceRoot, settings: settings) as NSString)
            .appendingPathComponent(settings.curatedFileName)
    }

    func dailyNotesDirectory(workspaceRoot: String, settings: MemorySettings) -> String {
        (projectDirectory(workspaceRoot: workspaceRoot, settings: settings) as NSString)
            .appendingPathComponent("daily")
    }

    func ensureReady(workspaceRoot: String, settings: MemorySettings) throws {
        try paths.ensureCreated()
        let projectDir = projectDirectory(workspaceRoot: workspaceRoot, settings: settings)
        let daily = dailyNotesDirectory(workspaceRoot: workspaceRoot, settings: settings)
        try fileManager.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(atPath: daily, withIntermediateDirectories: true)
        let curated = curatedPath(workspaceRoot: workspaceRoot, settings: settings)
        if !fileManager.fileExists(atPath: curated) {
            try "# MEMORY\n\n".write(toFile: curated, atomically: true, encoding: .utf8)
        }
    }

    func appendTurnNote(
        workspaceRoot: String,
        settings: MemorySettings,
        sessionId: String,
        userSnippet: String,
        assistantSnippet: String
    ) throws {
        try ensureReady(workspaceRoot: workspaceRoot, settings: settings)
        let stamp = ISO8601DateFormatter.athlon.string(from: Date())
        let day = dayStamp(from: Date())
        let dailyFile = (dailyNotesDirectory(workspaceRoot: workspaceRoot, settings: settings) as NSString)
            .appendingPathComponent("\(day).md")

        let note = """

        ## \(stamp) · session \(sessionId.prefix(8))
        - User: \(clamp(userSnippet, 240))
        - Assistant: \(clamp(assistantSnippet, 480))

        """

        try append(note, to: curatedPath(workspaceRoot: workspaceRoot, settings: settings))
        if !fileManager.fileExists(atPath: dailyFile) {
            try "# Daily \(day)\n".write(toFile: dailyFile, atomically: true, encoding: .utf8)
        }
        try append(note, to: dailyFile)
        try pruneDailyNotes(workspaceRoot: workspaceRoot, settings: settings)
    }

    func search(
        workspaceRoot: String,
        settings: MemorySettings,
        query: String,
        maxHits: Int = 8
    ) throws -> [(path: String, snippet: String)] {
        try ensureReady(workspaceRoot: workspaceRoot, settings: settings)
        let tokens = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return [] }

        var files: [String] = [curatedPath(workspaceRoot: workspaceRoot, settings: settings)]
        let dailyDir = dailyNotesDirectory(workspaceRoot: workspaceRoot, settings: settings)
        if let names = try? fileManager.contentsOfDirectory(atPath: dailyDir) {
            files.append(contentsOf: names.sorted().reversed().prefix(30).map {
                (dailyDir as NSString).appendingPathComponent($0)
            })
        }

        var hits: [(String, String)] = []
        for path in files {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let lower = text.lowercased()
            let score = tokens.reduce(0) { $0 + (lower.contains($1) ? 1 : 0) }
            guard score > 0 else { continue }
            let snippet = extractSnippet(text: text, tokens: tokens)
            hits.append((path, snippet))
            if hits.count >= maxHits { break }
        }
        return hits
    }

    func get(path: String, maxChars: Int = 8_000) throws -> String {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        if text.count <= maxChars { return text }
        return String(text.prefix(maxChars)) + "\n…(truncated)"
    }

    // MARK: - Helpers

    private func append(_ text: String, to path: String) throws {
        if !fileManager.fileExists(atPath: path) {
            try text.write(toFile: path, atomically: true, encoding: .utf8)
            return
        }
        guard let handle = FileHandle(forWritingAtPath: path) else {
            throw FileStorageError.io("Cannot open \(path)")
        }
        defer { try? handle.close() }
        try handle.seekToEnd()
        if let data = text.data(using: .utf8) {
            try handle.write(contentsOf: data)
        }
    }

    private func pruneDailyNotes(workspaceRoot: String, settings: MemorySettings) throws {
        let dailyDir = dailyNotesDirectory(workspaceRoot: workspaceRoot, settings: settings)
        guard let names = try? fileManager.contentsOfDirectory(atPath: dailyDir) else { return }
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -max(1, settings.dailyFileRetentionDays),
            to: Date()
        ) ?? Date.distantPast
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        for name in names where name.hasSuffix(".md") {
            let day = String(name.dropLast(3))
            guard let date = formatter.date(from: day), date < cutoff else { continue }
            try? fileManager.removeItem(atPath: (dailyDir as NSString).appendingPathComponent(name))
        }
    }

    private func dayStamp(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func clamp(_ text: String, _ max: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        if trimmed.count <= max { return trimmed }
        return String(trimmed.prefix(max)) + "…"
    }

    private func extractSnippet(text: String, tokens: [String]) -> String {
        let lower = text.lowercased()
        guard let token = tokens.first, let range = lower.range(of: token) else {
            return String(text.prefix(200))
        }
        let start = text.index(range.lowerBound, offsetBy: -60, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(start, offsetBy: 240, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[start..<end]).replacingOccurrences(of: "\n", with: " ")
    }
}
