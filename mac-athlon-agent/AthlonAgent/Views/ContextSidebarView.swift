// AthlonAgent/Views/ContextSidebarView.swift
import SwiftUI

// MARK: - Context Sidebar (Right Panel)
struct ContextSidebarView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: ContextSidebarViewModel

    private var colors: ThemeColors {
        appState.theme == .dark ? .dark : .light
    }

    init() {
        // Temporary: StateObject needs an initial value before @EnvironmentObject is injected.
        // onAppear updates viewModel.appState with the real AppState.
        _viewModel = StateObject(wrappedValue: ContextSidebarViewModel(appState: AppState()))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("上下文")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colors.subtleText)
                Spacer()
                Button(action: { appState.clearContext() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .foregroundColor(colors.subtleText)
                .help("清空当前对话在模型中的可见历史")
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.md)
            .background(colors.panel)

            Divider().background(colors.border)

            // Tab bar
            HStack(spacing: 0) {
                ForEach(ContextSidebarViewModel.Tab.allCases, id: \.self) { tab in
                    Button(tab.rawValue) {
                        viewModel.selectedTab = tab
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.md)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(
                        viewModel.selectedTab == tab ? colors.accent : colors.subtleText
                    )
                    .background(
                        VStack {
                            Spacer()
                            if viewModel.selectedTab == tab {
                                Rectangle()
                                    .fill(colors.accent)
                                    .frame(height: 2)
                            }
                        }
                    )
                    .buttonStyle(.plain)
                }
            }
            .background(colors.panelAlt)

            Divider().background(colors.border)

            // Tab content
            Group {
                switch viewModel.selectedTab {
                case .files:
                    WorkspaceTreeView(
                        nodes: $viewModel.workspaceTreeNodes,
                        rootName: viewModel.workspaceRootName,
                        colors: colors,
                        onOpenInEditor: { path in
                            appState.openFileEditor(path: path)
                        }
                    )
                case .skills:
                    SkillsListView(skills: viewModel.skills, colors: colors)
                case .mcp:
                    McpServerStatusView(
                        servers: viewModel.mcpServers, colors: colors
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            viewModel.appState = appState
            viewModel.refresh()
        }
        .onReceive(appState.$workspaceRootPath) { _ in
            viewModel.refreshWorkspaceTree()
        }
    }

// MARK: - Skills List
private struct SkillsListView: View {
    let skills: [String]
    let colors: ThemeColors

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                ForEach(skills, id: \.self) { skill in
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Circle()
                            .fill(skill.hasPrefix("●") ? Color.green : Color.gray)
                            .frame(width: 6, height: 6)
                        Text(skill)
                            .font(.system(size: 12))
                            .foregroundColor(colors.text)
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                }
            }
            .padding(.vertical, DesignTokens.Spacing.md)
        }
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
