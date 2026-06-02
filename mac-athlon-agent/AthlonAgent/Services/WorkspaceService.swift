import Foundation
import Combine

// MARK: - Workspace Service
/// Manages workspace file tree scanning, ignore pattern filtering, file icons, and change monitoring.
class WorkspaceService: ObservableObject {
    @Published var rootPath: String?
    @Published var files: [WorkspaceNode] = []
    @Published var fileTree: [WorkspaceNode] = []
    @Published var isScanning = false
    @Published var lastScanDate: Date?

    private var ignorePatterns: [String] = []
    private let fileManager = FileManager.default
    private var dispatchSource: DispatchSourceFileSystemObject?
    private let monitorQueue = DispatchQueue(label: "com.athlon.workspace.monitor", qos: .background)

    // Cache
    private var flatPathList: [String] = []

    init(ignorePatterns: [String] = []) {
        self.ignorePatterns = ignorePatterns
    }

    // MARK: - Set Workspace Root
    func setWorkspaceRoot(_ path: String, scanNow: Bool = true) {
        rootPath = path
        if scanNow { scanWorkspace() }
    }

    // MARK: - Scan
    func scanWorkspace(maxDepth: Int = 8) {
        guard let root = rootPath else { return }
        isScanning = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let rootURL = URL(fileURLWithPath: root)
            var nodes: [WorkspaceNode] = []
            var flatPaths: [String] = []

            self.enumerateDirectory(
                at: rootURL,
                into: &nodes,
                flatPaths: &flatPaths,
                maxDepth: maxDepth,
                currentDepth: 0
            )

            let tree = self.buildTree(from: nodes, relativeTo: root)

            DispatchQueue.main.async {
                self.files = nodes
                self.fileTree = tree
                self.flatPathList = flatPaths
                self.isScanning = false
                self.lastScanDate = Date()
            }
        }
    }

    private func enumerateDirectory(
        at url: URL,
        into nodes: inout [WorkspaceNode],
        flatPaths: inout [String],
        maxDepth: Int,
        currentDepth: Int
    ) {
        guard currentDepth <= maxDepth else { return }

        let relativePath = relativePathOf(url)

        // Skip ignored
        if isIgnored(relativePath) { return }

        flatPaths.append(relativePath)

        // Get directory contents
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        // Sort: directories first, then files, alphabetically
        let sorted = contents.sorted { a, b in
            let aIsDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let bIsDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if aIsDir != bIsDir { return aIsDir }
            return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }

        for childURL in sorted {
            let childRelPath = relativePathOf(childURL)
            if isIgnored(childRelPath) { continue }

            let isDir = (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            let node = WorkspaceNode(
                id: childRelPath,
                name: childURL.lastPathComponent,
                path: childRelPath,
                isDirectory: isDir,
                iconKind: iconKind(for: childURL.lastPathComponent, isDirectory: isDir)
            )
            nodes.append(node)

            // Recurse into directories
            if isDir && currentDepth < maxDepth {
                enumerateDirectory(
                    at: childURL,
                    into: &nodes,
                    flatPaths: &flatPaths,
                    maxDepth: maxDepth,
                    currentDepth: currentDepth + 1
                )
            }
        }
    }

    // MARK: - Tree Builder
    private func buildTree(from flatNodes: [WorkspaceNode], relativeTo root: String) -> [WorkspaceNode] {
        var nodeMap: [String: WorkspaceNode] = [:]
        var children: [String: [WorkspaceNode]] = [:]

        for node in flatNodes {
            nodeMap[node.path] = node
            let parent = parentPath(of: node.path)
            children[parent, default: []].append(node)
        }

        // Attach children
        var result: [WorkspaceNode] = []
        for node in flatNodes {
            if let kids = children[node.path] {
                node.children = kids.sorted { a, b in
                    if a.isDirectory != b.isDirectory { return a.isDirectory }
                    return a.name.localizedStandardCompare(b.name) == .orderedAscending
                }
            }
            nodeMap[node.path] = node
        }

        // Find root-level items (parent is workspace root)
        let rootPrefix = root.hasSuffix("/") ? root : root + "/"
        for node in flatNodes {
            let parent = parentPath(of: node.path)
            if parent == "" || parent == rootPrefix || parent == root {
                if let nodeWithChildren = nodeMap[node.path] {
                    result.append(nodeWithChildren)
                }
            }
        }

        return result.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    // MARK: - Ignore Logic
    func setIgnorePatterns(_ patterns: [String]) {
        ignorePatterns = patterns
    }

    private func isIgnored(_ path: String) -> Bool {
        let components = path.components(separatedBy: "/")
        for component in components {
            for pattern in ignorePatterns {
                if component == pattern { return true }
                // Simple glob: *.ext or directory/*
                if pattern.hasPrefix("*") {
                    let ext = String(pattern.dropFirst())
                    if component.hasSuffix(ext) { return true }
                }
                if pattern.hasSuffix("/*") {
                    let dir = String(pattern.dropLast(2))
                    if path.hasPrefix(dir + "/") || component == dir { return true }
                }
            }
        }

        // Always ignore some defaults
        let defaultIgnores: Set<String> = [
            ".git", ".svn", ".hg", "__pycache__", "node_modules",
            ".DS_Store", ".cache", "bin", "obj", "dist", "build",
            ".next", ".nuxt", ".svelte-kit", ".idea", ".vscode",
            "*.tmp", "*.log", "*.lock"
        ]
        for component in components {
            if defaultIgnores.contains(component) { return true }
        }

        return false
    }

    // MARK: - File Monitoring
    func startMonitoring() {
        guard let root = rootPath else { return }
        stopMonitoring()

        let fd = open(root, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: monitorQueue
        )

        source.setEventHandler { [weak self] in
            // Debounce: rescan after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self?.scanWorkspace()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        dispatchSource = source
    }

    func stopMonitoring() {
        dispatchSource?.cancel()
        dispatchSource = nil
    }

    // MARK: - Helpers
    private func relativePathOf(_ url: URL) -> String {
        guard let root = rootPath else { return url.path }
        let rootURL = URL(fileURLWithPath: root)
        let rel = url.path.replacingOccurrences(of: rootURL.path, with: "")
        if rel.hasPrefix("/") { return String(rel.dropFirst()) }
        return rel
    }

    private func parentPath(of path: String) -> String {
        let components = path.components(separatedBy: "/")
        guard components.count > 1 else { return "" }
        return components.dropLast().joined(separator: "/")
    }

    private func iconKind(for filename: String, isDirectory: Bool) -> WorkspaceIconKind {
        if isDirectory { return .folder }
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .swift
        case "cs": return .csharp
        case "ts", "tsx": return .typescript
        case "js", "jsx": return .javascript
        case "json": return .json
        case "py": return .python
        case "md", "markdown": return .markdown
        case "html", "htm": return .html
        case "css", "scss", "less": return .css
        case "png", "jpg", "jpeg", "gif", "webp", "heic": return .image
        case "yml", "yaml": return .yaml
        case "xml", "plist": return .xml
        case "sh", "bash", "zsh": return .shell
        case "gitignore", "dockerignore": return .config
        case "xcodeproj", "xcworkspace": return .xcode
        default: return .file
        }
    }

    // MARK: - Search / Filter
    func searchFiles(query: String) -> [WorkspaceNode] {
        guard !query.isEmpty else { return files }
        let lower = query.lowercased()
        return files.filter { $0.name.lowercased().contains(lower) || $0.path.lowercased().contains(lower) }
    }

    var fileCount: Int { files.filter { !$0.isDirectory }.count }
    var directoryCount: Int { files.filter { $0.isDirectory }.count }
    var flatFilePaths: [String] { flatPathList.filter { $0.components(separatedBy: "/").count > 1 } }

    // MARK: - Read File
    func readFileContent(path relativePath: String) -> String? {
        guard let root = rootPath else { return nil }
        let fullPath = root.hasSuffix("/") ? root + relativePath : root + "/" + relativePath
        return try? String(contentsOfFile: fullPath, encoding: .utf8)
    }

    func writeFileContent(path relativePath: String, content: String) throws {
        guard let root = rootPath else { throw NSError(domain: "Athlon", code: -1, userInfo: [NSLocalizedDescriptionKey: "No workspace root"]) }
        let fullPath = root.hasSuffix("/") ? root + relativePath : root + "/" + relativePath
        try content.write(toFile: fullPath, atomically: true, encoding: .utf8)
    }
}
