import Foundation

struct GrepFilesTool: AgentTool {
    let name = "grep_files"
    let description = "Search file contents for a literal text pattern."
    let parametersSchema: [String: String] = [
        "pattern": "Literal text pattern to search for",
        "path": "Optional directory path (relative to workspace or absolute)",
        "glob": "Optional file glob filter, e.g. *.swift"
    ]

    private let guard_: WorkspaceGuard
    private let maxFilesToScan = 2000
    private let maxMatches = 200
    private let maxFileSizeBytes: Int64 = 2 * 1024 * 1024

    init(guard workspaceGuard: WorkspaceGuard) {
        self.guard_ = workspaceGuard
    }

    func invoke(arguments: [String: String]) async throws -> String {
        let pattern = try ToolArguments.required(arguments, name: "pattern", tool: name)
        let requestedPath = try ToolArguments.optionalNormalizedPath(arguments, tool: name)
        let fullPath = try guard_.normalize(requestedPath)

        let glob = arguments["glob"] ?? "*"
        let ignorePatterns = guard_.getIgnorePatterns()
        let baseRoot = try guard_.normalize(".")
        let files = collectFiles(at: fullPath, glob: glob, ignorePatterns: ignorePatterns)

        var matches: [String] = []
        for file in files {
            let attrs = try? FileManager.default.attributesOfItem(atPath: file)
            let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            if size > maxFileSizeBytes { continue }

            guard let handle = FileHandle(forReadingAtPath: file),
                  let data = try? handle.readToEnd(),
                  let text = String(data: data, encoding: .utf8) else { continue }

            let relative = relativePath(from: baseRoot, to: file)
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() {
                if line.range(of: pattern, options: .caseInsensitive) == nil { continue }
                matches.append("\(relative):\(index + 1):\(line.trimmingCharacters(in: .whitespaces))")
                if matches.count >= maxMatches { break }
            }
            if matches.count >= maxMatches { break }
        }

        if matches.isEmpty {
            return ToolResultFormatter.success("No matches found", content: "No matches found")
        }
        return ToolResultFormatter.success("Found \(matches.count) matches", content: matches.joined(separator: "\n"))
    }

    private func collectFiles(at fullPath: String, glob: String, ignorePatterns: [String]) -> [String] {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory), !isDirectory.boolValue {
            return [fullPath]
        }
        guard isDirectory.boolValue else { return [] }

        var files: [String] = []
        guard let enumerator = FileManager.default.enumerator(atPath: fullPath) else { return [] }
        for case let entry as String in enumerator {
            let path = (fullPath as NSString).appendingPathComponent(entry)
            if WorkspacePathFilter.shouldIgnorePath(path, directoryNames: ignorePatterns) {
                continue
            }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { continue }
            let fileName = (path as NSString).lastPathComponent
            if glob == "*" || fnmatch(glob, fileName, 0) == 0 {
                files.append(path)
            }
            if files.count >= maxFilesToScan { break }
        }
        return files
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

private func fnmatch(_ pattern: String, _ string: String, _ flags: Int32) -> Int32 {
    pattern.withCString { patternPtr in
        string.withCString { stringPtr in
            Darwin.fnmatch(patternPtr, stringPtr, flags)
        }
    }
}
