import Foundation

nonisolated struct GlobFilesTool: AgentTool {
    let name = "glob_files"
    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Find files under the workspace matching a glob pattern (e.g. **/*.swift).",
            parameters: [
                "type": "object",
                "properties": [
                    "pattern": ["type": "string"] as [String: Any],
                    "path": ["type": "string", "description": "Optional subdirectory to search"] as [String: Any],
                ] as [String: Any],
                "required": ["pattern"],
            ]
        )
    }

    func invoke(arguments: String, context: AgentRunContext) async throws -> String {
        let args = try ToolJSON.object(from: arguments)
        guard let pattern = args["pattern"] as? String, !pattern.isEmpty else {
            throw AgentToolError.invalidArguments("pattern is required")
        }
        let sub = (args["path"] as? String) ?? "."
        let guard_ = WorkspaceGuard(workspaceRoot: context.workspaceRoot, ignorePatterns: context.ignorePatterns)
        let root = try guard_.resolve(sub)
        let fm = FileManager.default
        var matches: [String] = []

        guard let enumerator = fm.enumerator(atPath: root) else { return "[]" }
        var count = 0
        while let item = enumerator.nextObject() as? String {
            if guard_.isIgnored(relativePath: item) {
                enumerator.skipDescendants()
                continue
            }
            if GlobMatcher.matches(item, pattern: pattern) || GlobMatcher.matches((item as NSString).lastPathComponent, pattern: pattern) {
                matches.append(item)
                count += 1
                if count >= 2000 { break }
            }
        }
        matches.sort()
        let data = try JSONSerialization.data(withJSONObject: matches, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}

nonisolated enum GlobMatcher {
    static func matches(_ path: String, pattern: String) -> Bool {
        let nsPath = path as NSString
        // NSPredicate glob: convert ** to * for simple matching after normalizing.
        if pattern.contains("**") {
            let regexPattern = globToRegex(pattern)
            return path.range(of: regexPattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        return nsPath.pathMatchesPattern(pattern)
    }

    private static func globToRegex(_ pattern: String) -> String {
        var result = "^"
        var i = pattern.startIndex
        while i < pattern.endIndex {
            let ch = pattern[i]
            if ch == "*" {
                let next = pattern.index(after: i)
                if next < pattern.endIndex, pattern[next] == "*" {
                    result += ".*"
                    i = pattern.index(after: next)
                    if i < pattern.endIndex, pattern[i] == "/" { i = pattern.index(after: i) }
                    continue
                }
                result += "[^/]*"
                i = next
                continue
            }
            if ch == "?" {
                result += "[^/]"
                i = pattern.index(after: i)
                continue
            }
            if "\\.[]{}()+-^$|".contains(ch) {
                result.append("\\")
            }
            result.append(ch)
            i = pattern.index(after: i)
        }
        result += "$"
        return result
    }
}

private extension NSString {
    func pathMatchesPattern(_ pattern: String) -> Bool {
        let predicate = NSPredicate(format: "self LIKE %@", pattern)
        return predicate.evaluate(with: self as String)
            || predicate.evaluate(with: lastPathComponent)
    }
}
