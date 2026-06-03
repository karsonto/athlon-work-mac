import Foundation

struct FileListTool: AgentTool {
    let name = "file_list"
    let description = "List files in a directory."
    let parametersSchema = ["path": "Optional directory path (relative to workspace or absolute)"]

    private let guard_: WorkspaceGuard

    init(guard workspaceGuard: WorkspaceGuard) {
        self.guard_ = workspaceGuard
    }

    func invoke(arguments: [String: String]) async throws -> String {
        let requestedPath = try ToolArguments.optionalNormalizedPath(arguments, tool: name)
        let fullPath = try guard_.normalize(requestedPath)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ToolError.notFound("Directory not found: \(fullPath)")
        }

        let ignorePatterns = guard_.getIgnorePatterns()
        let entries = try FileManager.default.contentsOfDirectory(atPath: fullPath)
            .filter { !WorkspacePathFilter.shouldIgnoreEntryName($0, directoryNames: ignorePatterns) }
            .sorted { a, b in
                let aPath = (fullPath as NSString).appendingPathComponent(a)
                let bPath = (fullPath as NSString).appendingPathComponent(b)
                let aIsDir = (try? FileManager.default.attributesOfItem(atPath: aPath)[.type] as? FileAttributeType) == .typeDirectory
                let bIsDir = (try? FileManager.default.attributesOfItem(atPath: bPath)[.type] as? FileAttributeType) == .typeDirectory
                if aIsDir != bIsDir { return aIsDir }
                return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }
            .prefix(200)
            .map { entry -> String in
                let entryPath = (fullPath as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: entryPath, isDirectory: &isDir)
                if isDir.boolValue {
                    return "[DIR]  \(entry)"
                }
                let size = (try? FileManager.default.attributesOfItem(atPath: entryPath)[.size] as? NSNumber)?.intValue ?? 0
                return "[FILE] \(entry) (\(size) bytes)"
            }

        let content = entries.isEmpty ? "(empty directory)" : entries.joined(separator: "\n")
        let fileName = (fullPath as NSString).lastPathComponent
        return ToolResultFormatter.success("Listed \(entries.count) entries from \(fileName)", content: content)
    }
}
