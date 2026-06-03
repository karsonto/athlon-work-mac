import Foundation

struct GlobFilesTool: AgentTool {
    let name = "glob_files"
    let description = "Find files matching a glob pattern."
    let parametersSchema: [String: String] = [
        "pattern": "Glob pattern (supports ** and {a,b} extensions), e.g. **/*.swift or **/*.{png,jpg}",
        "path": "Optional directory path (relative to workspace or absolute)"
    ]

    private let guard_: WorkspaceGuard

    init(guard workspaceGuard: WorkspaceGuard) {
        self.guard_ = workspaceGuard
    }

    func invoke(arguments: [String: String]) async throws -> String {
        let pattern = try ToolArguments.required(arguments, name: "pattern", tool: name)
        let requestedPath = try ToolArguments.optionalNormalizedPath(arguments, tool: name)
        let fullPath = try guard_.normalize(requestedPath)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ToolError.notFound("Directory not found: \(fullPath)")
        }

        let ignorePatterns = guard_.getIgnorePatterns()
        let matches = GlobPatternHelper.enumerateMatches(
            rootDirectory: fullPath,
            pattern: pattern,
            ignorePatterns: ignorePatterns
        ).map { path -> String in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            let relative = relativePath(from: fullPath, to: path)
            if isDir.boolValue {
                return "\(relative)/"
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.intValue ?? 0
            return "\(relative) (\(size) bytes)"
        }

        if matches.isEmpty {
            return ToolResultFormatter.success("No matching files found", content: "No matching files found")
        }
        return ToolResultFormatter.success("Found \(matches.count) matching entries", content: matches.joined(separator: "\n"))
    }

    private func relativePath(from root: String, to path: String) -> String {
        let rootPath = URL(fileURLWithPath: root).standardizedFileURL.path
        let filePath = URL(fileURLWithPath: path).standardizedFileURL.path
        if filePath.hasPrefix(rootPath + "/") {
            return String(filePath.dropFirst(rootPath.count + 1))
        }
        return (path as NSString).lastPathComponent
    }
}
