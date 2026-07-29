import Foundation

nonisolated struct GrepFilesTool: AgentTool {
    let name = "grep_files"
    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Search file contents under the workspace for a regex/literal pattern.",
            parameters: [
                "type": "object",
                "properties": [
                    "pattern": ["type": "string"] as [String: Any],
                    "path": ["type": "string"] as [String: Any],
                    "glob": ["type": "string"] as [String: Any],
                    "case_insensitive": ["type": "boolean"] as [String: Any],
                    "max_matches": ["type": "integer"] as [String: Any],
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
        let glob = args["glob"] as? String
        let caseInsensitive = (args["case_insensitive"] as? Bool) ?? true
        let maxMatches = min(500, max(1, (args["max_matches"] as? Int) ?? 100))

        var options: NSRegularExpression.Options = []
        if caseInsensitive { options.insert(.caseInsensitive) }
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            throw AgentToolError.invalidArguments("Invalid regex: \(error.localizedDescription)")
        }

        let guard_ = WorkspaceGuard(workspaceRoot: context.workspaceRoot, ignorePatterns: context.ignorePatterns)
        let root = try guard_.resolve(sub)
        let fm = FileManager.default
        var hits: [String] = []

        guard let enumerator = fm.enumerator(atPath: root) else { return "(no matches)" }
        while let item = enumerator.nextObject() as? String {
            if guard_.isIgnored(relativePath: item) {
                enumerator.skipDescendants()
                continue
            }
            if let glob, !GlobMatcher.matches(item, pattern: glob) {
                continue
            }
            let full = (root as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue else { continue }
            guard let text = try? String(contentsOfFile: full, encoding: .utf8) else { continue }

            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for (idx, line) in lines.enumerated() {
                let lineStr = String(line)
                let range = NSRange(lineStr.startIndex..<lineStr.endIndex, in: lineStr)
                if regex.firstMatch(in: lineStr, options: [], range: range) != nil {
                    hits.append("\(item):\(idx + 1):\(lineStr)")
                    if hits.count >= maxMatches {
                        return hits.joined(separator: "\n")
                    }
                }
            }
        }
        return hits.isEmpty ? "(no matches)" : hits.joined(separator: "\n")
    }
}
