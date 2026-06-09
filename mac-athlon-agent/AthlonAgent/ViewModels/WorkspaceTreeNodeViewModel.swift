// AthlonAgent/ViewModels/WorkspaceTreeNodeViewModel.swift
import Foundation

/// Represents a single node in the workspace file tree sidebar.
@MainActor
final class WorkspaceTreeNodeViewModel: ObservableObject, Identifiable {
    let id = UUID()
    let name: String
    let fullPath: String?
    let isDirectory: Bool
    let iconKind: WorkspaceFileIconKind
    @Published var isExpanded: Bool = false
    @Published var children: [WorkspaceTreeNodeViewModel] = []
    @Published var isPlaceholder: Bool
    @Published var isExpanderPlaceholder: Bool

    private var childrenLoaded = false
    private let ignorePatterns: [String]
    private static let maxEntries = 2000

    init(name: String, fullPath: String?, isDirectory: Bool, isPlaceholder: Bool = false,
         isExpanderPlaceholder: Bool = false, ignorePatterns: [String] = []) {
        self.name = name
        self.fullPath = fullPath
        self.isDirectory = isDirectory
        self.isPlaceholder = isPlaceholder
        self.isExpanderPlaceholder = isExpanderPlaceholder
        self.ignorePatterns = ignorePatterns
        self.iconKind = WorkspaceFileIconKindResolver.resolve(name: name, isDirectory: isDirectory)
    }

    static func placeholder(_ message: String) -> WorkspaceTreeNodeViewModel {
        WorkspaceTreeNodeViewModel(name: message, fullPath: nil, isDirectory: false, isPlaceholder: true)
    }

    private static func expanderPlaceholder() -> WorkspaceTreeNodeViewModel {
        WorkspaceTreeNodeViewModel(name: "", fullPath: nil, isDirectory: false, isExpanderPlaceholder: true)
    }

    func ensureChildrenLoaded() {
        guard !childrenLoaded, !isPlaceholder, isDirectory, let fullPath, !fullPath.isEmpty else { return }
        childrenLoaded = true
        children.removeAll()

        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: fullPath) else { return }

        let sorted = entries
            .filter { !ignorePatterns.contains($0) }
            .sorted { name1, name2 in
                let p1 = (fullPath as NSString).appendingPathComponent(name1)
                let p2 = (fullPath as NSString).appendingPathComponent(name2)
                let d1 = fm.isDirectory(p1)
                let d2 = fm.isDirectory(p2)
                if d1 != d2 { return d1 }
                return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
            }

        var count = 0
        for name in sorted {
            guard count < Self.maxEntries else {
                children.append(Self.placeholder("…"))
                break
            }
            count += 1
            let entryPath = (fullPath as NSString).appendingPathComponent(name)
            let isDir = fm.isDirectory(entryPath)
            let child = WorkspaceTreeNodeViewModel(
                name: name, fullPath: entryPath, isDirectory: isDir,
                ignorePatterns: ignorePatterns
            )
            if isDir && mayHaveChildren(entryPath) {
                child.children.append(Self.expanderPlaceholder())
            }
            children.append(child)
        }
    }

    private func mayHaveChildren(_ path: String) -> Bool {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: path) else { return false }
        return entries.contains { !ignorePatterns.contains($0) }
    }

    static func buildTree(rootPath: String?, ignorePatterns: [String]) -> [WorkspaceTreeNodeViewModel] {
        guard let rootPath, !rootPath.isEmpty,
              FileManager.default.fileExists(atPath: rootPath) else {
            return [placeholder("未配置工作区")]
        }
        let root = WorkspaceTreeNodeViewModel(
            name: (rootPath as NSString).lastPathComponent,
            fullPath: rootPath, isDirectory: true,
            ignorePatterns: ignorePatterns
        )
        root.isExpanded = true
        root.ensureChildrenLoaded()
        return [root]
    }
}

private extension FileManager {
    func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}
