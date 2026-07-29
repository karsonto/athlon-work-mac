import SwiftUI

struct WorkspaceTreeView: View {
    @Bindable var treeStore: WorkspaceTreeStore
    var onOpenFile: (String) -> Void
    var onRevealInFinder: ((String) -> Void)? = nil

    var body: some View {
        Group {
            if treeStore.isLoading {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = treeStore.errorMessage, treeStore.root == nil {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if let root = treeStore.root {
                List {
                    OutlineGroup(rootChildren(root), children: \.children) { node in
                        nodeRow(node)
                    }
                }
                .listStyle(.sidebar)
            } else {
                Text("无工作区")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func rootChildren(_ root: WorkspaceTreeNode) -> [WorkspaceTreeNode] {
        root.children ?? []
    }

    @ViewBuilder
    private func nodeRow(_ node: WorkspaceTreeNode) -> some View {
        Label {
            Text(node.name)
                .lineLimit(1)
        } icon: {
            Image(systemName: node.isDirectory ? "folder" : "doc.text")
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if !node.isDirectory {
                onOpenFile(node.path)
            }
        }
        .contextMenu {
            if !node.isDirectory {
                Button("打开") { onOpenFile(node.path) }
            }
            Button("在 Finder 中显示") {
                onRevealInFinder?(node.path)
            }
        }
    }
}
