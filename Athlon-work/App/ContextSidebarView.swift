import AppKit
import SwiftUI

struct ContextSidebarView: View {
    @Environment(MainShellStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabBar
            Divider()
            content
        }
        .frame(minWidth: UiLayoutConstraints.contextSidebarMinWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(store.themeManager.chrome.panel.color)
        .onAppear { store.refreshCatalogs() }
    }

    private var header: some View {
        HStack {
            Text(L10n.t("context.title", language: store.language))
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Button {
                store.refreshCatalogs()
                Task { await store.connectMcp() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh skills / MCP")
        }
        .padding(.horizontal, 14)
        .frame(height: AppLayoutMetrics.panelHeaderHeight)
    }

    private var tabBar: some View {
        Picker("", selection: Bindable(store).contextTab) {
            ForEach(ContextSidebarTab.allCases) { tab in
                Text(tab.title(language: store.language)).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch store.contextTab {
        case .files:
            WorkspaceTreeView(
                treeStore: store.workspaceTreeStore,
                onOpenFile: { path in store.openFile(path: path) },
                onRevealInFinder: { path in
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            )
        case .skills:
            skillsAndMcp
        }
    }

    private var skillsAndMcp: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.t("context.skills", language: store.language))
                    .font(.system(size: 13, weight: .semibold))

                if store.skillInfos.isEmpty {
                    Text(L10n.t("context.skillsEmpty", language: store.language))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.skillInfos) { skill in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(skill.enabled ? Color.green.opacity(0.8) : Color.secondary.opacity(0.4))
                                .frame(width: 8, height: 8)
                                .padding(.top, 4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skill.name)
                                    .font(.system(size: 12, weight: .medium))
                                if !skill.description.isEmpty {
                                    Text(skill.description)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                            }
                        }
                    }
                }

                Divider()

                Text(L10n.t("context.mcpTitle", language: store.language))
                    .font(.system(size: 13, weight: .semibold))

                if store.mcpStatuses.isEmpty {
                    Text(L10n.t("context.mcpEmpty", language: store.language))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.mcpStatuses) { status in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(mcpColor(status))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(status.name)
                                    .font(.system(size: 12, weight: .medium))
                                Text(mcpCaption(status))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func mcpColor(_ status: McpServerStatus) -> Color {
        if !status.enabled { return .secondary.opacity(0.4) }
        if status.connected { return .green.opacity(0.85) }
        return .orange.opacity(0.85)
    }

    private func mcpCaption(_ status: McpServerStatus) -> String {
        if !status.enabled { return "disabled" }
        if status.connected { return "connected · \(status.toolCount) tools" }
        return status.lastError ?? "disconnected"
    }
}

#Preview {
    ContextSidebarView()
        .environment(MainShellStore())
        .frame(width: 320, height: 600)
}
