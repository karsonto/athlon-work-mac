import Foundation

enum ComposerSlashResult: Equatable {
    /// Local command handled; do not send to agent.
    case handled(status: String)
    /// Text ready to send (possibly expanded).
    case send(String)
}

struct ComposerFileSuggestion: Identifiable, Hashable, Sendable {
    var id: String { path }
    var path: String
    var name: String
}

/// Basic slash-command expansion and `@` file mention stubs.
@MainActor
final class ComposerCoordinator {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Expand/handle slash commands before send.
    func processBeforeSend(_ raw: String) -> ComposerSlashResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else {
            return .send(raw)
        }

        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let command = parts.first.map(String.init)?.lowercased() ?? ""
        let argument = parts.count > 1 ? String(parts[1]) : ""

        switch command {
        case "/clear":
            return .handled(status: "cleared")
        case "/help":
            if argument.isEmpty {
                return .handled(status: """
                可用命令：
                /clear — 清空当前会话时间线显示
                /help — 显示帮助
                @文件名 — 提及工作区文件（发送时保留原文）
                """)
            }
            return .send(raw)
        default:
            return .send(raw)
        }
    }

    /// Detect `@` query at caret (or end of text) and suggest workspace files.
    func fileSuggestions(
        for composerText: String,
        workspaceRoot: String?,
        ignorePatterns: [String] = [],
        limit: Int = 12
    ) -> [ComposerFileSuggestion] {
        guard let query = activeAtQuery(in: composerText) else { return [] }
        guard let root = workspaceRoot, !root.isEmpty,
              fileManager.fileExists(atPath: root) else { return [] }

        let lowered = query.lowercased()
        var results: [ComposerFileSuggestion] = []
        let rootURL = URL(fileURLWithPath: root, isDirectory: true)
        let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let url = enumerator?.nextObject() as? URL {
            if results.count >= limit { break }
            let relative = url.path.replacingOccurrences(of: root.hasSuffix("/") ? root : root + "/", with: "")
            let name = url.lastPathComponent
            if shouldIgnore(relativePath: relative, patterns: ignorePatterns) {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator?.skipDescendants()
                }
                continue
            }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            if lowered.isEmpty
                || name.lowercased().contains(lowered)
                || relative.lowercased().contains(lowered) {
                results.append(ComposerFileSuggestion(path: relative, name: name))
            }
        }
        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Replace the active `@query` with `@path ` when user accepts a suggestion.
    func acceptSuggestion(
        text: String,
        suggestion: ComposerFileSuggestion
    ) -> String {
        guard let range = activeAtRange(in: text) else {
            return text + "@\(suggestion.path) "
        }
        var result = text
        let replacement = "@\(suggestion.path) "
        result.replaceSubrange(range, with: replacement)
        return result
    }

    // MARK: - Internals

    private func activeAtQuery(in text: String) -> String? {
        guard let range = activeAtRange(in: text) else { return nil }
        let token = String(text[range])
        return String(token.dropFirst()) // drop '@'
    }

    private func activeAtRange(in text: String) -> Range<String.Index>? {
        guard let atIndex = text.lastIndex(of: "@") else { return nil }
        let after = text.index(after: atIndex)
        let tail = text[after...]
        if tail.contains(where: { $0.isWhitespace || $0 == "\n" }) {
            return nil
        }
        // Require start-of-text or whitespace before '@'.
        if atIndex > text.startIndex {
            let before = text[text.index(before: atIndex)]
            if !before.isWhitespace && before != "\n" {
                return nil
            }
        }
        return atIndex..<text.endIndex
    }

    private func shouldIgnore(relativePath: String, patterns: [String]) -> Bool {
        let parts = relativePath.split(separator: "/").map(String.init)
        for part in parts {
            for pattern in patterns {
                if part.caseInsensitiveCompare(pattern) == .orderedSame {
                    return true
                }
                if pattern.hasPrefix("*.") {
                    let ext = String(pattern.dropFirst(2))
                    if part.lowercased().hasSuffix("." + ext.lowercased()) {
                        return true
                    }
                }
            }
        }
        return false
    }
}
