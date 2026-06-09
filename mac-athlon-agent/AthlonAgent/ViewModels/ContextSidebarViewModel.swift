// AthlonAgent/ViewModels/ContextSidebarViewModel.swift
import Foundation

@MainActor
final class ContextSidebarViewModel: ObservableObject {
    enum Tab: String, CaseIterable {
        case files = "文件"
        case skills = "技能"
        case mcp = "MCP"
    }

    @Published var selectedTab: Tab = .files
    @Published var workspaceTreeNodes: [WorkspaceTreeNodeViewModel] = []
    @Published var skills: [String] = []
    @Published var mcpServers: [McpServerStatusItem] = []
    @Published var workspaceRootName: String = "未配置工作区"

    var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    func refresh() {
        refreshWorkspaceTree()
        refreshSkills()
        refreshMcpServers()
    }

    func refreshWorkspaceTree(rootPath: String? = nil) {
        let root = rootPath ?? appState?.workspaceRootPath
        let ignorePatterns = appState?.settings.workspaceIgnore.directoryNames ?? []
        workspaceRootName = root.map { ($0 as NSString).lastPathComponent } ?? "未配置工作区"
        workspaceTreeNodes = WorkspaceTreeNodeViewModel.buildTree(
            rootPath: root, ignorePatterns: ignorePatterns
        )
    }

    func refreshSkills() {
        guard let catalog = appState?.skillService else {
            skills = ["技能服务未初始化"]
            return
        }
        let names = catalog.skills.map { $0.name }
        if names.isEmpty {
            skills = ["未安装技能"]
        } else {
            skills = names.sorted()
        }
    }

    func refreshMcpServers() {
        guard let appState else { return }
        let configs = appState.settings.mcpServers
        if configs.isEmpty {
            mcpServers = [McpServerStatusItem(
                name: "未配置 MCP 服务器", isEnabled: false, status: nil
            )]
        } else {
            mcpServers = configs.map { server in
                let state = appState.mcpClientService?.connectionState(for: server.id)
                return McpServerStatusItem(
                    name: server.name,
                    isEnabled: server.enabled,
                    status: state
                )
            }
        }
    }
}

struct McpServerStatusItem: Identifiable {
    let id = UUID()
    let name: String
    let isEnabled: Bool
    let status: McpUiConnectionState?
}
