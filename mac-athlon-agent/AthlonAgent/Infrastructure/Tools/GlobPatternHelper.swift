import Foundation

enum GlobPatternHelper {
    static func expandBraces(_ pattern: String) -> [String] {
        guard let start = pattern.firstIndex(of: "{"),
              let end = pattern[start...].firstIndex(of: "}") else {
            return [pattern]
        }
        let prefix = String(pattern[..<start])
        let suffix = String(pattern[pattern.index(after: end)...])
        let alternatives = pattern[pattern.index(after: start)..<end]
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !alternatives.isEmpty else { return [pattern] }
        return alternatives.flatMap { expandBraces(prefix + $0 + suffix) }
    }

    static func enumerateMatches(
        rootDirectory: String,
        pattern: String,
        ignorePatterns: [String],
        maxResults: Int = 200
    ) -> [String] {
        let expanded = expandBraces(pattern)
        var results: [String] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: rootDirectory),
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let url as URL in enumerator {
            let fullPath = url.standardizedFileURL.path
            if WorkspacePathFilter.shouldIgnorePath(fullPath, directoryNames: ignorePatterns) {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            let relative = relativePath(from: rootDirectory, to: fullPath)
            if expanded.contains(where: { matchesGlob(relative, pattern: $0) || matchesGlob(url.lastPathComponent, pattern: $0) }) {
                results.append(fullPath)
                if results.count >= maxResults { break }
            }
        }
        return results
    }

    private static func relativePath(from root: String, to path: String) -> String {
        let rootURL = URL(fileURLWithPath: root).standardizedFileURL.path
        let pathURL = URL(fileURLWithPath: path).standardizedFileURL.path
        if pathURL.hasPrefix(rootURL + "/") {
            return String(pathURL.dropFirst(rootURL.count + 1))
        }
        return (path as NSString).lastPathComponent
    }

    /// Case-insensitive glob match; supports `*`, `?`, and `**` (crosses `/`, aligned with WPF FileSystemGlobbing).
    static func matchesGlob(_ text: String, pattern: String) -> Bool {
        let normalizedText = text.replacingOccurrences(of: "\\", with: "/")
        let normalizedPattern = pattern.replacingOccurrences(of: "\\", with: "/")
        guard let regex = try? NSRegularExpression(
            pattern: globPatternToRegex(normalizedPattern),
            options: [.caseInsensitive]
        ) else {
            return false
        }
        let range = NSRange(normalizedText.startIndex..., in: normalizedText)
        return regex.firstMatch(in: normalizedText, options: [], range: range) != nil
    }

    /// Converts a glob pattern to a regex. `**` matches zero or more characters including `/`.
    private static func globPatternToRegex(_ pattern: String) -> String {
        var regex = "^"
        var index = pattern.startIndex
        while index < pattern.endIndex {
            let character = pattern[index]
            switch character {
            case "*":
                let next = pattern.index(after: index)
                if next < pattern.endIndex, pattern[next] == "*" {
                    regex += ".*"
                    index = pattern.index(after: next)
                    if index < pattern.endIndex, pattern[index] == "/" {
                        index = pattern.index(after: index)
                    }
                } else {
                    regex += "[^/]*"
                    index = pattern.index(after: index)
                }
            case "?":
                regex += "[^/]"
                index = pattern.index(after: index)
            case ".", "+", "(", ")", "[", "]", "{", "}", "^", "$", "|":
                regex += "\\\(character)"
                index = pattern.index(after: index)
            default:
                if character == "\\" {
                    regex += "\\\\"
                } else {
                    regex.append(character)
                }
                index = pattern.index(after: index)
            }
        }
        return regex + "$"
    }
}
