import SwiftUI

// MARK: - Settings Page
struct SettingsPageView: View {
    @State private var selectedTab: SettingsTab = .model

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("设置")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(hex: "#F4F4F5"))
                Spacer()
                Button("返回") {
                    // Return to chat (handled by parent navigation)
                    // Would set appState.currentPage = .chat
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#6366F1"))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(height: LayoutMetrics.splitPaneHeaderHeight)
            .background(Color(hex: "#1B1B1E"))
            .overlay(
                Rectangle().fill(Color(hex: "#3F3F46")).frame(height: 1),
                alignment: .bottom
            )

            // Tab bar + content
            HStack(spacing: 0) {
                // Sidebar tabs
                VStack(spacing: 2) {
                    ForEach(SettingsTab.allCases) { tab in
                        settingsTabRow(tab)
                    }
                    Spacer()
                }
                .frame(width: 180)
                .background(Color(hex: "#1B1B1E"))

                Rectangle()
                    .fill(Color(hex: "#3F3F46"))
                    .frame(width: 1)

                // Content
                ScrollView {
                    settingsTabContent
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(hex: "#18181B"))
    }

    @ViewBuilder
    private func settingsTabRow(_ tab: SettingsTab) -> some View {
        Button(action: { selectedTab = tab }) {
            HStack(spacing: 8) {
                Image(systemName: tab.iconName)
                    .frame(width: 18)
                Text(tab.title)
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .foregroundColor(selectedTab == tab ? Color(hex: "#F4F4F5") : Color(hex: "#A1A1AA"))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedTab == tab ? Color(hex: "#6366F1").opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var settingsTabContent: some View {
        switch selectedTab {
        case .model:
            modelSettingsContent
        case .mcp:
            mcpSettingsContent
        case .skills:
            skillsSettingsContent
        case .ignore:
            ignoreSettingsContent
        }
    }

    // MARK: - Model Settings
    private var modelSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("模型配置")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(hex: "#F4F4F5"))

            VStack(alignment: .leading, spacing: 8) {
                settingsField("Provider", placeholder: "openai")
                settingsField("API Endpoint", placeholder: "https://api.openai.com/v1")
                settingsField("Model Name", placeholder: "gpt-4o")
                settingsField("Max Tokens", placeholder: "0 (auto)")
                settingsField("API Key", placeholder: "sk-...", secure: true)
            }

            Toggle("启用流式输出", isOn: .constant(true))
                .font(.system(size: 13))
                .toggleStyle(.switch)
                .foregroundColor(Color(hex: "#F4F4F5"))
        }
    }

    // MARK: - MCP Settings
    private var mcpSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MCP 服务器")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(hex: "#F4F4F5"))

            Text("配置 MCP 服务器以扩展工具能力")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "#A1A1AA"))

            Button("添加 MCP 服务器") {
                // Placeholder
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Skills Settings
    private var skillsSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("技能")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(hex: "#F4F4F5"))

            Text("管理可用的技能模块")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "#A1A1AA"))
        }
    }

    // MARK: - Ignore Settings
    private var ignoreSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("忽略目录")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(hex: "#F4F4F5"))

            Text("配置不扫描的目录名称")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "#A1A1AA"))

            let defaults = ["node_modules", "dist", ".next", "build", "bin", "obj",
                          ".git", ".svn", "__pycache__", ".venv", "venv",
                          ".idea", ".vs", ".vscode", "target", "Debug", "Release"]

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 6) {
                ForEach(defaults, id: \.self) { dir in
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#A1A1AA"))
                        Text(dir)
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#D4D4D8"))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: "#27272A")))
                }
            }
        }
    }

    @ViewBuilder
    private func settingsField(_ label: String, placeholder: String, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#A1A1AA"))
            Group {
                if secure {
                    SecureField(placeholder, text: .constant(""))
                } else {
                    TextField(placeholder, text: .constant(""))
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: "#27272A")))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: "#3F3F46"), lineWidth: 1))
        }
    }
}

// MARK: - Settings Tab Enum
enum SettingsTab: String, CaseIterable, Identifiable {
    case model, mcp, skills, ignore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .model: "模型"
        case .mcp: "MCP 服务"
        case .skills: "技能"
        case .ignore: "忽略目录"
        }
    }

    var iconName: String {
        switch self {
        case .model: "brain"
        case .mcp: "server.rack"
        case .skills: "sparkles"
        case .ignore: "eye.slash"
        }
    }
}
