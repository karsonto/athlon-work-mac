import Foundation

nonisolated struct FileListTool: AgentTool {
    let name = "file_list"
    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: "List files and directories under a workspace-relative path.",
            parameters: [
                "type": "object",
                "properties": [
                    "path": [
                        "type": "string",
                        "description": "Relative or absolute path within the workspace. Defaults to workspace root.",
                    ] as [String: Any],
                    "recursive": [
                        "type": "boolean",
                        "description": "When true, list recursively (depth-limited).",
                    ] as [String: Any],
                ] as [String: Any],
                "required": [] as [String],
            ]
        )
    }

    func invoke(arguments: String, context: AgentRunContext) async throws -> String {
        let args = try ToolJSON.object(from: arguments)
        let path = (args["path"] as? String) ?? "."
        let recursive = (args["recursive"] as? Bool) ?? false
        let guard_ = WorkspaceGuard(workspaceRoot: context.workspaceRoot, ignorePatterns: context.ignorePatterns)
        let root = try guard_.resolve(path)
        let fm = FileManager.default

        var results: [String] = []
        if recursive {
            guard let enumerator = fm.enumerator(atPath: root) else {
                return "[]"
            }
            var count = 0
            while let item = enumerator.nextObject() as? String {
                if guard_.isIgnored(relativePath: item) {
                    enumerator.skipDescendants()
                    continue
                }
                results.append(item)
                count += 1
                if count >= 2000 { break }
            }
        } else {
            let children = (try? fm.contentsOfDirectory(atPath: root)) ?? []
            for name in children.sorted() {
                let rel = guard_.relativePath(for: (root as NSString).appendingPathComponent(name))
                if guard_.isIgnored(relativePath: rel.isEmpty ? name : rel) { continue }
                var isDir: ObjCBool = false
                let full = (root as NSString).appendingPathComponent(name)
                _ = fm.fileExists(atPath: full, isDirectory: &isDir)
                results.append(isDir.boolValue ? name + "/" : name)
            }
        }
        let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
