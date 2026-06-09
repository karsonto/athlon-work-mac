import Foundation

/// Loads AGENTS.md and knowledge/ catalog into the environment prompt (WPF-aligned).
enum WorkspacePromptLoader {
    private static let agentsFileName = "AGENTS.md"
    private static let knowledgeDirName = "knowledge"
    private static let knowledgeIndexFileName = "KNOWLEDGE.md"
    private static let truncationNotice = "\n\n... (truncated — read the full file with file_read) ...\n"

    static func appendWorkspaceFiles(to builder: inout String, context: EnvironmentPromptContext) {
        guard context.hasWorkspace,
              let workspaceRootRaw = context.workspaceRoot,
              !workspaceRootRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let workspaceRoot = URL(fileURLWithPath: workspaceRootRaw).standardizedFileURL.path
        let settings = context.promptSettings
        var hasContent = false

        if let agentsContent = tryReadAgentsMd(workspaceRoot: workspaceRoot, maxChars: settings.maxAgentsMdChars) {
            if !hasContent {
                builder += "\n"
            }
            builder += "## AGENTS.md\n"
            builder += "<loaded_context>\n"
            builder += agentsContent.trimmingCharacters(in: .newlines)
            builder += "\n</loaded_context>\n\n"
            hasContent = true
        }

        if let knowledgeBlock = buildKnowledgeBlock(
            workspaceRoot: workspaceRoot,
            ignorePatterns: context.ignorePatterns,
            settings: settings
        ) {
            if !hasContent {
                builder += "\n"
            }
            builder += knowledgeBlock
            if !knowledgeBlock.hasSuffix("\n") {
                builder += "\n"
            }
            builder += "\n"
        }
    }

    private static func tryReadAgentsMd(workspaceRoot: String, maxChars: Int) -> String? {
        let agentsPath = (workspaceRoot as NSString).appendingPathComponent(agentsFileName)
        guard FileManager.default.fileExists(atPath: agentsPath),
              isUnderRoot(fullPath: agentsPath, rootPath: workspaceRoot) else {
            return nil
        }
        return readTextWithLimit(path: agentsPath, maxChars: maxChars)
    }

    private static func buildKnowledgeBlock(
        workspaceRoot: String,
        ignorePatterns: [String],
        settings: PromptSettings
    ) -> String? {
        let knowledgeRoot = (workspaceRoot as NSString).appendingPathComponent(knowledgeDirName)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: knowledgeRoot, isDirectory: &isDirectory),
              isDirectory.boolValue,
              isUnderRoot(fullPath: knowledgeRoot, rootPath: workspaceRoot) else {
            return nil
        }

        var block = ""
        block += "## Domain Knowledge\n"
        block += "knowledge/ reference docs below; use file_read or grep_files for content not inlined.\n\n"

        let knowledgeMdPath = (knowledgeRoot as NSString).appendingPathComponent(knowledgeIndexFileName)
        if FileManager.default.fileExists(atPath: knowledgeMdPath),
           isUnderRoot(fullPath: knowledgeMdPath, rootPath: workspaceRoot),
           let indexContent = readTextWithLimit(path: knowledgeMdPath, maxChars: settings.maxKnowledgeMdChars),
           !indexContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            block += "### knowledge/KNOWLEDGE.md\n"
            block += "<loaded_context>\n"
            block += indexContent.trimmingCharacters(in: .newlines)
            block += "\n</loaded_context>\n\n"
        }

        let catalog = collectKnowledgePaths(
            knowledgeRoot: knowledgeRoot,
            workspaceRoot: workspaceRoot,
            ignorePatterns: ignorePatterns,
            maxEntries: settings.maxKnowledgeCatalogEntries
        )
        if !catalog.paths.isEmpty {
            block += "### knowledge/ file catalog\n"
            for path in catalog.paths {
                block += "- \(path)\n"
            }
            if catalog.truncated {
                block += "... (\(catalog.totalFound) paths total; listing capped at \(settings.maxKnowledgeCatalogEntries))\n"
            }
        }

        let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private struct KnowledgeCatalogResult {
        let paths: [String]
        let totalFound: Int
        let truncated: Bool
    }

    private static func collectKnowledgePaths(
        knowledgeRoot: String,
        workspaceRoot: String,
        ignorePatterns: [String],
        maxEntries: Int
    ) -> KnowledgeCatalogResult {
        let ignored = Set(ignorePatterns.map { $0.lowercased() })
        var paths: [String] = []
        var totalFound = 0

        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: knowledgeRoot),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return KnowledgeCatalogResult(paths: [], totalFound: 0, truncated: false)
        }

        let indexRelative = "\(knowledgeDirName)/\(knowledgeIndexFileName)"

        for case let fileURL as URL in enumerator {
            let filePath = fileURL.path
            guard isUnderRoot(fullPath: filePath, rootPath: workspaceRoot) else { continue }

            var isRegularFile = false
            if let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]) {
                isRegularFile = values.isRegularFile == true
            } else {
                var isDir: ObjCBool = false
                isRegularFile = FileManager.default.fileExists(atPath: filePath, isDirectory: &isDir) && !isDir.boolValue
            }
            guard isRegularFile else { continue }

            let relativeFromWorkspace = relativePath(from: workspaceRoot, to: filePath)
            if shouldIgnorePath(relativePath: relativeFromWorkspace, ignored: ignored) { continue }
            if relativeFromWorkspace.caseInsensitiveCompare(indexRelative) == .orderedSame { continue }

            totalFound += 1
            if paths.count < maxEntries {
                paths.append(relativeFromWorkspace)
            }
        }

        paths.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return KnowledgeCatalogResult(paths: paths, totalFound: totalFound, truncated: totalFound > maxEntries)
    }

    private static func shouldIgnorePath(relativePath: String, ignored: Set<String>) -> Bool {
        let segments = relativePath.split(separator: "/").map(String.init)
        return segments.contains { ignored.contains($0.lowercased()) }
    }

    private static func readTextWithLimit(path: String, maxChars: Int) -> String? {
        guard maxChars > 0,
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        if content.count <= maxChars {
            return content
        }
        return String(content.prefix(maxChars)) + truncationNotice
    }

    private static func isUnderRoot(fullPath: String, rootPath: String) -> Bool {
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

    private static func relativePath(from root: String, to fullPath: String) -> String {
        let normalizedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
        let normalizedPath = URL(fileURLWithPath: fullPath).standardizedFileURL.path
        let rootPrefix = normalizedRoot.hasSuffix("/") ? normalizedRoot : normalizedRoot + "/"
        guard normalizedPath.hasPrefix(rootPrefix) else {
            return normalizedPath
        }
        return String(normalizedPath.dropFirst(rootPrefix.count))
    }
}
