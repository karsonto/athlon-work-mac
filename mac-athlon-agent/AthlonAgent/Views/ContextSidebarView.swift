import SwiftUI

// MARK: - Context Sidebar (Right Panel)
struct ContextSidebarView: View {
    @EnvironmentObject var appState: AppState

    private var colors: ThemeColors {
        appState.theme == .dark ? .dark : .light
    }

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader

            Divider()
                .foregroundColor(colors.border)

            GeometryReader { geo in
                let planReserve: CGFloat = appState.plan == nil ? 0 : 140
                let bodyHeight = max(geo.size.height - planReserve, 160)
                let topHeight = min(max(bodyHeight * 0.42, 120), 360)

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            skillsSection
                            mcpSection
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                    .frame(width: geo.size.width, height: topHeight)

                    Divider()
                        .foregroundColor(colors.border)

                    workspaceBottomSection
                        .frame(width: geo.size.width, height: bodyHeight - topHeight)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(maxHeight: .infinity)

            if let plan = appState.plan {
                Divider()
                    .foregroundColor(colors.border)
                planTrackerSection(plan)
            }
        }
    }

    private var sidebarHeader: some View {
        HStack {
            Text("上下文")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(colors.subtleText)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var workspaceBottomSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("工作区文件")
                    .font(.system(size: 12))
                    .foregroundColor(colors.subtleText)
                Spacer()
                Button(action: { appState.refreshWorkspace() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }

            Text(activeWorkspaceName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(colors.text)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(colors.panelAlt)
                RoundedRectangle(cornerRadius: 12)
                    .stroke(colors.border, lineWidth: 1)

                ScrollView {
                    WorkspaceFileTreeView(
                        nodes: appState.workspaceService.fileTree,
                        colors: colors,
                        onOpenFile: { path in appState.openFileEditor(path: path) }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var activeWorkspaceName: String {
        if let ws = appState.activeWorkspace {
            return (ws as NSString).lastPathComponent
        }
        return "未选择工作区"
    }

    private var mcpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "server.rack")
                    .font(.system(size: 12))
                Text("MCP 服务器")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(appState.mcpServers.count)")
                    .font(.system(size: 10))
                    .foregroundColor(colors.accent)
            }
            .foregroundColor(colors.subtleText)

            ForEach(appState.mcpServers) { server in
                McpServerRow(server: server)
            }

            if appState.mcpServers.isEmpty {
                Text("无 MCP 服务")
                    .font(.system(size: 12))
                    .foregroundColor(colors.subtleText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colors.border, lineWidth: 1)
                .background(RoundedRectangle(cornerRadius: 12).fill(colors.panelAlt))
        )
    }

    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                Text("技能")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(appState.skills.count)")
                    .font(.system(size: 10))
                    .foregroundColor(colors.accent)
            }
            .foregroundColor(colors.subtleText)

            ForEach(appState.skills) { skill in
                SkillRow(skill: skill)
            }

            if appState.skills.isEmpty {
                Text("无可用技能")
                    .font(.system(size: 12))
                    .foregroundColor(colors.subtleText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colors.border, lineWidth: 1)
                .background(RoundedRectangle(cornerRadius: 12).fill(colors.panelAlt))
        )
    }

    private func planTrackerSection(_ plan: AgentPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "list.clipboard")
                    .font(.system(size: 12))
                Text(plan.name)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            .foregroundColor(colors.subtleText)

            ForEach(plan.subtasks) { subtask in
                HStack(spacing: 6) {
                    Circle()
                        .fill(subtask.status == .done ? Color(hex: "#22C55E") :
                              subtask.status == .inProgress ? Color(hex: "#6366F1") :
                              Color(hex: "#52525B"))
                        .frame(width: 6, height: 6)
                    Text(subtask.name)
                        .font(.system(size: 11))
                        .foregroundColor(colors.text)
                        .lineLimit(1)
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(colors.panelAlt)
    }
}

// MARK: - Right sidebar toggle glyph (WPF RightSidebarToggleIcon)
struct RightSidebarToggleIcon: View {
    let isPanelOpen: Bool

    @Environment(\.themeColors) private var colors

    var body: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 2.5)
                .stroke(colors.subtleText, lineWidth: 1.15)
                .frame(width: 16, height: 14)

            RoundedRectangle(cornerRadius: 1)
                .fill(colors.subtleText.opacity(isPanelOpen ? 1 : 0.35))
                .frame(width: 4.5, height: 10)
                .padding(.trailing, 2.5)
        }
        .frame(width: 18, height: 18)
    }
}

// MARK: - Expandable file tree
struct WorkspaceFileTreeView: View {
    let nodes: [WorkspaceNode]
    let colors: ThemeColors
    let onOpenFile: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if nodes.isEmpty {
                Text("暂无文件")
                    .font(.system(size: 11))
                    .foregroundColor(colors.subtleText)
            } else {
                ForEach(nodes) { node in
                    WorkspaceTreeNodeRow(node: node, depth: 0, colors: colors, onOpenFile: onOpenFile)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
}

struct WorkspaceTreeNodeRow: View {
    @ObservedObject var node: WorkspaceNode
    let depth: Int
    let colors: ThemeColors
    let onOpenFile: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if node.isDirectory {
                    Button(action: { node.isExpanded.toggle() }) {
                        Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9))
                            .foregroundColor(colors.subtleText)
                            .frame(width: 12)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 12)
                }

                Image(systemName: node.iconKind.systemName)
                    .font(.system(size: 10))
                    .foregroundColor(colors.subtleText)

                Text(node.name)
                    .font(.system(size: 11))
                    .foregroundColor(colors.text)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture {
                        if node.isDirectory {
                            node.isExpanded.toggle()
                        } else {
                            onOpenFile(node.path)
                        }
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, CGFloat(depth) * 12)

            if node.isDirectory, node.isExpanded, let children = node.children {
                ForEach(children) { child in
                    WorkspaceTreeNodeRow(node: child, depth: depth + 1, colors: colors, onOpenFile: onOpenFile)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Row Components
struct McpServerRow: View {
    let server: McpServerItem

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(server.isStatusHealthy ? Color(hex: "#22C55E") : Color(hex: "#EF4444"))
                .frame(width: 6, height: 6)
            Text(server.name)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#D4D4D8"))
            Spacer()
            if server.isEnabled {
                Image(systemName: "checkmark")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#22C55E"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.03)))
    }
}

struct SkillRow: View {
    let skill: SkillItem

    var body: some View {
        HStack(spacing: 8) {
            Text(skill.displayInitial)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(hex: "#C4B5FD"))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color(hex: "#4C1D95").opacity(0.3)))
            Text(skill.name)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#D4D4D8"))
            Spacer()
        }
    }
}
