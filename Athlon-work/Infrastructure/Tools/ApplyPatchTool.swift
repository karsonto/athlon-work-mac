import Foundation

nonisolated struct ApplyPatchTool: AgentTool {
    let name = "apply_patch"
    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Apply a basic unified diff patch to a file in the workspace.",
            parameters: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Target file path"] as [String: Any],
                    "patch": ["type": "string", "description": "Unified diff text"] as [String: Any],
                ] as [String: Any],
                "required": ["path", "patch"],
            ]
        )
    }

    func invoke(arguments: String, context: AgentRunContext) async throws -> String {
        let args = try ToolJSON.object(from: arguments)
        guard let path = args["path"] as? String, !path.isEmpty else {
            throw AgentToolError.invalidArguments("path is required")
        }
        guard let patch = args["patch"] as? String, !patch.isEmpty else {
            throw AgentToolError.invalidArguments("patch is required")
        }
        let guard_ = WorkspaceGuard(workspaceRoot: context.workspaceRoot, ignorePatterns: context.ignorePatterns)
        let resolved = try guard_.resolve(path)
        let original = (try? String(contentsOfFile: resolved, encoding: .utf8)) ?? ""
        let updated = try UnifiedDiffApplier.apply(patch: patch, to: original)
        let dir = (resolved as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try updated.write(toFile: resolved, atomically: true, encoding: .utf8)
        return "Applied patch to \(guard_.relativePath(for: resolved))"
    }
}

nonisolated enum UnifiedDiffApplier {
    static func apply(patch: String, to original: String) throws -> String {
        let patchLines = patch.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var hunks: [Hunk] = []
        var i = 0
        while i < patchLines.count {
            let line = patchLines[i]
            if line.hasPrefix("@@") {
                guard let hunk = parseHunk(patchLines, start: &i) else {
                    throw AgentToolError.executionFailed("Failed to parse hunk near: \(line)")
                }
                hunks.append(hunk)
                continue
            }
            i += 1
        }
        if hunks.isEmpty {
            // Treat as full-file replacement when no hunk headers.
            if patch.contains("---") || patch.contains("+++") {
                throw AgentToolError.executionFailed("Patch contained headers but no @@ hunks")
            }
            return patch
        }

        var lines = original.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // Apply from bottom to top so earlier offsets stay valid.
        for hunk in hunks.reversed() {
            let start = max(0, hunk.oldStart - 1)
            let end = min(lines.count, start + hunk.oldCount)
            let oldSlice = Array(lines[start..<end])
            if oldSlice != hunk.oldLines && hunk.oldCount > 0 {
                // Soft match: search nearby for oldLines sequence.
                if let found = findSequence(hunk.oldLines, in: lines) {
                    lines.replaceSubrange(found..<found + hunk.oldLines.count, with: hunk.newLines)
                    continue
                }
                throw AgentToolError.executionFailed("Hunk context mismatch at line \(hunk.oldStart)")
            }
            lines.replaceSubrange(start..<end, with: hunk.newLines)
        }
        return lines.joined(separator: "\n")
    }

    private struct Hunk {
        var oldStart: Int
        var oldCount: Int
        var oldLines: [String]
        var newLines: [String]
    }

    private static func parseHunk(_ lines: [String], start i: inout Int) -> Hunk? {
        let header = lines[i]
        i += 1
        // @@ -l,s +l,s @@
        guard let regex = try? NSRegularExpression(
            pattern: #"@@\s*-(\d+)(?:,(\d+))?\s+\+(\d+)(?:,(\d+))?\s*@@"#,
            options: []
        ) else {
            return nil
        }
        let ns = header as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: header, options: [], range: full),
              match.numberOfRanges >= 2 else {
            return nil
        }
        let oldStart = Int(ns.substring(with: match.range(at: 1))) ?? 1
        let oldCount: Int
        if match.range(at: 2).location != NSNotFound {
            oldCount = Int(ns.substring(with: match.range(at: 2))) ?? 1
        } else {
            oldCount = 1
        }

        var oldLines: [String] = []
        var newLines: [String] = []
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("@@") { break }
            if line.hasPrefix("---") || line.hasPrefix("+++") {
                i += 1
                continue
            }
            if line.hasPrefix("\\") {
                i += 1
                continue
            }
            if line.hasPrefix("+") {
                newLines.append(String(line.dropFirst()))
            } else if line.hasPrefix("-") {
                oldLines.append(String(line.dropFirst()))
            } else if line.hasPrefix(" ") {
                let body = String(line.dropFirst())
                oldLines.append(body)
                newLines.append(body)
            } else if line.isEmpty {
                // tolerate
            } else {
                break
            }
            i += 1
        }
        return Hunk(oldStart: oldStart, oldCount: oldCount, oldLines: oldLines, newLines: newLines)
    }

    private static func findSequence(_ needle: [String], in haystack: [String]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return needle.isEmpty ? 0 : nil }
        outer: for idx in 0...(haystack.count - needle.count) {
            for j in 0..<needle.count where haystack[idx + j] != needle[j] {
                continue outer
            }
            return idx
        }
        return nil
    }
}
