import Foundation

nonisolated enum WorkspaceGuardError: Error, LocalizedError {
    case emptyWorkspace
    case outsideWorkspace(String)

    var errorDescription: String? {
        switch self {
        case .emptyWorkspace: return "Workspace root is not set"
        case let .outsideWorkspace(path): return "Path is outside the workspace: \(path)"
        }
    }
}

nonisolated struct WorkspaceGuard: Sendable {
    let workspaceRoot: String
    let ignorePatterns: [String]
    private let fileManager: FileManager

    init(workspaceRoot: String, ignorePatterns: [String] = [], fileManager: FileManager = .default) {
        self.workspaceRoot = (workspaceRoot as NSString).standardizingPath
        self.ignorePatterns = ignorePatterns
        self.fileManager = fileManager
    }

    /// Resolves a relative or absolute path and ensures it stays under workspace root.
    func resolve(_ path: String) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !workspaceRoot.isEmpty else { throw WorkspaceGuardError.emptyWorkspace }

        let candidate: String
        if trimmed.isEmpty || trimmed == "." {
            candidate = workspaceRoot
        } else if (trimmed as NSString).isAbsolutePath {
            candidate = (trimmed as NSString).standardizingPath
        } else {
            candidate = ((workspaceRoot as NSString).appendingPathComponent(trimmed) as NSString).standardizingPath
        }

        let root = workspaceRoot.hasSuffix("/") ? workspaceRoot : workspaceRoot + "/"
        let normalized = candidate.hasSuffix("/") ? String(candidate.dropLast()) : candidate
        let rootNoSlash = workspaceRoot.hasSuffix("/") ? String(workspaceRoot.dropLast()) : workspaceRoot

        if normalized == rootNoSlash {
            return normalized
        }
        if !normalized.hasPrefix(root) && normalized != rootNoSlash {
            // Case-insensitive compare for APFS default.
            let lowerNorm = normalized.lowercased()
            let lowerRoot = root.lowercased()
            let lowerRootNoSlash = rootNoSlash.lowercased()
            if lowerNorm != lowerRootNoSlash && !lowerNorm.hasPrefix(lowerRoot) {
                throw WorkspaceGuardError.outsideWorkspace(path)
            }
        }
        return normalized
    }

    func isIgnored(relativePath: String) -> Bool {
        let parts = relativePath.split(separator: "/").map(String.init)
        for part in parts {
            if ignorePatterns.contains(where: { $0.caseInsensitiveCompare(part) == .orderedSame }) {
                return true
            }
        }
        for pattern in ignorePatterns {
            if relativePath == pattern || relativePath.hasPrefix(pattern + "/") {
                return true
            }
        }
        return false
    }

    func relativePath(for absolutePath: String) -> String {
        let root = workspaceRoot.hasSuffix("/") ? workspaceRoot : workspaceRoot + "/"
        if absolutePath.hasPrefix(root) {
            return String(absolutePath.dropFirst(root.count))
        }
        if absolutePath == workspaceRoot {
            return ""
        }
        return absolutePath
    }
}
