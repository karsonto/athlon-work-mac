import SwiftUI

// MARK: - Context Sidebar (Right Panel)
struct ContextSidebarView: View {
    @EnvironmentObject var appState: AppState

    private var colors: ThemeColors {
        appState.theme == .dark ? .dark : .light
    }

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader("上下文")

            Divider()
                .foregroundColor(colors.border)

            ScrollView {
                VStack(spacing: 16) {
                    workspaceSection
                    mcpSection
                    skillsSection
                }
                .padding(12)
            }
            .frame(maxHeight: .infinity)

            // Plan tracker toggle
            if let plan = appState.plan {
                Divider()
                    .foregroundColor(colors.border)
                planTrackerSection(plan)
            }
        }
    }

    // MARK: - Sections
    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "folder")
                    .font(.system(size: 12))
                Text("当前工作区")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            .foregroundColor(colors.subtleText)

            if let ws = appState.activeWorkspace {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ws)
                        .font(.system(size: 13))
                        .foregroundColor(colors.text)
                        .lineLimit(2)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(colors.panelAlt))
            } else {
                Text("未选择工作区")
                    .font(.system(size: 13))
                    .foregroundColor(colors.subtleText)
            }

            // File tree placeholder
            fileTreePreview
        }
    }

    private var fileTreePreview: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(appState.workspaceFiles.prefix(8)) { node in
                HStack(spacing: 6) {
                    Image(systemName: node.isDirectory ? "folder" : "doc")
                        .font(.system(size: 10))
                        .foregroundColor(colors.subtleText)
                    Text(node.name)
                        .font(.system(size: 11))
                        .foregroundColor(colors.text)
                        .lineLimit(1)
                }
            }
        }
        .padding(.top, 4)
    }

    private var mcpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "server.rack")
                    .font(.system(size: 12))
                Text("MCP 服务")
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

    @ViewBuilder
    private func sidebarHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(colors.subtleText)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
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
