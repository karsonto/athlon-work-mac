import Foundation
import Observation

struct WorkspaceTreeNode: Identifiable, Hashable {
    var id: String { path }
    var name: String
    var path: String
    var isDirectory: Bool
    var children: [WorkspaceTreeNode]?
}

/// Loads a directory tree from the active workspace root.
@Observable
@MainActor
final class WorkspaceTreeStore {
    private(set) var root: WorkspaceTreeNode?
    private(set) var rootPath: String = ""
    private(set) var errorMessage: String?
    private(set) var isLoading: Bool = false

    private let fileManager: FileManager
    private let maxEntriesPerDirectory = 2000

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load(rootPath: String?, ignorePatterns: [String]) {
        guard let rootPath, !rootPath.isEmpty else {
            self.root = nil
            self.rootPath = ""
            self.errorMessage = "未选择工作区"
            return
        }

        let standardized = (rootPath as NSString).standardizingPath
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: standardized, isDirectory: &isDir), isDir.boolValue else {
            root = nil
            self.rootPath = standardized
            errorMessage = "工作区路径不存在"
            return
        }

        self.rootPath = standardized
        let name = (standardized as NSString).lastPathComponent
        root = WorkspaceTreeNode(
            name: name.isEmpty ? standardized : name,
            path: standardized,
            isDirectory: true,
            children: loadChildren(of: standardized, ignorePatterns: ignorePatterns)
        )
    }

    func reload(ignorePatterns: [String]) {
        load(rootPath: rootPath.isEmpty ? nil : rootPath, ignorePatterns: ignorePatterns)
    }

    private func loadChildren(of directory: String, ignorePatterns: [String]) -> [WorkspaceTreeNode]? {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else {
            return nil
        }

        let filtered = entries
            .filter { name in
                if name.hasPrefix(".") { return false }
                return !shouldIgnore(name: name, patterns: ignorePatterns)
            }
            .sorted { lhs, rhs in
                let lhsPath = (directory as NSString).appendingPathComponent(lhs)
                let rhsPath = (directory as NSString).appendingPathComponent(rhs)
                var lhsDir: ObjCBool = false
                var rhsDir: ObjCBool = false
                fileManager.fileExists(atPath: lhsPath, isDirectory: &lhsDir)
                fileManager.fileExists(atPath: rhsPath, isDirectory: &rhsDir)
                if lhsDir.boolValue != rhsDir.boolValue {
                    return lhsDir.boolValue && !rhsDir.boolValue
                }
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }

        var nodes: [WorkspaceTreeNode] = []
        for (index, name) in filtered.enumerated() {
            if index >= maxEntriesPerDirectory {
                nodes.append(WorkspaceTreeNode(name: "…", path: directory + "/…", isDirectory: false, children: nil))
                break
            }
            let path = (directory as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: path, isDirectory: &isDir)
            if isDir.boolValue {
                nodes.append(WorkspaceTreeNode(
                    name: name,
                    path: path,
                    isDirectory: true,
                    children: loadChildren(of: path, ignorePatterns: ignorePatterns)
                ))
            } else {
                nodes.append(WorkspaceTreeNode(name: name, path: path, isDirectory: false, children: nil))
            }
        }
        return nodes
    }

    private func shouldIgnore(name: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            if name.caseInsensitiveCompare(pattern) == .orderedSame {
                return true
            }
        }
        return false
    }
}
