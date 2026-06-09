import Foundation

/// Validates and normalizes paths within the active workspace.
final class WorkspaceGuard {
    private let workspaceService: WorkspaceService
    private let settings: AppSettings
    private let appPaths: AppPathProvider
    var sessionRootPath: String?

    init(
        workspaceService: WorkspaceService,
        settings: AppSettings,
        appPaths: AppPathProvider = .shared
    ) {
        self.workspaceService = workspaceService
        self.settings = settings
        self.appPaths = appPaths
    }

    var hasConfiguredWorkspace: Bool { tryGetWorkspaceRoot() != nil }

    func tryGetWorkspaceRoot() -> String? {
        if let sessionRootPath, !sessionRootPath.isEmpty {
            return URL(fileURLWithPath: sessionRootPath).standardizedFileURL.path
        }
        if let root = workspaceService.rootPath, !root.isEmpty {
            return URL(fileURLWithPath: root).standardizedFileURL.path
        }
        if let configured = settings.workspaces.first(where: { !$0.rootPath.isEmpty }) {
            return URL(fileURLWithPath: configured.rootPath).standardizedFileURL.path
        }
        return nil
    }

    func isInsideWorkspace(_ path: String) -> Bool {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let fullPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return allowedRoots().contains { isPathUnderRoot(fullPath, rootPath: $0) }
    }

    func normalize(_ path: String, cwd: String? = nil) throws -> String {
        let normalized = ToolPathNormalizer.forModel(path)
        if normalized.hasPrefix("/") {
            return URL(fileURLWithPath: normalized).standardizedFileURL.path
        }

        let base = cwd ?? tryGetWorkspaceRoot() ?? FileManager.default.currentDirectoryPath
        let rooted = (base as NSString).appendingPathComponent(normalized)
        return URL(fileURLWithPath: rooted).standardizedFileURL.path
    }

    func getIgnorePatterns() -> [String] {
        var patterns: [String]
        if let root = tryGetWorkspaceRoot() {
            let normalizedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
            if let workspace = settings.workspaces.first(where: {
                !$0.rootPath.isEmpty
                    && URL(fileURLWithPath: $0.rootPath).standardizedFileURL.path == normalizedRoot
            }), let workspacePatterns = workspace.ignorePatterns, !workspacePatterns.isEmpty {
                patterns = workspacePatterns
            } else {
                patterns = settings.workspaceIgnore.directoryNames
            }
        } else {
            patterns = settings.workspaceIgnore.directoryNames
        }

        for exclude in settings.memory.excludePatterns {
            let normalized = exclude.hasSuffix("/") ? String(exclude.dropLast()) : exclude
            if !normalized.isEmpty, !patterns.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
                patterns.append(normalized)
            }
        }
        return patterns
    }

    private func allowedRoots() -> [String] {
        var roots: [String] = []
        if let workspaceRoot = tryGetWorkspaceRoot() {
            roots.append(workspaceRoot)
        }
        if !appPaths.rootPath.isEmpty {
            roots.append(URL(fileURLWithPath: appPaths.rootPath).standardizedFileURL.path)
        }
        return roots
    }

    private func isPathUnderRoot(_ fullPath: String, rootPath: String) -> Bool {
        guard !rootPath.isEmpty else { return false }
        var normalizedRoot = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        while normalizedRoot.count > 1, normalizedRoot.hasSuffix("/") {
            normalizedRoot.removeLast()
        }
        let normalizedPath = URL(fileURLWithPath: fullPath).standardizedFileURL.path
        let root = normalizedRoot.lowercased()
        let path = normalizedPath.lowercased()
        if path == root { return true }
        return path.hasPrefix(root + "/")
    }
}
