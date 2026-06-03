import Foundation

enum ToolPathNormalizeError: Error, LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

enum ToolPathNormalizer {
    static let pathArgumentName = "path"

    static func forModel(_ path: String) -> String {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return path }
        return path.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func tryNormalizeForFileOperation(_ path: String?) -> Result<String, ToolPathNormalizeError> {
        guard let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.message("Path cannot be empty."))
        }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("\0") {
            return .failure(.message("Path contains invalid characters."))
        }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("file://") {
            return .failure(.message("Path must be a workspace file path, not a URI."))
        }
        let normalized = forModel(trimmed)
        if normalized.isEmpty {
            return .failure(.message("Path cannot be empty."))
        }
        return .success(normalized)
    }

    static func normalizePathArguments(_ arguments: [String: String]) -> [String: String] {
        guard let path = arguments[pathArgumentName],
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return arguments
        }
        switch tryNormalizeForFileOperation(path) {
        case .success(let normalized):
            if normalized == path { return arguments }
            var copy = arguments
            copy[pathArgumentName] = normalized
            return copy
        case .failure:
            return arguments
        }
    }

    static func resolveRelativeToWorkspaceRoot(_ path: String, workspaceRoot: String) -> String {
        let path = forModel(path)
        guard !path.isEmpty, !workspaceRoot.isEmpty else { return path }

        var normalizedRoot = URL(fileURLWithPath: workspaceRoot).standardizedFileURL.path
        while normalizedRoot.count > 1, normalizedRoot.hasSuffix("/") {
            normalizedRoot.removeLast()
        }
        let rootForward = normalizedRoot.replacingOccurrences(of: "\\", with: "/")
        let pathForFull = path.replacingOccurrences(of: "/", with: "/")

        if pathForFull.hasPrefix("/") {
            let full = URL(fileURLWithPath: pathForFull).standardizedFileURL.path
            if full == normalizedRoot { return "." }
            let prefix = normalizedRoot + "/"
            if full.hasPrefix(prefix) {
                let rel = String(full.dropFirst(prefix.count))
                return forModel(rel)
            }
            return path
        }

        if path == rootForward { return "." }
        if path.hasPrefix(rootForward + "/") {
            return String(path.dropFirst(rootForward.count + 1))
        }

        let folderName = (normalizedRoot as NSString).lastPathComponent
        if folderName.isEmpty { return path }
        if path == folderName { return "." }
        if path.hasPrefix(folderName + "/") {
            return String(path.dropFirst(folderName.count + 1))
        }
        return path
    }
}

enum ToolArguments {
    static func required(_ arguments: [String: String], name: String, tool: String) throws -> String {
        if let value = arguments[name], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        throw ToolError.missingArgument(name, tool: tool)
    }

    static func int32(_ arguments: [String: String], name: String, defaultValue: Int) -> Int {
        guard let value = arguments[name], let parsed = Int(value) else { return defaultValue }
        return parsed
    }

    static func normalizedPath(_ arguments: [String: String], tool: String) throws -> String {
        guard let raw = arguments[ToolPathNormalizer.pathArgumentName] else {
            throw ToolError.missingArgument(ToolPathNormalizer.pathArgumentName, tool: tool)
        }
        switch ToolPathNormalizer.tryNormalizeForFileOperation(raw) {
        case .success(let path): return path
        case .failure(let error): throw ToolError.invalidPath(error.localizedDescription, tool: tool)
        }
    }

    static func optionalNormalizedPath(
        _ arguments: [String: String],
        tool: String,
        defaultPath: String = "."
    ) throws -> String {
        guard let raw = arguments[ToolPathNormalizer.pathArgumentName],
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ToolPathNormalizer.forModel(defaultPath)
        }
        switch ToolPathNormalizer.tryNormalizeForFileOperation(raw) {
        case .success(let path): return path
        case .failure(let error): throw ToolError.invalidPath(error.localizedDescription, tool: tool)
        }
    }
}

// MARK: - Tool path display (model vs resolved)

struct ToolExecutionDisplayNotes: Equatable {
    let normalizedArguments: [String: String]
    let resolvedFullPath: String?

    static func build(
        rawArguments: [String: String],
        normalizedArguments: [String: String],
        workspaceRoot: String?
    ) -> ToolExecutionDisplayNotes? {
        let root = workspaceRoot?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolved = root.isEmpty ? nil : ToolPathNormalizer.tryResolveFullPath(
            fromNormalizedArguments: normalizedArguments,
            workspaceRoot: root
        )
        let normChanged = normalizedArguments != rawArguments
        let hasPath = normalizedArguments[ToolPathNormalizer.pathArgumentName] != nil
            || rawArguments[ToolPathNormalizer.pathArgumentName] != nil
        guard normChanged || resolved != nil || hasPath else { return nil }
        return ToolExecutionDisplayNotes(
            normalizedArguments: normalizedArguments,
            resolvedFullPath: resolved
        )
    }
}

extension ToolPathNormalizer {
    /// Mirrors `WorkspaceGuard.normalize` for UI / tool-result display (no throw).
    static func tryResolveFullPath(
        fromNormalizedArguments arguments: [String: String],
        workspaceRoot: String
    ) -> String? {
        guard let rawPath = arguments[pathArgumentName],
              !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return tryResolveFullPath(path: ".", workspaceRoot: workspaceRoot)
        }
        return tryResolveFullPath(path: rawPath, workspaceRoot: workspaceRoot)
    }

    static func tryResolveFullPath(path: String, workspaceRoot: String) -> String? {
        let basePath = URL(fileURLWithPath: workspaceRoot).standardizedFileURL.path
        var normalized = forModel(path)
        normalized = resolveRelativeToWorkspaceRoot(normalized, workspaceRoot: basePath)
        let rooted: String
        if normalized.hasPrefix("/") {
            rooted = normalized
        } else {
            rooted = (basePath as NSString).appendingPathComponent(normalized)
        }
        return URL(fileURLWithPath: rooted).standardizedFileURL.path
    }
}
