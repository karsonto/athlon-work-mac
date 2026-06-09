// AthlonAgent/Views/WorkspaceTreeView.swift
import SwiftUI

struct WorkspaceTreeView: View {
    @Binding var nodes: [WorkspaceTreeNodeViewModel]
    let rootName: String
    let colors: ThemeColors
    let onOpenInEditor: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(rootName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colors.text)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.bottom, DesignTokens.Spacing.sm)

                ForEach(nodes) { node in
                    TreeNodeView(
                        node: node, colors: colors,
                        onOpenInEditor: onOpenInEditor, level: 0
                    )
                }
            }
            .padding(.vertical, DesignTokens.Spacing.md)
        }
    }
}

private struct TreeNodeView: View {
    @ObservedObject var node: WorkspaceTreeNodeViewModel
    let colors: ThemeColors
    let onOpenInEditor: (String) -> Void
    let level: Int

    var body: some View {
        if node.isExpanderPlaceholder {
            EmptyView()
        } else if node.isPlaceholder {
            Text(node.name)
                .font(.system(size: 12))
                .foregroundColor(colors.subtleText)
                .padding(.leading, CGFloat(level + 1) * 16 + DesignTokens.Spacing.md)
                .padding(.vertical, 2)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: {
                    if node.isDirectory {
                        withAnimation(.easeInOut(duration: DesignTokens.Duration.fast)) {
                            node.isExpanded.toggle()
                        }
                        if node.isExpanded { node.ensureChildrenLoaded() }
                    } else if let path = node.fullPath {
                        onOpenInEditor(path)
                    }
                }) {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        if node.isDirectory {
                            Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10))
                                .foregroundColor(colors.subtleText)
                                .frame(width: 12)
                        } else {
                            Spacer().frame(width: 12)
                        }
                        Image(systemName: node.iconKind.symbolName)
                            .font(.system(size: 12))
                            .foregroundColor(colors.subtleText)
                            .frame(width: 16)
                        Text(node.name)
                            .font(.system(size: 13))
                            .foregroundColor(colors.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, 2)
                    .padding(.leading, CGFloat(level) * 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if !node.isDirectory, let path = node.fullPath {
                        Button("在编辑器中打开") { onOpenInEditor(path) }
                    }
                }

                if node.isDirectory && node.isExpanded {
                    ForEach(node.children) { child in
                        TreeNodeView(
                            node: child, colors: colors,
                            onOpenInEditor: onOpenInEditor, level: level + 1
                        )
                    }
                }
            }
        }
    }
}
